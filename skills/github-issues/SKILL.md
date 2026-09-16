---
name: github-issues
description: Use when working with GitHub issue dependencies (blocked-by/blocking), sub-issues, or Projects v2 boards from the CLI — setting them, querying them, or answering "what is startable right now". Covers the parts gh does not wrap, where the GraphQL field names are easy to invent, and the pagination default that returns a confidently wrong answer.
---

# GitHub issues beyond `gh`

Verified against the live API, September 2026. `gh issue` covers create/list/edit/close.
Dependencies, sub-issues and Projects v2 fields are GraphQL, and that is where the
mistakes live.

## `first: 100` silently truncates

The default page is not "everything", and nothing warns you. On a repo with 132 open
issues, `issues(states:OPEN, first:100)` returned a page covering roughly the middle
of the range and omitted the four most recently created — including every dependency
added that day. The query succeeded. The answer was wrong.

Any repo-wide question — what is blocked, what is startable, dependency graphs —
**must paginate**:

```bash
gh api graphql --paginate -f query='query($endCursor:String){
  repository(owner:"OWNER", name:"REPO"){
    issues(states:OPEN, first:100, after:$endCursor){
      pageInfo{ hasNextPage endCursor }
      nodes{ number title blockedBy(first:20){ nodes{ number state } } }
    } } }'
```

The query **must** declare `$endCursor` and pass it to `after:` — `--paginate` drives
that variable and does nothing without it. Check `totalCount` against the number of
nodes you got back whenever the answer matters.

## Field names that exist, and ones that don't

On `Issue`:

| Field | Returns |
|---|---|
| `blockedBy(first:n)` | issues blocking this one |
| `blocking(first:n)` | issues this one blocks |
| `subIssues(first:n)` | children |
| `parent` | the parent issue, or null |
| `subIssuesSummary` | `{ total, completed, percentCompleted }` |
| `issueDependenciesSummary` | `{ blockedBy, blocking, totalBlockedBy, totalBlocking }` |

**`blockedByIssues` and `blockedByOpen` do not exist** — both are plausible, both are
the kind of name a model invents, and both fail with `undefinedField`. There is no
"open blockers" count; `blockedBy` returns every blocker regardless of state, so
filter on `state == "OPEN"` yourself.

## Mutations take node IDs, not numbers

```graphql
addBlockedBy(input:{ issueId: ID!, blockingIssueId: ID! })
removeBlockedBy(input:{ issueId: ID!, blockingIssueId: ID! })
addSubIssue(input:{ issueId: ID!, subIssueId: ID! })
removeSubIssue(input:{ issueId: ID!, subIssueId: ID! })
```

**"A blocks B" and "B is blocked by A" are the same mutation with the arguments
swapped.** There is no `addBlocking`. Whichever direction you are expressing, the
issue that is *stuck* goes in `issueId`.

Resolve both node IDs in one aliased query rather than two round-trips:

```bash
gh api graphql -f query='{ repository(owner:"OWNER",name:"REPO"){
  a: issue(number:904){ id }  b: issue(number:905){ id } } }'
```

## Projects v2: the IDs are opaque and per-board

Setting a field value needs the project id, the field id and — for a single-select —
the *option* id, all opaque hashes belonging to one board. They cannot be derived
from the schema. Get them in one call and write them down:

```bash
gh project field-list <NUMBER> --owner <OWNER> --format json
# ProjectV2SingleSelectField | Status | PVTSSF_...
#      option: Backlog f75ad846
```

Two ordering traps:

- **An issue must already be an item on the board before any field can be set.**
  Setting a field on a non-member fails with "not found in project", which reads like
  the issue doesn't exist.
- **`gh issue create --project "<name>"` adds it at creation**, by project *name*, and
  avoids a separate `gh project item-add` entirely. Easy to miss — it is the only
  place in this workflow that takes a human-readable name instead of an id.

## What is startable right now

The one query worth keeping around: open issues with no *open* blocker. `blockedBy`
includes closed blockers, so the filter is on state, not on emptiness.

```bash
gh api graphql --paginate -f query='query($endCursor:String){
  repository(owner:"OWNER", name:"REPO"){
    issues(states:OPEN, first:100, after:$endCursor){
      pageInfo{ hasNextPage endCursor }
      nodes{ number title blockedBy(first:20){ nodes{ number state } } }
    } } }' \
  --jq '.data.repository.issues.nodes[]
        | select([.blockedBy.nodes[] | select(.state=="OPEN")] | length == 0)
        | "#\(.number) \(.title)"'
```

Flip `length == 0` to `length > 0` to list what is blocked and by what. Run the
unpaginated version of this and it will answer confidently and wrongly.

## Sub-issue trees

GraphQL does not recurse, so a tree needs one query per level. Two levels covers most
real hierarchies; if you need arbitrary depth, iterate until no node has children
rather than trying to express it in one query. `subIssuesSummary` gives completion
counts without fetching the children at all — prefer it when you only need progress.

## Wrapping this in a Makefile or script

Worth wrapping: the paginated composite queries above, and a board's discovered ids.
Not worth wrapping: single mutations — they are two lines, and a wrapper that hides
them means you cannot improvise when the shape changes.

A wrapper that lives in one repo will drift from its copies and is invisible to anyone
who has not been told it exists. Derive the repo with `gh repo view --json
nameWithOwner` instead of hardcoding it, so at least the same file works everywhere.

---
name: refs
description: Tag each paragraph with a per-message reference number (2.1, 2.2, 3.1), each list item with a letter (2.2a, 2.2b), and everything that needs an answer with a conversation-wide $N number ($1, $2), so the user can point at a specific point instead of quoting it back. Opt-in only - invoke when the user explicitly runs /refs, asks for reference tags or paragraph numbering, or says "refs on" / "number your paragraphs". Do NOT invoke on your own initiative. Once invoked, stay active for the rest of the conversation.
---

# Refs

Make your output addressable. The user should be able to say "3.2 is wrong" or
"expand 2.5" rather than copying text back at you.

## Tag format

Prefix each substantive paragraph with a bold tag, no brackets:

```
**3.1** The parser reads the whole file into memory first, which is fine for
configs but will not hold for the log ingest path.

**3.2** Two ways out:

- **a** Stream it. More work, but the log files are already at 400MB.
- **b** Cap the size and fail loudly.

**$7** Do you want 3.2a, or 3.2b as a stopgap?
```

## Numbering

- **Paragraphs: `M.N`.** `M` is one higher than the highest `M` you have already
  used in this conversation; untagged replies do not consume a number. `N`
  restarts at 1 in every message, so a message's tags are always
  `M.1, M.2, M.3...`.
- **List items: letters.** In a reply that carries tags, every top-level list
  item gets a bold letter — **a**, **b**, **c** — whether the list holds
  options, findings, files or steps. Its reference is the tag right above the
  list plus the letter: `3.2b`, or `$7b` for an option under a question.
  Letters, not numbers: `3.2.1` would read as a version number. Nested items
  get no letter. A list with no tag right above it gets a tagged line
  introducing it. An item that itself needs an answer gets its own `$N`
  instead of a letter.
- **Questions: `$1, $2, ...`** on a single counter that runs across the whole
  conversation and never resets. Questions get asked in one message and
  answered five messages later, so a global counter keeps them findable.
  Questions do not consume a paragraph number.

  A question is anything that needs an answer from the user: a direct question,
  an offer ("want me to...?"), a choice between options, a request for something
  you cannot go on without. Each goes on its own line, led by its tag. One
  asked through a tool rather than in prose still gets a number, at the start
  of the question text — it is still something to point back at.

  The prefix is `$`. Not `?`: typed at the start of a prompt, it opens Claude
  Code's shortcut popup. Not a letter: letter-number IDs belong to other tools
  (mikado's `Q142` quests, `J7` journeys). In a regex, escape it — `\$[0-9]+` —
  and single-quote that in a shell.
- **Never renumber.** Once emitted, a tag permanently means that text. If you
  revise a point, give it a new tag and name the old one: `**4.2** revising
  3.1: ...`.

This survives compaction and resumed sessions on its own — the highest tag still
visible in context is all you need. Skipping a number is harmless; reusing one is
not.

## What does NOT get a tag

Tags are for prose the user might want to argue with. Skip:

- Code blocks, file paths, command output, tables, diagrams
- Headings
- One-line acknowledgements: "Done.", "Fixed — tests pass."
- Narration of what you're about to do with a tool

Aim for roughly one idea per tag — a few sentences. If a whole reply is short
or purely mechanical, emit no tags at all rather than tagging a throwaway line.
Questions still get their `$` number even in an otherwise untagged reply.

## Referring back

When the user writes "3.2 is wrong" or "more on 2.5", resolve the tag from your
earlier messages and answer that specific point — don't restate the whole
topic. If the tag isn't in context or is ambiguous, ask which one they mean
rather than guessing.

## Listing what is open

If the user asks what is still open, list every `$N` you have emitted that they
have not answered — oldest first, with the question text. A question counts as
answered when the user addresses it, not when you move on from it. This is the
main thing the global `$` counter is for: in a long session, questions asked in
passing get lost, and the counter is what makes them recoverable.

## Tags stay in the conversation

Tags are addressing for a live discussion, nothing more. Never write them into
anything durable — files, commits, PR descriptions, issues, documentation,
artifacts, code comments. If you are drafting text that will be read outside
this conversation, it gets no tags even while the skill is active.

## Turning it off

If the user says "refs off" or "stop numbering", drop the tags immediately and
don't resume unless asked again.

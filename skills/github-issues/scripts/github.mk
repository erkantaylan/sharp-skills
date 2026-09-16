# github.mk — the GitHub issue queries that are worth wrapping.
#
# Single mutations are not here on purpose: they are two lines of GraphQL and
# hiding them stops you improvising when the shape changes. What is here is the
# paginated composite queries, because the unpaginated version of these answers
# confidently and wrongly.
#
#   make -f github.mk ready
#   make -f github.mk blockers ISSUE=904
#   make -f github.mk tree ISSUE=412
#   make -f github.mk fields PROJECT=11
#
# REPO defaults to the current directory's repo. Override it for any other:
#   make -f github.mk ready REPO=owner/name
#
# Queries are on single long lines deliberately: a backslash continuation inside
# a single-quoted recipe string reaches jq and GraphQL as a literal backslash.

.PHONY: help ready blocked blockers blocking tree fields
.DEFAULT_GOAL := help

REPO  ?= $(shell gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)
OWNER  = $(firstword $(subst /, ,$(REPO)))
NAME   = $(word 2,$(subst /, ,$(REPO)))

_require_repo  = $(if $(REPO),,$(error Not in a GitHub repo; pass REPO=owner/name))
_require_issue = $(if $(ISSUE),,$(error Usage: make -f github.mk $(1) ISSUE=<number>))

# --paginate only works because the query declares $$endCursor and passes it to
# after:. Without that it silently returns page 1 and the answer is wrong.
_SWEEP = gh api graphql --paginate -f query='query($$endCursor:String){ repository(owner:"$(OWNER)", name:"$(NAME)"){ issues(states:OPEN, first:100, after:$$endCursor){ pageInfo{ hasNextPage endCursor } nodes{ number title blockedBy(first:50){ nodes{ number state } } } } } }'

ready: ## Open issues with no open blocker — what is actually startable
	@$(call _require_repo)
	@$(_SWEEP) --jq '.data.repository.issues.nodes[] | select([.blockedBy.nodes[] | select(.state=="OPEN")] | length == 0) | "#\(.number)  \(.title)"'

blocked: ## Open issues that have an open blocker, and which one
	@$(call _require_repo)
	@$(_SWEEP) --jq '.data.repository.issues.nodes[] | select([.blockedBy.nodes[] | select(.state=="OPEN")] | length > 0) | "#\(.number)  blocked by \([.blockedBy.nodes[] | select(.state=="OPEN") | "#\(.number)"] | join(", "))  \(.title)"'

blockers: ## What is blocking ISSUE. Usage: make -f github.mk blockers ISSUE=904
	@$(call _require_repo)
	@$(call _require_issue,blockers)
	@gh api graphql -f query='{ repository(owner:"$(OWNER)",name:"$(NAME)"){ issue(number:$(ISSUE)){ blockedBy(first:50){ nodes{ number state title } } } } }' --jq '.data.repository.issue.blockedBy.nodes[] | "[\(.state)] #\(.number)  \(.title)"'

blocking: ## What ISSUE is blocking. Usage: make -f github.mk blocking ISSUE=905
	@$(call _require_repo)
	@$(call _require_issue,blocking)
	@gh api graphql -f query='{ repository(owner:"$(OWNER)",name:"$(NAME)"){ issue(number:$(ISSUE)){ blocking(first:50){ nodes{ number state title } } } } }' --jq '.data.repository.issue.blocking.nodes[] | "[\(.state)] #\(.number)  \(.title)"'

# GraphQL does not recurse; this is two levels, which covers most real hierarchies.
tree: ## Sub-issue tree, two levels. Usage: make -f github.mk tree ISSUE=412
	@$(call _require_repo)
	@$(call _require_issue,tree)
	@gh api graphql -f query='{ repository(owner:"$(OWNER)",name:"$(NAME)"){ issue(number:$(ISSUE)){ number title subIssuesSummary{ total completed } subIssues(first:100){ nodes{ number state title subIssues(first:100){ nodes{ number state title } } } } } } }' --jq '.data.repository.issue | "#\(.number)  \(.title)  [\(.subIssuesSummary.completed)/\(.subIssuesSummary.total)]", (.subIssues.nodes[] | "  [\(.state)] #\(.number)  \(.title)", (.subIssues.nodes[] | "      [\(.state)] #\(.number)  \(.title)"))'

# Projects v2 field and option ids are opaque and belong to one board. They
# cannot be derived from the schema — read them once and write them down.
fields: ## Discover a board's field/option ids. Usage: make -f github.mk fields PROJECT=11
	@$(if $(PROJECT),,$(error Usage: make -f github.mk fields PROJECT=<number> [OWNER=<owner>]))
	@gh project field-list $(PROJECT) --owner $(OWNER) --format json --jq '.fields[] | "\(.type)  \(.name)  \(.id)", (.options // [] | .[] | "      \(.name)  \(.id)")'

help: ## Show this help
	@echo "github.mk — repo: $(if $(REPO),$(REPO),<none detected>)"
	@echo
	@grep -hE '^[a-z-]+:.*##' $(MAKEFILE_LIST) | sed 's/:.*##/\t/' | expand -t22

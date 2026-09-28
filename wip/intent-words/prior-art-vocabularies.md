# Prior-art vocabularies — what's already been invented

Companion to [intent-words.md](intent-words.md). Before we finalize an `x:` command set, here are the existing closed intent-vocabularies to build on rather than reinvent. The short version: **the AI↔AI lane is a solved-and-named problem (agent communication languages, 1990s); the human↔AI lane is speech-act theory, and parts are measured.** Our genuinely new pieces are at the bottom.

## 1. KQML performatives (DARPA Knowledge Sharing Effort, ~1993)

A closed, reserved set of message *performatives* — the speech act a message performs — independent of content or transport. Core reserved set, grouped:

| Group | Performatives |
|---|---|
| Inform | `tell`, `untell`, `deny`, `insert`, `delete`, `achieve`, `unachieve` |
| Query | `evaluate`, `ask-if`, `ask-one`, `ask-all`, `ask-about`, `sorry` |
| Multi-response query | `stream-all`, `stream-about` |
| Generator | `standby`, `ready`, `next`, `rest`, `discard`, `generator` |
| Capability / networking | `register`, `unregister`, `advertise`, `subscribe`, `monitor`, `forward`, `broadcast` |
| **Facilitation (delegation!)** | `broker-one`, `broker-all`, `recommend-one`, `recruit-one`, `recruit-all` |
| Error | `error`, `sorry` |

Note the facilitation group: KQML already has **delegation performatives** (`recruit`, `broker`, `recommend`) — the ancestor of our `x:sling` (hand it to sub-agents).

## 2. FIPA-ACL communicative acts (FIPA standard, 1996→2002)

The 22 standardized communicative acts, each with formal semantics (feasibility preconditions + rational effect):

`accept-proposal` · `agree` · `cancel` · `cfp` (call for proposal) · `confirm` · `disconfirm` · `failure` · `inform` · `inform-if` · `inform-ref` · `not-understood` · `propagate` · `propose` · `proxy` · `query-if` · `query-ref` · `refuse` · `reject-proposal` · `request` · `request-when` · `request-whenever` · `subscribe`

**Why it died in practice:** the formal semantics (each act has a logical precondition/effect) was heavy and rarely honored. Lesson for us: **keep the `x:` table a lookup, not a logic.**

## 3. Speech Act Theory (Austin 1962 / Searle 1969) — the human↔AI lane

Searle's five illocutionary classes — the root taxonomy under all of the above:

| Class | Does | Our axis |
|---|---|---|
| **Assertives** (representatives) | commit speaker to a truth (state, report, claim) | STATUS (`di`/`mis`) |
| **Directives** | get the hearer to do something (request, ask, command) | INTENT (`ask` / `do`) |
| **Commissives** | commit *speaker* to future action (promise, offer) | agent-side "will do" |
| **Expressives** | express a state (thank, apologize) | `fyi` |
| **Declarations** | change reality by saying it ("you're hired") | RELEASE (`execute`) |

## Mapping our draft `x:` set onto the prior art

| `x:` command | Axis | Nearest classic ancestor | New? |
|---|---|---|---|
| `ask` | intent | FIPA `query-if`/`query-ref`, KQML `ask-one` | — borrow |
| `do` | intent | FIPA `request`, KQML `achieve` | — borrow |
| `fyi` | intent | FIPA `inform`, KQML `tell` | — borrow |
| `plan` (propose→wait) | intent/mode | FIPA `propose` / `cfp` | partial |
| `execute` (release) | release | FIPA `accept-proposal`; Searle *declaration*; ACP-125 EXECUTE | — borrow |
| `disregard` | flow | FIPA `cancel` | — borrow |
| `say-again` | flow | FIPA `not-understood` | — borrow |
| `wait` | flow | KQML `standby` | — borrow |
| `sling` (delegate) | who | KQML `recruit`/`broker`/`recommend`, FIPA `proxy` | — borrow |
| **`discuss` / `auto`** (sticky modes) | mode | *none — ACLs are stateless per-message* | **NEW** |
| **`di` / `mis`** (witnessed vs inferred) | status | FIPA `confirm`/`disconfirm` mark truth, not *source* | **NEW** (from Turkish evidential past) |
| **`sd` / `notify` / `commit`** (run lifecycle) | lifecycle | *none — ACLs model message intent, not run lifecycle* | **NEW** |

## What is genuinely ours (not in KQML/FIPA/ACP-125)

1. **A sticky FLOW state-machine** (`discuss` ⊂ `plan` ⊂ `auto` + the code-gate). Classic ACLs are stateless: one performative per message, no session mode.
2. **Evidential STATUS** (`di`/`mis`): marking *how you know* a claim (witnessed vs. inferred), borrowed from Turkish grammar. ACLs mark whether a proposition is asserted, not its evidential source.
3. **LIFECYCLE post-hooks** (`sd`, `notify`, `commit`): about the *run*, not the message.
4. **Stackability**: an ACL message carries exactly one performative; we compose several into one run-spec (`x:plan x:sling x:sd`).
5. **Ergonomics for a human**: one-char `x:` prefix, bilingual TR/EN, typed inline mid-chat — ACLs were machine-to-machine S-expressions.

## What the measured research says (2026 web search)

- **Implicature study** — explicitly handling indirect requests ("can you X" = "do X") gave *measurably better* human-LLM alignment vs. baseline. Evidence the "can you X" problem is real and addressable. ([arXiv 2510.25426](https://arxiv.org/pdf/2510.25426))
- **Intent-comprehension study** (1.77M responses) — models show **articulation sensitivity**: behavior shifts with *phrasing* at constant intent. That's the exact disease a fixed marker treats. It did *not* test explicit marking — an open experiment we could run. ([arXiv 2506.16584](https://arxiv.org/html/2506.16584v3))
- **Classic ACLs not adopted by LLM agents** — modern protocols (MCP, A2A, Coral) optimize tokens/structure, not speech-act performatives. ([survey, arXiv 2509.02515](https://arxiv.org/pdf/2509.02515))
- **The competing approach: "ask, don't mark."** A line of SE-ambiguity work has the agent fire a *clarifying question* when unsure, instead of the user pre-labeling intent — i.e. our "doubt and loop" rule, and it may be the best-evidenced piece of the whole design. ([arXiv 2502.13069](https://arxiv.org/html/2502.13069v1), [arXiv 2511.10453](https://arxiv.org/html/2511.10453v2))

## Sources

- [Agent Communication Languages: FIPA-ACL and KQML (comparison)](https://www.academia.edu/88620133/Agent_Communication_Languages_Comparison_Fipa_Acl_and_KQML)
- [KQML — Wikipedia](https://en.wikipedia.org/wiki/Knowledge_Query_and_Manipulation_Language)
- [FIPA ACL communicative acts spec](http://www.fipa.org/specs/fipa00037/)
- [Speech act — Wikipedia (Searle's classes)](https://en.wikipedia.org/wiki/Speech_act)
- Measured LLM work: [2510.25426](https://arxiv.org/pdf/2510.25426), [2506.16584](https://arxiv.org/html/2506.16584v3), [2509.02515](https://arxiv.org/pdf/2509.02515), [2502.13069](https://arxiv.org/html/2502.13069v1), [2511.10453](https://arxiv.org/html/2511.10453v2)

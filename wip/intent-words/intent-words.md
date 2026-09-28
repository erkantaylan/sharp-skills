# Intent words — research notes

Goal: a small shared vocabulary so that the user and an agent never have to guess what a message *wants*. The recurring failure: the user asks a question and wants an answer, the agent treats it as an order and starts changing things (or the reverse).

Status: research + design. Not a skill yet. This conversation (2026-09-28) moved it from a proword list toward a stackable command dictionary usable in two lanes (human↔AI and AI↔AI) — see "Design v2" below. Prior art now mapped (agent communication languages; see [prior-art-vocabularies.md](prior-art-vocabularies.md)) and probe #1 run (null result — see "Probe #1"). Probe #2 (2026-09-29) tested `x:frame`: positive, but the value is **packaging** (a reliable handle) not better comprehension.

## The problem has a name

Linguistics calls it an **indirect speech act**: the grammatical form (question) differs from the intent (request). "Can you add X?" is a question in form and an order in intent; "why is X broken?" is a question in form, but agents often hear "fix X". Every field that cannot afford misreads solved it the same way: **mark the intent explicitly, with a fixed, small vocabulary**, instead of inferring it from phrasing.

## Prior art

| Source | What it does | Useful for us |
|---|---|---|
| Military / aviation radio (ACP 125, below) | Fixed procedure words (prowords) with one meaning each | Acknowledge / comply / wait / correct / end, without prose |
| [Conventional Comments](https://conventionalcomments.org) | Code-review comments start with a label: `question:`, `suggestion:`, `nitpick:`, `issue:`, `praise:`, plus decorations like `(non-blocking)` | Label-before-message is exactly "is this a question or an order" |
| Engineering chat shorthand | `FYI`, `NRN` (no reply needed), `PTAL`, `nit:`, `EOM` (whole message is in the subject) | Reply expectations |
| [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) | `MUST` / `SHOULD` / `MAY` | How firm an instruction is |
| Claude Code plan mode (Shift+Tab) | Session-wide: the agent may read and propose, but not change anything | Heavy-handed "don't dive in"; not per-message |
| [inocult/xo PR #14](https://github.com/inocult/xo/pull/14) | An agent persona that opens replies with ACP 125 prowords (ROGER, WILCO, WAIT, SAY AGAIN, CORRECTION, WRONG, OUT); drops OVER because the end of a turn already hands the exchange back | Someone already tried prowords on an agent — same conclusion about OVER |

## Prior art II — it's already been invented (and partly measured)

The AI↔AI lane has a name and a 30-year history: **agent communication languages** (KQML, 1993; FIPA-ACL, 1996) are closed sets of intent *performatives* — `ask` / `tell` / `achieve` / `request` / `inform` / `confirm` / `cancel` — the direct ancestors of our `x:` commands (KQML even has delegation performatives `recruit`/`broker`, the ancestor of `x:sling`). The human↔AI lane is **speech act theory** (Searle's five classes). The full mapping of our draft set onto both — and what is genuinely new (sticky flow-modes, evidential `di`/`miş`, lifecycle hooks, stacking) — is in [prior-art-vocabularies.md](prior-art-vocabularies.md).

Measured findings worth knowing:

- Explicitly handling indirect requests ("can you X" = "do X") **measurably improves** human-LLM alignment (implicature study). The "can you X" problem is real.
- Models show **articulation sensitivity** — behavior changes with phrasing at constant intent — exactly what a fixed marker would stabilize. Nobody has tested marking directly: an open experiment.
- Classic ACLs were **not adopted** by LLM agents; modern protocols (MCP, A2A, Coral) optimize tokens, not performatives. So lean on compression, and keep the table a lookup, not a formal logic (FIPA's heavy semantics is why it died).
- A competing, well-evidenced approach is **"ask, don't mark"**: the agent fires a clarifying question when unsure (= our doubt-and-loop rule), possibly the strongest single piece of the design.

## Military (NATO) — ACP 125 prowords

ACP 125 is the Allied Communications Publication for radiotelephone procedure. The Turkish Armed Forces are a NATO member and use it in English on joint/NATO nets.

| Proword | Meaning |
|---|---|
| ROGER | I received your last transmission satisfactorily. |
| WILCO | I understand and will comply. (Includes ROGER — never say both.) |
| OVER | My transmission is ended; I expect a response. |
| OUT | End of transmission; no answer required. (Never with OVER.) |
| SAY AGAIN | Repeat all, or the following part, of your last transmission. |
| I SAY AGAIN | I am repeating. |
| READ BACK | Repeat this back to me exactly as received. |
| WAIT | I must pause for a few seconds. |
| WAIT OUT | I must pause longer; I'll call you. |
| STANDBY | Wait and I will call you. |
| CORRECTION | I made an error; continuing from the last correct word. |
| WRONG | Your last transmission was incorrect; the correct version is… |
| DISREGARD | Ignore (the transmission in progress). |
| AFFIRMATIVE / NEGATIVE | Yes / No (or permission not granted). |
| EXECUTE | Carry out the order now. |
| BREAK | Separates parts of a message. |

## Turkish — telsiz işlem kelimeleri

TSK's own internal procedure manuals are not public. What *is* public is the Turkish standard for civil/maritime radio (GMDSS *işletme kelimeleri*) and general telsiz-konuşma guides, which describe the same NATO-derived set. Treat the table as "Turkish radio usage", not "TSK doctrine".

| Türkçe | English proword | Meaning |
|---|---|---|
| Anlaşıldı | ROGER | Aldım, anladım |
| Tamam | OVER | Sözüm bitti, cevap bekliyorum |
| Bitti / Tamam, bitti | OUT | Haberleşme bitti, cevap beklenmiyor |
| Tekrar ediniz / Tekrarlayınız | SAY AGAIN | Tekrarla, anlaşılmadı |
| Yeniden söylüyorum | I SAY AGAIN | Tekrar ediyorum |
| Bekle / Bekleyiniz | WAIT / STANDBY | Kısa bekleme |
| Doğrusu | CORRECTION | Hata yaptım, doğrusu şu |
| Hata | MISTAKE | Yanlış oldu |
| Doğru / Doğrudur | AFFIRMATIVE | Evet / izin verildi |
| Hayır / Olumsuz | NEGATIVE | Hayır |
| Teyit et / Onayla | CONFIRM / ACKNOWLEDGE | Aldığını/anladığını bildir |
| Devam ediniz | GO AHEAD | Devam et |
| Burası … | THIS IS | Çağıran istasyon |
| Sizi dinliyorum | (I am listening) | Karşı taraf konuşabilir |

Note the collision: in Turkish radio **"tamam" = OVER**, while in everyday Turkish "tamam" means "OK / agreed". Do not use bare `tamam` in the vocabulary — it would be read both ways.

## Draft vocabulary (TR/EN mixed, either form accepted)

### User → agent: what this message wants

Prefix at the start of the message. Turkish and English forms are synonyms.

| Prefix | Meaning | Agent must NOT |
|---|---|---|
| `ask:` / `soru:` | Answer only. | Edit, run state-changing commands, "quickly fix" what the answer reveals. |
| `plan:` | Propose, then wait. | Act before `execute` / `uygula`. |
| `do:` / `yap:` | Act. | Stop to ask what a sensible default already answers. |
| `fyi:` / `bilgi:` | Context for later. | Act on it; reply is one line at most. |
| `execute` / `uygula` | Go ahead with the last proposal. | Re-propose. |
| `wait` / `bekle` | Stop what you are doing. | Continue the current step. |
| `disregard` / `iptal` | Ignore my previous message. | Act on it. |
| `say again` / `tekrar` | Re-explain, differently. | Repeat verbatim. |

**Default when unmarked** (the most important rule — most messages won't carry a prefix): an imperative ("add X", "move Y") → act. A question ("why…", "what…", "is…", "can we…") → answer, then offer to act; don't act. "Can you X" is the one exception: it's an imperative in polite form → act.

### Agent → user: reply opener (optional)

| Opener | Meaning |
|---|---|
| ROGER / Anlaşıldı | Understood; answered, nothing changed. |
| WILCO | Will do — followed by doing it. |
| WAIT / Bekle | Still working (long task). |
| CORRECTION / Doğrusu | Replaces something I said earlier (name the ref). |
| OUT / Bitti | This thread is finished. |

OVER / `tamam` is dropped: in chat, the end of a turn already hands the floor back.

## Idea: the execute gate

One `.md` that explains the whole protocol, and one of its rules is: **do not start writing code unless the user says `execute` / `uygula`.** Until then the agent may read, investigate, answer and propose, but not edit files or run state-changing commands. This makes `plan:` the default mode for code, and `execute` the single word that releases it. It is ACP 125's EXECUTE ("carry out the order now") used exactly as the military uses it.

Open: whether the gate covers only code, or every state-changing action (moving files, deleting memories, installing things).

## Design v2 — from prowords to a stackable command dictionary

Reframe from the 2026-09-28 conversation. This is no longer "intent prefixes for the user." It is a **shared command dictionary** used in two lanes:

- **Human ↔ AI** — so the agent never misreads what a message wants (answer vs. act).
- **AI ↔ AI** — so a parent agent and its subagents pass intent, confidence and flow-state in *tokens* instead of prose. This is also a context-simplification lever: less hedging prose to carry between agents, and delegation keeps the parent's own context clean.

### Not fuzzy words — a closed table

Plain-English prowords (`do`, `wait`, `disregard`) still leave room for the exact misread we are trying to kill. So the vocabulary is a **closed, defined command table**: the agent *looks up* a token, it does not *interpret* it. A token not in the table is not a command. That is the line between a dictionary and a vibe.

Prefix: **`x:`** — short, meaningless in both TR and EN, so it never collides with a real word. Commands read `x:plan`, `x:sling`, `x:sd`, …

### Stackable

Commands compose. One line carries several, applied together as a small "run spec":

```
x:plan x:sling x:sd
= plan it out, hand implementation to subagents, shut the machine down when the jobs finish
```

Build question, deferred: whether these are real slash-commands (harness-routed, hardest to misread, but they do not stack on one line), a token-grammar taught by one skill (stackable, still a closed set), or a hybrid. Currently leaning token-grammar or hybrid.

### The axes (categories in the table)

| Category | Draft commands | Means |
|---|---|---|
| MODE (loop involvement) | `discuss` / `plan` / `auto` | in the loop (agent asks me) / solo → artifact (I'm out) / just do it |
| WHO | `self` / `sling` | do it here / hand to subagents |
| LIFECYCLE | `sd` / `notify` / `commit` | shutdown when done / ping me / commit when done |
| RELEASE (one-shot) | `execute` / `go` | release the proposal on the table |
| STATUS (return direction) | see evidentiality below | how sure is this content |
| FIRMNESS | `must` / `should` / `may` | how binding (RFC 2119) |

### MODE is loop-involvement, and it is sticky

- `discuss` — **in the loop.** Agent asks *me* questions and converges *with* me. I'm involved. (This very conversation.)
- `plan` — **out of the loop.** Agent runs solo and returns the plan/artifact. I review at the end.
- `auto` — gate off, just do the work.

Sticky "ceiling" = the most the agent may do on its own initiative. `execute` is orthogonal: a one-shot release of the single proposal on the table; afterwards it falls back to the ceiling. So one `execute` never kills the gate for good.

### The execute gate + the doubt rule

Default ceiling for code is **plan**: the agent may read, investigate, answer and propose, but **writes no code until `x:execute`**. The gate sits *above* phrasing — "add function X" becomes "propose adding X, then wait." The gate is **code only**; reading, searching, answering, moving a file stay free (otherwise it is plan-mode with a password, nagging on every side effect).

Top safety rule: **when a stack is contradictory, or the situation is weird/unexpected, do not guess — drop into the loop and ask.** Doubt beats a confident misread. This is what makes `x:auto x:sling x:sd` safe to hand over: "weird" always bounces back to the human.

### `x:frame` — the read-back handshake

A validation gate borrowed from aviation read-back/hearback and Polya's given/unknown: before acting, the agent restates the problem in three parts and **stops** for the human to confirm (or `x:execute`):

- **Given** — the facts I'm working from
- **Asked** — the goal as I understand it
- **Assumptions** — anything I'm inferring that you didn't say ← *the line you actually validate*

Two rules, both load-bearing (proven in Probe #2):

1. **Name unknowns as unknowns.** The Assumptions line must flag under-specified decisions as open questions, not launder them into settled choices — otherwise the frame is a rubber-stamp that looks thorough while deciding for you.
2. **Selective, not mandatory.** Fire on command, or auto-fire only when the agent's own confidence is low (ties to doubt-and-loop). Read-back on every message is friction.

The human doesn't structure the request — the AI structures its understanding and the human audits it. Slots into the flow gate as a front state: `x:frame` → (validate) → `x:execute`. Measured value: **packaging** (a reliable handle for "frame + flag unknowns"), not better comprehension. Ancestor: ACP-125 READ BACK; FIPA `query-if` / `not-understood`.

### Multilingual sourcing — borrow the concept, not the token

Principle: some distinctions are grammaticalized far more clearly in one language than another. Borrow the *distinction* (decide which axis should exist); the token itself can stay short ASCII.

The strongest lead, from Turkish: **evidential past.** Turkish marks whether you witnessed something yourself (**-di**: *gördüm*, "I saw it") vs. reported or inferred it (**-miş**: *görmüş*, "apparently / it is said"). That is exactly the STATUS/confidence axis for AI→AI reporting:

- `x:di` (witnessed) — I verified this myself: I ran it, I read the file.
- `x:mis` (reported/inferred) — I'm inferring or relaying; not verified.

An agent that tags each claim `di` vs. `mis` hands the receiver its confidence for free, with no hedging prose — the compression the AI↔AI lane is after. Other veins to mine: Japanese sentence-final `yo`/`ne` (informing vs. seeking-agreement = reply expectation), hortative moods ("let's"), German modal particles. Concepts to steal, not vocabulary to memorize.

### Measuring it — the anti-snake-oil guard

The risk: this *feels* clever but changes nothing over plain English. To not build snake oil, it must be **falsifiable**.

1. **Baseline vs. treatment.** Same task, given two ways: plain-English ("plan only, don't code, ask if unsure") vs. the `x:` command. If they produce the same behavior, the command adds nothing.
2. **The plumbing constraint (test this first).** A subagent only "obeys `x:plan`" if the table is in *its* context. Spawn a subagent with, and without, the dictionary injected, and see whether the command is understood at all. This decides whether the dictionary must be always-on (a `CLAUDE.md` every agent inherits) rather than an opt-in skill — for the AI↔AI lane it almost certainly must travel with every dispatch.
3. **What to actually measure** (aim where the value plausibly is; don't strawman it):
   - *Obedience* — does the subagent honor the ceiling (no code before `execute`), consistently, across N runs?
   - *Composability* — does stacking (`plan sling sd`) hold together where English gets verbose or ambiguous?
   - *Cost* — tokens spent: is it actually leaner (the "simpler context" claim)?
   - *Misread rate* — on deliberately ambiguous messages, does the marked version misfire less than the unmarked one?
4. **Honest null result.** If a clear English sentence obeys just as well and the only win is brevity, say so — the value is then *compression + stacking + sticky modes*, not "AI understands commands better." Name the real win; cut the parts that don't earn it.

### Probe #1 — result (2026-09-28): null, and why

54 Haiku sub-agents (`general-purpose`), 9 per arm, on one ambiguous task (`average(nums)` crashes on `[]`; prompt "what's going on?"). Obedience scored from the files on disk, not self-report.

| Arm | Signal | Edited file? | Quality |
|---|---|---|---|
| A · bare | *(none)* | 0/9 | 9/9 correct diagnosis |
| B · plain-hold | "don't change anything" | 0/9 | 9/9 |
| C · cmd-hold | `x:plan` + table | 0/9 | 9/9 |
| D · capability | "return 0 on empty" | 9/9 | 9/9 |
| E1 · plain-release | "fix it" | 9/9 | 9/9 reasonable |
| E2 · cmd-release | `x:execute` + table | 9/9 | 9/9 reasonable |

Every arm perfect; the command tied plain English *and* bare. Read straight:

- **The trap didn't spring.** 0/9 bare agents over-acted — a fresh sub-agent handed a question diagnoses by default. No misread for `x:plan` to prevent, so C≈B≈A shows the baseline is clean, not that the command works. The over-action failure lives in *interactive, multi-turn* sessions, not one-shot dispatch. **Wrong arena.**
- **Plumbing works.** C/E2 agents cited the table back ("without modifying files per x:plan", "awaiting x:execute") — a cheap model parsed and obeyed the injected vocabulary.
- **Release ≠ specification.** E1 "fix it" and E2 `x:execute` both acted but split on *what* the fix was (return 0 vs. raise ValueError; E2 was 3 vs 6). Only D, which stated intent, got uniform output. `x:execute` releases *whether* to act, not *what* to do — as designed. A deterministic dispatch must carry the WHAT.
- Matches the compliance literature: models already obey plain instructions; measured gains appear only on *hard* cases. Value, if any, is **compression + stacking + hard-ambiguity**, not single-intent obedience.

Next probe must put the baseline where it *fails*: a harder, action-leaning trap; the interactive-momentum arena; or a direct test of the stacking value.

### Probe #2 — `x:frame` read-back (2026-09-29): packaging, not comprehension

Does a read-back frame *surface hidden ambiguity*, and does `x:frame` beat plain instructions? Six deliberately under-specified requests ("make it faster", "clean it up", "handle weird results", "add error handling", "handle all edge cases", "fix and improve"), all output the same Given/Asked/Assumptions schema (structure held constant), 3 reps each. Haiku framed; **Sonnet judged** whether the frame named a real missing decision or just restated the request.

| Arm | Instruction (structure/token held constant) | Surfaced ambiguity |
|---|---|---|
| PLAIN | "list your assumptions" | **4/18 (22%)** |
| PLAIN_PLUS | "restate **and flag every under-specified decision**" (no `x:`) | **14/18 (78%)** |
| FRAME (`x:frame`) | table: Given/Asked/Assumptions + "name what is unclear" | **16/18 (89%)** |

Read straight:

- **The instruction is the lever, not the token.** Naive framing 22% → flag-unknowns framing 78–89%: a ~3.5× jump. PLAIN_PLUS (a plain sentence, no `x:`) recovers **84% of the gap**. FRAME's extra 11 pts over PLAIN_PLUS is **within noise at N=18** (2 runs; partly 2 agents that misread PLAIN_PLUS and emptied the assumptions field, partly judge jitter). So **`x:frame` ≈ a fair plain instruction; it does not comprehend better.**
- **`x:frame`'s real value is packaging** — a short, reliable handle for "restate + flag every open decision," a behaviour people want repeatedly but rarely type in full, and that the naive "restate the problem" *misses entirely*. A reliability/compression win, not a comprehension one — matching the prior-art verdict (models already comprehend; the win is structure/compression). This validates building it as a command, for the right reason.
- **The failure mode is assumption-laundering.** Naive framing converted open decisions into *settled* ones ("optimize for runtime speed", "standard exception patterns are appropriate") — thorough-looking, but silently deciding for you: the rubber-stamp/hearback trap. **Design law: whatever the command is called, its definition MUST say "name unknowns as unknowns," or the frame backfires.**
- First probe where the baseline *could* fail — and it did (PLAIN 22%), unlike Probe #1's already-perfect baseline. Net thesis across both: the `x:` set is valuable as **reliable handles for behaviours people don't reliably type**, not as a smarter language.

## Open decisions

- **Build form (deferred):** real slash-commands vs. token-grammar vs. hybrid for stacking. Leaning token-grammar/hybrid.
- **Where it lives:** for the AI↔AI lane the table must travel with every dispatch, which argues for always-on (`CLAUDE.md` every agent inherits) over an opt-in skill — confirm with the plumbing test before committing.
- **Which languages to mine** beyond TR/EN, and whether the evidential tokens read `di`/`mis` or `verified`/`inferred`.
- **The exact command set** per axis — the table above is a first draft, not settled.
- **`refs` stays separate.** It shapes agent *output* (numbering paragraphs); this marks *input + status* intent. Opposite directions — cross-link, don't merge. Reply openers (ROGER/WILCO) mostly cut; `CORRECTION` kept.
- **Probe #1 run (2026-09-28): null result** — command tied plain English because the over-action failure didn't occur in one-shot dispatch (see above). Plumbing confirmed; differential value still untested. Next probe needs a setting where the baseline *fails*.
- **Don't reinvent the vocabulary** — align intent commands with KQML/FIPA performatives where they overlap (see [prior-art-vocabularies.md](prior-art-vocabularies.md)); reserve novelty for the parts that are actually new (flow-modes, evidential status, lifecycle, stacking).
- **`x:frame` decided (?12):** the read-back command is `x:frame` (given/asked/assumptions); on-demand + auto-fire-when-unsure, not mandatory; its definition must bake in the flag-unknowns rule (Probe #2).
- **Working thesis:** the vocabulary's value is **packaging** — reliable handles for behaviours people want but don't reliably type — not smarter comprehension (single-intent obedience is already solved). Design and measure accordingly.

## Sources

- [Procedure word — Wikipedia](https://en.wikipedia.org/wiki/Procedure_word)
- [ACP 125 — Wikipedia](https://en.wikipedia.org/wiki/ACP_125), [ACP 125(F) PDF](https://www.navy-radio.com/manuals/acp/acp125f.pdf)
- [inocult/xo PR #14 — ACP 125 persona](https://github.com/inocult/xo/pull/14)
- [LRC-TR: İşletme kelimeleri (eGMDSS)](https://www.egmdss.com/gmdss-courses/mod/page/view.php?id=1888)
- [SRC-TR: VHF Telsiz Sesli Haberleşme Usulleri (eGMDSS)](https://www.egmdss.com/gmdss-courses/mod/page/view.php?id=930)
- [Askeri Telsiz Konuşması Nasıl Yapılır? (telsiz.com.tr)](https://www.telsiz.com.tr/blog/icerik/askeri-telsiz-konusmasi-nasil-yapilir)
- [Conventional Comments](https://conventionalcomments.org)
- [prior-art-vocabularies.md](prior-art-vocabularies.md) — KQML/FIPA-ACL performatives, Searle's classes, and the mapping of our `x:` set onto them
- Measured LLM research: [Implicature 2510.25426](https://arxiv.org/pdf/2510.25426), [Intent comprehension 2506.16584](https://arxiv.org/html/2506.16584v3), [Classic-vs-LLM MAS survey 2509.02515](https://arxiv.org/pdf/2509.02515), [SE ambiguity 2502.13069](https://arxiv.org/html/2502.13069v1), [Reasoning about intent 2511.10453](https://arxiv.org/html/2511.10453v2)

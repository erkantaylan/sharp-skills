# Credits

Skills here are written from scratch and verified against the shipping tools. Where
an existing collection pointed at a topic worth covering, it is credited below — as
a starting point, not as a source of text.

Each entry also records what was wrong with it, because that is usually the reason
the skill exists.

---

### [`github/awesome-copilot`](https://github.com/github/awesome-copilot) — MIT

Pointed at Aspire as worth covering, and its reference layout (a short entry point
plus load-on-demand references) is a good shape.

What did not survive contact with the tools, checked at commit `9ce8148`:

- The CLI section was headed *"Valid commands in Aspire CLI 13.1"* and listed
  `aspire mcp init` and `aspire mcp start`. **Neither command exists.** MCP is
  `aspire agent mcp`; `aspire mcp` is an unrelated feature for MCP servers a
  *resource* exposes.
- It omitted the entire lifecycle surface — `ps`, `stop`, `describe`, `logs`, `otel`,
  `resource`, `wait` — which is most of what the CLI is for.
- Its testing reference taught three things that do not exist:
  `WaitForResourceReadyAsync` (offered as "best practice #1"),
  `<IsAspireTestProject>`, and a single-lambda `CreateAsync` overload with an
  `--exclude-resource` flag. Copied as written, it does not compile.
- It documented `get_integration_docs` as an available MCP tool. Calling it returns
  JSON-RPC `-32601 Unknown tool`.
- It framed Docker Compose as something to be migrated into an AppHost, which is
  wrong for anyone using Aspire for local development and compose for deployment.
- Advice to run `aspire update --self --channel daily` — daily builds of an
  orchestration CLI.
- A Context7 / GitHub-search fallback ladder and 13.1-vs-13.2 version gating, both
  already stale.

### [`microsoft/aspire-skills`](https://github.com/microsoft/aspire-skills) — MIT

First-party, and the `aspire` skill here links to it for breadth rather than copying
it. Five things were verified there and merged in: the `MSB3491`/`CS2012` file-lock
rule, `.WithHttpHealthCheck()` as the `ASPIRE006` remedy, the stale-persistent-volume
password symptom, `WaitForCompletion()` for migration resources, and the
`describe --include-hidden` / `wait --status` / `resource --help` flags. It also
caught a genuine error here: this skill had claimed experimental diagnostics were
`ASPIRE_HOSTINGX_*`, which does not exist — the real shape is `ASPIRE<AREA><NNN>`.

Why it is not simply adopted, checked at commit `27f3b61`:

- **No integration-testing content at all.** `DistributedApplicationTestingBuilder`,
  `Aspire.Hosting.Testing`, `CreateHttpClient`: zero occurrences across 140 files. Its
  router says *"DO NOT USE FOR: ordinary build/test tasks."*
- It says to pair `WithReference()` with `WaitFor()` but never says what happens if
  you don't, so the trap reads as a style preference.
- `targetPort` appears once in the whole repo, uncommented. No analyzer diagnostics
  are documented anywhere.
- `aspire agent mcp` is never named; every MCP path routes through `aspire agent
  init`, which is recommended in six places and which installs a `PostToolUse`
  telemetry hook into the user's agent settings.
- `--format Json` is documented as supported on `describe` and `start` only; in 13.5.2
  it also works on `ps`, `logs`, `otel` and `doctor`. `aspire ls` and every `logs`
  flag are undocumented.
- Roughly a third is Azure/AWS/Kubernetes/TypeScript, and it recommends
  `ContainerLifetime.Persistent` for databases and treats `docker-compose.yml` as an
  AppHost migration source — both wrong for a setup that runs second checkouts and
  deploys with compose.

### [`Aaronontheweb/dotnet-skills`](https://github.com/Aaronontheweb/dotnet-skills) — MIT

Reviewed. Its nullable-reference-types and database-performance material is the best
in that collection and worth revisiting if those topics get covered here.

Not used as written: most of the set is pinned to .NET 8 / C# 12, its Testcontainers
guidance uses the 2.x API obsoleted in 2023, and several skills contradict each other
(one forbids `AddServiceDiscovery()` in app projects, another mandates it).

### [`wshobson/agents`](https://github.com/wshobson/agents) — MIT

Reviewed. Its `operating-kit` agents are properly tool-scoped and specific, unlike
most of the catalogue — worth revisiting if agents get added here.

Not used as written: of 202 agent files there are 144 distinct bodies, 72% contain no
code, and 52% contain no trade-off or failure-mode reasoning anywhere.

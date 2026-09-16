---
name: aspire
description: Use when running, debugging, or testing an Aspire distributed application — the CLI lifecycle (ps/stop/describe/logs/otel/resource/wait), why a resource cannot reach its dependency, and how Aspire relates to an existing Docker Compose setup.
---

# Aspire

Verified against **Aspire CLI 13.5.2**. This covers what is easy to get wrong, not
what Aspire is.

| Reference | Load when |
|---|---|
| [Wiring](references/wiring.md) | A service cannot find or reach another one |
| [Testing](references/testing.md) | Writing integration tests that boot the AppHost |

---

## Aspire is local dev; compose is deployment

They are not alternatives and there is no migration between them. A repo that runs
`aspire run` locally and ships hand-written compose files is in its intended
configuration — **do not rewrite either one to match the other**, and do not read a
`docker-compose.yml` as an AppHost waiting to happen.

Running both at once means two copies of the same services fighting over ports and
databases. Bring one down first.

---

## The CLI owns the lifecycle

Never grep for stray processes or `kill` a PID — there are commands for this, and
they are easy to miss:

```bash
aspire ps                          # what is running, machine-wide
aspire stop [--all] [--force]      # --force also clears persistent resources
aspire run [--detach]              # --detach, or `aspire start`, for background

aspire describe [resource]         # state, health, URLs
aspire logs <resource> --tail 100 --search "timeout"
aspire otel traces <resource>      # also: otel logs, otel spans
aspire resource <resource> restart # also: stop, start, rebuild
aspire wait <resource>             # block until it reaches its target state
```

`ps`, `logs`, `describe`, `otel` and `doctor` all take `--format Json`:

```bash
aspire describe api --format Json | jq -r '.endpoints[0].url'
aspire describe --include-hidden        # proxies, helper containers, migration jobs
aspire wait api --status up --timeout 60
aspire resource api --help              # which commands this resource supports
```

`aspire ps` first, always: a stale AppHost from an earlier session holds ports, and
`aspire run` kills it silently rather than warning you.

`aspire resource <name> rebuild` recompiles and restarts **one** service. Prefer it
to restarting a stack whose entry point waits on everything.

---

## MCP server

Skip it. `aspire agent mcp` starts one, but every tool it exposes has a better CLI
equivalent — `list_resources` → `aspire describe --format Json`, `list_console_logs`
→ `aspire logs --search`, `list_traces` → `aspire otel traces`,
`execute_resource_command` → `aspire resource <name> <command>` — and the CLI gives
targeted output instead of a 61 KB resource dump or a 112 KB `list_docs` response.

**Do not run `aspire agent init`.** It writes no MCP config. It installs a global
`PostToolUse` telemetry hook into your agent's settings file, firing on every tool
call, and ignores `--workspace-root` when doing it.

---

## Gotchas worth knowing

- **`.WaitFor()` is not implied by `.WithReference()`.** A consumer that reads its
  dependency's address once at startup comes up with an empty address list and then
  fails silently forever. See [Wiring](references/wiring.md).
- **`ASPIRE006`** means you wrote `.WaitFor()` on a resource that has no health check.
- **Experimental-API diagnostics are `ASPIRE<AREA><NNN>`** — `ASPIRECOMPUTE002`,
  `ASPIREINTERACTION001`, `ASPIREJAVASCRIPT001`. The areas get renamed between
  releases (13.3 renamed `ASPIREEXTENSION001` to `ASPIREJAVASCRIPT001`), so read the
  code the compiler gives you rather than looking it up.
- **Ports are per-run** unless pinned. Nothing should hardcode one, including test
  fixtures and sibling services' settings files.
- **`MSB3491` or `CS2012` on a project that built fine yesterday means the AppHost is
  running and holding a lock on its output assemblies.** Stop the AppHost. Do not
  report a permanent build failure, do not delete `bin/`/`obj/`, and do not `pkill
  dotnet`.

---

## Going deeper

Microsoft publishes [`microsoft/aspire-skills`](https://github.com/microsoft/aspire-skills)
— six skills covering `aspire init` scaffolding, wiring an unwired AppHost, deployment
to Azure/AWS/Kubernetes, and per-release breaking-change notes. Most of it is breadth
we do not need, but investigate it directly when you need that breadth; its
`skills/aspire/references/aspire-13-*-breaking-changes.md` files are the best record
of API renames and experimental diagnostic IDs per release.

Two things it says that do **not** apply here: it treats `docker-compose.yml` as a
migration source for an AppHost, and it recommends `ContainerLifetime.Persistent` for
databases. See the scope section above and [Wiring](references/wiring.md).

It also recommends `aspire agent init` in several places. Don't — see above.

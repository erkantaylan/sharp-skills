# Upstream documentation errata

Errors found in third-party documentation while writing these skills. Kept here so a skill can
cite the correct value and say why another source is wrong, and so we can decide separately
whether to report each one upstream.

---

## Blazor metrics: `metrics/blazor.md` reference page has stale preview-era instrument names

**Found:** 2026-09-17 · **Status:** not reported upstream · **Affects:** `skills/blazor-server`

Microsoft Learn's [Blazor (Components) metrics](https://learn.microsoft.com/en-us/aspnet/core/metrics/blazor?view=aspnetcore-10.0)
reference page documents instrument names that were **renamed before .NET 10 GA** and no longer
exist. The [Blazor performance](https://learn.microsoft.com/en-us/aspnet/core/blazor/performance/?view=aspnetcore-10.0)
page has the correct names.

Verified against shipped source, not docs — `v10.0.0` and `main` are identical:
[`ComponentsMetrics.cs`](https://github.com/dotnet/aspnetcore/blob/v10.0.0/src/Components/Components/src/ComponentsMetrics.cs#L40-L67),
[`CircuitMetrics.cs`](https://github.com/dotnet/aspnetcore/blob/v10.0.0/src/Components/Server/src/Circuits/CircuitMetrics.cs#L25-L39).

| Reference page (wrong) | Actual name in source | Type | Unit |
|---|---|---|---|
| `aspnetcore.components.navigation` | `aspnetcore.components.navigate` | Counter\<long\> | `{route}` |
| `aspnetcore.components.event_handler` | `aspnetcore.components.handle_event.duration` | Histogram\<double\> | `s` |
| `aspnetcore.components.update_parameters` | `aspnetcore.components.update_parameters.duration` | Histogram\<double\> | `s` |
| `aspnetcore.components.render_diff` | `aspnetcore.components.render_diff.duration` | Histogram\<double\> | `s` |
| *claimed to be the attribute `aspnetcore.components.diff.length`* | `aspnetcore.components.render_diff.size` — a real instrument; `diff.length` is not a tag anywhere in the repo (0 hits) | Histogram\<int\> | `{elements}` |
| `aspnetcore.components.circuit.active` / `.connected` / `.duration` | same — correct | UpDownCounter / Histogram | `{circuit}` / `s` |

Two further reference-page errors: the event attribute is `code.function.name`, not
`aspnetcore.components.method`; and `error.type` is listed on the navigation counter, which never
adds it.

**Provenance.** dotnet/aspnetcore **#62754** (2025-07-17) did all four renames, added
`render_diff.size`, and deleted the `diff.length` tag. The docs text landed via AspNetCore.Docs
**#35698** two days *earlier*, so it was stale on arrival. The performance page was corrected by
**#35772**; the reference text never was, and was carried forward verbatim through the page split
(**#37421**) and the move to `aspnetcore/metrics/blazor.md` (**#37547**). Both `v10.0.0` and `main`
carry the post-rename names, so there is no .NET 10 / .NET 11 moniker split.

**Why it matters:** querying a non-existent instrument returns no data and no error. A dashboard
built from the reference page looks wired up and is empty.

**Correct names to use in the skill:** the ones in the "Actual name in source" column above.
Also note for `skills/blazor-server` that issue 856 (Mercury) advises "trust the reference page" —
that guidance is backwards and should be corrected there too.

**Prior art:** none. No open or closed issue/PR on dotnet/AspNetCore.Docs reports this.

**Filing route:** `.github/ISSUE_TEMPLATE/doc-issue.md` says *not* to use that form for ASP.NET Core
articles — use the "Open a documentation issue" link at the foot of the published page.
`CONTRIBUTING.md` permits a direct PR to `main` for simple corrections; CLA at
cla.dotnetfoundation.org. A PR against `aspnetcore/metrics/blazor.md` is the faster route.
Draft issue + patch (`git apply --check` clean): session scratchpad `docsissue/`.

**Also noted:** the performance page's AOT section is WebAssembly-only, and at 549 words that page
is an index node — the real guidance (`ShouldRender`, `@key`, `Virtualize`) is in the child
articles under `blazor/performance/`.

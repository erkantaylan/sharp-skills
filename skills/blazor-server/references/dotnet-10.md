# .NET 10 deltas

Verified against **.NET 10** (SDK 10.0.111, ASP.NET Core 10.0.11). API names, defaults and the
instrument names below are read from the shipped source at tag `v10.0.0`, not from the docs — see
the warning under *Metrics* for why that distinction earns its keep here.

## `<NotFound>` is obsolete, and two different things replace it

`Router`'s `<NotFound>` render fragment carries
`[Obsolete("NotFound is deprecated. Use NotFoundPage instead.")]`. It is **not removed**: the router
still renders it as a fallback when `NotFoundPage` is unset, and the `[Obsolete]` has no
`DiagnosticId`, so an upgrade produces CS0618 — a warning, not a build failure, unless warnings are
errors. Setting both parameters throws `InvalidOperationException`. Microsoft's prose says the
fragment "isn't supported" in .NET 10, but no breaking-change entry was published for it.

In a Blazor Web App the fragment was already inert on .NET 8 and 9 — accepted without error, never
effective — so there the upgrade puts a warning on markup that was already dead. In a standalone
WebAssembly app the fragment is genuinely effective, so the same warning marks live markup that
has to be replaced rather than deleted.

Two replacements, because "not found" is two different problems.

**No route matched the URL.** Middleware, so it sets a real 404 whatever the render mode:

```csharp
app.UseStatusCodePagesWithReExecute("/not-found", createScopeForStatusCodePages: true);
```

`createScopeForStatusCodePages` is new in .NET 10 and defaults to `false`. It swaps
`HttpContext.RequestServices` for a fresh scope while the not-found path re-executes, so that page
does not inherit a scoped service the failed request already consumed or faulted — a `DbContext` left
in a broken state being the usual one. The .NET 10 Blazor Web App template passes `true`.

**The route matched but the entity does not exist.** A component concern:

```razor
<Router AppAssembly="@typeof(Program).Assembly" NotFoundPage="typeof(Pages.NotFound)">
```

`NavigationManager.NotFound()` triggers it from component code and **does not terminate the calling
method** — put a `return` after it. The status behaviour is three-way, not two: static SSR sets 404;
the prerender pass of an interactive component sets 404; once the component is interactive, or if
`prerender: false`, Not Found content renders at **HTTP 200** and no status is ever set. An app with
prerendering off globally therefore answers 200 for every missing entity, and the component's own UI
has to say so. Returning 200 for unknown URLs is also what makes an app invisible to uptime monitors
and link checkers — which is what the middleware above exists to fix.

## Metrics and tracing

Ten additive lines, replacing a hand-written `CircuitHandler`:

```csharp
builder.Services.ConfigureOpenTelemetryMeterProvider(m =>
{
    m.AddMeter("Microsoft.AspNetCore.Components");
    m.AddMeter("Microsoft.AspNetCore.Components.Lifecycle");
    m.AddMeter("Microsoft.AspNetCore.Components.Server.Circuits");
});
builder.Services.ConfigureOpenTelemetryTracerProvider(t =>
{
    t.AddSource("Microsoft.AspNetCore.Components");
    t.AddSource("Microsoft.AspNetCore.Components.Server.Circuits");
});
```

| Instrument | Type | Unit | Meter |
|---|---|---|---|
| `aspnetcore.components.navigate` | Counter\<long\> | `{route}` | `…Components` |
| `aspnetcore.components.handle_event.duration` | Histogram\<double\> | `s` | `…Components` |
| `aspnetcore.components.update_parameters.duration` | Histogram\<double\> | `s` | `…Lifecycle` |
| `aspnetcore.components.render_diff.duration` | Histogram\<double\> | `s` | `…Lifecycle` |
| `aspnetcore.components.render_diff.size` | Histogram\<int\> | `{elements}` | `…Lifecycle` |
| `aspnetcore.components.circuit.active` | UpDownCounter\<long\> | `{circuit}` | `…Server.Circuits` |
| `aspnetcore.components.circuit.connected` | UpDownCounter\<long\> | `{circuit}` | `…Server.Circuits` |
| `aspnetcore.components.circuit.duration` | Histogram\<double\> | `s` | `…Server.Circuits` |

Tags: `aspnetcore.components.type`, `.route`, `.attribute.name`, `code.function.name`, `error.type`.
Circuit instruments carry none. Activities: `…Components.StartCircuit`, `.Navigate`, `.HandleEvent`.

> **The `/metrics/blazor` reference page on Microsoft Learn is wrong.** It documents pre-GA names —
> `navigation`, `event_handler`, `update_parameters`, `render_diff` — and claims batch size is an
> attribute called `aspnetcore.components.diff.length`. aspnetcore#62754 renamed all four and deleted
> that tag before GA; `diff.length` exists nowhere in the ASP.NET Core source. The *performance* page
> has the correct names. Querying an instrument name that does not exist returns no data and no
> error, so a dashboard built from the reference page looks wired up and is permanently empty.
> Confirm with `dotnet-counters` rather than trusting either page.

Two readings worth alerting on: `circuit.active` − `circuit.connected` is the disconnected-circuit
backlog, which is what predicts an OOM; `render_diff.size` bucketed quantifies over-rendering.

## Validation for nested models

`AddValidation()` (`Microsoft.Extensions.DependencyInjection`, assembly
`Microsoft.Extensions.Validation`) with `[ValidatableType]` (namespace
`Microsoft.Extensions.Validation` — the two need different `using`s) validates nested objects and
collections, which DataAnnotations alone never did.

**The model types must live in `.cs` files, not in a `.razor` file.** This feature and the Razor
compiler are both source generators, and one generator's output cannot be another's input. Miss it
and nothing announces the problem: validation silently falls back to pre-.NET 10 behaviour —
top-level DataAnnotations only — and the nested members go unchecked while the form still appears to
validate.

## Circuit pause and resume

`[PersistentState]` with `Blazor.pauseCircuit()` / `Blazor.resumeCircuit()` lets a circuit survive
disconnection, tab throttling and a deliberate pause. Two limits.

**It is not a substitute for `<ErrorBoundary>`.** Persistence addresses disconnection, not faults. An
unhandled exception is still fatal to the circuit and the only way back is a page reload.

**Only one persistence path is protected.** State saved *to the client* goes through
`ProtectedPrerenderComponentApplicationStore` and is Data-Protection protected. State saved through
an `ICircuitPersistenceProvider` — in-memory, or `HybridCache` over Redis — is handed to the provider
raw. With Redis, confidentiality is entirely the backing store's problem: TLS and encryption at rest
are yours to configure.

## Navigation behaviour changes

- `NavLink Match="NavLinkMatch.All"` now ignores query string and fragment. The `AppContext` switch
  `Microsoft.AspNetCore.Components.Routing.NavLink.EnableMatchAllForQueryStringAndFragment` restores
  the old behaviour; `ShouldMatch` is now `protected virtual`, which is the cleaner escape hatch.
  Audit every `Match="All"` on upgrade.
- `NavigateTo` no longer scrolls to the top on same-page navigation, so changing a query string or
  fragment no longer resets the viewport.

## Static assets (.NET 9, commonly skipped)

`MapStaticAssets`, `@Assets[...]` and `<ImportMap />` shipped in **.NET 9**, not 10. The Blazor
script is a static web asset, so `<script src="@Assets["_framework/blazor.web.js"]">` gets
fingerprinting and compression that a hardcoded path does not.

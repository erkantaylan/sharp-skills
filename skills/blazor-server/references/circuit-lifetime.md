# Circuit lifetime, reconnection and errors

Verified against .NET 10 (ASP.NET Core 10.0.11).

`CircuitOptions` defaults: `DisconnectedCircuitRetentionPeriod` `00:03:00` ·
`DisconnectedCircuitMaxRetained` `100` · `JSInteropDefaultCallTimeout` `00:01:00` ·
`MaxBufferedUnacknowledgedRenderBatches` `10` · `DetailedErrors` `false` ·
`PersistedCircuitInMemoryRetentionPeriod` `02:00:00` ·
`PersistedCircuitDistributedRetentionPeriod` `08:00:00`.

A dropped connection keeps the circuit — every component instance, field and DI scope — in server
memory for three minutes; reconnect inside that window and the page is exactly as the user left it
(which is why tab-away/back preserves state for free). Miss it and all state is gone and the client
must reload. Nothing is persisted client-side, so scale-out needs sticky sessions.

The circuit renders at the client's pace, not the server's. `RemoteRenderer.ProcessPendingRender`
returns without rendering while `MaxBufferedUnacknowledgedRenderBatches` batches are outstanding, so
the server stops producing batches until the browser acknowledges one. The only signal is a
`Debug`-level log, event id 107, `"The queue of unacknowledged render batches is full."` A user on a
bad connection therefore sees a **frozen** UI rather than a slow one: events still dispatch, handlers
still run and state still mutates, but nothing renders until a slot frees. Raising the limit buys
latency tolerance at the price of holding that many serialized batches per circuit in memory.

`DetailedErrors = true` sends the terminating exception to the browser console instead of the
generic line; without it in staging, circuit crashes are nearly undiagnosable, with it in
production you leak stack traces — read the value the deployed environment actually supplies
(container env vars, orchestrator config, `appsettings.Production.json`), not only
`appsettings.Development.json`.

Data Protection is a hidden dependency of three circuit features at once: cookie authentication,
persisted circuit state and `ProtectedLocalStorage`. Left unconfigured the key ring falls back to a
location a container does not persist, so keys are regenerated on every restart and all three fail
together — cookies rejected, persisted state undecryptable, stored values throwing
`CryptographicException`. Configure persistent key storage and `SetApplicationName`; the latter also
decides whether two replicas can read each other's payloads at all.

The client reveals `#blazor-error-ui` by setting `style.display = "block"`, so that element must
exist in the host page and the stylesheet must default it to `display: none`. Reconnection UI runs
off `components-reconnect-*` classes on `#components-reconnect-modal`; .NET 10 injects a default if
you supply none. An unhandled exception anywhere kills the whole circuit, not just the component —
wrap risky subtrees in `<ErrorBoundary>`. And since the transport *is* SignalR,
`AddSignalR(o => …)` configures the circuit hub too: scope sizing with
`AddInteractiveServerComponents().AddHubOptions(…)` or `AddHubOptions<THub>(…)`, never globally.

That limit is also a hard ceiling on interop payloads. `RemoteJSRuntime.ReceiveByteArray` accumulates
bytes across a single call and throws `ArgumentOutOfRangeException: Exceeded the maximum byte array
transfer limit for a call.` once the total would pass `MaximumReceiveMessageSize` — **32 KB by
default**. A `[JSInvokable]` taking `byte[]`, or any JS-to-.NET return of binary data, works on test
fixtures and fails the first time a real payload arrives. The counter charges `Math.Max(4, length)`
per array, so many small arrays in one call trip it too. Either raise the limit for the circuit hub,
or move the payload to `IJSStreamReference` / `DotNetStreamReference`, which chunk beneath it and are
bounded by `JSInteropDefaultCallTimeout` instead.


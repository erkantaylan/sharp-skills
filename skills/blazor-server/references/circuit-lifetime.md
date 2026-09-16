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

`DetailedErrors = true` sends the terminating exception to the browser console instead of the
generic line; without it in staging, circuit crashes are nearly undiagnosable, with it in
production you leak stack traces — check what the deployed compose/env sets, not only
`appsettings.Development.json`.

The client reveals `#blazor-error-ui` by setting `style.display = "block"`, so that element must
exist in the host page and the stylesheet must default it to `display: none`. Reconnection UI runs
off `components-reconnect-*` classes on `#components-reconnect-modal`; .NET 10 injects a default if
you supply none. An unhandled exception anywhere kills the whole circuit, not just the component —
wrap risky subtrees in `<ErrorBoundary>`. And since the transport *is* SignalR,
`AddSignalR(o => …)` configures the circuit hub too: scope sizing with
`AddInteractiveServerComponents().AddHubOptions(…)` or `AddHubOptions<THub>(…)`, never globally.


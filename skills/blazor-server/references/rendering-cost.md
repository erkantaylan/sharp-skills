# Render cost on a circuit

Verified against .NET 10 (ASP.NET Core 10.0.11); mechanisms read from the shipped source at tag
`v10.0.0`. On a circuit a render is a serialized diff, a network round-trip and an acknowledgement,
so render count is a latency and memory budget rather than a CPU one. See
[Circuit lifetime](circuit-lifetime.md) for the batch queue these costs accumulate in.

## An async event handler renders twice

`ComponentBase`'s `IHandleEvent.HandleEventAsync` calls `StateHasChanged()` the moment your handler
returns its `Task`, then awaits that task and calls it **again** on completion. Every `async` handler
therefore produces two render batches and two round-trips: one showing pre-await state, one showing
the result. That is where "the list flashes empty, then fills" comes from, and why setting a spinner
field inside a handler works without an explicit render call.

Suppress both by implementing the interface yourself:

```csharp
Task IHandleEvent.HandleEventAsync(EventCallbackWorkItem callback, object? arg)
    => callback.InvokeAsync(arg);
```

The cost is that exceptions from the handler no longer reach `<ErrorBoundary>` — route them through
`DispatchExceptionAsync` if you take this, or you have traded two renders for a silent failure. A
grid whose per-row handlers are all `async` spends two batches on every row interaction.

## `MayHaveChanged` treats far fewer types as immutable than the guidance implies

Published guidance says to use "immutable types, such as `string`, `int`, `bool`, `DateTime`" so a
child subtree can be skipped. The actual predicate is `ChangeDetection.IsKnownImmutableType`:
`Type.GetTypeCode(type) != TypeCode.Object`, plus exactly `Guid`, `DateOnly`, `TimeOnly` and
`IEventCallback`.

Everything else is `TypeCode.Object` and **always** reports changed — `DateTimeOffset`, `TimeSpan`,
`Uri`, every `record`, every value tuple. A `[Parameter] public TimeSpan Duration` looks primitive,
defeats the optimization completely, and re-renders that child on every parent render for the life of
the app. Nothing reports it. It is found by reading the predicate, not by profiling.

## `<CascadingValue IsFixed="true">` wherever the value cannot change

A non-fixed cascade registers every descendant `[CascadingParameter]` in a `HashSet<ComponentState>`
and notifies each one on every value change — materially more expensive than a plain `[Parameter]`,
and the subscriber list lives as long as the circuit. Set `IsFixed="true"` whenever the value
genuinely cannot change; `<CascadingValue Value="this" IsFixed="true">` is the common case.

It cannot be toggled. `CascadingValue<T>.SetParametersAsync` throws `InvalidOperationException: The
value of IsFixed cannot be changed dynamically.` when it differs from the previous render. That is an
unhandled render exception, so binding `IsFixed` to a field that flips mid-session kills the circuit,
not the component.

## `Virtualize` is a round-trip per scroll, and its exceptions are fatal

`Virtualize<TItem>` drives itself from a JS `IntersectionObserver` on spacer elements, so every scroll
notification is an inbound SignalR message, an `ItemsProvider` call and an outbound batch. Fed
straight from a database that is one query per scroll tick, issued on the dispatcher.

Defaults that decide the behaviour: `ItemSize` 50f, `OverscanCount` 3 (applied above *and* below).
`ItemSize` wrong relative to real row height makes the component request the wrong window and thrash.

The exception path is what bites. A throw from your `ItemsProvider` is not returned to the caller —
it is cached and rethrown from `BuildRenderTree`, making it an unhandled render exception. A transient
database timeout inside one list therefore terminates the whole circuit unless an `<ErrorBoundary>`
sits above it.

Framework code is narrower here than the disposal rule in the main skill: `VirtualizeJsInterop`
catches `JSDisconnectedException` only — not `ObjectDisposedException`, not `JSException`.

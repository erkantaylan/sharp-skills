---
name: blazor-server
description: Use when writing or debugging Blazor Server / InteractiveServer components — circuit-scoped DI and DbContext, StateHasChanged off the dispatcher, timer and event-handler leaks, prerendering, JS interop during disposal, reconnection and circuit lifetime.
---

# Blazor Server

Traps that compile, pass review, work on localhost, then corrupt data or leak memory in production.
Verified against **.NET 10** (ASP.NET Core 10.0.11); exception text and option defaults are quoted
from the shipped assemblies.

| Reference | Load when |
|---|---|
| [Circuit lifetime](references/circuit-lifetime.md) | Reconnection, retention windows, `CircuitOptions`, error and reconnect UI, SignalR sizing |
| [Render cost](references/rendering-cost.md) | Too many renders, double renders, `MayHaveChanged`, cascading values, `Virtualize` |
| [.NET 10 deltas](references/dotnet-10.md) | Upgrading, `<NotFound>` removal, real 404s, built-in metrics and tracing, nested-model validation, circuit pause/resume |

## A DI scope is the circuit, not a request

Highest-cost mistake, and the wrong code is what you would write in MVC:

```razor
@inject AppDbContext Db     @* ❌ one DbContext for the user's entire session *@
```

The scope opens with the circuit and closes minutes or hours later, spanning every page the user
visits. `DbContext` is not thread-safe and concurrent renders share it, so you get, at random,
`InvalidOperationException: A second operation was started on this context instance…` — plus a
change tracker that never forgets an entity and serves stale data from its identity map.

```csharp
builder.Services.AddDbContextFactory<AppDbContext>(o => o.UseNpgsql(cs));   // Program.cs
[Inject] public required IDbContextFactory<AppDbContext> DbFactory { get; set; }
await using var db = await DbFactory.CreateDbContextAsync(ct);   // one per operation
```

**Do not also register `AddScoped<AppDbContext>` for convenience** — that makes the broken
`@inject` resolve instead of failing at startup. Same reasoning for anything scoped holding mutable
state or an unsynchronised connection; `OwningComponentBase<T>` gives one component its own scope,
disposed with the component, when per-page really is the right lifetime.

The same arithmetic catches `new HttpClient()` in a scoped service's constructor: one client, one
handler and one connection pool **per circuit**, none of them disposed, all of them holding sockets
and cached DNS for as long as the user keeps the tab open. Take `IHttpClientFactory` or a typed
client, whose handlers are pooled and rotated independently of the circuit.

## Everything that renders must be on the renderer's dispatcher

`Renderer.AddToRenderQueue` calls `Dispatcher.AssertAccess()` before anything else:
`InvalidOperationException: The current thread is not associated with the Dispatcher. Use
InvokeAsync() to switch execution to the Dispatcher when triggering rendering or component state.`

You are off it whenever the continuation did not come from the renderer: a timer callback, a
`BackgroundService`, a SignalR client callback, an event raised by a singleton.

**A `DelegatingHandler` or a Polly retry pipeline does not put you off it**, however much it looks
like it should. `await` captures `SynchronizationContext.Current` in the *awaiting* method; a
callee's `ConfigureAwait(false)` cannot reach into the caller's state machine. Measured on a live
circuit: the handler exits with `SyncCtx=null` on a different thread and the component still resumes
on `RendererSynchronizationContext`, with bare `StateHasChanged()` working. The thread id does
change — it changes across a plain `HttpClient` call with no handler at all — but the dispatcher is
context-affine, not thread-affine. Never promote "the thread moved" into "the dispatcher is gone".

What *does* lose it is **`ConfigureAwait(false)` on an await in your own component method**. After
that, bare `StateHasChanged()` throws, and `await InvokeAsync(...)` does not restore the context for
the remainder of the method — the next bare `StateHasChanged()` terminates the circuit.

```csharp
private async void OnFeedChanged(Snapshot s)          // raised by a singleton, pool thread
{
    items = s.Items;
    await InvokeAsync(StateHasChanged);               // ✅ marshal, then render
}
```

- Mutating fields off-dispatcher is a data race too. Marshal the whole update, not just the render.
- **Never call a UI service off-dispatcher.** Toast/dialog/notification services mutate a provider
  component; awaiting one from a pool thread renders nothing and may never return. Decouple: a
  circuit-scoped queue anyone may call synchronously, plus a renderless relay component in the
  layout that subscribes and does `_ = InvokeAsync(async () => { try { … } catch { } })`. The `try`
  goes *inside* the marshalled body — the discarded task observes nothing.
- **Getting onto the dispatcher is half of it; not holding it is the other half.** The dispatcher is
  one logical queue per circuit, so anything synchronous and slow in a handler — building a
  spreadsheet, hashing a file, a CPU-bound loop — blocks rendering *and* event handling for that user
  until it returns. It never shows up as an exception, only as a page that has stopped responding.
  Push CPU-bound work to `Task.Run` and marshal the result back, and move file generation to a real
  endpoint (`MapGet` + `Results.File`) instead of producing bytes on the circuit and pushing them
  through interop — which also sidesteps the byte-array ceiling in
  [Circuit lifetime](references/circuit-lifetime.md).
- Mirror image: `StateHasChanged` from an **already-disposed** component neither throws nor warns —
  `AddToRenderQueue` calls `GetOptionalComponentState`, gets null, drops the render. Never conclude
  from "no error" that a teardown-time handler did not fire, and re-check a `disposed` flag *inside*
  the marshalled body: the component can die between the raise and the hop.

## Subscribe and arm timers before the first await

```csharp
protected override async Task OnInitializedAsync()
{
    Feed.Changed += OnChanged;               // ✅ above every await
    timer = new Timer(Tick, null, 0, 500);   // ❌ below it: Dispose already ran, nothing removes it
    data = await Api.LoadAsync();            // component can be disposed while this is in flight
}
public void Dispose() { disposed = true; Feed.Changed -= OnChanged; timer?.Dispose(); }

private void StartPolling()                  // when arming genuinely must follow the await:
{ if (disposed || isPolling) return; … }     // ✅ check the flag Dispose set
```

Blazor disposes a component whose `OnInitializedAsync` task is still pending when the user
navigates away: `Dispose` runs first and unsubscribes nothing, then the continuation subscribes to
a **singleton's** invocation list and starts a timer nothing will ever remove. Since circuits
outlive requests, that handler pins the dead circuit's whole object graph — component, DI scope,
DbContexts, cached DTOs — for the process lifetime. Silent by construction; visible only as a slow
memory ramp. Same for any `Start*()` reached from an API callback.

`new Timer(async _ => ...)` binds an async lambda to the void-returning `TimerCallback`, so it is
`async void`: an exception after its first await is unhandled on a pool thread and takes the
process down. Wrap every timer body in try/catch. Worth a static test flagging `+=` and timer
construction after the first `await` in a lifecycle method — inline `@code` blocks included.

## The Router reuses the component across route parameter changes

`/orders/5` → `/orders/7` does not build a new component. The Router keeps the instance, pushes the
new parameter and re-renders — so `OnInitialized(Async)`, which runs once per instance, never fires
again and the page keeps showing the record it loaded the first time, under the new URL. Nothing
throws. The data is simply wrong and the address bar disagrees with it.

```csharp
protected override async Task OnParametersSetAsync()
{
    if (loadedId == Id) return;              // ✅ without this, every parent re-render refetches
    loadedId = Id;
    order = await Api.GetOrderAsync(Id, ct);
}
```

The guard is not optional: `OnParametersSetAsync` runs on **every** parameter change, including ones
unrelated to the id, so an unguarded load turns one page view into an unbounded number of queries.
A route with two parameters — `/orders/{id}/lines/{lineId}` — has this shape twice, and the
half-fixed version guards one in `OnParametersSetAsync` while still loading the other in
`OnInitializedAsync`, so that one goes stale from the second navigation on.

## Prerendering

With prerendering **on** (the default), `OnInitialized(Async)` and `OnParametersSetAsync` run
**twice** — once on the static SSR pass, once when the circuit starts and the component is rebuilt
from scratch — and field state does not carry over, so a POST, a counter or an audit row does not
belong there. Carry the SSR result across with `[PersistentState]` /
`PersistentComponentState.PersistAsJson` + `TryTakeFromJson`, move the side effect to
`OnAfterRenderAsync(firstRender)` which never runs during prerender, or turn it off (on
`<HeadOutlet>` too, or the head renders twice — and the app then returns nothing to plain `curl`):

```razor
<Routes @rendermode="@(new InteractiveServerRenderMode(prerender: false))" />
```

`IJSRuntime` injects during prerender but is unusable: `InvalidOperationException: JavaScript
interop calls cannot be issued at this time. This is because the component is being statically
rendered…` So `localStorage`, cookies, viewport and time zone are `OnAfterRenderAsync(firstRender)`
concerns, and `NavigationManager.NavigateTo` has its own variant. Branch on
`RendererInfo.IsInteractive` rather than catching.

## Disposal races around JS interop

`OnAfterRenderAsync` schedules interop that completes one or more round-trips later. If the
component is disposed inside that window — usual shape: *an event on the page, then a navigation a
beat later* — the interop resumes against a dead component and the unhandled exception **terminates
the whole circuit**: `ObjectDisposedException: '…JSInterop.Implementation.JSObjectReference'`,
`JSDisconnectedException: … the circuit has disconnected and is being disposed.`, or a `JSException`
from JS that ran against a node Blazor already removed. The window is about one RTT:
near-unreproducible on localhost, routine over real latency.

```csharp
public async ValueTask DisposeAsync()
{
    try { if (module is not null) await module.DisposeAsync(); }
    catch (JSDisconnectedException) { }   // typed, not a blanket catch
    catch (ObjectDisposedException) { }
}
```

When a third-party component re-arms interop every render with no guard of its own, subclass it and
override `OnAfterRenderAsync` to swallow exactly those shapes — narrowly, so real JS bugs still
propagate. The race lives in the after-render path, so per-page fixes cannot reach it.

## HttpContext and auth do not flow the way they look like they do

`HttpContext` exists only for the request that establishes the circuit; afterwards there is none
and `IHttpContextAccessor` returns null or a stale context, with no error. Capture user id, tenant
and culture during that first request into a circuit-scoped service. Consequence: **an
`IHttpClientFactory` `DelegatingHandler` cannot reach the circuit** — handlers resolve in the
factory's own DI scope, where JS interop throws and `localStorage` is unreachable. Attach the token
imperatively instead (`client.DefaultRequestHeaders.Authorization = new("Bearer", token)`). A
token-refresh timer fires off-dispatcher and `NotifyAuthenticationStateChanged` ends in a render, so
marshal it, and skip it when the principal is unchanged.

`@attribute [Authorize]` on a **routable** component becomes endpoint authorization metadata under
`MapRazorComponents`. Without authentication middleware every request to that page 500s:
`InvalidOperationException: Endpoint … contains authorization metadata, but a middleware was not
found that supports authorization.` When the app authenticates inside the circuit rather than via
cookies, gate with `<AuthorizeView>` and leave the attribute off. `app.UseAntiforgery()` is
required for the same endpoint-metadata reason.

**Authentication cookies cannot be written from a component.** A component renders after the
response headers are flushed, so `SignInAsync`/`SignOutAsync` from a lifecycle method throws or
silently does nothing. Login and logout are real HTTP endpoints — a `Logout.razor` that appears to
work is usually clearing state nothing else reads.

## `ProtectedLocalStorage` is not a place for a credential

The default purpose is `$"{GetType().FullName}:{_storeName}:{key}"` — type name, store name, key.
**No user identity anywhere in it**, so every user's ciphertext is decryptable by the same protector:
exfiltrate a blob, replay it from another browser, and the server decrypts it for you. It defeats a
user reading their own `localStorage`; it does not defeat the XSS that is the actual threat. Keep it
for a theme preference or a cache, and pass an explicit purpose containing the user id whenever the
value is per-user at all.

`GetAsync` returns `Success = false` **only when the key is absent**. Undecryptable data — a rotated
key ring, a value from another app — reaches `protector.Unprotect` with no catch around it and
throws `CryptographicException` out of the call. Every read needs a `try`, not a `Success` check.

## Smaller ones

- **Render volume is a circuit cost** — every node in a batch is serialized and server-diffed.
  Thousands in one render stalls the circuit; page the data, keep big catalogs `static`. The same
  applies per event: `@onmousemove`, `@onscroll` and an unthrottled `@bind:event="oninput"` each fire
  tens to hundreds of times a second, and every one is a SignalR message plus a render. Throttle in
  JS and call back through a `DotNetObjectReference` at a bounded interval.
- **Interop call volume is a separate cost** — each `IJSRuntime` call crosses the network twice and
  is JSON-serialized both ways, so the floor is a round-trip, not microseconds. A loop of N calls
  costs N round-trips; push the loop into one JS function. There is no synchronous escape on a
  circuit: `RemoteJSRuntime` does not implement `IJSInProcessRuntime`, so the `(IJSInProcessRuntime)`
  cast that appears in client-side samples throws `InvalidCastException` here.
- **`RenderFragment` cannot cross a render-mode boundary**: "Templated content can't be passed
  across a rendermode boundary, because it is arbitrary code and cannot be serialized."
- **`DateTime.Now`/`.Today`, `TimeZoneInfo.Local`, `ToLocalTime()` resolve against the server
  clock** (usually UTC in a container) and are the server's wall clock, never the user's.
- **`CurrentCulture` is the server's too**, and a circuit never picks up the browser's locale on its
  own. Whatever the host provides is what every `ToString()` and `Parse` uses — in a container
  usually Invariant, so `1,5` round-trips on a developer machine and silently becomes `15` in
  production. Pin `CultureInfo.DefaultThreadCurrentCulture`/`DefaultThreadCurrentUICulture` at
  startup, or set culture per circuit from a value captured during the establishing request; never
  leave it ambient and never patch it with `Replace(',', '.')` at the call site.
- **A component library's after-render code runs on your circuit.** Interop it re-arms on every
  render faults in the same disposal window yours does, so a library bug there terminates the
  circuit — it presents as the whole page dropping, not as one broken component.

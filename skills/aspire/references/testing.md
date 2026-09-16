# Testing against the AppHost

## APIs that look right and are not

Published examples and model priors both get these wrong. Verified against the
shipped `Aspire.Hosting.Testing` 13.5.3 assembly.

| Looks plausible | Actually |
|---|---|
| `app.WaitForResourceReadyAsync(name)` | **No such method.** Use `app.ResourceNotifications.WaitForResourceHealthyAsync(name, ct)` |
| `<IsAspireTestProject>true</IsAspireTestProject>` | **Not a real MSBuild property.** (The AppHost-side one is `IsAspireHost`.) |
| `CreateAsync<T>(args => { args.Args = [...] })` | **No single-lambda overload** — see below |
| `--exclude-resource <name>` | **Not a recognised switch.** Remove from `builder.Resources` instead |

The configure overload takes **`string[]` first, then a two-parameter lambda**:

```csharp
var builder = await DistributedApplicationTestingBuilder.CreateAsync<Projects.MyApp_AppHost>(
    ["--environment", "Testing"],
    (options, settings) => { settings.EnvironmentName = "Testing"; });
```

To drop a resource, mutate the model:

```csharp
builder.Resources.Remove(builder.Resources.Single(r => r.Name == "worker"));
```

## Wait for health, never `Task.Delay`

A started app is not a ready app.

```csharp
using var cts = new CancellationTokenSource(TimeSpan.FromMinutes(2));
await app.ResourceNotifications.WaitForResourceHealthyAsync("api", cts.Token);
```

Needs the resource to have a health check — `MapDefaultEndpoints()` supplies
`/health`. For a resource without one, wait on state instead:

```csharp
await app.ResourceNotifications.WaitForResourceAsync(
    "worker", KnownResourceStates.Running, cts.Token);
```

## Two smaller traps

- **`Projects.*` replaces dots with underscores.** `AspireApp.AppHost` →
  `Projects.AspireApp_AppHost`.
- **`CreateHttpClient` prefers https when the resource declares both schemes.** Pass
  the endpoint name when it matters: `app.CreateHttpClient("api", "http")`.

## Boot the AppHost once per class, not per test

Each `CreateAsync` + `StartAsync` starts *every* resource the AppHost declares —
every database container included. A test class that calls its setup helper from each
`[Fact]` pays that repeatedly. Put it in an `IAsyncLifetime` fixture and share it with
`IClassFixture` (per class) or `ICollectionFixture` (across classes), remembering that
a shared app means shared databases.

Pair it with `[Fact(Timeout = 120_000)]` — a hung container otherwise hangs the run.

## When not to boot the AppHost at all

If the test exercises one service, `WebApplicationFactory<TProgram>` plus a single
Testcontainer is far faster. Point the host at the container by overriding the
setting the Aspire resource would have supplied:

```csharp
builder.UseSetting("ConnectionStrings:cs-store", db.GetConnectionString());
```

Boot the full AppHost when the thing under test *is* the wiring — service discovery,
a gateway resolving logical names, cross-service calls. Otherwise don't.

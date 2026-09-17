# Wiring — why a service cannot reach its dependency

## `WithReference` does not wait

```csharp
.WithReference(db)            // wires config + dependency edge. Does NOT wait.
.WaitFor(db)                  // gates startup on the dependency's health check.
.WithReference(db).WaitFor(db)  // usually what you want
```

The damage is worst for a service that resolves addresses **once at startup** rather
than per request — a reverse proxy resolving logical service names, for example.
Without `WaitFor` it starts before endpoints are allocated, reads an empty
`services__*` set, and then runs happily forever routing to nothing. No crash, no
error at boot; requests just fail to resolve.

`WaitFor` needs the target to have a health check, or you get `ASPIRE006`. For a
project resource that is `MapDefaultEndpoints()` on the service side supplying
`/health`, plus the AppHost side declaring it:

```csharp
.WithHttpHealthCheck("/health")
```

For a resource that is supposed to run once and exit — a migration or seed job — wait
for it to *finish*, not to become healthy:

```csharp
.WaitForCompletion(migrations)
```

Two cases where omitting `WaitFor` is deliberate, not a bug:

- **Self-reference** — `api.WithEnvironment("SelfUrl", api.GetEndpoint("http"))`.
  Waiting on your own endpoint never resolves.
- **Reference cycles** — if A references B and B references A, only one direction may
  wait. `WithReference` alone is cycle-safe precisely because it does not block.

## The name is the contract

```
ConnectionStrings__<resource-name>          # databases, caches, brokers
services__<resource-name>__<endpoint-name>__0   # http services; endpoint name, not scheme —
                                                #   it is "http"/"https" only by default
```

`AddDatabase("catalog", …)` produces `ConnectionStrings__catalog`, which is what
`AddNpgsqlDbContext<T>("catalog")` reads. Spell it differently in the two places
and you get a null connection string at first use — no build error, no startup error.

## Ports are per-run

```csharp
.WithHttpEndpoint()                          // both auto — every run differs
.WithHttpEndpoint(targetPort: 8000)          // service listens on 8000, external auto
.WithHttpEndpoint(port: 3000, targetPort: 5173)  // external pinned
```

`port` is the external port on DCP's proxy; `targetPort` is what the service itself
listens on. Leaving both unset is normal for .NET projects and is what lets two
checkouts run side by side. Pass addresses between resources rather than writing them
down:

```csharp
.WithEnvironment("Upstream__BaseUrl",
    ReferenceExpression.Create($"{api.GetEndpoint("http")}/v1"))
```

## Three things that bite later

**`ContainerLifetime.Persistent` is machine-wide.** A second checkout of the same
solution attaches to the same container, and therefore the same database. The default
(fresh per run) is usually what you want.

**Set `<UserSecretsId>` on the AppHost if any resource has a generated password.**
Without it the password changes each run, which changes the resource's config hash,
which makes Aspire recreate persistent containers — taking their data with them.

The same thing seen from the other end: repeated `password authentication failed`
against a container that worked yesterday usually means a *persistent* volume still
holds the password from an earlier run while Aspire has generated a new one. The
volume wins, because the database only reads the generated password on first init.
Remove the container **and its volume**, not just the container.

**Never pass a secret through `WithArgs()`.** Process arguments are visible in `ps`
output and task managers. Use `WithEnvironment` or a parameter.

**`AddServiceDefaults()` is a bundle, not a law.** It includes
`AddStandardResilienceHandler()`, which stacks a retry pipeline and imposes its own
timeouts on every `HttpClient`. A service with its own Polly policy, or one that
deliberately uses a long timeout, should call the pieces it wants
(`ConfigureOpenTelemetry()`, `AddDefaultHealthChecks()`) instead.

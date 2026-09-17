---
name: ef-core-npgsql
description: Use when writing or debugging EF Core against PostgreSQL/Npgsql — "Cannot write DateTime with Kind=" errors, ExecuteUpdate/ExecuteDelete, migrations across several DbContexts, xmin concurrency, jsonb/enum mapping, or EF 8-era code that no longer compiles on EF 10.
---

# EF Core + Npgsql

Verified against **EF Core 10.0.11**, **Npgsql 10.0.2**, **Npgsql.EntityFrameworkCore.PostgreSQL 10.0.0**, `dotnet ef` 10.0.x.
Error texts and signatures were read out of the installed assemblies or produced by running them.

## DateTime Kind is load-bearing

Defaults, confirmed by building a model: `DateTime` → `timestamp with time zone`, `DateTimeOffset` → `timestamp with time zone`,
`uint` + `IsRowVersion()` → `xid` named `xmin`.

`timestamptz` accepts **only `DateTimeKind.Utc`**. Local and Unspecified throw `ArgumentException` at *bind* time — when the
command executes, so the stack points at `SaveChangesAsync`, not at the assignment:

```
Cannot write DateTime with Kind=Local to PostgreSQL type 'timestamp with time zone', only UTC is supported. Note that it's
not possible to mix DateTimes with different Kinds in an array, range, or multirange. (Parameter 'value')
```

The reverse is enforced too — `timestamp without time zone` rejects `Utc` (and renders `Kind=UTC` uppercase, where the
message above renders `Kind=Local` / `Kind=Unspecified`):

```
Cannot write DateTime with Kind=UTC to PostgreSQL type 'timestamp without time zone', consider using 'timestamp with time zone'. ...
```

So `DateTime.Now` and `new DateTime(2026, 1, 1)` throw. Only `DateTime.UtcNow` and
`DateTime.SpecifyKind(x, DateTimeKind.Utc)` are safe. Reads give `Kind=Utc` from `timestamptz` and `Kind=Unspecified` from
`timestamp`, so a value round-tripped through `timestamp` returns in a state you cannot write back to a `timestamptz` column.

`DateTime.MinValue`/`MaxValue` are special-cased to `±infinity` and **skip the Kind check entirely** — even
`SpecifyKind(MinValue, Local)` writes without complaint. That makes `default(DateTime)` the dangerous case: it *is*
`MinValue`, so an unset non-nullable column does not throw, it silently stores `-infinity`. Read back, `±infinity` returns as
`MinValue`/`MaxValue` with `Kind=Unspecified` rather than `Utc`, so it will not round-trip into a `timestamptz` write.

`DateTimeOffset` must have `Offset == TimeSpan.Zero`; anything else throws (`Cannot write DateTimeOffset with Offset=03:00:00
... only offset 0 (UTC) is supported.` — the double space before `(Parameter 'value')` is in the literal). It always reads back
as offset 0, so it does not preserve the original offset. It is UTC with ceremony.

**The legacy switch is a shim.** `Npgsql.EnableLegacyTimestampBehavior` makes `DateTime` default to `timestamp`, `timestamptz`
accept every Kind, reads return `Kind=Local`, and `DateTimeOffset` accept any offset. It is read **once** into a
`static readonly bool`, and again separately in the EF provider's `NpgsqlTypeMappingSource` static constructor — so
`AppContext.SetSwitch` that runs too late is silently ignored. Both sites are `internal static readonly bool` initialised in a
static constructor — Npgsql's `Util.Statics` and, separately, the provider's own copy, which cannot see Npgsql's `internal` one.
The trigger is building a data source or opening a connector, and on the EF side the first model build; merely constructing an
`NpgsqlConnection` does not initialise `Statics`. Rather than reason about which call wins, set it in the project file:

```xml
<RuntimeHostConfigurationOption Include="Npgsql.EnableLegacyTimestampBehavior" Value="true" />
```

There is no per-data-source, per-DbContext or connection-string form — it is process-wide. For a genuine wall-clock value (a
birthday, an opening time) do not reach for it: map that column `timestamp without time zone` and keep the CLR side `Unspecified`.

## EF 8-era APIs that no longer compile

**`ExecuteUpdate` moved twice.** EF 8: `RelationalQueryableExtensions`, Relational assembly,
`Expression<Func<SetPropertyCalls<T>, SetPropertyCalls<T>>>`. EF 9: `EntityFrameworkQueryableExtensions`, in **core**. EF 10:
takes `Action<UpdateSettersBuilder<T>>`, and **`SetPropertyCalls<T>` is deleted**. Namespace stayed `Microsoft.EntityFrameworkCore`.

```csharp
q.ExecuteUpdate(s => s.SetProperty(x => x.Name, "n").SetProperty(x => x.Hits, 0));  // still compiles
q.ExecuteUpdate(s => {                                    // new statement-body form
    s.SetProperty(x => x.Name, "n");
    s.SetProperty(x => x.Hits, x => x.Hits + 1);
});
Expression<Func<SetPropertyCalls<Blog>, SetPropertyCalls<Blog>>> reusable = ...;    // CS0246
```

Inline call sites survive because the builder returns itself; the "reusable setters" variable is what breaks.

Removed in 10: `SetPropertyCalls<T>`, the public `EntityTypeExtensions` (the `Internal` ones survive),
`MutableEntityTypeExtensions`, `ConventionEntityTypeExtensions`, `EntityTypeBuilder<T>.ToQuery(...)` and the defining-query
family, `PropertyValues.EntityType` (→ `StructuralType`). **`ListComparer<T>` went in EF 9**, not 10 — replaced by
`ListOfValueTypesComparer` / `ListOfNullableValueTypesComparer` / `ListOfReferenceTypesComparer` — so do not go looking for it
as a 9→10 break.

Newly obsolete **in 10**: `IReadOnlyEntityType.GetQueryFilter()` → *"Use GetDeclaredQueryFilters() instead."*, and
`TranslateParameterizedCollectionsTo{Constants,Parameters}()` → *"Use UseParameterizedCollectionMode instead."* — the latter on
`RelationalDbContextOptionsBuilder<TBuilder,TExtension>` in Relational, not on `DbContextOptionsBuilder`. Two more that look
new and are not: `DatabaseFacade.AutoTransactionsEnabled` → *"Use AutoTransactionBehavior instead"* and
`IProperty.DeclaringEntityType` → *"Use DeclaringType and cast to IEntityType or IComplexType"* carry the **same `[Obsolete]`
in 8.0.11**.

Newer than you may assume: `EF.Parameter` and `ToHashSetAsync` arrived in **9**; complex-type collections and named filters
`HasQueryFilter(string filterKey, ...)` in **10**. `EF.Constant` is 8.0.**x** — absent from 8.0.0, present by 8.0.11 — so a
project pinned to the original 8.0.0 does not have it.

`LeftJoin`/`RightJoin` in EF 10 are **BCL** methods on `System.Linq.Queryable`, net10.0 only, so the `using` is `System.Linq`
and the result selector is `Func<TOuter, TInner?, TResult>` — a nullability change. EF never shipped a usable shim for either:
`RightJoin` did not exist in 8 or 9, and the `LeftJoin` that did was an `Internal`-namespace marker whose body threw
`NotSupportedException`.

29 core APIs are `[Experimental]` (`EF9100`, `EF9101`, `EF9002`), a build error without a pragma or `<NoWarn>`. Two caveats:
that count is the core assembly only — Relational adds 17 more — and core 9.0.4 also totals 29, so it is not an EF 10 signal.

## ExecuteUpdate / ExecuteDelete semantics

- **The change tracker is not involved.** Already-tracked entities keep stale values, and a later `SaveChanges` can write them
  back over the update.
- **No `SaveChanges` runs, so a `SaveChanges` override and `ISaveChangesInterceptor` never fire.** Audit stamping, soft-delete
  conversion (`Deleted`→`Modified`) and outbox writes silently do not happen; `ExecuteDelete` is a real `DELETE` even on a
  soft-deletable entity. If the entity is audited, set those columns by hand in the same call.
- **Each call is its own implicit transaction and commits immediately.** Combined with `SaveChanges` that is two transactions,
  and a failure between them leaves the first committed. Open an explicit transaction around both when they must be atomic.
- **EF 10 added no interceptor for them** (verified by diffing every `*Interceptor` type, 8 vs 10). They are observable only via
  `DbCommandInterceptor`, discriminated by `CommandEventData.CommandSource` — but note `CommandSource.ExecuteUpdate` is an
  **alias of** the obsolete `BulkUpdate`, both `8`, so a `switch` cannot carry both arms. Only `ExecuteDelete` has a value of
  its own.

## xmin concurrency: the extension method is gone

`UseXminAsConcurrencyToken()` does not exist in provider 9.0.4 / 10.0.0 / 10.0.3 — it gives `CS1061: 'PropertyBuilder<uint>' does
not contain a definition for 'UseXminAsConcurrencyToken'`. It is now a **convention**: a `uint` property (store type `xid`) that
is a concurrency token and `ValueGenerated.OnAddOrUpdate` is automatically renamed to the column `xmin`.

```csharp
public uint Version { get; set; }                         // uint — not byte[], not [Timestamp]
mb.Entity<Doc>().Property(d => d.Version).IsRowVersion();
// verified: col=xmin store=xid concTok=True valGen=OnAddOrUpdate
```

`xmin` is a Postgres system column, so no migration creates it — optimistic concurrency with zero schema change, and equally,
nothing in the migrations reveals it is switched on. `[Timestamp]` on `byte[]` is SQL Server's `rowversion` and does **not** do
this on Postgres.

## Migrations across several DbContexts

`--context` is mandatory once a project exposes more than one; the rest depends on layout.

```bash
# context lives in the project that also configures DI — no --startup-project needed
dotnet ef migrations add AddFoo -c OrdersDbContext -p src/Orders/Orders.csproj

# migrations project separate from the app that builds the host
dotnet ef migrations add AddFoo -c OrdersDbContext -p src/Infrastructure/Infrastructure.csproj \
  -s src/Api/Api.csproj -o Database/Migrations
```

`-p/--project` holds the migration files and snapshot; `-s/--startup-project` is built and run for config and DI. `--help` says
both default to the current directory; in practice the fallback is **symmetric** — omit one and it takes the other. That is the
usual cause of a design-time failure, and the real message names the type and carries the inner exception that explains it:

```
Unable to create a 'DbContext' of type 'OrdersDbContext'. The exception 'Unable to resolve service for type
'Microsoft.EntityFrameworkCore.DbContextOptions`1[OrdersDbContext]' while attempting to activate 'OrdersDbContext'.'
was thrown while attempting to create an instance. For the different patterns supported at design time, see ...
```

Read the inner exception, not the outer one. An `IDesignTimeDbContextFactory<T>`
short-circuits all of it: EF uses the factory instead of booting the startup project, so a hardcoded design-time connection string
is fine and the database need not exist. `-c "*"` runs a command for every context found.

**Never hand-write a migration class.** EF discovers migrations through `[DbContext]` and `[Migration("<id>")]`, which the
tooling emits into the `.Designer.cs`. Both attributes are required and the Designer file itself is not — put both on the class
and it runs. Get it wrong and the failure mode depends on which one is missing, verified against a live database:

| What you wrote | What happens |
|---|---|
| Neither attribute | **Silent.** Absent from `migrations list`, absent from `script`, nothing logged even at Debug. |
| `[Migration]` only | **Also silent** — discovery filters on `[DbContext]` first and drops non-matches without a word. |
| `[DbContext]` only | Warns: `RelationalEventId.MigrationAttributeMissingWarning[20407]` — *"A [Migration] attribute is not specified on the 'X' class."* |
| Both | Applies correctly, Designer or not. |

The two silent cases are the reason to scaffold rather than hand-write, including for a data-only migration that just calls
`migrationBuilder.Sql(...)`. Verify before merging:

```bash
dotnet ef migrations list -c OrdersDbContext -p ...       # yours MUST appear
dotnet ef migrations script <prev-id> -c OrdersDbContext  # and MUST emit your SQL
dotnet ef migrations has-pending-model-changes -c OrdersDbContext
```

**Never edit an applied migration.** Unapplied everywhere → `dotnet ef migrations remove -c <Ctx>`, then re-scaffold. Already
applied → write a new migration that corrects it.

**A non-nullable column's existing rows get the migration's `defaultValue`, not the C# property initializer.** When the two
disagree, new rows are right and pre-existing rows are wrong — correct in a fresh dev database, broken in production. Match them,
or add an explicit backfill in the same migration.

## Applying migrations

`Database.Migrate()` at startup is common and has real costs. EF 9 added migration locking, which Npgsql implements as
`LOCK TABLE "__EFMigrationsHistory" IN ACCESS EXCLUSIVE MODE`, so concurrent replicas serialize rather than corrupt — but each
blocks on boot for the duration.

- **Two *applications* migrating one database is the genuine corruption case.** Where a database is shared, exactly one service
  owns the schema and the others register their context with no migration step. Otherwise the migration ID sets diverge and each
  tries to apply the other's "missing" ones.
- **DDL runs while the previous version is still serving.** A plain `CreateIndex` takes a SHARE lock that blocks writes for the
  whole build. On a large hot table use `CREATE INDEX CONCURRENTLY` with `suppressTransaction: true` (it cannot run inside a
  transaction); an interrupted build leaves an INVALID index — find it with
  `SELECT indexrelid::regclass FROM pg_index WHERE NOT indisvalid;` then `DROP INDEX CONCURRENTLY`.
- **Cross-service ordering becomes impossible.** "Apply the migration before deploying the binary" cannot be honoured when the
  binary *is* the migrator. `dotnet ef migrations bundle -c <Ctx> -o efbundle-orders` produces a self-contained executable for a
  deploy step (per-context, so name the output); `migrations script --idempotent` produces SQL for review.

Adopting an already-deployed schema into a new project: copy the migration files **verbatim, same IDs**, so the deployed
`__EFMigrationsHistory` makes startup a no-op. Regenerating an "Initial" tries to re-create existing tables. And a seeder guarded
by an "already seeded" row never reaches an existing database — anything that must land everywhere exactly once belongs in a
migration.

## Npgsql specifics

**Identifiers.** The provider snake_cases nothing, so `class Customer { int Id; }` becomes `"Customer"."Id"` — case-sensitive
forever, and every hand-written SQL string must repeat the quotes. The actual `RequiresQuoting` rule is narrower than
"not all-lowercase": the first character must be lowercase or `_`, the rest lowercase, a digit, `_` or `$`, **and** the
identifier must not be a reserved word. So `customer_id`, `_x` and `cust1` are left bare, while `select`, `user`, `table` and
`order` are quoted despite being all-lowercase. Decide at project start: add `EFCore.NamingConventions` (a separate package, `UseSnakeCaseNamingConvention()`) or accept
quoted PascalCase. Switching later renames every table.

**Enums — two complementary APIs on two different builders, not alternatives:**

```csharp
opt.UseNpgsql(cs, o => o.MapEnum<Status>("status"));  // options builder: CLR↔PG mapping
modelBuilder.HasPostgresEnum<Status>();               // ModelBuilder: makes migrations emit CREATE TYPE
```

`HasPostgresEnum` is **not** obsolete in 10. Storing enums as `text` via `.HasConversion<string>()` avoids both — no `CREATE TYPE`,
no data-source registration, and adding a member is not a migration.

**jsonb.** `HasColumnType("jsonb")` on a `string` always works. Mapping a POCO or `Dictionary` directly needs dynamic JSON on the
**data source**, which is not reachable from the EF options builder alone — miss it and you get a runtime mapping failure, not a
compile error. EF's own `.ToJson()` owned-entity mapping needs no switch.

```csharp
opt.UseNpgsql(cs, o => o.ConfigureDataSource(dsb => dsb.EnableDynamicJson()));
```

**Execution strategy.** With `EnableRetryOnFailure` a retry re-runs your delegate **on the same DbContext**, which still tracks
everything the failed attempt did. Begin the delegate with `db.ChangeTracker.Clear()` and do the reads *inside* it — a read hoisted
outside means the retry mutates entities the failed attempt already touched. With a retrying strategy you also cannot call
`BeginTransaction` directly; go through `Database.CreateExecutionStrategy().ExecuteAsync(...)`.

**Unique index plus soft delete.** A soft-deleted row is still in the table, so a plain unique index permanently blocks reusing the
key. Filter it: `HasIndex(...).IsUnique().HasFilter("\"DeletedAt\" IS NULL")`. The usual symptom is somebody working around it with
a hard `ExecuteDelete`, which then escapes the surrounding transaction.

**Override every `SaveChanges` overload.** Audit and soft-delete logic placed only in `SaveChangesAsync(CancellationToken)` is
bypassed by a synchronous `SaveChanges()`, which then hard deletes what the async path soft deletes — silently. Cover all four
overloads, or put the logic in an `ISaveChangesInterceptor`, which catches every one.

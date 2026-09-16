---
name: api-conventions
description: Use when a coding convention needs mechanical enforcement rather than review — banning APIs with Microsoft.CodeAnalysis.BannedApiAnalyzers (BannedSymbols.txt, RS0030), wiring AdditionalFiles, promoting an analyzer diagnostic to a build error, scoping an exemption, or designing the throw-an-exception error contract that banning Ok()/BadRequest()/NotFound() forces on controllers.
---

# Mechanically enforced API conventions

Measured against **BannedApiAnalyzers 5.6.0**, .NET SDK 10.0.111 (2026-09) — not read from docs,
several of which are wrong.

## Four ways the ban list silently does nothing

It never complains about its own configuration, so a misconfigured list looks like a clean build.

1. **No `AdditionalFiles` item.** The package ships no glob for `BannedSymbols.txt`; its
   `buildTransitive` targets only add a global analyzer config.
2. **Wrong file name.** Matching is on the physical path: exactly `BannedSymbols.txt` or
   `BannedSymbols.<x>.txt` — the dot is required, case-sensitive on Linux. All matching files are read.
3. **`Link="BannedSymbols.txt"` renames nothing** — it reads `AdditionalText.Path`, not `Link`.
4. **A line resolving to no symbol is skipped without a word** — typo, missing prefix, moved type,
   `M:` where `P:` was needed. It doubles as the comment syntax. Verify each batch of new entries by
   compiling a deliberate violation.

```xml
<!-- src/Api/Directory.Build.props — covers every project below this folder -->
<Project>
  <PropertyGroup>
    <WarningsAsErrors>$(WarningsAsErrors);RS0030</WarningsAsErrors>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Microsoft.CodeAnalysis.BannedApiAnalyzers" Version="5.6.0" PrivateAssets="all" />
    <AdditionalFiles Include="$(MSBuildThisFileDirectory)BannedSymbols.txt" />
  </ItemGroup>
</Project>
```

`$(MSBuildThisFileDirectory)` is load-bearing — a bare `Include="BannedSymbols.txt"` here resolves
against each **project** directory. The package is a `developmentDependency` and does not flow
transitively, so every project needs the `PackageReference`; hence `Directory.Build.props`. MSBuild
imports only the **nearest** one walking up, so if the repo root has one, re-import it with
`$([MSBuild]::GetPathOfFileAbove(...))`.

## Line format

`{documentation comment ID};{message}`, prefixes `T: M: P: F: E: N:`. Only the first `;` splits; the
message is appended to the diagnostic and is the only place a developer learns the replacement.

**An `M:` entry with no parameter list bans only the parameterless overload.** Published docs say it
bans all of them; it does not. `M:System.Console.WriteLine` catches `WriteLine()` and leaves
`WriteLine("a")` alone, so banning a result helper needs a line per overload:

```
M:Microsoft.AspNetCore.Mvc.ControllerBase.Ok;Return the typed value directly — the action's return type is the contract
M:Microsoft.AspNetCore.Mvc.ControllerBase.Ok(System.Object);Return the typed value directly — the action's return type is the contract
M:Microsoft.AspNetCore.Mvc.ControllerBase.BadRequest(Microsoft.AspNetCore.Mvc.ModelBinding.ModelStateDictionary);Throw BadRequestApiException instead
P:System.DateTime.Now;Use a clock abstraction, or DateTime.UtcNow
```

- **Properties need `P:`** — `M:System.DateTime.get_UtcNow` resolves to nothing.
- Parameter types are fully qualified, no spaces; **constructed generics use braces**:
  `System.Nullable{System.Int32}`, `IDictionary{System.String,System.Object}`. Arity uses backticks
  (``T:N.Box`1``); constructors are `#ctor`. Matching is exact — enumerate the overloads from the
  framework source and count them, because that is where the hole appears when an SDK adds one.
- Ban the *error* helpers and untyped `Ok`, not all of `ControllerBase`. `NoContent`, `File`,
  `Content`, `Redirect` have no typed-return equivalent; banning them only manufactures exemptions.
- **`T:` and `N:` fire on use, not mention** — construction, `typeof`, member access; *not* a
  field/parameter/return type, local declaration, cast, `is`, generic argument or `using`.
- The ban binds to `ControllerBase`. **Minimal APIs are a different type**, so `Results.Ok` /
  `TypedResults.Ok` stay legal — ban `T:Microsoft.AspNetCore.Http.Results` too.
- `RS0031` = symbol listed twice (even across two ban files); it points at the ban file, not the code.
  `dotnet_banned_api_analyzer.exclude_generated_code = true` in `.editorconfig` skips EF designers.

## Escalating to an error

RS0030 ships enabled at `warning`, so it needs escalating, not enabling. Two verified traps:

- **A blanket `TreatWarningsAsErrors` is not enough.** The package's own props add
  `RS0030;RS0031;RS0035` to `WarningsNotAsErrors` whenever `TreatWarningsAsErrors=true` and
  `CodeAnalysisTreatWarningsAsErrors=false` — the pairing repos pick to keep third-party analyzers
  advisory — dropping the ban back to a warning.
- **`<WarningsAsErrors>RS0030</WarningsAsErrors>` overrides `.editorconfig`
  `dotnet_diagnostic.RS0030.severity = none`**, resurrecting exempted files as errors. Path-scoped
  editorconfig exemptions only work when escalation also comes from editorconfig or `-warnaserror`.

## Exemptions

`#pragma warning disable RS0030` suppresses **the whole ban list** in its region, not the symbol being
excused. The predictable failure: a file-scoped pragma opened so one endpoint can hand-craft an error
body then also permits `Ok(...)` on that file's success path. Look for exactly that when reviewing one.

1. `disable`/`restore` around the **smallest** region, with a comment naming the client and the part
   of the contract that depends on it. Works under `WarningsAsErrors`.
2. Path-scoped `.editorconfig` for a legacy area, subject to the caveat above. Globs are relative to
   the `.editorconfig`'s own directory, and `**/*.cs` needs an intervening directory:
   `[src/Legacy/**.cs]` matches `src/Legacy/Old.cs`, `[src/Legacy/**/*.cs]` does not.
3. `[SuppressMessage("ApiDesign", "RS0030", Justification = "…")]` — only the id is checked, so the
   category string is decoration and the `Justification` slot is the point.

An undocumented exemption is a review reject: the list's whole value is that every surviving call site
was decided deliberately.

## The error contract the ban forces

```csharp
[HttpGet("{id:int}")]                                 // ActionResult<T> converts implicitly;
public async Task<ActionResult<OrderResponse>> Get(   // Ok(x) takes object? and erases the check
    int id, CancellationToken ct) => await mediator.Send(new GetOrder(id), ct);

if (order is null) throw new OrderNotFoundApiException(id);   // -> problem+json, 404

public abstract class ApiException(string title, int status, object? details = null)
    : Exception(title)   // <- pass it; otherwise .Message is "Exception of type 'X' was thrown."
{ public string Title { get; } = title; public int StatusCode { get; } = status; /* … */ }
```

`Exception(title)` is not cosmetic: every `catch (Exception e) { log(e.Message) }` and every per-item
error field in the system otherwise records the placeholder, and it only shows up in a log nobody reads.

Writing the response:

- **`detail` must be a string.** RFC 9457 says so and conforming clients call `GetString()` on it; an
  object there makes a strict parser throw and fall back to raw JSON, losing `title` too. Structured
  data goes in its own extension member.
- **`type` is a URI**, not `ex.GetType().Name` — a CLR name leaks internals and cannot be dispatched on.
- **Never put `ex.ToString()` or an inner exception's message into `Title`/`Detail`.** That branch is
  trusted by construction and usually has no environment check, so one wrapper doing
  `throw new XApiException(inner.ToString())` ships stack traces to every client.
- Register the middleware **before** authentication, or exceptions from the auth middleware escape it.

The payoff: tests assert `await Assert.ThrowsAsync<OrderNotFoundApiException>(() => controller.Get(9))`
on the controller method directly — which only works if failures are **domain subclasses**, not
`NotFoundApiException("…")`.

## Where throw-don't-return stops working

- **`[ApiController]` model-state 400s never reach the middleware.** The framework short-circuits with
  `ValidationProblemDetails` (`{"errors":{…}}`) — a second error shape on the wire, which is what the
  ban was meant to eliminate. Document it or funnel it through
  `ConfigureApiBehaviorOptions(o => o.InvalidModelStateResponseFactory = …)`. A repo carries both
  shapes for years unnoticed, so check explicitly.
- **Multiple field errors.** One `Title` cannot carry a field→messages map, so the practical result is
  sequential single-error throws where the first failure wins. Mirror the `errors` key in a structured
  extension member, or leave field validation to the framework.
- **Batch operations are not errors.** When some items of a bulk apply fail the answer is 200 with
  `{ succeeded, failed, results: [{ id, success, error }] }`; throwing turns partial success into total
  loss. Long batches return a job id and poll a progress object.
- **A client needing a different envelope** gets a **path-scoped exception middleware registered later
  in the pipeline** (later = closer to the controller = catches first), not a pragma, so its controllers
  stay inside the convention. Reserve the pragma for what a status-plus-body translator cannot express
  at all: a response header, or a per-status machine-readable code the client dispatches on.
- **Outside the HTTP pipeline there is no translator.** The same exception from a background job,
  consumer or hub becomes a retry loop or a generic fault and its status code is meaningless — catch it
  at that boundary and map it to that transport's vocabulary.

## When a banned symbol cannot express the rule

Ordering and shape rules — "subscribe before the first `await`", "every action declares a concrete
return type" — are not symbol bans. Before writing a real analyzer, try an xUnit test that parses the
sources with `CSharpSyntaxTree.ParseText`: no packaging, no analyzer host, and it covers files written
tomorrow. Give it a **vacuity assertion** (`Assert.True(methodsScanned > 50)`) so a broken path locator
cannot pass by scanning nothing.

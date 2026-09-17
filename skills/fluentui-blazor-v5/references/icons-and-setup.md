# Registration, providers, icons and package shape

Verified against 5.0.0-rc.5-26219.1.

## Registration

```csharp
builder.Services.AddFluentUIComponents();            // or (LibraryConfiguration) / (Action<LibraryConfiguration>)
```

Registers `LibraryConfiguration`, `IDialogService`, `INotificationService`, `IFluentLocalizer`,
`IKeyCodeService`, `IThemeService`, and — only when `configuration.Tooltip.UseServiceProvider` —
`ITooltipService`. Everything at `configuration.ServiceLifetime`, default **Scoped**.

Only `Singleton` and `Scoped` are legal:

```
NotSupportedException: Transient lifetime is not supported for Fluent UI services.
```

On Blazor Server, Scoped means the circuit — which is the right lifetime here, since these services
talk to provider components mounted in the layout.

## `<FluentProviders />` does not mount everything

It renders a `display:contents` div containing exactly four providers:

`FluentDialogProvider` · `FluentToastProvider` · `FluentTooltipProvider` · `FluentKeyCodeProvider`

**`FluentMessageBarProvider` is not among them** — despite the shipped README and the published
installation page both saying `FluentProviders` covers message bars.

This is by design, not an oversight. The message-bar provider is **section-scoped**: its `Section`
parameter is required, and a message published to a section with no matching provider is simply
never displayed. There is no sensible section for `FluentProviders` to pick, so it cannot mount one
for you. Upstream's own MessageBar documentation says you must add at least one yourself:

```razor
<FluentProviders />
<FluentMessageBarProvider Section="MAIN" />
```

All the individual providers still exist as public types, so mounting them one by one remains valid.
`FluentKeyCodeProvider` is only reachable through `FluentProviders` or an explicit tag; the README
never mentions it.

A provider that was mounted and later torn down leaves a stale non-empty `ProviderId`, which defeats
the library's own "provider not available" check — see the hang paths in
[Dialogs and notifications](dialogs-and-notifications.md).

## Global per-component defaults

`LibraryConfiguration.DefaultValues` sets a parameter's default for every instance of a component,
so you stop repeating the same attribute on every call site:

```csharp
builder.Services.AddFluentUIComponents(config =>
{
    config.DefaultValues.For<FluentButton>().Set(p => p.Appearance, ButtonAppearance.Primary);
    config.DefaultValues.ForAny<FluentSelect<string, string>>().Set(p => p.Size, TextInputSize.Small);
});
```

`Set<TValue>(Expression<Func<TComponent, TValue>>, TValue)` resolves the `PropertyInfo` once and
`ApplyDefaults` writes it into each new instance. Use `ForAny<T>()` for a generic component — it
matches on the open type, ignoring the type arguments, which `For<T>()` does not.

## Subclassing a Fluent component

`FluentComponentBase` has exactly one constructor:

```csharp
protected FluentComponentBase(LibraryConfiguration configuration)
```

There is **no parameterless overload**, so every custom component deriving from it — directly or
through `FluentInputBase<T>`, `FluentDataGrid<T>` and so on — must accept and forward a
`LibraryConfiguration`. A v4 subclass will not compile until it does. The property it lands in is
`protected internal LibraryConfiguration?`.

Two members moved off the base at the same time: `Element` is now on `IFluentComponentElementBase`,
and `ParentReference` is gone.

## Host page

No script tag is needed: the library's `lib.module.js` is a Blazor JS initializer and auto-loads.
What you do want statically linked is the base stylesheet, so `<body>` is not unstyled until the
circuit boots — see [Tokens and CSS](tokens-and-css.md).

The README's instruction to register a default `AddHttpClient()` before `AddFluentUIComponents` is
**stale**. The string `HttpClient` does not appear anywhere in the assembly in either RC; it is a v4
leftover, as is the unused `Microsoft.Extensions.Http` package dependency.

## Icons

Icons ship in **satellite assemblies** — `Icons.Regular.dll` (10.7 MB), `Icons.Filled.dll` (9.0 MB),
`Icons.Light.dll`, `Icons.Color.dll`. The facade `Icons.dll` is 5 KB and contains **zero type
definitions**; referencing it alone gets you nothing.

Sizes are top-level static classes per variant namespace, with the icons nested inside them:

```csharp
namespace Microsoft.FluentUI.AspNetCore.Components.Icons.Regular;
public static class Size20 { public class Accessibility : Icon { … } }
```

`Regular.Size20` and `Filled.Size20` share a simple name, so any file using more than one variant or
size needs aliases:

```csharp
@using Reg20 = Microsoft.FluentUI.AspNetCore.Components.Icons.Regular.Size20
```

**Not every icon exists in every size.** Regular and Filled ship all eight sizes
(10/12/16/20/24/28/32/48); Light has only 24/28/32/48 and is effectively Size32-only; Color has
16/20/24/28/32/48. In rc.5's Regular set there are 3,016 distinct icon names and **not one exists in
all eight sizes** — 897 exist in exactly two, 308 in exactly one. Check the size you want before
committing to it.

rc.5 counts, Regular: 16→1786, 20→2918, 24→2565, 28→1006, 32→852, 48→710 (10,056 total). Filled is
slightly larger at 10,182.

Two behaviours to know:

- `FluentIcon.Color` is nullable with no default, and `GetIconColor()` falls through to
  **`currentColor`**. In v4 it defaulted to `Accent`, so icons that used to be brand-coloured now
  inherit their parent's colour. Set `Color="Color.Primary"` to restore the old look.
- Setting `CustomColor` without `Color="Color.Custom"` throws from `OnParametersSet`:
  `ArgumentException: CustomColor can only be used when Color is set to Color.Custom.`
  `Icon.WithColor(...)` sets the colour directly and bypasses the check.

Rendering a whole catalogue is a circuit cost — these are inline SVGs, and thousands in one batch
will stall it. Cap a browser page at roughly a hundred.

## Package shape

- Core ships **net8.0, net9.0 and net10.0** — all three are complete builds, not stubs. The net10.0
  one carries two extra classes from `Microsoft.Extensions.Validation.Embedded`.
- Icons ship **net9.0 only**.
- Core is marked `[assembly: AssemblyMetadata("IsTrimmable", "True")]`.
- **The icons nuspec still declares a dependency on a v4 core** — `4.14.3` in rc.4, bumped to
  `4.14.4` in rc.5, still v4. NuGet resolves up to whatever v5 the app references, so it usually
  passes unnoticed, but `dotnet add package` on a bare project drags in the v4 core.
- The `emoji` package has no 5.x build. Using `FluentEmoji` means a v4 package against a v5 core.
- `staticwebassets` lost the content hash in its bundle filename between 4.x and 5.x:
  `…exfvxuochq.bundle.scp.css` became `Microsoft.FluentUI.AspNetCore.Components.bundle.scp.css`.

## Version pinning in a mixed solution

Central Package Management pins one version per solution, which breaks down while one project is on
v5 and the rest are on v4. `VersionOverride` on the single project is the mechanism:

```xml
<PackageReference Include="Microsoft.FluentUI.AspNetCore.Components" VersionOverride="5.0.0-rc.5-26219.1" />
<PackageReference Include="Microsoft.FluentUI.AspNetCore.Components.Icons" VersionOverride="5.0.0-rc.5-26219.1" />
```

Keep core and icons on the same version. Expect obsolete-API warnings from the RC and do not treat
warnings as errors in that project — upstream's own install guidance says the same.

## Undocumented runtime hooks

- Theme state persists to `localStorage` under `fluentui-blazor:theme-settings`, read at
  `beforeStart`. `data-theme` (`light|dark|system`) and `data-theme-color` on `<body>` are honoured
  too, and `dir` is read and written on `<html>`.
- The library sets `data-media` on `<body>` to `xs|sm|md|lg|xl|xxl` and raises a `mediaChanged`
  CustomEvent — a responsive hook nothing documents.

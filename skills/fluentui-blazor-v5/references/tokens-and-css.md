# Design tokens, theming and CSS

Verified against 5.0.0-rc.5-26219.1. The token table is byte-identical to rc.4.

## Tokens are `const string` holding the `var()` reference

`StylesVariables` has **472** leaf members, every one a `public const string` whose value is the CSS
reference itself — `SystemColors.Brand.Background == "var(--colorBrandBackground)"`. `SystemColors`
is an empty subclass of `StylesVariables.Colors`, there for brevity.

Use the typed constants, never a hand-typed `var(--…)`. A wrong constant is a compile error; a
hand-typed name that does not exist resolves to nothing and the element renders transparent, with
no warning anywhere.

Groups, with the names that trip people up:

| Group | Note |
|---|---|
| `Colors.*` (380) | `Alerts`, `Background`, `Brand`, `Compound`, `Highlight`, `Neutral`, `Palette`, `Presence`, `Scrollbar`, `Status`, `Stroke`, `Subtle`, `Transparent` |
| `Borders.Radius` (11), `Lines.Height` (10), `Durations` (8) | flat |
| `Fonts.{Family,Size,Weight}` | |
| `Spacings.{Horizontal,Vertical}` | **no flat `Spacings`** |
| `Curves.{Accelerate,Decelerate,Easy,Linear}` | **nested**, e.g. `Curves.Linear.Default` |
| `Shadows` (12) | awkward: `Shadows.Shadows16` → `var(--shadow16)` |
| `Strokes.Width` (4) | `Thin/Thick/Thicker/Thickest` |

**All 472 resolve at runtime.** 459 are emitted by the theme generator via `setProperty`; the other
13 — `--success`, `--warning`, `--error`, `--info`, `--highlight-bg` and the eight `--presence-*` —
are defined in a `:root` block inside the stylesheet the library adopts at `afterStarted`. There are
no dead tokens. A claim that some are dead usually comes from grepping `lib.module.js`, which cannot
see keys built from template literals.

They do all depend on the JS having run: `beforeStart` initialises the theme, `afterStarted` adopts
the stylesheet. Nothing in the static CSS bundle defines them.

## The palette is flat and per-hue inconsistent

Constants are flat — `Palette.GreenForeground1`, never `Palette.Green.Foreground1`. 35 hues in three
tiers:

| Tier | Hues | Available |
|---|---|---|
| Full + inverted | Green, Red, Yellow | Fg1-3, **FgInverted**, Bg1-3, Border1-2, BorderActive |
| Full | Berry, DarkOrange, LightGreen, Marigold | Fg1-3, Bg1-3, Border1-2, BorderActive |
| Minimal (28 hues) | Anchor, Beige, Blue, Brass, Brown, Cornflower, Cranberry, DarkGreen, DarkRed, Forest, Gold, Grape, Lavender, LightTeal, Lilac, Magenta, Mink, Navy, Peach, Pink, Platinum, Plum, Pumpkin, Purple, RoyalBlue, Seafoam, Steel, Teal | **Foreground2, Background2, BorderActive only** |

So a palette that works for Green may not exist for Teal. This is the strongest argument for typed
constants: the compiler knows which hue has which ramp and you do not.

There is **no numbered `--colorBrand10…160` ramp** as CSS variables — only semantic brand tokens.
The numbered ramp exists JS-internally and is reachable as data via `IThemeService.GetColorRampAsync()`.

## Theming is `IThemeService`, and it is JS interop

`FluentDesignTheme` does not exist in v5. Theming is:

```csharp
public sealed record ThemeSettings(string Color = "0F6CBD", double HueTorsion = 0.0,
    double Vibrancy = 0.0, ThemeMode Mode = ThemeMode.Light, bool IsExact = false);
enum ThemeMode { Light, Dark, System }    enum ThemeColorVariant { Default, Teams }
```

`CreateCustomThemeAsync(ThemeSettings)` regenerates the whole brand ramp from one hex.
`SetThemeAsync` has overloads for a variant, a mode, a colour, settings, or a `Theme`. Also
`IsDarkModeAsync`, `IsSystemDarkAsync`, `SwitchThemeAsync`, `SwitchDirectionAsync`,
`GetBrandColorAsync`, `GetColorRampAsync`, `SetThemeToElementAsync`, `ClearStoredThemeSettingsAsync`.

**Every member is a bare `InvokeAsync` with no prerender guard.** Call any of them from
`OnInitializedAsync` under prerendering and it throws — twice over, because `Blazor.theme` is only
attached to the Blazor instance during `afterStarted`. `OnAfterRenderAsync(firstRender)` is the only
correct place.

Initial theme is a different code path entirely: `beforeStart` reads `localStorage` key
`fluentui-blazor:theme-settings`, plus `data-theme` and `data-theme-color` attributes on `<body>`,
and `dir` on `<html>`. That is why the theme is applied before Blazor starts, and why
`IThemeService` is not involved in the first paint.

Note the default `Color` is `"0F6CBD"` with no `#`, contradicting its own doc example. The JS
validator accepts both.

## `<body>` has no styling until the JS runs

`css/default-fuib.css` is the base reset, and it is **fetched over HTTP and adopted from JS** at
`afterStarted` — not shipped in the CSS bundle. It is the only source of
`body { color: var(--colorNeutralForeground1); background-color: …; font-family: … }`; the scoped
bundle's three `body{…}` rules set none of those.

So between first paint and the circuit booting, inherited text has no colour rule — which on a
coloured header reads as invisible text. Linking it statically in the host page removes the flash:

```html
<link rel="stylesheet" href="_content/Microsoft.FluentUI.AspNetCore.Components/css/default-fuib.css" />
```

Injection is idempotent, but **not by element id** — it uses `document.adoptedStyleSheets` with
module-scope singletons, re-checked on `enhancedload`. Opt out entirely with a `no-fuib-style`
attribute on `<body>` or `<html>`; a `MutationObserver` watches for it live.

`reboot.css` also ships (a Bootstrap-derived reset) and is **opt-in only**, via a `use-reboot`
attribute.

**The bundle contains no `#blazor-error-ui` rules at all.** Without your own, Blazor's error banner
is visible on every page.

## `Margin` and `Padding` are component parameters

Spacing is a first-class parameter on components rather than something you write in CSS. `Margin`
and `Padding` are types (`Margin.All4`, `Padding.Horizontal3`), converted through
`ConvertSpacing()` into a style string by each component's style builder — `FluentInputBase`,
`FluentDataGridCell` and `DialogOptions` all do it. The scale maps onto the
`--spacingHorizontal*` / `--spacingVertical*` tokens.

One caveat carried from an open upstream report rather than verified here: `Margin` and `Padding`
are said to **silently drop `var()` token values**, so a raw token string passed to them may
produce nothing. Test it before relying on it.

## The component → element map, because guessing fails

Every component renders into shadow DOM (`shadowRootMode: "open"`), but the root element is often a
plain HTML tag carrying a `fluent-*` **class**, not a `fluent-*` element. Selectors written from the
C# name mostly miss.

Real custom elements whose tag is not the obvious one:

| Component | Element |
|---|---|
| `FluentSelect`, `FluentCombobox` | `fluent-dropdown` (wrapping `fluent-listbox`) |
| `FluentTextArea` | `fluent-textarea` — **no hyphen** |
| `FluentTextInput`, `FluentNumberInput`, `FluentDatePicker` | `fluent-text-input` |
| `FluentOption` | `fluent-option` (registered as `dropdown-option`) |
| `FluentDialog` | `fluent-dialog` **or `fluent-drawer`** |
| `FluentDialogBody` | `fluent-dialog-body` **or `fluent-drawer-body`** |
| `FluentPopover` | `fluent-popover-b` |
| `FluentToast` | `fluent-toast-b` |
| `FluentTreeView` | `fluent-tree` |

Components whose root is a plain element with a class — style these with `.fluent-…`, not `fluent-…`:

`FluentDataGrid` → `table.fluent-data-grid` · `FluentNav` → `nav.fluent-nav` ·
`FluentNavItem`/`FluentNavCategory` → `button` with `.fluent-navitem` / `.fluent-navcategoryitem` /
`.fluent-navsubitem` · `FluentTabs` → `div.fluent-tabs` wrapping a real `fluent-tablist` ·
`FluentMultiSplitter` → `div.fluent-multi-splitter` · `FluentStack` →
`div.fluent-stack-horizontal|-vertical` · `FluentCard`, `FluentGrid`, `FluentPaginator`,
`FluentCalendar`, `FluentSkeleton`, `FluentWizard`, every `*Provider` → `div` with a matching class ·
`FluentIcon`/`FluentEmoji` → `svg` · `FluentHighlighter` → `mark` · `FluentBadge` and
`FluentPresenceBadge` → a `fluent-badge-container` wrapper around `fluent-badge`.

## Scoped CSS mostly cannot reach this library

Five traps, in the order they bite:

1. The library stylesheet carries **no `b-…` scope attributes at all**, so nothing it generates can
   be reached from a `.razor.css`. Grid cells, nav internals and provider DOM are all global-only.
2. Your app's own `<AssemblyName>.styles.css` must be linked in the host page or **every**
   `*.razor.css` in the project silently does nothing. It is a different file from the library's
   `…bundle.scp.css`.
3. The `b-…` attribute is stamped on `.razor` **markup** only — never on DOM built from a
   code-behind `RenderTreeBuilder`, a `RenderFragment`, or a `MarkupString`.
4. **`::deep` cannot reach a Fluent component at all.** v5 builds with `ScopedCssEnabled=false`, so
   the library carries no scoped-CSS identifier for `::deep` to combine with. `::deep` still works
   against plain HTML you authored yourself — anchored on an element in *this* component, never on a
   child component's root — but any v5 `::deep` rule carried over from v4 is now dead.
5. A `<style>` block inside a `.razor` file is **global**, not scoped.

**Classes that fail the library's regex are silently dropped.** `CssBuilder` filters every class
name through `^-?[_a-zA-Z]+[_a-zA-Z0-9-]*$` and discards the rest without complaint, so utility
classes containing brackets, slashes or colons never reach the DOM. Set
`CssBuilder.ValidateClassNames = false` at startup if you use a utility framework.

Beat a library rule by **matching its specificity**, not by escalating to `!important`. The base
grid rule is `.fluent-data-grid` at (0,1,0), so `table.fluent-data-grid` at (0,1,1) wins on the tie
by load order — but rc.5's `[display-mode=grid]` rules are (0,2,0) and need the same treatment
again.

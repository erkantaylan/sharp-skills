---
name: fluentui-blazor-v5
description: Use when writing or debugging Microsoft FluentUI Blazor v5 (Microsoft.FluentUI.AspNetCore.Components 5.x) — FluentDataGrid columns and ItemKey, FluentSelect/FluentOption generics, dialogs and FluentDialogBody, toasts and message bars, tabs, nav, design tokens, custom element tag names, icons, providers and registration. Also use when upgrading between v5 release candidates, where component availability, CSS hooks and keyboard behaviour have changed silently.
---

# FluentUI Blazor v5

Everything here was read out of the shipped assembly and static assets of
**5.0.0-rc.5-26219.1**, diffed against **5.0.0-rc.4-26180.1**. Nothing is taken from the
documentation, which is wrong in specific named ways — see *The documentation is not a source*.

## Check the version before you trust a word of this

This library is **pre-GA**. Between rc.4 and rc.5 alone: one component was removed, an entire
subsystem was rewritten, every DataGrid CSS hook changed from class to attribute, two bugs were
fixed, two were not, and dialog keyboard handling changed. Component availability has already
shifted twice between release candidates.

**If the project's restored version is not exactly `5.0.0-rc.5-26219.1`, treat every fact in this
skill as a hypothesis** and re-verify the ones you are about to depend on. Do not assume a patch
bump is safe; the class→attribute migration above shipped inside one.

```bash
# what is pinned, and what is actually restored
grep -rn "FluentUI" Directory.Packages.props **/*.csproj
ls ~/.nuget/packages/microsoft.fluentui.aspnetcore.components/

# read the truth out of the assembly
~/.dotnet/tools/ilspycmd -p -o /tmp/fluent5 \
  ~/.nuget/packages/microsoft.fluentui.aspnetcore.components/<version>/lib/net10.0/Microsoft.FluentUI.AspNetCore.Components.dll
```

Three rules for that verification, each learned by getting it wrong first:

- **Diff two versions; do not just read one.** Most of what breaks on upgrade is a silent rename
  that compiles and then does nothing.
- **Grep cannot see computed keys.** The theme generator builds CSS variable names from template
  literals (`` [`colorStatus${r}Background1`] `` inside a `reduce`), so searching the JS for a token
  name finds nothing and proves nothing. Slice `lib.module.js` up to the theme factories, run it
  under `node`, dump `Object.keys()`. A static grep once "proved" five live tokens were dead.
- **The shipped XML docs are evidence of intent, not of behaviour.** Read the decompiled body.

## The documentation is not a source for this library

Named, verified errors in what ships with the package:

- The **README is v4-era** in both RCs. It still describes FAST, `Appearance.Accent`, and a
  `AddHttpClient()` prerequisite that nothing in the assembly uses — the string `HttpClient` does
  not appear anywhere in it.
- The README says `<FluentProviders />` adds "all available providers". **It does not mount
  `FluentMessageBarProvider`.**
- `FluentMenuButton`'s XML `<summary>` describes `FluentToggleButton`.
- `FluentTabs.ActiveTabIdChanged`'s XML doc says it takes a `FluentTab`. It is
  `EventCallback<string?>`.
- `TextAreaResize`'s member docs describe border appearance, not resizing.
- `ThemeSettings.Color`'s doc example is `"#0078D4"`; the actual default is `"0F6CBD"`, no `#`.

Decompile instead. It is faster than reading the docs and it is correct.

| Reference | Load when |
|---|---|
| [Data grid](references/data-grid.md) | Columns, `ItemKey`, sorting, pagination, pinning, the rc.5 CSS migration, the disposal race |
| [Forms and enums](references/forms-and-enums.md) | `FluentSelect`/`FluentOption` generics, text and number inputs, pickers, every enum's real members |
| [Dialogs and notifications](references/dialogs-and-notifications.md) | `ShowDialogAsync`, `FluentDialogBody`, toasts, message bars, awaits that never return, overlays, popovers |
| [Tabs and navigation](references/tabs-and-nav.md) | `FluentTabs` teardown, `DeferredLoading`, the nav family's nesting rules, layout areas |
| [Tokens and CSS](references/tokens-and-css.md) | Design tokens, theming, shadow DOM, the component → element map, scoped-CSS traps |
| [Icons and setup](references/icons-and-setup.md) | Registration, providers, icon assemblies and sizes, package shape |

## Known-false beliefs

These are in circulation — in project notes, issue trackers and prior analyses. Each was tested
against the assembly and is **wrong**. If you meet one in a codebase, this is the correction.

**"A `DelegatingHandler` or Polly pipeline drops the Blazor `SynchronizationContext`, so toasts
must be marshalled."** False, and measured false on a live circuit: `await` captures the context in
the *awaiting* method and a callee's `ConfigureAwait(false)` cannot reach into the caller's state
machine. The real cause of an awaited notification never returning is library-side and specific —
see [Dialogs and notifications](references/dialogs-and-notifications.md).

**"`IDialogService.ShowDialogAsync<T>` is broken — it renders with no header and no buttons."**
False. `FluentDialog` renders no chrome at all; the title, close button and footer live in
**`FluentDialogBody`, which your dialog component must render itself**. A dialog that omits it gets
exactly that symptom regardless of options.

**"`FluentMultiSplitter`, `FluentMenuButton`, `FluentRadioGroup`, `FluentLabel`, `FluentAutocomplete`
and `FluentCombobox` are absent or unreliable in v5."** All present, none `[Obsolete]`. Genuinely
gone: `FluentTextField`, `FluentNumberField`, `FluentSearch`, `FluentAnchor`, `FluentDesignTheme`,
`IToastService`, and — new in rc.5 — `FluentOverflowItem`.

**"`FluentNumberField`'s `Min`/`Max`/`Step` semantics were lost."** The opposite:
`FluentNumberInput<T>` types them as `TValue`, derives type bounds automatically, and clamps on
parse. What was actually dropped is `DataList`, `MaxLength`, `MinLength`, `ParsingErrorMessage` and
`ChildContent`.

**"Enter cannot submit an `EditForm` because the real input is in shadow DOM."** False.
`fluent-text-input` is form-associated and implements `implicitSubmit()` on host `keydown`. The real
failure is the ordinary HTML rule: with two or more text fields and no element whose `type` is
`"submit"`, implicit submission deliberately does nothing.

**"Binding a `FluentDatePicker` and a `FluentTimePicker` to one `DateTime` loses the time."** Not in
v5 — each explicitly preserves the other's half. Time is lost only on the *typed* or
`RenderStyle="Native"` path, which parses with no preservation.

**"Some typed token constants compile but emit a dead `var()`."** False — all 472 resolve at
runtime. This one was "proved" by grepping the JS, which cannot see computed keys.

**"`FluentPaginator` pages client-side over already-loaded items."** It does no paging at all. The
grid pages on the `IQueryable`, which under EF becomes `OFFSET`/`FETCH` on the server.

**"v5 builds only for net9.0 and net10.0."** net8.0 is a complete build.

**"You cannot style inside v5's shadow DOM."** Out of date: rc.5 added `ControlStyle` on the text,
textarea and number inputs, which pierces it via `applyShadowStyle`.

## Two habits that pay here

**Report the mechanism only when you have read it.** Every false belief above began as a real
symptom with an invented explanation, and the explanation then hardened into a rule — in one case
into a project-wide ban and a pile of hand-rolled replacement UI. A symptom you observed and a
mechanism you inferred are different claims; say which one you have.

**A component that compiles and renders nothing is the normal failure mode here.** Wrong enum
member, wrong `TValue`, a missing provider, a CSS hook that was renamed, a token typed by hand —
none of these throw. When something is invisible rather than broken, suspect one of those before
suspecting your own logic.

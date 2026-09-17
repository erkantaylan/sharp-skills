# Known issues and silent behaviour changes in rc.5

From the upstream issue tracker and migration documentation, as of the rc.5 release.

## Read this framing first

**46 issues were closed *after* the rc.5 tag.** Every one of them is still present in the released
package. A closed issue does not mean a fixed package unless a later version shipped — and at the
time of writing **no rc.6 or GA has been tagged**, the branch reorganisation for v5 is still in
flight (#5231), and `dev-v5` is 73 commits and 300 files ahead of the tag while still carrying the
version suffix `RC.5`.

Two of those are **regressions rc.5 introduced against rc.4**: data-grid arrow-key navigation stops
scrolling and sticks at virtualized edges (#5153), and a virtualized grid gets permanently stuck on
"No data to show" once `TotalItemCount` has ever been 0 (#5151).

## Open issues an rc.5 consumer will actually hit

| Issue | Effect |
|---|---|
| #5250 | Debounced inputs submit **stale values** before `ImmediateDelay` expires — silent data loss |
| #4833 | `[StreamRendering]` on a page with a `FluentDataGrid` throws `ArgumentException: The renderer does not have a component with ID …` |
| #5214 / #5215 | AppBar overflow menu does not open, and renders outside the viewport on small screens — mobile navigation unreachable. An rc.5 regression |
| #5281 | `FluentAutocomplete` with `Required` stays invalid after a selection — the form cannot be submitted |
| #5241 | `FluentListbox` selection marker lands on the wrong item after filtering |
| #4725 | `FluentAutocomplete` in single-select mode cannot retype over an existing value |
| #5140 | `FluentLink` / `FluentAnchorButton` cannot be middle-clicked into a new tab — a regression against v4 |
| #5274 | The official project template's login page fails with *"The value 'on' is not valid for 'RememberMe'"* |
| #5252 | Preview packages emit NU3018/NU3027/NU3042 signature warnings, which blocks strict-NuGet and `TreatWarningsAsErrors` builds |
| #4699, #4968 | `AutoFocus` ignored on conditionally rendered components, and after navigation |

**#5180 is the single most useful issue to read before committing to rc.5** — feedback from a real
production v4→v5 migration of a large Blazor Server app, 14 numbered defects plus five addenda,
closed by maintainers as too large to triage and mostly never split out. Still unfixed in it:
`Tooltip` unusable in both service modes; `DialogOptions.Width` is a no-op and dialogs cannot size to
content; the markup sanitizer's `ThrowOnUnsafe` **terminates the Blazor Server circuit** on a title
containing `<`; the data grid copies `Class` onto every `th` and `td`; dynamic columns lose their
declared position; `Margin` and `Padding` silently drop `var()` tokens; `FluentRadio`'s
`ChildContent` no longer labels the control.

Two bugs verified in the assembly have **no open issue at all** — nobody has reported them, and
neither is fixed on `dev-v5`: `FluentJSModule.DisposeAsync` leaving a disposed reference reachable,
and the popover's missing connectedness guard. The rc.5 data-grid class→attribute migration likewise
has no regression reports despite being a released breaking change.

## Silent default changes from v4

None of these produce a warning. Each changes rendering on upgrade.

- **`FluentGrid.Spacing` default 3 → 0** and **`FluentStack`'s always-applied 10px gap is gone**.
  Layouts collapse together and it reads as a CSS problem.
- **`FluentIcon` default colour `Color.Accent` → `currentColor`** — icons inherit their parent
  instead of being brand-coloured.
- **`FluentSkeleton`** `Width` 50px → 100%, `Height` 50px → 48px; it is no longer a web component.
- **`FluentAppBar.Count`** default 0 → null.
- **`FluentGridItem`'s `xs`/`sm`/… became `Xs`/`Sm`/…** — the wrong casing throws
  `InvalidOperationException` at runtime, not at compile time.
- **Drag event parameters changed from `Action<…>` to `EventCallback<…>`** — null checks must become
  `.HasDelegate`.
- **`FluentKeyCode.PreventMultipleKeyDown` was a static field and is now an instance parameter.**
- **`@onclick` on a `FluentMenuItem` must become the `OnClick` parameter** or, in upstream's own
  words, *"your app will crash at runtime when loading the page"*.

## Removed with no replacement

`FluentFlipper`, `FluentHorizontalScroll`, `FluentCollapsibleRegion`, `FluentAccessibility`,
`FluentEditForm`, `FluentProfileMenu`, `FluentBreadcrumb`, `FluentSliderLabel<TValue>`, interactive
rating (only the read-only `FluentRatingDisplay` survives), `TooltipGlobalOptions`, and
`FluentDialog`'s `TrapFocus`, `PreventDismissOnOverlayClick`, `PreventScroll` and aria options.

Replaced rather than removed: `FluentHeader`/`FluentBodyContent`/`FluentFooter`/`FluentMainLayout` →
`FluentLayout` + `FluentLayoutItem`; `FluentSplitter` → `FluentMultiSplitter`;
`FluentValidationMessage<T>` → `FluentField`; `FluentToast`/`FluentToastProvider` → `FluentMessageBar`
for the *component* path, though `INotificationService.ShowToastAsync` is very much alive.

## Migration helpers exist, and are not a package

`Microsoft.FluentUI.AspNetCore.Components.Migration` is a **namespace inside the core assembly**, not
a separate NuGet package. It ships conversion extensions for the v4 enums:

- `ToButtonAppearance()` — Neutral→Default, Accent→**Primary**, Hypertext→Default,
  Lightweight→**Transparent**, Outline→Outline, Stealth→**Subtle**, Filled→Default
- `ToBadgeAppearance()` — Lightweight→**Ghost**, everything else→**Filled**
- `ToTextInputAppearance()` and `ToTextAreaAppearance()` — Outline→Outline, Filled→**FilledDarker**
- `ToPositioning()` for tooltip positions

plus obsolete shims for `Appearance`, `FluentInputAppearance`, `TooltipPosition`, `MouseButton` and a
few components. Only the two `Appearance` extensions have tests; the rest are untested.

## Snapshot files in the upstream repo lie

Five orphaned `.verified.razor.html` files still contain `class="column-header"` and
`class="fluent-data-grid grid"` — pre-migration residue with no live test method behind them. If you
grep the repository for current DataGrid markup, read
`FluentDataGridTests.FluentDataGrid_Default.verified.razor.html` instead, which has the real
attribute vocabulary: `cell-type`, `col-index`, `col-justify`, `col-sort`, `col-select`, `select-all`,
`col-pinned`, `row-type`, `display-mode`.

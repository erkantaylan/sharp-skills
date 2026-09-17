# FluentDataGrid

Verified against 5.0.0-rc.5-26219.1, diffed against rc.4-26180.1.

## rc.5 renamed every CSS hook from class to attribute

The single biggest upgrade hazard, and it is completely silent: no compile error, no runtime error,
the rules simply stop matching.

| rc.4 | rc.5 |
|---|---|
| `.column-header` | `[cell-type=columnheader]` |
| `.resizable` | `[resizable=true]` |
| `.col-pinned-start` / `.col-pinned-end` | `[col-pinned=start]` / `[col-pinned=end]` |
| `.select-all` / `.multiline-text` | `[select-all=true]` / `[multiline=true]` |
| `.col-header-ui` / `.resize-handle` | `[col-header-ui]` / `[resize-handle]` |
| `.col-sort-button` / `.col-title-text` | `[col-sort-button]` / `[col-title-text]` |
| `.fluent-data-grid.grid` | `.fluent-data-grid[display-mode=grid]` |
| `.hover` on rows | `[hover=true]` |
| `empty-content-row`, `loading-content-row` | `[row-state=…]` |
| `.empty-content-cell` / `.loading-content-cell` | `[row-state=empty-content]>td` / `[row-state=loading-content]>td` |

The **cell** classes in that last row are the ones apps actually target for padding, and they are
gone from rc.5 entirely (0 occurrences in the bundle), joined by a new `[row-state=error-content]`.
rc.4's hover rule excluded empty rows with `td:not(.empty-content-cell)`; rc.5 does it at row level
with `[row-state=…]` exclusions instead.

Upstream shipped one stale selector doing this: `[dir=rtl] .fluent-data-grid .col-header-ui svg` is
the only class-based grid rule left in rc.5, and `col-header-ui` is now an attribute — so the RTL
chevron flip never applies.

## `ItemKey` defaults to the item instance

`public Func<TGridItem, object> ItemKey { get; set; } = (TGridItem x) => x;`, consumed as
`SetKey(ItemKey(item))` on each row. Blazor matches keys with `object.Equals`, so for a reference
type with no `Equals` override this is **reference identity**.

Re-materialise `Items` on every render — a re-issued `AsNoTracking` query, a `.Select(x => new Dto{…})`
in the render path — and no key matches, so Blazor tears down and rebuilds every row component and
every cell instead of patching attributes. Clicks land on dead elements, focused inputs are destroyed
mid-keystroke, popovers anchored to a row throw. Records and other value-equality types are immune.
Otherwise set `ItemKey="@(x => x.Id)"` and memoise the projection.

`SelectColumn` derives its equality comparer from `ItemKey`, so this is also what decides whether a
selection survives. Upstream's own test proves the good case: with `ItemKey="@(p => p.PersonId)"`
and a provider handing back fresh instances per page, selection survives repagination. Leave the
default and selection is reference-based, so every page change silently clears it.

## Column configuration throws

All in `FinishCollectingColumns()` / `ValidatePinnedColumnConstraints()`, identical in both RCs:

- `GridTemplateColumns` on the grid **and** `Width` on any column:
  `"You can use either the 'GridTemplateColumns' parameter on the grid or the 'Width' property at the column level, not both."`
  `SelectColumn<T>` is exempt — and so is `HierarchicalSelectColumn<T>`, which derives from it.
- `"Only one column can have 'HierarchicalToggle' set to true."` and
  `"The 'HierarchicalToggle' parameter can only be set on the first column of the grid."`
- `"Column '…' has Pin set but no Width. Pinned columns require an explicit Width."`
- Start- and end-pinned columns must be contiguous, each with its own message.
- `"FluentDataGrid cannot use both Virtualize and RowDetails at the same time."`, likewise with
  `MultiLine`, and `"FluentDataGrid requires one of Items or ItemsProvider, but both were specified."`

**A `SelectColumn` silently costs you the `1fr` layout.** Its constructor sets `Width = "50px"`, and
`UpdateGridTemplateColumns` switches to `string.Join(' ', _columns.Select(x => x.Width ?? "auto"))`
as soon as *any* column has a width. Every other column becomes `auto`. Set `GridTemplateColumns`
explicitly on any grid with row selection.

The `AutoFit` path is subtler than it looks: the `Width ?? "auto"` branch is **not** an `else`, so it
fires regardless of `AutoFit` whenever some column has a width — and with `AutoFit` and no widths at
all nothing is assigned server-side, leaving `grid-template-columns` absent until the JS
`AutoFitGridColumns` measures and writes it inline after first render.

## `PropertyColumn` is not sortable for free

It derives `SortBy` from `Property` **only inside `if (Sortable.HasValue)`**. Leave `Sortable` unset
and `SortBy` is never assigned, `IsSortableByDefault()` returns false, and the column does not sort.
Write `Sortable="true"`.

Moving the display into a `TemplateColumn` drops sorting for the other reason: `TemplateColumn` has
no `Property` to derive from, so it needs an explicit
`SortBy="@(GridSort<T>.ByAscending(x => x.Field))"`.

## Rows are `display: contents`, and nothing in the library is scoped

`.fluent-data-grid[display-mode=grid] thead|tbody|>tr { display: contents }` — the real grid items
are the `td`/`th`, which the library generates.

**Row height is a parameter, not a CSS fight.** `FluentDataGrid.RowSize` takes
`DataGridRowSize { Smaller = 24, Small = 32, Medium = 44, Large = 58 }` and defaults to `Small`.
`FluentDataGridCell.BuildStyle` writes it as an **inline** `height` on every cell, so a stylesheet
rule cannot beat it without `!important` — and does not need to. Rendered and measured: default
gives `height: 32px`, `RowSize="DataGridRowSize.Medium"` gives `height: 44px`. `Large` (58) is the
ceiling; past that you really are fighting an inline style. Cell **padding** is different — that one
is a global rule (`.fluent-data-grid td:not([col-select=true]) { padding: 0 18px }`) and is styled
globally.

That same rule also sets `overflow: hidden; text-overflow: ellipsis; white-space: nowrap` on every
cell. A column a few pixels too narrow therefore does not wrap and does not visibly clip — it paints
a single ellipsis dot that reads as punctuation.

The broader fact: `Microsoft.FluentUI.AspNetCore.Components.bundle.scp.css` contains **zero `[b-…]`
scope attributes** in either RC. The whole library stylesheet is global; there is no scope id to
fight, and no `.razor.css` rule can ever reach library-generated DOM.

Specificity, for the common width fight: the base rule is plain `.fluent-data-grid` at (0,1,0), so
`table.fluent-data-grid` at (0,1,1) beats it. But rc.5's `[display-mode=grid]` rules are **(0,2,0)**
and that trick does not beat them.

## Pagination is server-side when your source is

`FluentPaginator` performs no paging — `GoToPageAsync` sets an index and raises a callback. The grid
pages in `ResolveItemsRequestAsync` with `.Skip(request.StartIndex).Take(request.Count.Value)` on the
`IQueryable`, which with an EF provider translates to `OFFSET`/`FETCH` and an async `CountAsync`. It
is client-side only if you hand the grid an in-memory queryable.

`PaginationState.TotalItemCount` is `int?` with a **private setter** — set it via
`SetTotalItemCountAsync(int, bool force = false)`, which the grid also calls itself. A paginator not
attached to a grid therefore renders "0 items" over a screen full of rows, because nothing ever set
it. `ItemsPerPage` defaults to **10** and has a plain public setter that notifies nothing; use
`SetItemsPerPageAsync`.

`SetItemsPerPageAsync` **clamps, it does not reset**: it ends in
`if (CurrentPageIndex > 0 && CurrentPageIndex > LastPageIndex) SetCurrentPageIndexAsync(LastPageIndex)`.
A user on page 5 of 20-per-page who switches to 100-per-page stays on a valid-but-arbitrary page 5.
Follow it with `SetCurrentPageIndexAsync(0)` if you want the usual behaviour.

## Loading and empty states, and why they are English

Neither is documented by the component's own naming, and the two halves work differently.

`Loading` is `bool?`, and the grid uses `EffectiveLoadingValue => Loading ?? (ItemsProvider != null)`.
If you bind `Items=` (an `IQueryable`) rather than `ItemsProvider=`, `Loading` stays `null` and
resolves to **false forever** — so `LoadingContent` is unreachable by construction for the most
common grid shape. Set `Loading` explicitly if you want a loading row.

The defaults come from two different places:

- **`LoadingContent`** defaults to hard-coded English markup in `BuildRenderTree`.
- **Empty content** defaults to `Localizer[LanguageResource.DataGrid_EmptyContent]` — *"No data to
  show."* — which goes through `IFluentLocalizer`.

So translating one does not touch the other. Rendering an empty grid confirms both the string and
that the row carries `row-state="empty-content"`. The empty state is also unpadded: it is a bold
sliver hard under the header, which reads as a rendering fault rather than an empty result.

`EmptyContent` is a named child-content element, so adding it forces every column on that grid into
an explicit `<ChildContent>` wrapper — otherwise **RZ9996**. Same Razor rule as `HeaderCellItemTemplate`
below.

## `ShowHover` is a click affordance, not a row tint

It defaults to `false`, and rc.5 emits it as `hover="true"` from `ShowHoverAttribute => Grid.ShowHover`.
The library ships both halves of the affordance in one rule —
`…tr[hover]:not(…):hover td { cursor: pointer; background-color: … }` — so you cannot take the tint
without the pointer. Turning it on for a grid whose rows ignore clicks paints a `cursor: pointer`
over a dead row, which is a usability bug, not decoration. Turn it on only where the row is actually
clickable.

## Header templates and select-all

`HeaderCellItemTemplate` replaces the header **content**, not the cell: an early return that skips
the sort button, title, sort icon and aria wiring. The `<th>`, its attributes, the `col-header-ui`
div and the resize handle are still emitted, so resize and reorder survive. Adding the template
means the column's own body needs an explicit `<ChildContent>`, because the implicit shorthand is no
longer available once there are two render-fragment children.

`FluentCheckbox` needs `ThreeState="true"` for indeterminate, and its built-in cycle is
**Unchecked → Checked → Indeterminate** — not select-all semantics. Its state is `bool? CheckState`
/ `CheckStateChanged`, not `Value`. Recompute the header state rather than trusting what it reports.

## The disposal race, and exactly what rc.5 fixed

Every grid render re-arms `EnableColumnResizing` and `EnableColumnReordering` for the next
`OnAfterRenderAsync`. That interop completes one to three round-trips later; if navigation disposes
the page inside that window the exception is unhandled in the after-render path. Whether that
**terminates the circuit** depends on you: `ComponentState.NotifyRenderCompletedAsync` routes it
through `HandleExceptionViaErrorBoundary`, which walks the logical parent chain for an
`IErrorBoundary`. With no `ErrorBoundary` ancestor — the usual case — the circuit dies. An
`ErrorBoundary` is not a fix, though: it renders `ErrorContent` *instead of* `ChildContent`, so the
page blanks. Invisible on localhost; with a TCP delay proxy, event-then-navigate reproduced 10/10.

**rc.4:** `EnableColumnResizing` goes straight to `gridElement.querySelectorAll('.column-header.resizable')`
with no guard, while its sibling `Initialize` does guard. `EnableColumnReordering` is unguarded too.

**rc.5 fixes those two.** Both functions now open with
`if (gridElement === undefined || gridElement === null) { return; }`, and the selector became
`th[cell-type='columnheader'][resizable='true']`.

**Six other entry points in rc.5's `FluentDataGrid.razor.js` still dereference `gridElement`
unguarded:** `CheckColumnPopupPosition`, `ResetColumnWidths`, `ResizeColumnDiscrete`,
`ResizeColumnExact`, `AutoFitGridColumns` and `UpdatePinnedColumnOffsets`. The two that got guards
are not the whole story.

**The other half is still broken in rc.5.** `FluentJSModule.DisposeAsync` disposes the module but
never nulls `_jsModule`, so `Imported` stays `true` and `ObjectReference` keeps handing back a
disposed reference instead of throwing. An `ObjectDisposedException` from that path is still live.

If you must guard it yourself, subclass and override `OnAfterRenderAsync`, swallowing exactly
`ObjectDisposedException`, `JSDisconnectedException`, and the `JSException` raised from this
module — narrowly, so real JS errors still surface.

**Do not filter on the message naming `gridElement`.** The browser reports the *dereferenced
property*, not the variable: the real text is `Cannot read properties of null (reading 'id')`, and
the property varies by browser and by which call site lost the race (`id`, `querySelector`,
`querySelectorAll`, `parentElement`). A filter looking for `gridElement` misses every one of them.
The stable discriminator is the **origin**: the JS stack, including the script URL, is part of
`JSException.Message`, so match on the path `"/Components/DataGrid/FluentDataGrid"` — not the
filename, which is fingerprinted.

Subclassing note: repeat `[CascadingTypeParameter(nameof(TGridItem))]` on the subclass. The Razor
compiler reads it off the tag's own class and does not reliably inherit it, and without it every
child `PropertyColumn`/`TemplateColumn` loses type inference.

## New in rc.5

- **Row details:** `RowDetails`, `HasRowDetails`, `OnRowDetailsToggle`, `IsRowDetailsExpanded`, the
  `Toggle`/`Expand`/`CollapseRowDetailsAsync` family, and a `DataGridRowState` enum.
- **A plain `<td>` fast path** that bypasses the `FluentDataGridCell<T>` component when
  `CellNeedsComponent` is false. Attaching a single `OnCellClick` or `OnCellFocus` handler flips
  **every** column back to the component path — a real performance cliff from one parameter.
- **Deterministic header ids** — `HeaderButtonId => $"{Grid.Id}-col-{Index}"` replaces a random
  per-column id, which finally makes headers addressable from tests and JS.

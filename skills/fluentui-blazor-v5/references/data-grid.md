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
are the `td`/`th`, which the library generates. Row height and cell padding must be styled globally.

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
`SetTotalItemCountAsync(int, bool force = false)`, which the grid also calls itself.

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
the page inside that window the exception is unhandled in the after-render path and **terminates the
circuit**. Invisible on localhost; with a TCP delay proxy, event-then-navigate reproduced 10/10.

**rc.4:** `EnableColumnResizing` goes straight to `gridElement.querySelectorAll('.column-header.resizable')`
with no guard, while its sibling `Initialize` does guard. `EnableColumnReordering` is unguarded too.

**rc.5 fixes half of it.** Both functions now open with
`if (gridElement === undefined || gridElement === null) { return; }`, and the selector became
`th[cell-type='columnheader'][resizable='true']`.

**The other half is still broken in rc.5.** `FluentJSModule.DisposeAsync` disposes the module but
never nulls `_jsModule`, so `Imported` stays `true` and `ObjectReference` keeps handing back a
disposed reference instead of throwing. An `ObjectDisposedException` from that path is still live.

If you must guard it yourself, subclass and override `OnAfterRenderAsync`, swallowing exactly
`ObjectDisposedException`, `JSDisconnectedException`, and the `JSException` whose message names a
null `gridElement` — narrowly, so real JS errors still surface.

## New in rc.5

- **Row details:** `RowDetails`, `HasRowDetails`, `OnRowDetailsToggle`, `IsRowDetailsExpanded`, the
  `Toggle`/`Expand`/`CollapseRowDetailsAsync` family, and a `DataGridRowState` enum.
- **A plain `<td>` fast path** that bypasses the `FluentDataGridCell<T>` component when
  `CellNeedsComponent` is false. Attaching a single `OnCellClick` or `OnCellFocus` handler flips
  **every** column back to the component path — a real performance cliff from one parameter.
- **Deterministic header ids** — `HeaderButtonId => $"{Grid.Id}-col-{Index}"` replaces a random
  per-column id, which finally makes headers addressable from tests and JS.

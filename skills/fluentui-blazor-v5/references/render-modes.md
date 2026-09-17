# Render modes, static SSR and accessibility

Verified against 5.0.0-rc.5-26219.1 and the upstream `dev-v5` source at the rc.5 tag.

## v5 components do render under static SSR

The claim that they do not is false, and upstream's own repository disproves it: rc.5 ships
`examples/Samples/FluentUI.Samples.SSR/`, a pure static-SSR app whose `Program.cs` calls
`AddRazorComponents()` with **no** `.AddInteractiveServerComponents()` and `MapRazorComponents<App>()`
with **no** render mode — and which renders a `FluentDataGrid` with four sortable columns, plus
`FluentLayout`, `FluentStack` and `FluentProviders`.

The mechanism is that the library ships a **Blazor JS initializer**
(`Microsoft.FluentUI.AspNetCore.Components.lib.module.js`), and `blazor.web.js` runs initializers on
a Blazor Web App even when zero interactive render modes are configured. Its `beforeStart` calls
`defineComponents()`, registering every `fluent-*` custom element, so the elements upgrade and the
CSS applies regardless of render mode. The source is explicit about supporting this — one comment
reads *"Wire up hamburger menus even when statically rendered (no interactive render mode)"*, and
`FluentInputBase.Name` carries *"This value needs to be set manually for SSR scenarios to work
correctly."*

**What actually breaks under static SSR:** every `EventCallback` — `@onclick`, `@bind`, `OnClick`;
`IJSRuntime`, so `OnAfterRenderAsync` never runs and no JS module is ever imported; and the dialog,
toast, tooltip and keycode services, which need a circuit.

**Hard requirement:** `blazor.web.js` must be on the page. A Razor Pages or MVC host without it gets
un-upgraded custom elements and no styling.

The belief comes from one blunt line in the install documentation — *"Fluent UI Blazor requires
interactive rendering"* — which the maintainers' own home page qualifies: *"most components will
display correctly but will not offer complete, if any, functionality."* Read as "interactive
components require interactivity", which is what the post-rc.5 README now says.

Two static-SSR gaps are open upstream and present in rc.5: `[StreamRendering]` on a page containing
a `FluentDataGrid` throws `ArgumentException: The renderer does not have a component with ID …`
(#4833, acknowledged by a maintainer as a known DataGrid issue), and form components have no
automatic `Name`, so SSR form posts need it set by hand (#4835).

## Accessibility

Upstream has **no accessibility documentation** — no a11y page, nothing in the migration guide. What
follows is read from source and from the component pages that do carry an a11y section.

**Focus trapping is not implemented in this library.** v5 removed the `TrapFocus` option outright,
there is no focus-trap code in the repository, and the `tabbable` dependency is unused. Trapping is
delegated to the native `<dialog>` and popover semantics of the underlying web components. If you
need to state what a v5 dialog does about focus trapping, the authority is
`@fluentui/web-components` v3, not this package — and the docs site never mentions it either.

**Focus restoration is implemented.** The dialog script stores `document.activeElement` on open and
calls `previousActiveElement?.focus()` on close.

**Dialog keyboard shortcuts are deliberately narrow.** Enter and Escape fire the primary and
secondary actions only when focus is inside the dialog *and* within `[slot="action"]`,
`[slot="footer"]`, `[slot="close"]` or `[slot="title-action"]` — which is why Enter in a text field
inside a dialog does nothing in rc.5, and why the shortcuts stop working once you supply your own
buttons in place of the standard actions.

**Documented keyboard behaviour worth knowing:**

- **Data grid.** Arrow keys navigate. On a sortable header, Tab reaches the sort button and Enter
  toggles direction; **Shift+S** removes column sorting and restores the default, though it cannot
  remove the grid's own default sort. With options enabled, Tab reaches the options button, Enter
  toggles the popover, Escape closes it. With resizing enabled, **+** and **−** resize the focused
  column in 10px steps and **Shift+R** resets. With a `SelectColumn` and the default
  `SelectFromEntireRow="true"`, Enter toggles row selection. Right-clicking a header removes
  sorting. A sortable column has a **75px minimum width**.
- **Nav.** Arrow Up/Down, Home and End move between items; Enter or Space expands a category.
  Because it renders both `<a>` and `<button>`, it uses a **roving tabindex** — tabbing away and
  back returns focus to the last focused item.
- **Toast.** Announcements use an alert role and live-region behaviour keyed to `ToastOptions.Intent`,
  and assertive intents interrupt screen-reader users. A toast with no actions never receives
  keyboard focus, so its hover-to-pause timer is mouse-only.

**ARIA wiring is thin and mostly manual.** Across the whole component source: `aria-label` ×59,
`aria-hidden` ×9, `aria-rowindex` ×4, `aria-expanded` ×4, `aria-live` ×3, and single-digit counts
for the rest. The data grid is the densest consumer; most components wire nothing.

**Two open a11y bugs, both present in rc.5:** `AutoFocus` is ignored on conditionally rendered
components (#4699), and ignored after navigation — it works only on a full page load (#4968).

Upstream's own `FluentWizard` page carries a disclaimer that it "is not yet fully compatible with
accessibility."

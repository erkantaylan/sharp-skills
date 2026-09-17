# Tabs, navigation and layout

Verified against 5.0.0-rc.5-26219.1. All tab types are byte-identical to rc.4.

## `ActiveTabIdChanged` fires during teardown, not just on click

`FluentTab.DisposeAsync` calls `Owner.RemoveTabAsync(this)`, and that method re-points the
selection:

```csharp
FluentTab fluentTab = Tabs.FirstOrDefault();
string firstTabId = fluentTab?.Id;
if (!string.Equals(firstTabId, tab.Id, StringComparison.Ordinal))
{
    ActiveTab = fluentTab; ActiveTabId = firstTabId;
    if (ActiveTabChanged.HasDelegate)   { await ActiveTabChanged.InvokeAsync(fluentTab); }
    if (ActiveTabIdChanged.HasDelegate) { await ActiveTabIdChanged.InvokeAsync(firstTabId); }
}
```

Two things make this worse than it first looks. It re-points at the **first registered** tab, not
the next one. And the guard compares that id to the *disposing* tab's — it has nothing to do with
whether the disposing tab was active. So **any conditionally-rendered `@if` tab disappearing
anywhere in the set silently resets the user's selection and raises the callback**, and disposing
the whole component raises it one final time with `null`.

If the handler navigates — the `@bind-ActiveTabId:after` pattern — this drives the router back into
a page that is already tearing down. Guard on URI ownership: teardown runs *after* `Nav.Uri` has
already moved to the destination, so comparing against the tab's own route separates a real click
from teardown cleanly.

A plain `@bind-ActiveTabId` with no navigation needs no guard; the renderer drops `StateHasChanged`
from a disposing component silently.

## `DeferredLoading` is the opposite of lazy

`BuildRenderTree` always emits a `role="tabpanel"` div for **every** visible tab; hiding is the web
component's job via `activeid`. `DeferredLoading` changes only what goes inside:

```csharp
if (item.DeferredLoading && ActiveTabId != item.Id)  // loading template or FluentProgressBar
else                                                  // item.ChildContent
```

So with it off, every tab's content is in the tree at all times. With it **on**, the subtree is
swapped out the moment the tab stops being active — Blazor disposes those components, so returning
re-runs `OnInitializedAsync` and refetches on *every* switch. If you want load-once-then-keep, use a
`visited` flag, not this parameter.

The condition tests `ActiveTabId` only, never `ActiveTab?.Id`. Bind only `@bind-ActiveTab` and leave
`ActiveTabId` null, and every deferred panel renders its loading state forever.

## Every `FluentTab` needs an explicit `Id`

The constructor assigns `Id = Identifier.NewId()` — a fresh random 8-character value per component
*instance*. The whole identity model is keyed on that string: `ActiveTabId`, `aria-controls`,
`TabPanelId => Id + "-panel"`, and the `DeferredLoading` comparison. Any re-instantiation — an
unkeyed `@foreach`, a parent re-render that changes tree shape — mints a new id and orphans the
binding.

## The nav family, and what it does not enforce

`FluentNav`, `FluentNavCategory`, `FluentNavItem`, `FluentNavSectionHeader` replace v4's
`FluentNavMenu`/`FluentNavGroup`/`FluentNavLink`, which no longer exist.

Three runtime guards, verbatim:

```
FluentNavCategory can only be used as a direct child of FluentNav.
FluentNavItem can only be used as a direct child of FluentNav.
FluentNavItem can only be used as a direct child of FluentNav or a FluentNavCategory.
FluentNavSectionHeader can only be used as a direct child of FluentNav.
```

`FluentNavCategory.RegisterSubitem` takes `List<FluentNavItem>`, so a category cannot hold a
category — **but this is not enforced by a throw.** Both guards test the unnamed `Owner` cascade,
which resolves to the root `FluentNav` however deeply you nest, and `FluentNavCategory` does not
consume the `Category` cascade at all. A category inside a category therefore *renders*: registered
against the root, absent from `_subitems`, ignored by `HasActiveSubitem()` and auto-expand, with
broken chrome. If you are expecting an exception to tell you the nesting is wrong, you will not get
one. Two levels is the limit; build deeper structure yourself.

New in rc.5: a disabled `FluentNavItem` with an `Href` no longer renders a live `NavLink` and emits
a `disabled` attribute. In rc.4 it was still clickable.

## Layout areas — the enum name is not the attribute value

```csharp
LayoutArea { Header→"header", Footer→"footer", Navigation→"nav", Content→"content", Aside→"aside" }
```

`Navigation` emits `area="nav"`. Write CSS against `[area="nav"]`. `Area` defaults to `Content`, and
header and footer get an implicit `height: var(--layout-header-height|--layout-footer-height)`
unless `Height` is set.

**The header is a hardcoded brand bar.** From the shipped bundle:

```css
.fluent-layout-item[area=header]{
  background-color:var(--colorBrandBackground);
  color:var(--colorNeutralForegroundOnBrand); … }
```

Override only `background-color` and the text stays near-white on your new colour — and
`FluentLayoutHamburger` hardcodes the same foreground token on its button in C#. The selector is
(0,2,0), so a plain custom class will not win it: use inline `Style=`, match the specificity, or
redefine `--colorBrandBackground` / `--colorNeutralForegroundOnBrand` on the element.

## `FluentAnchorButton` stopped being a full page load in rc.5

In **rc.4** nothing patched the web component, so its shadow-DOM `<a>` was a plain browser
navigation that Blazor's enhanced navigation never intercepted — every click a full page load.

**rc.5** adds a `ForceLoad` parameter and a startup override that replaces `handleNavigation` on
both `fluent-anchor-button` and `fluent-link`, routing same-origin URLs through
`Blazor.navigateTo(...)`. Cross-origin still clicks an internal proxy anchor.

Both directions matter on upgrade. A workaround that assumed "anchor buttons always full-load" is
now wrong; and anything that *relied* on the full load — to escape a component-lifetime race, for
instance — now needs `ForceLoad="true"` to keep behaving the same.

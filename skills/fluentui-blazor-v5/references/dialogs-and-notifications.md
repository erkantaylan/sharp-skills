# Dialogs, toasts, message bars, overlays and popovers

Verified against 5.0.0-rc.5-26219.1, diffed against rc.4-26180.1.

## A dialog renders no chrome unless you render `FluentDialogBody`

This is the one that gets misdiagnosed as a library bug. `FluentDialog` emits only the custom
element plus a `DynamicComponent` for your type — no title slot, no close button, no action slot.
**Every piece of chrome lives in `FluentDialogBody`, which your dialog component must render
itself.** The shipped `FluentMessageBox` is the canonical example: a plain `ComponentBase` whose
whole render tree is a `FluentDialogBody`.

Omit it and you get a dialog with no header and no footer buttons no matter what options you pass.
That symptom is correct behaviour, not a defect.

Then there are two content gates, and they differ:

```csharp
// DialogOptionsFooterAction — Visible defaults TRUE, so Label is the only gate
internal bool ToDisplay { get { if (!string.IsNullOrEmpty(Label)) { return Visible; } return false; } }

// DialogOptionsHeaderAction — Visible has NO initializer, so it defaults FALSE
public bool Visible { get; set; }
internal bool ToDisplay { get { if (!string.IsNullOrEmpty(Label) || Icon != null) { return Visible; } return false; } }
```

`CloseAction` is constructed with a Dismiss icon but its `Visible` is never set — by anything in the
library, including the built-in message boxes. **The ✕ is strictly opt-in.**

Working shape:

```csharp
await DialogService.ShowDialogAsync<MyDialog>(o =>
{
    o.Header.Title = "Edit customer";
    o.Header.CloseAction.Visible = true;      // opt-in
    o.Footer.PrimaryAction.Label = "Save";
    o.Footer.SecondaryAction.Label = "Cancel";
    o.Parameters["CustomerId"] = id;
});
```

`DialogOptions.Parameters` replaces v4's `DialogParameters` and `IDialogContentComponent<T>`, both
of which are gone. It is a `Dictionary<string, object?>` with **`StringComparer.Ordinal`**, consumed
by `DynamicComponent` — so keys are case-sensitive and must match the `[Parameter]` property name
exactly or Blazor throws at render.

`DialogOptionsHeader.AddAction(...)` sets `Visible = true` for you, unlike `CloseAction` and
`InfoAction`. Extra actions render before Info and Close.

## Deriving from `FluentDialogInstance`

Its `OnInitializedAsync` supplies default OK/Cancel labels when yours are null, wires the close
action's click handler, and then calls `OnInitializeDialog(header, footer)`. **`OnInitializeDialog`
is the intended override point.** Override `OnInitializedAsync` without awaiting `base` and you lose
the default labels, the default handlers and the initialisation call at once.

This is also the one path where a bare `DialogOptions` still produces footer buttons.

## `IDialogService`, and the v4 argument trap

Message-first throughout: `ShowSuccessAsync(message, title = null, button = null)`, likewise
Warning/Error/Info. `ShowConfirmationAsync(message, title, primaryButton, secondaryButton)` returns
`Task<DialogResult>` **directly** — check `.Cancelled`; there is no `await dialog.Result`.

v4 was also message-first, so that part of the migration is a non-issue. The genuine trap is
`ShowConfirmationAsync`, where v4's `(message, primaryText, secondaryText, title)` became v5's
`(message, title, primaryButton, secondaryButton)`. A v4 call like
`ShowConfirmationAsync(msg, "Save", "Discard")` compiles and silently reinterprets "Save" as the
title and "Discard" as the primary button.

Also present: `ShowMessageBoxAsync`, `ShowOverlayAsync`/`HideOverlayAsync`, `ShowDrawerAsync<T>`,
`RegisterInputFileAsync`/`UnregisterInputFileAsync`, `CloseAsync`.

## Why an awaited notification call can never return

Every `Show*Async` on both services ends in `return await instance.Result;` — a
`TaskCompletionSource`. Whether it is ever completed depends on `ResultTiming`.

**Message bars, rc.4: a genuine hang.** `MessageBarOptions` had no `ResultTiming`, the TCS was
completed only in `CloseCoreAsync`, and `Lifetime` defaults to null meaning "until dismissed". So
`await NotificationService.ShowErrorBarAsync(...)` **never returns until a human clicks the ✕**.
In a request path that is an indefinite hang, and everything after the await never runs.

**rc.5 fixes it**: adds `MessageBarResultTiming { Closed, Visible }`, defaults it to `Visible`,
completes the task on display, and forces `Visible` in the four `Show*BarAsync` helpers.

**Toasts were never affected under defaults** — `ToastOptions.ResultTiming` is `Queued` and the
instance is marked queued synchronously before the first await. Three opt-in paths still hang:

- `ResultTiming.Closed` on a toast that never auto-closes. Setting `QuickAction1.Label` or
  `QuickAction2.Label` makes `GetLifetime` return `TimeSpan.Zero` — no timeout — regardless of the
  configured 7-second default.
- `ResultTiming.Visible` with more than `MaxToastCount` (default **4**) live toasts; the fifth parks
  until a slot frees.
- Either of those with the provider torn down. A missing provider normally throws
  `FluentServiceProviderException<FluentToastProvider>`, but that check tests whether `ProviderId`
  is empty, and `ProviderId` survives a tear-down — so a provider that was mounted and then removed
  by navigation leaves the call to proceed and the task to hang.

None of this requires a `SynchronizationContext` explanation, and the one in circulation is false
(see the main skill). For fire-and-forget from a request path, rely on the rc.5 defaults or do not
await the returned task.

The same shape applies to dialogs by design: `ShowDialogAsync` completes only in
`DialogService.CloseAsync`, because that is how you get the user's answer. Never await it on a path
that has to return.

## `INotificationService` replaced `IToastService` in rc.4

`IToastService` is present in rc.3, absent from rc.4 onward. The API is async-only. Toast text goes
in **`Title`** — `FluentToast` emits the title slot only when `Title` is non-empty, and the provider
returns null content when both `Message` and a custom component are absent. So `Title` alone renders
correctly; `Message` alone renders a body with no title.

## Popovers are still unguarded in rc.5

`FluentPopover` renders `fluent-popover-b`, and the `opened` attribute setter calls `showPopover()`
behind only:

```js
showPopover(){ !this.dialog || !this.anchorEl || ( … this.dialog.showPopover(), … ) }
```

`anchorEl` is a live `getElementById` lookup, so it passes for any anchor still in the document —
but **nothing checks whether the popover host itself is still connected**, and `connectedCallback`
does not retry. A host detached by a row re-render at the moment `Opened` flips throws
`InvalidStateError: Failed to execute 'showPopover' … Invalid on disconnected popover elements`.

Identical in rc.4 and rc.5; rc.5 only defers positioning by a frame. The precondition is item churn,
so a stable `ItemKey` and a memoised projection remove most of the exposure — see
[Data grid](data-grid.md).

## rc.5 changed dialog keyboard handling

Enter and Escape now fire the primary and secondary actions **only when focus is inside a footer or
header action slot**, gated by a new JS check. In rc.4, Enter in a text field inside a dialog
triggered the primary action. Any form relying on Enter-to-submit from inside a dialog breaks on
upgrade.

Relatedly, rc.5 made `FluentDialog` implement `IHandleEvent` to suppress its automatic render: menu
and listbox popovers rendered inside a dialog bubble `toggle`/`keydown` events that Blazor attributed
to the dialog, and the resulting `StateHasChanged` recreated keyed children and detached open
popovers.

## Overlays

`FluentOverlay` exists with `FullScreen`, `Interactive`, `BackgroundColor` (default
`var(--colorBackgroundOverlay)`), `Opacity` (40), `CloseMode`, `Visible`/`VisibleChanged`, and
`ChildContent` — which renders a `FluentSpinner` when null.

The service-level global overlay is a separate path and is **disabled by default**:

```
InvalidOperationException: The global overlay is disabled in the library configuration.
To enable it, set the UseGlobalOverlay property to true in the LibraryConfiguration.
```

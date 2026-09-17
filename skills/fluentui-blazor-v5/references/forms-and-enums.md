# Forms, inputs and enums

Verified against 5.0.0-rc.5-26219.1. All enums in this file are byte-identical to rc.4.

## `FluentSelect` and `FluentOption` have different arities

`FluentSelect<TOption, TValue>` takes two type parameters; `FluentOption<TValue>` takes one. The
option's `TValue` is inferred from its `Value=` expression, or supplied by the parent's
`[CascadingTypeParameter]` when `Value` is absent — so an option with no `Value` can never mismatch.

A mismatch throws at render, killing the circuit on page load:

```
InvalidOperationException: The type parameter 'Int32' of the FluentOption component
does not match the type 'Nullable`1' of the parent List component.
```

Note the message prints `` Nullable`1 ``, never `Int32?`, which makes it much less legible than it
should be. The usual cause is a nullable select (`TValue="int?"` for a "(all)" filter) whose loop
variable is uncast: `Value="@item.Id"` infers `int`. Cast it — `Value="@((int?)item.Id)"`.
`string` versus `string?` is immune, because NRT annotations are erased.

**`TOption=` on a `FluentOption` is not a silent no-op.** It does nothing for typing, but it is
captured by `CaptureUnmatchedValues` and splatted, so it lands in the DOM verbatim:
`<fluent-option id="…" value="1" TOption="string">`.

The nullable-`TValue` pattern also makes the library's generated `TypeInference` helpers emit
**CS8669** — expected noise, not a bug in your code.

## Text input

`FluentTextInput : FluentInputImmediateBase<string?>`, with `Immediate` defaulting to **false** and
`ImmediateDelay` to **200**. So `@bind-Value` commits on `change`/blur: a handler that reads the
model on Enter sees the previous value, because Enter does not blur. Set
`Immediate="true" ImmediateDelay="0"` when you need per-keystroke state.

`TextInputType` is exactly: `Text, Email, Password, Telephone, Url, Color, Search, Number`. **No
`Date`, no `DateTimeLocal`** — though the underlying web component does support them, because the
template forwards `type` verbatim to the inner `<input>`.

**Enter does reach the form.** `fluent-text-input` is form-associated, binds `keydown` on the host,
and implements `implicitSubmit()` which calls `form.requestSubmit()` or clicks the submit button.
What actually stops it is the standard HTML rule it faithfully implements: with two or more
text-ish fields and no element whose `type` attribute is `"submit"`, implicit submission is
suppressed. `fluent-textarea` has no `implicitSubmit`, correctly.

## Textarea

There is **no `Rows`**. It splats to an ignored HTML attribute and you get roughly two lines. Size
with `Height`, plus `Resize` (`TextAreaResize` = `None, Both, Horizontal, Vertical`), `AutoResize`,
`Size`, `Width`, `MaxLength`, `MinLength`.

The web component sets `--inline-size: 18rem` on `fluent-textarea`, and a separate
`max-width: 400px` on **`fluent-text-input`** — not on the textarea. Both are already neutralised by
the library's own bundle (`fluent-text-input{width:100%;max-width:unset}`, `fluent-textarea{width:100%}`),
so a width problem here is usually an unstretched flex ancestor, not the component.

## Number input

`FluentNumberInput<TValue>` types `Min`, `Max` and `Step` as `TValue`, fills them from a per-type
table at construction, and **clamps in `TryParseValueFromString`**. Type bounds are automatic — v4's
`UseTypeConstraints` opt-in is gone because it is now the default. An unsupported `TValue` throws at
construction:

```
InvalidOperationException: Unsupported type …. Supported types are sbyte, byte, short, ushort,
int, uint, long, ulong, float, double, and decimal (including nullable versions).
```

What v4's `FluentNumberField` had and this does not: `DataList`, `MaxLength`, `MinLength`,
`ParsingErrorMessage`, `ChildContent`, and `Size` as an `int` (now the `TextInputSize?` enum).
`HideStep` became `StepButtons` (`NumberInputStepVisibility = Visible, Hidden, Auto`).

## Dates and times

There is **no combined date-time component**. But the two compose correctly by design in v5:
`FluentDatePicker.OnSelectedDateAsync` preserves the existing time-of-day, and
`FluentTimePicker.TryParseValueFromString` preserves the existing date. Bind both to one `DateTime`.

The exception is the text path: **typing** a date, or `RenderStyle="Native"`, routes through a bare
`DateTime.TryParse` with no preservation, so the time becomes midnight. Only the popup-calendar
click path composes.

`FluentTimePicker<TValue>` defaults `StartHour = 8`, `EndHour = 18`, `Increment = 15` — an all-day
field needs `StartHour="0" EndHour="23"`. It derives from `FluentInputBase<TValue>`, **not** the
calendar base, so it has no `MinDate`/`MaxDate` at all; `MinDate`/`MaxDate` exist only on
`FluentCalendarBase`, i.e. `FluentCalendar` and `FluentDatePicker`. Supported `TValue`: `DateTime`,
`DateTime?`, `TimeOnly`, `TimeOnly?`. With a null `Value` its fallback date is
`Culture.Calendar.MinSupportedDateTime` (0001-01-01), not today.

## Enums, in full

A wrong member does not produce a helpful error. It produces a misleading **CS1662**
lambda-conversion error somewhere else entirely. Fix the enum first, then re-read the real error.

```csharp
ButtonAppearance { Default, Outline, Primary, Subtle, Transparent }
// no Lightweight, no Stealth, no Accent

BadgeColor { Brand, Danger, Important, Informative, Severe, Subtle, Success, Warning }
// no Neutral — the neutral pill is Subtle

VerticalAlignment   { Top, Center, Bottom, Stretch, SpaceBetween }
HorizontalAlignment { Left, Start, Center, Right, End, Stretch, SpaceBetween, Baseline }
// asymmetric: no Start/End vertically. VerticalAlignment also carries no [Description] at all.

DataGridCellAlignment { Start, Center, End }   // the column Align parameter's type
// there is no `Align` enum anywhere in the assembly

TextInputType          { Text, Email, Password, Telephone, Url, Color, Search, Number }
TextAreaResize         { None, Both, Horizontal, Vertical }
NumberInputStepVisibility { Visible, Hidden, Auto }
```

`Color` keeps four obsolete members with verbatim redirects: `Neutral` → *"Use Default instead."*,
`Accent` → *"Use Primary instead."*, `Fill` → *"Use Default instead."*, `FillInverse` → *"Use
Lightweight instead."* They still compile, and the RC emits obsolete-API warnings across the board —
which is why upstream's own install guidance says to turn `TreatWarningsAsErrors` off during the
prerelease.

## New in rc.5

- **`ControlStyle`** on text input, textarea and number input pierces the shadow DOM via
  `applyShadowStyle(Element, ".control", …)` — the supported way to style the inner `<input>`. Two
  ready-made constants ship for hiding browser chrome: `HidePasswordToggle`, `HideContactsToggle`.
- `IFluentControlAriaLabel` and `UseNativeConstraintValidationUI` on `FluentInputBase`.
- **`FluentOverflowItem` was removed** and the overflow API rewritten — `MoreButtonTemplate` renamed
  to `MoreTemplate`, `OnOverflowRaised` changed signature, new `OverflowItem`/`OverflowBehavior`/
  `OverflowState` types. rc.4 overflow code does not compile on rc.5.

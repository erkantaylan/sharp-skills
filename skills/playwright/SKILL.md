---
name: playwright
description: Use when writing, debugging, or fixing flaky end-to-end browser tests with Playwright — selectors, waiting, authentication, tracing, CI setup. Covers the JavaScript and .NET bindings, including the assertion form that silently does not retry.
---

# Playwright

The traps below are the ones that produce tests which pass locally, fail in CI, and
get "fixed" with a sleep. Verified against Playwright 1.62.

## Use the assertion that retries

This is the single most common Playwright bug, and the wrong form looks completely
reasonable:

```ts
// ❌ Reads the DOM once, right now. Fails if the UI has not caught up yet.
expect(await page.locator('#total').textContent()).toBe('42');

// ✅ Polls until it matches or times out.
await expect(page.locator('#total')).toHaveText('42');
```

```csharp
// ❌ no retry
Assert.Equal("42", await page.Locator("#total").TextContentAsync());

// ✅ retries — Microsoft.Playwright.Assertions.Expect
await Expect(page.Locator("#total")).ToHaveTextAsync("42");
```

The rule: **the locator goes inside the assertion, not outside.** Anything of the
form `assert(await locator.something())` has already given up the retry. Web-first
assertions are `toHaveText`, `toBeVisible`, `toHaveValue`, `toHaveCount`,
`toHaveURL`, `toContainText` and friends — reach for those before reaching for a
manual read.

## Never sleep, and never `networkidle`

```ts
await page.waitForTimeout(2000);                    // ❌ flaky and slow
await page.waitForLoadState('networkidle');         // ❌ officially discouraged
```

Actions and web-first assertions already wait for the element to be attached,
visible, stable and enabled. If a test needs a wait that auto-waiting does not
cover, wait for the *observable consequence* — a response, a URL, an element state —
never for time:

```ts
await page.waitForResponse(r => r.url().includes('/api/orders') && r.ok());
await expect(page).toHaveURL(/\/orders\/\d+/);
```

`networkidle` is discouraged because an app with polling, websockets or analytics
never goes idle, so it either hangs until timeout or resolves at an arbitrary moment.

## Locators are strict

A locator matching more than one element **throws** rather than picking the first.
That is a feature — it catches selectors that silently drifted onto a second match.

```ts
page.getByRole('button', { name: 'Delete' })          // throws if there are 3
page.getByRole('button', { name: 'Delete' }).first()  // usually papering over it
```

Prefer narrowing the scope to taking `.first()`:

```ts
page.getByRole('row', { name: 'Invoice 42' }).getByRole('button', { name: 'Delete' })
```

Locators are lazy — they re-resolve on every use, so they survive re-renders.
`ElementHandle` and the legacy `page.$` / `page.$$` do not; a handle held across a
re-render points at a detached node. Use locators unless you have a specific reason.

## Selector priority

Pick the first that fits: **role** (`getByRole`) → **label** (`getByLabel`) →
**placeholder** → **text** → **test id** (`getByTestId`) → CSS/XPath.

Role and label selectors assert accessibility as a side effect and survive restyling.
CSS selectors tied to class names break on every refactor. `getByTestId` is the
escape hatch when there is no accessible handle — it requires adding attributes to
production markup, which is a team decision, not a default.

## Log in once, not per test

Logging in through the UI in every test is usually the largest chunk of a slow suite.
Do it once, save the cookies and local storage, and load them per test.

```ts
// setup project writes the state
await page.context().storageState({ path: 'playwright/.auth/user.json' });

// playwright.config.ts
projects: [
  { name: 'setup', testMatch: /.*\.setup\.ts/ },
  { name: 'chromium', use: { storageState: 'playwright/.auth/user.json' },
    dependencies: ['setup'] },
]
```

A **setup project with `dependencies`** is the current pattern; `globalSetup` is the
older one and does not give you a browser, fixtures or tracing. In .NET, pass
`StorageStatePath` in `ContextOptions()`.

Never commit the auth state file — it holds live session cookies.

## Debugging is the trace viewer

Reading a stack trace from a browser test is mostly wasted effort. Record a trace and
look at the DOM snapshot at the moment of failure.

```ts
// playwright.config.ts — record only on a retried failure, so it costs nothing green
use: { trace: 'on-first-retry' }
```

```bash
npx playwright show-trace trace.zip
npx playwright test --ui        # interactive, for local work
npx playwright test --debug     # step through with Inspector
```

In .NET there is no runner config file — start and stop tracing around the test:

```csharp
await Context.Tracing.StartAsync(new() { Screenshots = true, Snapshots = true });
// ...
await Context.Tracing.StopAsync(new() { Path = "trace.zip" });
```

## .NET binding specifics

```xml
<PackageReference Include="Microsoft.Playwright.Xunit" />   <!-- or .NUnit / .MSTest -->
```

All three provide the same base classes — `PageTest`, `ContextTest`, `BrowserTest`,
`PlaywrightTest` — each giving a fresh browser context per test. Inherit `PageTest`
and you get `Page`, `Context` and `Expect()` for free.

**Browsers are installed by a script generated into the build output**, not by `npx`:

```bash
dotnet build
pwsh bin/Debug/net10.0/playwright.ps1 install --with-deps
```

This needs PowerShell (`pwsh`) on the machine, including in CI, and the path contains
the TFM — so it changes when you retarget.

Other divergences: every call is `...Async`, assertions come from
`Microsoft.Playwright.Assertions.Expect` (not the test framework's `Assert`), roles
are an enum (`AriaRole.Button`), and there is no `playwright.config.ts` — parallelism
and retries come from the test framework, not from Playwright.

## CI

```yaml
- uses: actions/cache@v4
  with:
    path: ~/.cache/ms-playwright
    key: playwright-${{ runner.os }}-${{ hashFiles('**/package-lock.json') }}
```

Browser binaries are ~400 MB and downloading them on every run dominates the job.
Key the cache on whatever pins the Playwright version — the lockfile, or
`Directory.Packages.props` for a .NET repo — because a cached browser set that does
not match the client version fails at launch.

`--with-deps` installs OS packages as root; on a self-hosted runner install them once
in the image instead.

Set `retries: 2` in CI only. Retries locally hide flakiness at the moment you are
best placed to fix it.

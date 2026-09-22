---
name: rider-razor
description: Use when Rider or ReSharper reports errors in a .razor file that dotnet build does not — "Cannot resolve symbol" on every identifier in one component, "Closing brace expected" at the end of the file, "Cannot convert expression type 'lambda expression' to return type RenderFragment", "Ambiguous invocation … AppendFormatted", or a project-level "Generator 'RazorSourceGenerator' failed to generate sources". Also use before putting a raw string literal, a tuple deconstruction or a Guid into an @code block, and when deciding whether a red IDE means the code is wrong.
---

# Rider disagrees with the Razor compiler, and the compiler is right

A model handed *"the IDE shows 91 errors"* starts rewriting working code. That is the failure this
skill exists to prevent: in a `.razor` file the IDE's error list and the build disagree, and it is
almost always the IDE that is behind.

**The check is one command, and it comes first.** If `dotnet build` is clean, no amount of red
justifies changing logic:

```bash
dotnet build <project>.csproj -v q --nologo   # 0 errors => the IDE is wrong, not the code
```

**The fix, every time, is to move the offending C# into the `.razor.cs` code-behind.** ReSharper
parses ordinary C# files correctly; only its *Razor* C# path lags. Moving a method changes no IL
and no behaviour — the generated component is already a partial class.

Measured on **Rider 2026.2.0.2 (build 262.8665.400)**, .NET SDK 10.0.303, a Blazor Server app on
`net10.0`. Each entry below was confirmed by editing the construct in place and re-querying the
analyzer, against a tree that `dotnet build` reported as 0 errors throughout.

## Four constructs that build clean and light Rider up

| In a `.razor` file | Rider says | Real? |
|---|---|---|
| `$""" … """` in `@code` | *Unterminated string literal*, then **every** symbol in the file unresolved | No |
| `""" … """` in `@code` | project-level *Generator 'RazorSourceGenerator' failed to generate sources* | Its generator really does fail |
| `(string a, string b) = x switch {…}` as a statement-lambda's first statement | *Cannot convert expression type 'lambda expression' to return type 'RenderFragment'* | No |
| `@($"… {someGuid} …")` in markup | *Ambiguous invocation … AppendFormatted* | No |

### 1. An interpolated raw string poisons the whole file

```razor
@code {
    private static string Text(Owner o) => $"""          @* ❌ ~90 phantom errors in one file *@
        {o.Phone} belongs to {o.Name}
        """;
}
```

The tokenizer does not know `$"""`. It reads `$"` followed by `""`, reports *"Unterminated string
literal. Strings that start with a quotation mark (") must be terminated before the end of the
line. However, strings that start with @ and a quotation mark (@") can span multiple lines"* — a
message that predates C# 11 — and then never recovers. The whole component is re-parsed in a
shifted state, so `@inject ApiRequest Api` on line 6 becomes *"Cannot resolve symbol 'ApiRequest'"*,
every field and method call becomes *"Cannot resolve symbol"*, and the last line of the file becomes
*"Closing brace expected"*.

**One file like this can account for an entire solution-wide error count.** Do not start fixing the
symbols; find the string.

### 2. A plain raw string breaks the generator without a squiggle

`""" … """` with no `$` is the quieter one: ReSharper's own analysis handles it, so the file shows
zero errors and looks innocent. What fails is Rider's bundled Razor source generator, which surfaces
only as a **project-level warning** — `Generator 'RazorSourceGenerator' failed to generate sources`,
same "unterminated string literal" text — and stops generating for that project. Nothing points at
the file. It is easy to carry for months.

A JSON sample, a SQL snippet or a template in a `@code` block belongs in the code-behind as a
`const`, where it keeps its shape.

### 3. Deconstruction at the head of a statement-lambda

```razor
@code {
    private static RenderFragment Badge(Status s) => builder =>
    {
        (string bg, string label) = s switch { … };   // ❌ "Cannot convert … to RenderFragment"
        var (bg2, label2)         = s switch { … };   // ✅ identical IL, parses fine
```

Only the **explicitly typed** tuple deconstruction trips it, and only as the first statement. The
same lambda shape with any other opening statement is fine — verified against four other
`RenderFragment X(…) => builder => { … }` members in the same project, all clean.

### 4. A `Guid` in an interpolation hole in markup

```razor
<span title="@($"Batch: {row.BatchId}")">          @* ❌ Ambiguous invocation … AppendFormatted *@
<span title="@($"Pharmacy: {row.PharmacyId}")">    @* ✅ int *@
<span title="@($"UTC: {row.CapturedAt:yyyy-MM-dd}")">  @* ✅ DateTimeOffset with a format *@
```

Tested in one file, same `context`, same interpolated-string shape: an `int` hole, a `string`
ternary hole and a formatted `DateTimeOffset` hole all resolve; the `Guid` hole does not. Neither
`.ToString()` nor `:D` rescues it — with `:D` the reported candidate list merely drops to the
three-argument overloads. The candidates ReSharper prints are all non-generic
(`object?`, `scoped ReadOnlySpan<char>`, `string?`), which suggests it is not considering
`AppendFormatted<T>(T)` here; that explanation is a hypothesis, the behaviour is not.

Build the string in a code-behind helper and call it: `title="@RowTitle(context)"`.

## Finding which file owns the count

The solution-wide counter tells you how many, never where. **Rider's MCP `get_project_problems`
under-reports these badly** — it returned a single Roslyn warning while the IDE was showing 91
errors, because the ReSharper-side diagnostics are not in that set. `get_file_problems` per file is
the only reliable enumeration, and it is fast enough to sweep a whole component tree:

```bash
find src -name '*.razor' -not -path '*/obj/*'    # then get_file_problems on each, errorsOnly
```

Worth re-running after an IDE or SDK bump, not just when someone notices red.

## The one real cost of moving code out

Blazor stamps the scoped-CSS attribute only on elements authored in `.razor` **markup**. DOM built
by a `RenderFragment`/`RenderTreeBuilder` in a code-behind gets no scope attribute, so a
`.razor.css` rule will never match it. If the moved code emits styled markup, keep the styling
inline or in the global stylesheet — or leave that particular member in the `.razor` file and move
only the string.

## Upstream

The Razor **compiler** carried the same two string defects: [dotnet/razor#7084](https://github.com/dotnet/razor/issues/7084)
*"Improve string handling support"* (`Area-Razor-Compiler`, `area-parsing`), filed 2022-08-02,
listing exactly (1) interpolated strings with `"` in a hole and (2) C# 11 raw string literals. It is
closed, and the shipping net10 compiler handles both — which is why the build is clean and the IDE
is not. On the JetBrains side the raw-string reports are RIDER-91864 and RSRP-492678; this skill
does not assert their current state, only that the behaviour above reproduces on the build named at
the top.

**Scope, honestly:** one Rider build, one Windows machine, one Blazor Server solution. The four
constructs and their fixes were each verified by edit-and-recheck; they are not claimed for Visual
Studio, for other ReSharper versions, or as a complete list.

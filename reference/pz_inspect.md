# Inspect the current page state

Prints a console summary of the page: URL, device, recording and cursor
state, and – when `target` is given – the target's matches resolved
relative to the current scope **without** auto-waiting: a single
resolution pass, each match shown as a short opening tag with its
visibility, enabled state, and box (long lists are truncated).

The header names the context. At the root it reads `paparazzi page`. In
a scoped context from
[`pz_find()`](https://posit-dev.github.io/paparazzi/reference/pz_find.md)
it reads `paparazzi scope`, with the scope stack right under it: live
match counts for each level, plus a warning when pinned elements have
gone stale.

`show = "screenshot"` additionally captures an annotated screenshot:
dashed outlines over the scope's elements, solid numbered outlines over
the target's matches, drawn under paparazzi's shadow-root overlay, so
they never appear in
[`pz_screenshot()`](https://posit-dev.github.io/paparazzi/reference/pz_screenshot.md)
output. `show = "browser"` draws the same outlines in the live page,
leaves them, and opens the browser via the page's `$view()`.
`show = "auto"` picks `"screenshot"` in interactive sessions and
`"none"` otherwise.

## Usage

``` r
pz_inspect(
  ctx,
  target = NULL,
  ...,
  path = NULL,
  show = c("auto", "screenshot", "browser", "none")
)
```

## Arguments

- ctx:

  A paparazzi context.

- target:

  A CSS selector string, a
  [`pz_loc()`](https://posit-dev.github.io/paparazzi/reference/pz_loc.md)
  spec, or a list of specs and strings (a union matching any of them).
  `NULL` (default) omits the target section.

- ...:

  Checked empty; reserved for future use.

- path:

  Where to write the annotated screenshot; `NULL` writes a temporary
  file. Only used with `show = "screenshot"`.

- show:

  How to visualize: `"auto"`, `"screenshot"` (annotated capture),
  `"browser"` (outlines left in the live page), or `"none"`.

## Value

`ctx`, invisibly, so it can be dropped anywhere in a chain.

## Examples

``` r
page <- pz_open(pz_example("tasks"))
page |> pz_inspect()
#> ── paparazzi page ──────────────────────────────────────────────────────────────
#> URL        http://127.0.0.1:4316/tasks.html
#> Device     992 × 1323 @1x · light
#> Recording  off · cursor hidden

# With a target: its matches, resolved inside the current scope
page |>
  pz_find(".task-list") |>
  pz_inspect(".task.done", show = "none")
#> ── paparazzi scope ─────────────────────────────────────────────────────────────
#> Scope      root › `.task-list` (1)
#> URL        http://127.0.0.1:4316/tasks.html
#> Device     992 × 1323 @1x · light
#> Target     `.task.done` → 1 match
#>   1  <li class="task done list-group-item d-flex align-items-cen…
#>      visible · enabled · at 146,400 · 685 × 48
#> Recording  off · cursor hidden

# An annotated screenshot outlines the scope and the numbered matches
page |>
  pz_find(".task-list") |>
  pz_inspect(".task-done", show = "screenshot", path = file.path(tempdir(), "inspect.png"))
#> ── paparazzi scope ─────────────────────────────────────────────────────────────
#> Scope      root › `.task-list` (1)
#> URL        http://127.0.0.1:4316/tasks.html
#> Device     992 × 1323 @1x · light
#> Target     `.task-done` → 7 matches
#>   1  <button type="button" class="task-done btn btn-sm btn-outli…
#>      visible · enabled · at 760,264 · 55 × 31
#>   2  <button type="button" class="task-done btn btn-sm btn-outli…
#>      visible · enabled · at 760,312 · 55 × 31
#>   3  <button type="button" class="task-done btn btn-sm btn-outli…
#>      visible · enabled · at 760,360 · 55 × 31
#>   4  <button type="button" class="task-done btn btn-sm btn-outli…
#>      hidden · enabled · at 760,408 · 55 × 31
#>   5  <button type="button" class="task-done btn btn-sm btn-outli…
#>      visible · enabled · at 760,456 · 55 × 31
#>   6  <button type="button" class="task-done btn btn-sm btn-outli…
#>      visible · enabled · at 760,504 · 55 × 31
#>   7  <button type="button" class="task-done btn btn-sm btn-outli…
#>      visible · enabled · at 760,552 · 55 × 31
#> Recording  off · cursor hidden
#> Annotated screenshot: /tmp/Rtmpt9tYl8/inspect.png
pz_close(page)
```

# Expect elements to be visible

`pz_expect_visible()` passes when at least one element matches and every
match is visible. `pz_expect_hidden()` is exactly
`pz_expect_visible(not = TRUE)`: it passes when no match is visible,
including when nothing matches.

Visibility follows the browser's own `checkVisibility()`
(<https://developer.mozilla.org/en-US/docs/Web/API/Element/checkVisibility>)
with CSS checks, so `display: none` and `visibility: hidden` anywhere up
the ancestor chain count as hidden. Opacity and viewport position are
not considered; use
[`pz_expect_in_viewport()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_in_viewport.md)
for position.

Outside of testthat, a failure aborts with a classed error of class
`"paparazzi_expectation_failure"`; inside testthat, the failure is
reported as a test failure instead. See
[`pz_expect_exists()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_exists.md)
for the retry, timeout, and bridge behavior shared by all expectations.

## Usage

``` r
pz_expect_visible(ctx, target = NULL, ..., not = FALSE, timeout = NULL)

pz_expect_hidden(ctx, target = NULL, ..., not = FALSE, timeout = NULL)
```

## Arguments

- ctx:

  A paparazzi context.

- target:

  A CSS selector string, a
  [`pz_loc()`](https://posit-dev.github.io/paparazzi/reference/pz_loc.md)
  spec, or a list of specs and strings (a union matching any of them).
  `NULL` means the current context: the pinned set at a scoped context
  (so
  [`pz_expect_exists()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_exists.md)
  on one trivially passes while the scope is live), the page body at the
  root.

- ...:

  Checked empty; reserved for future use.

- not:

  Invert the check.

- timeout:

  Seconds to wait for the expectation to pass; `NULL` (default) uses the
  session default, `0` checks once.

## Value

`ctx`, invisibly.

## Examples

``` r
if (FALSE) { # paparazzi:::examples_run()
page <- pz_open(pz_example("tasks"))
page |> pz_expect_hidden(target = "#help")

page |>
  pz_act_click("#toggle-help") |>
  pz_expect_visible(target = "#help")

# Every match must pass, so check one task or narrow the target
page |> pz_expect_visible(target = pz_loc(".task", has_text = "passport"))
pz_close(page)
}
```

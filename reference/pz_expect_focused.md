# Expect elements to be focused

`pz_expect_focused()` passes when at least one element matches and every
match is the page's focused element (`document.activeElement`). Focus it
with
[`pz_act_focus()`](https://posit-dev.github.io/paparazzi/reference/pz_act_focus.md)
or a
[`pz_act_click()`](https://posit-dev.github.io/paparazzi/reference/pz_act_click.md),
and remove it with
[`pz_act_blur()`](https://posit-dev.github.io/paparazzi/reference/pz_act_blur.md).

Outside of testthat, a failure aborts with a classed error of class
`"paparazzi_expectation_failure"`; inside testthat, the failure is
reported as a test failure instead. See
[`pz_expect_exists()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_exists.md)
for the retry, timeout, and bridge behavior shared by all expectations.

## Usage

``` r
pz_expect_focused(ctx, target = NULL, ..., not = FALSE, timeout = NULL)
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
page |>
  pz_act_click("#task-title") |>
  pz_expect_focused(target = "#task-title")

page |>
  pz_act_press("Tab") |>
  pz_expect_focused(target = "#task-priority")
pz_close(page)
}
```

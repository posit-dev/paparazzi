# Expect a class

`pz_expect_class()` passes when at least one element matches and every
match carries `class`. With `not = TRUE` it passes when no match does,
including when nothing matches. `class` is one class name, not a
space-separated list: expect each class with its own call.

Outside of testthat, a failure aborts with a classed error of class
`"paparazzi_expectation_failure"`; inside testthat, the failure is
reported as a test failure instead. See
[`pz_expect_exists()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_exists.md)
for the retry, timeout, and bridge behavior shared by all expectations.

## Usage

``` r
pz_expect_class(ctx, class, target = NULL, ..., not = FALSE, timeout = NULL)
```

## Arguments

- ctx:

  A paparazzi context.

- class:

  A single class name to expect on every match.

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
water <- pz_loc(".task", has_text = "Water")
page |> pz_expect_class("done", target = water, not = TRUE)

page |>
  pz_find(water) |>
  pz_act_click(".task-done") |>
  pz_expect_class("done")
pz_close(page)
}
```

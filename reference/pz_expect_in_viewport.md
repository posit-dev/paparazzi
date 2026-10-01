# Expect elements to be in the viewport

`pz_expect_in_viewport()` passes when at least one element matches and
every match overlaps the viewport: its bounding box crosses the visible
area by any amount. Elements entirely above, below, or beside the fold
fail; visibility itself is a separate expectation,
[`pz_expect_visible()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_visible.md).

Outside of testthat, a failure aborts with a classed error of class
`"paparazzi_expectation_failure"`; inside testthat, the failure is
reported as a test failure instead. See
[`pz_expect_exists()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_exists.md)
for the retry, timeout, and bridge behavior shared by all expectations.

## Usage

``` r
pz_expect_in_viewport(ctx, target = NULL, ..., not = FALSE, timeout = NULL)
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
page <- pz_open(pz_example("tasks"), height = 500)

# The last task is inside the scrolling list, below its visible area
last_task <- pz_loc(".task", which = "last")
page |> pz_expect_in_viewport(target = last_task, not = TRUE)
page |>
  pz_act_scroll(last_task) |>
  pz_expect_in_viewport(target = last_task)
pz_close(page)
}
```

# Expect at least one element to match

`pz_expect_exists()` passes when at least one element matching `target`
is in the DOM, visible or not. It's the one expectation where multiple
matches don't all have to satisfy the check: existence needs only one.
With `not = TRUE` it passes when nothing matches.

Expectations retry until they pass or `timeout` elapses, then return
`ctx` invisibly. Outside of testthat, a failure aborts with a classed
error of class `"paparazzi_expectation_failure"` showing the target, the
last observed value, and the time waited; inside testthat, the failure
is instead reported as a test failure, and a pass counts as a successful
testthat expectation.

## Usage

``` r
pz_expect_exists(ctx, target = NULL, ..., not = FALSE, timeout = NULL)
```

## Arguments

- ctx:

  A paparazzi context.

- target:

  A CSS selector string, a
  [`pz_loc()`](https://posit-dev.github.io/paparazzi/reference/pz_loc.md)
  spec, or a list of specs and strings (a union matching any of them).
  `NULL` means the current context: the pinned set at a scoped context
  (so `pz_expect_exists()` on one trivially passes while the scope is
  live), the page body at the root.

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
page |> pz_expect_exists(target = ".task")

# The help panel is in the page even while it's hidden
page |> pz_expect_exists(target = "#help")
page |> pz_expect_exists(target = ".error-message", not = TRUE)

# A failing expectation retries until the timeout, then errors
try(pz_expect_exists(page, target = ".error-message", timeout = 0.5))
pz_close(page)
}
```

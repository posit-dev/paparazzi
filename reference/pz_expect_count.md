# Expect a number of matching elements

`pz_expect_count()` passes when the number of elements matching `target`
satisfies the requirement: `n` is exact, or `min` and/or `max` give an
inclusive range (either may be `NULL`, meaning unbounded). With
`not = TRUE` it passes when the count does anything else. Specify
exactly one of `n` or `min`/`max`.

Outside of testthat, a failure aborts with a classed error of class
`"paparazzi_expectation_failure"`; inside testthat, the failure is
reported as a test failure instead. See
[`pz_expect_exists()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_exists.md)
for the retry, timeout, and bridge behavior shared by all expectations.

## Usage

``` r
pz_expect_count(
  ctx,
  n = NULL,
  target = NULL,
  ...,
  min = NULL,
  max = NULL,
  not = FALSE,
  timeout = NULL
)
```

## Arguments

- ctx:

  A paparazzi context.

- n:

  Exact expected count. Exclusive with `min` and `max`. `NULL` disables
  the exact-count check; supply `min` or `max`.

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

- min:

  Minimum count; with `max`, an inclusive range check. `NULL` omits the
  lower bound.

- max:

  Maximum count; with `min`, an inclusive range check. `NULL` omits the
  upper bound.

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
page |> pz_expect_count(7, target = ".task")
page |> pz_expect_count(min = 1, max = 2, target = ".task.done")

# Expectations retry, so they wait for the page to catch up: the new task
# appears after a short "Saving..." delay
page |>
  pz_act_type("Buy milk", target = "#task-title") |>
  pz_act_click("#add-task") |>
  pz_expect_count(8, target = ".task")
pz_close(page)
}
```

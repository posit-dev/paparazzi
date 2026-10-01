# Expect a JavaScript predicate to hold

`pz_expect_js()` passes when at least one element matches and the
predicate holds for every match: `expr` is evaluated as a function
receiving the element, e.g. `"el => el.scrollTop > 0"`. It's the escape
hatch for conditions the catalog doesn't cover. A predicate that throws
is a JavaScript error, not a failed check.

Outside of testthat, a failure aborts with a classed error of class
`"paparazzi_expectation_failure"`; inside testthat, the failure is
reported as a test failure instead. See
[`pz_expect_exists()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_exists.md)
for the retry, timeout, and bridge behavior shared by all expectations.

## Usage

``` r
pz_expect_js(ctx, expr, target = NULL, ..., not = FALSE, timeout = NULL)
```

## Arguments

- ctx:

  A paparazzi context.

- expr:

  A JavaScript function receiving the element, as a string, e.g.
  `"el => el.scrollTop > 0"`.

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

# The predicate receives each matching element
page |> pz_expect_js("el => el.scrollHeight > el.clientHeight", target = ".task-list")
page |> pz_expect_js("el => el.draggable", target = ".task")
pz_close(page)
}
```

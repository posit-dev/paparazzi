# Expect the page title

`pz_expect_title()` passes when the page's `<title>` satisfies `title`.
It works from any context, scoped or root: the title belongs to the
page, not to an element.

Outside of testthat, a failure aborts with a classed error of class
`"paparazzi_expectation_failure"`; inside testthat, the failure is
reported as a test failure instead. See
[`pz_expect_exists()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_exists.md)
for the retry, timeout, and bridge behavior shared by all expectations.

## Usage

``` r
pz_expect_title(
  ctx,
  title,
  ...,
  match = c("contains", "exact", "regex"),
  not = FALSE,
  timeout = NULL
)
```

## Arguments

- ctx:

  A paparazzi context.

- title:

  The expected page title, a single string.

- ...:

  Checked empty; reserved for future use.

- match:

  How to compare `url`: `"contains"` (substring), `"exact"`, or
  `"regex"` (an R regex matched with
  [`grepl()`](https://rdrr.io/r/base/grep.html)).

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
page |> pz_expect_title("Tasks", match = "exact")
pz_close(page)
}
```

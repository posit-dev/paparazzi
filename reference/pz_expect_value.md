# Expect element values

`pz_expect_value()` passes when at least one element matches and the
`value` property of every match satisfies `value`. Elements without a
value property (paragraphs, divs) read as missing and satisfy no
`value`. Checkbox and radio values come from their `value` attribute
(the default is `"on"`), whatever their checked state.

A length-1 `value` applies to every match. A length-`n` `value` requires
exactly `n` matches and compares pairwise, in order. With `not = TRUE`,
the expectation passes when no match satisfies `value`, including when
nothing matches.

Outside of testthat, a failure aborts with a classed error of class
`"paparazzi_expectation_failure"`; inside testthat, the failure is
reported as a test failure instead. See
[`pz_expect_exists()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_exists.md)
for the retry, timeout, and bridge behavior shared by all expectations.

## Usage

``` r
pz_expect_value(
  ctx,
  value,
  target = NULL,
  ...,
  match = c("contains", "exact", "regex"),
  not = FALSE,
  timeout = NULL
)
```

## Arguments

- ctx:

  A paparazzi context.

- value:

  A character vector of expected values: length 1 applies to every
  match, length `n` is compared pairwise in order.

- target:

  A CSS selector string, a
  [`pz_loc()`](https://posit-dev.github.io/paparazzi/reference/pz_loc.md)
  spec, or a list of specs and strings (a union matching any of them).
  `NULL` means the current context: the pinned set at a scoped context,
  or the page body at the root, so `pz_expect_text(page, "Welcome")`
  checks the page text.

- ...:

  Checked empty; reserved for future use.

- match:

  How to compare `text`: `"contains"` (substring), `"exact"`, or
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
page |> pz_expect_value("normal", target = "#task-priority", match = "exact")

page |>
  pz_act_type("Buy milk", target = "#task-title") |>
  pz_expect_value("milk", target = "#task-title")
pz_close(page)
}
```

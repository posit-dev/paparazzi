# Expect attributes

`pz_expect_attr()` passes when at least one element matches and every
matched element satisfies every named attribute/value pair in `...`.
Missing attributes satisfy no pair. Comparisons are exact by default;
`.match = "contains"` or `"regex"` applies to all pairs in the call.

A length-1 value applies to every element. A vector requires exactly
that many matches and compares pairwise, in order. With `.not = TRUE`,
the expectation passes when the combined condition does not hold,
including when no element matches.

Outside of testthat, a failure aborts with a classed error of class
`"paparazzi_expectation_failure"`; inside testthat, the failure is
reported as a test failure. See
[`pz_expect_exists()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_exists.md)
for the retry, timeout, and bridge behavior shared by all expectations.

## Usage

``` r
pz_expect_attr(
  ctx,
  .target = NULL,
  ...,
  .match = c("exact", "contains", "regex"),
  .not = FALSE,
  .timeout = NULL
)
```

## Arguments

- ctx:

  A paparazzi context.

- .target:

  A CSS selector string, a
  [`pz_loc()`](https://posit-dev.github.io/paparazzi/reference/pz_loc.md)
  spec, or a list of either. `NULL` selects the current context.

- ...:

  Named attribute/value pairs. Values are character vectors; use
  backticks for names such as `aria-expanded`. Dynamic dots support
  splicing a named list with `!!!`.

- .match:

  Comparison mode for all pairs: `"exact"` (default), `"contains"`, or
  `"regex"`.

- .not:

  Invert the combined expectation?

- .timeout:

  Seconds to wait; `NULL` uses the session default.

## Value

`ctx`, invisibly.

## Examples

``` r
if (FALSE) { # paparazzi:::examples_run()
page <- pz_open(pz_example("tasks"))
page |> pz_expect_attr(
  pz_loc(".task", has_text = "tax"), `data-priority` = "high"
)

page |>
  pz_act_click("#toggle-help") |>
  pz_expect_attr("#toggle-help", `aria-expanded` = "true")
pz_close(page)
}
```

# Expect computed styles

`pz_expect_style()` passes when at least one element matches `.target`
and every match has every named property set to the expected value,
comparing **computed** styles – what the browser actually applied, the
same values Playwright's `toHaveCSS()` and jQuery's `.css()` read.

Property names accept snake_case, converted to the CSS kebab-case
spelling (`font_size` becomes `font-size`); custom properties
(`` `--bs-primary` = "#0d6efd" ``) pass through unchanged. By default
the expected values are normalized in the browser: what you write
(`"1.5rem"`, `"#0d6efd"`, `"50%"`, `"currentColor"`) is resolved against
the same context the target sees, so it matches the computed value the
browser reports. Numeric pixel values compare with a 0.5px tolerance.

Outside of testthat, a failure aborts with a classed error of class
`"paparazzi_expectation_failure"`; inside testthat, the failure is
reported as a test failure instead. See
[`pz_expect_exists()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_exists.md)
for the retry, timeout, and bridge behavior shared by all expectations.

## Usage

``` r
pz_expect_style(
  ctx,
  .target = NULL,
  ...,
  .not = FALSE,
  .timeout = NULL,
  .normalize = TRUE
)
```

## Arguments

- ctx:

  A paparazzi context.

- .target:

  A CSS selector string, a
  [`pz_loc()`](https://posit-dev.github.io/paparazzi/reference/pz_loc.md)
  spec, or a list of specs and strings (a union matching any of them).
  `NULL` means the current context: the pinned set at a scoped context,
  or the page body at the root.

- ...:

  Property/value pairs, e.g. `color = "red"`. Dynamic dots: a list
  spliced in with `!!!` works. Names are the CSS property names,
  snake_case accepted.

- .not:

  Invert the combined expectation?

- .timeout:

  Seconds to wait; `NULL` uses the session default.

- .normalize:

  Normalize expected values in the browser before comparing? See
  Details.

## Value

`ctx`, invisibly.

## Details

With `.not = TRUE` the expectation passes when at least one
property/value pair doesn't match (including when nothing matches). With
`.normalize = FALSE` the expected values are compared as raw strings
against the browser's computed output, for contexts the probe can't
reproduce (unusual `%` cases, container query units); the pixel
tolerance still applies.

Shorthand properties (`margin`, `border`, `background`, ...) are
unreliable in computed styles and error with a longhand suggestion;
check the longhand properties instead. A value the browser rejects
errors immediately as invalid CSS, without retrying (only detected with
`.normalize = TRUE`).

## Examples

``` r
if (FALSE) { # paparazzi:::examples_run()
page <- pz_open(pz_example("tasks"))

# Expected values are written as you'd write them in CSS
page |> pz_expect_style("#add-task", background_color = "#0d6efd")
page |> pz_expect_style("h1", font_size = "1.5rem")
page |> pz_expect_style("#help", display = "none")

page |>
  pz_act_click("#toggle-help") |>
  pz_expect_style("#help", display = "none", .not = TRUE)
pz_close(page)
}
```

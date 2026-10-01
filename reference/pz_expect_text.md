# Expect element text content

`pz_expect_text()` passes when at least one element matches and the text
of every match satisfies `text`. Whitespace collapses on both sides
before comparing, so `"Save now"` matches text reading "Save now".

A length-1 `text` applies to every match. A length-`n` `text` requires
exactly `n` matches and compares pairwise, in order. With `not = TRUE`,
the expectation passes when no match satisfies `text`, including when
nothing matches.

Outside of testthat, a failure aborts with a classed error of class
`"paparazzi_expectation_failure"`; inside testthat, the failure is
reported as a test failure instead. See
[`pz_expect_exists()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_exists.md)
for the retry, timeout, and bridge behavior shared by all expectations.

## Usage

``` r
pz_expect_text(
  ctx,
  text,
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

- text:

  A character vector of expected text: length 1 applies to every match,
  length `n` is compared pairwise in order.

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
page |> pz_expect_text("Tasks", target = "h1", match = "exact")
page |> pz_expect_text("passport", target = pz_loc(".task", which = "first"))

# A vector compares pairwise with the matches, in order
page |> pz_expect_text(c("All", "Open", "Done"), target = ".filters a")

# Regular expressions use R's syntax
page |> pz_expect_text("^[A-Z]", target = ".task-title", match = "regex")

# On failure, the error shows the target and the last text seen
try(pz_expect_text(page, "otters", target = "h1", timeout = 0.5))
pz_close(page)
}
```

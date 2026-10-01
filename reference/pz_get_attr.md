# Read an attribute of matching elements

`pz_get_attr()` returns the named attribute of every element matching
`target`, one entry per match. Missing attributes give `NA`.

## Usage

``` r
pz_get_attr(ctx, name, target = NULL, ...)
```

## Arguments

- ctx:

  A paparazzi context.

- name:

  The attribute name.

- target:

  A CSS selector string, a
  [`pz_loc()`](https://posit-dev.github.io/paparazzi/reference/pz_loc.md)
  spec, or a list of specs and strings (a union matching any of them).
  `NULL` means the current context: the pinned set at a scoped context,
  or the page body at the root.

- ...:

  Checked empty; reserved for future use.

## Value

A character vector, one entry per match.

## Examples

``` r
page <- pz_open(pz_example("tasks"))
pz_get_attr(page, "data-priority", target = ".task")
#> [1] "high"   "high"   "normal" "low"    "normal" "low"    "normal"

# Missing attributes are NA
pz_get_attr(page, "aria-label", target = "select, input[type='text']")
#> [1] NA         "Priority"
pz_close(page)
```

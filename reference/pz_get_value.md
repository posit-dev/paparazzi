# Read the value of matching elements

`pz_get_value()` returns the `value` property of every element matching
`target`, one entry per match. Elements without a value property
(non-form elements) give `NA`.

## Usage

``` r
pz_get_value(ctx, target = NULL, ...)
```

## Arguments

- ctx:

  A paparazzi context.

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
page |> pz_act_type("Buy milk", target = "#task-title")
pz_get_value(page, target = list("#task-title", "#task-priority"))
#> [1] "Buy milk" "normal"  
pz_close(page)
```

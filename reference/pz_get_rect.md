# Read the geometry of matching elements

`pz_get_rect()` returns the bounding box of every element matching
`target`, one row per match in match order.

## Usage

``` r
pz_get_rect(ctx, target = NULL, ...)
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

A tibble with columns `x`, `y`, `width`, `height` (doubles, CSS pixels,
viewport-relative), one row per match, plus an `element` list-column.
Each `element` entry is a context scoped to that one match, pinned at
get time, so a chain can continue from it:
`rects$element[[2]] |> pz_act_hover()`.

## Examples

``` r
page <- pz_open(pz_example("tasks"))
rects <- pz_get_rect(page, target = ".filters a")
rects
#> # A tibble: 3 × 5
#>       x     y width height element 
#>   <dbl> <dbl> <dbl>  <dbl> <list>  
#> 1  145   215.  51.8     32 <pz_ctx>
#> 2  201.  215.  74.7     32 <pz_ctx>
#> 3  280.  215.  74.1     32 <pz_ctx>

# Each row's element column is a context scoped to that match
rects$element[[3]] |>
  pz_act_click() |>
  pz_expect_url("#done")
pz_close(page)
```

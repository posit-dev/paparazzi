# Read the page title

`pz_get_title()` returns the page's current title.

## Usage

``` r
pz_get_title(ctx)
```

## Arguments

- ctx:

  A paparazzi context.

## Value

A character vector of length one.

## Examples

``` r
page <- pz_open(pz_example("tasks"))
pz_get_title(page)
#> [1] "Tasks"
pz_close(page)
```

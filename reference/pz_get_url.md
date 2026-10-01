# Read the page URL

`pz_get_url()` returns the page's current URL.

## Usage

``` r
pz_get_url(ctx)
```

## Arguments

- ctx:

  A paparazzi context.

## Value

A character vector of length one.

## Examples

``` r
page <- pz_open(pz_example("tasks"))
page |> pz_act_click(pz_loc(".filters a", has_text = "Open"))
basename(pz_get_url(page))
#> [1] "tasks.html#open"
pz_close(page)
```

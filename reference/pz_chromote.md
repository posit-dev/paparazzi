# Get the underlying ChromoteSession

Escape hatch for raw Chrome DevTools Protocol calls.

## Usage

``` r
pz_chromote(ctx)
```

## Arguments

- ctx:

  A paparazzi context.

## Value

The
[`chromote::ChromoteSession`](https://rstudio.github.io/chromote/reference/ChromoteSession.html)
backing the page.

## Examples

``` r
page <- pz_open(pz_example("tasks"))
session <- pz_chromote(page)

# Make raw Chrome DevTools Protocol calls
session$Browser$getVersion()$product
#> [1] "Chrome/154.0.8037.57"
session$Performance$enable()
#> named list()
metrics <- session$Performance$getMetrics()$metrics
Filter(function(m) m$name == "Nodes", metrics)[[1]]$value
#> [1] 274
pz_close(page)
```

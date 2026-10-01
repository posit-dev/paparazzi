# Close a page

Closes the page's browser session and any server it started. A page
opened from a shared serving handle leaves the server running. Closing
an already-closed page is a no-op.

## Usage

``` r
pz_close(page)
```

## Arguments

- page:

  A `PaparazziPage` from
  [`pz_open()`](https://posit-dev.github.io/paparazzi/reference/pz_open.md),
  or any context on it (such as the end of a chain). A chain from
  [`pz_record_start()`](https://posit-dev.github.io/paparazzi/reference/pz_record_start.md)
  whose recording is still running stops and writes it first.

## Value

The page, invisibly.

## Examples

``` r
if (FALSE) { # paparazzi:::examples_run()
page <- pz_open(pz_example("tasks"))
pz_close(page)

# Closing a closed page does nothing
pz_close(page)
}
```

# Serve static files over HTTP

Serves a directory or a single HTML file on a free local port. For a
file, its directory is served and the handle URL points to that file.
Other files in that directory are also accessible over HTTP.

## Usage

``` r
pz_serve_static(path, ...)
```

## Arguments

- path:

  A path to a directory or an `.html` file.

- ...:

  Reserved; must be empty.

## Value

A `PaparazziServe` handle with `$url`, `$port`, `$stop()`,
`$is_running()`, and `$logs()`. Static servers have no captured logs:
`$logs()` returns
[`character()`](https://rdrr.io/r/base/character.html). Pass the handle
to
[`pz_open()`](https://posit-dev.github.io/paparazzi/reference/pz_open.md)
to share a server across pages. Closing those pages leaves it running.
`$stop()` is idempotent; use `withr::defer(server$stop())` for cleanup.
A finalizer stops the server as a last resort.

## Examples

``` r
# Serve the example page over HTTP instead of opening it as file://
server <- pz_serve_static(pz_example("tasks"))
page <- pz_open(server)
pz_get_url(page)
#> [1] "http://127.0.0.1:7653/tasks.html"
pz_close(page)
server$stop()
```

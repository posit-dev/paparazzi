# Serve static files over HTTP

Serves a directory or a single HTML file on a free local port. For a
file, its directory is served and the handle URL points to that file.
Other files in that directory are also accessible over HTTP.

## Usage

``` r
pz_serve_static(path, ..., root = NULL)
```

## Arguments

- path:

  A path to a directory or an `.html` file.

- ...:

  Reserved; must be empty.

- root:

  The directory to serve as the server root. Defaults to the file's
  directory for an `.html` file. Only supported when `path` is a file,
  which must live inside `root` (both are resolved with
  [`normalizePath()`](https://rdrr.io/r/base/normalizePath.html), so
  symlinks are resolved first, and `root` can't be the filesystem root);
  the handle URL points at `path` relative to `root`. Use it when the
  page references assets outside its own directory, such as
  `../deps/styles.css`.

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
# pz_open() serves HTML files over HTTP on its own; pz_serve_static()
# creates a handle you can share across pages instead
server <- pz_serve_static(pz_example("tasks"))
page <- pz_open(server)
pz_get_url(page)
#> [1] "http://127.0.0.1:5953/tasks.html"
pz_close(page)
server$stop()
```

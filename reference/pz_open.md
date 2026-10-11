# Open a page

Opens a URL, local file, local server, or existing
[chromote::ChromoteSession](https://rstudio.github.io/chromote/reference/ChromoteSession.html)
as a paparazzi page: the root context that starts every `|>` chain.

## Usage

``` r
pz_open(
  x,
  ...,
  wait = c("auto", "load", "shiny", "none"),
  timeout = 10,
  shiny_options = list(),
  envvars = NULL
)
```

## Arguments

- x:

  What to open:

  - a URL string (any scheme, including `file://`, `about:`, `data:`);

  - a Shiny app directory or runnable app file (`app.R`, `app-*.R`,
    `*_app.R`, etc.);

  - a `.qmd` or `.Rmd` file, or a Quarto project directory;

  - a directory of static files, served over HTTP;

  - an `.html` file, served over HTTP when the httpuv package is
    installed (as `file://` otherwise). The file's directory is the
    server root, so pages that reference assets outside it, such as
    `../deps/styles.css`, need an explicit `file://` URL or a handle
    from
    [`pz_serve_static()`](https://posit-dev.github.io/paparazzi/reference/pz_serve_static.md)
    on the right root;

  - any other existing local file, opened as `file://` (use
    [`pz_serve_static()`](https://posit-dev.github.io/paparazzi/reference/pz_serve_static.md)
    to serve a page over HTTP);

  - a handle from
    [`pz_serve_shiny()`](https://posit-dev.github.io/paparazzi/reference/pz_serve_shiny.md),
    [`pz_serve_quarto()`](https://posit-dev.github.io/paparazzi/reference/pz_serve_quarto.md),
    or
    [`pz_serve_static()`](https://posit-dev.github.io/paparazzi/reference/pz_serve_static.md),
    shared across pages;

  - an existing `ChromoteSession` (wrapped as-is; nothing is navigated).

  Path detection checks Shiny first (directories containing `app.R` or
  `server.R`, or named app files), then Quarto (`.qmd`, `.Rmd`, or a
  directory containing `_quarto.yml`), then static sites: other
  directories and, when httpuv is installed, `.html` files. `ui.R` and
  `server.R` passed alone open as files. A path starts a one-off server
  using the backend defaults; closing the page stops it. Closing a page
  opened from a handle leaves its server running. Shiny app **objects**
  are not supported; supply an app path or a running app's URL instead.

- ...:

  Forwarded to
  [`pz_device()`](https://posit-dev.github.io/paparazzi/reference/pz_device.md)
  as device settings (e.g. `width = 390, mobile = TRUE`); they must be
  named.

- wait:

  What to wait for before returning. `"auto"` (the default) waits for
  Shiny idle on app paths and handles, and for load on other pages.
  `"load"` waits for the page to load. `"shiny"` explicitly waits for
  Shiny to connect and become idle; non-Shiny pages error. `"none"`
  returns without waiting. An existing `ChromoteSession` isn't
  navigated, so only `"shiny"` waits there.

- timeout:

  Session default timeout in seconds; defaults to 10. Per-call
  `timeout = NULL` in waits and expectations uses this default.

- shiny_options, envvars:

  Passed to
  [`pz_serve_shiny()`](https://posit-dev.github.io/paparazzi/reference/pz_serve_shiny.md)
  when opening an app path. `envvars = NULL` adds no process environment
  overrides.

## Value

A `PaparazziPage` (the root context).

## Browser

`pz_open()` opens pages in chromote's default browser
([`chromote::default_chromote_object()`](https://rstudio.github.io/chromote/reference/default_chromote_object.html))
and starts it if none is running. A browser paparazzi starts keeps its
profile in [`tempdir()`](https://rdrr.io/r/base/tempfile.html), so the
profile is removed when R exits, unless a `--user-data-dir` is already
set with
[`chromote::set_chrome_args()`](https://rstudio.github.io/chromote/reference/default_chrome_args.html).
A default set with
[`chromote::set_default_chromote_object()`](https://rstudio.github.io/chromote/reference/default_chromote_object.html)
is used as-is.

## Examples

``` r
# An HTML file is served over HTTP so the page gets bfcache and other
# HTTP-only behavior
page <- pz_open(pz_example("tasks"))
pz_get_url(page)
#> [1] "http://127.0.0.1:4831/tasks.html"
pz_close(page)

# Named arguments in `...` set up the device before the page loads
phone <- pz_open(pz_example("tasks"), width = 390, height = 844, mobile = TRUE)
pz_js(phone, "window.innerWidth")
#> [1] 390
pz_screenshot(phone, frame = pz_frame("#new-task", pad = 16))
pz_close(phone)
if (FALSE) { # paparazzi:::examples_run("shiny")
# An app directory runs in a background R process that the page owns.
# pz_open() returns once Shiny has connected and gone idle.
page <- pz_open(pz_example("tasks-app"))
pz_get_text(page, target = "#summary")
pz_close(page) # also stops the app
}
```

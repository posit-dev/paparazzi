# Run a Shiny app in a background process

Starts a Shiny app – a directory or an app file – in a background R
process and returns a handle for its lifecycle. One app can back any
number of pages: pass the handle to
[`pz_open()`](https://posit-dev.github.io/paparazzi/reference/pz_open.md)
for each page. Closing those pages leaves the app running.

## Usage

``` r
pz_serve_shiny(app, ..., envvars = NULL, shiny_options = list(), timeout = 10)
```

## Arguments

- app:

  A path to a Shiny app directory or an app file (anything
  [`shiny::runApp()`](https://rdrr.io/pkg/shiny/man/runApp.html) accepts
  as a path).

- ...:

  Reserved; must be empty.

- envvars:

  Named character vector of environment variables set in the app
  process, on top of the inherited environment. `NULL` adds no
  environment overrides.

- shiny_options:

  Additional options for
  [`shiny::runApp()`](https://rdrr.io/pkg/shiny/man/runApp.html), e.g.
  `list(test.mode = TRUE)`. `appDir` is reserved; use `app` to select
  the app. `host` and `port` are managed by paparazzi: `host` defaults
  to `"127.0.0.1"`, and `port` (default `NULL`) picks a random free
  port. If startup fails because the port was taken, a new port is
  tried.

- timeout:

  Seconds to wait for the app to start listening; defaults to 10.

## Value

A `PaparazziServe` handle with public fields `url` and `port` and
methods [`stop()`](https://rdrr.io/r/base/stop.html), `logs()`, and
`is_running()`.

## Details

The handle has `$stop()` and `$logs()` methods and a
[`print()`](https://rdrr.io/r/base/print.html) method showing the URL,
port, and status – the one place the paparazzi API uses methods rather
than `pz_*()` functions. `$stop()` interrupts, waits, then kills, and is
idempotent, so `withr::defer(app$stop())` is a safe cleanup. A finalizer
stops the app as a last resort.

App stdout and stderr go to a temporary log file (never an undrained
pipe), readable mid-run with `$logs()`.

## Examples

``` r
if (FALSE) { # paparazzi:::examples_run("shiny")
app <- pz_serve_shiny(pz_example("tasks-app"))
app

# Pages opened on a handle share the app, here at two screen sizes
desktop <- pz_open(app, width = 1280)
phone <- pz_open(app, width = 390, mobile = TRUE)
pz_get_text(phone, target = "#summary")
pz_close(desktop)
pz_close(phone)

# Closing the pages leaves the app running until you stop it
app$is_running()
head(app$logs())
app$stop()
}
```

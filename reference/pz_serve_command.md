# Serve an external app process with a command

Starts any local server command – a Shiny for Python app
(`shiny run app.py`), a dev server, anything that binds a port – in a
background process and returns a handle for its lifecycle. Pass the
handle to
[`pz_open()`](https://posit-dev.github.io/paparazzi/reference/pz_open.md)
to open pages on the server; closing those pages leaves it running.

## Usage

``` r
pz_serve_command(
  command,
  args = character(),
  ...,
  wd = NULL,
  port = NULL,
  envvars = NULL,
  path = "/",
  wait = c("load", "shiny"),
  timeout = 10
)
```

## Arguments

- command:

  The command to run, found on `PATH` or given as a path.

- args:

  Character vector of arguments. The string `{port}` in any argument is
  replaced with the port the server should listen on.

- ...:

  Reserved; must be empty.

- wd:

  Working directory for the command; defaults to the current directory.

- port:

  The port to listen on. `NULL` (the default) picks a random free port;
  if startup fails because the port was taken, a new port is tried. When
  `port` is `NULL`, `{port}` must appear in `args` or `envvars` so the
  command learns the chosen port. Pass a number when the command fixes
  its own port: paparazzi skips picking but still checks the port is
  free before starting and waits for it to listen.

- envvars:

  Named character vector of environment variables set in the process, on
  top of the inherited environment; `{port}` is replaced here too.
  `NULL` adds no environment overrides.

- path:

  URL path the app responds at. The handle's `$url` is
  `http://127.0.0.1:<port><path>`.

- wait:

  What
  [`pz_open()`](https://posit-dev.github.io/paparazzi/reference/pz_open.md)
  with `wait = "auto"` waits for on pages opened from this handle:
  `"shiny"` waits for Shiny idle (the case for Shiny for Python apps),
  `"load"` (the default) waits for the page to load.

- timeout:

  Seconds to wait for the command to start listening; defaults to 10.

## Value

A `PaparazziServe` handle with public fields `url` and `port` and
methods [`stop()`](https://rdrr.io/r/base/stop.html), `logs()`, and
`is_running()`.

## Details

The handle has the same contract as
[`pz_serve_shiny()`](https://posit-dev.github.io/paparazzi/reference/pz_serve_shiny.md):
`$stop()` interrupts, waits, then kills the process tree, and is
idempotent, so `withr::defer(server$stop())` is a safe cleanup. A
finalizer stops the process as a last resort. Standard output and errors
go to a temporary log file (never an undrained pipe), readable mid-run
with `$logs()`.

## Examples

``` r
# Any command that binds a port works; {port} is replaced with the
# port paparazzi picks
server <- pz_serve_command(
  file.path(R.home("bin"), "Rscript"),
  c(
    "-e",
    "httpuv::runServer('127.0.0.1', {port}, list(call = function(req) list(status = 200L, body = 'served by a command')))"
  )
)
page <- pz_open(server)
pz_get_text(page, target = "body")
#> [1] "served by a command"
pz_close(page)
server$stop()
```

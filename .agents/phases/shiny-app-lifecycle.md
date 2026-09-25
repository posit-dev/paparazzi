# Phase note: Shiny app lifecycle (kata paparazzi#k2dr)

Mechanism decisions for the app-lifecycle task, resolved before code.
Durable requirements live in `.agents/SPEC.md` ("Sessions and apps" ->
"Apps"); this note holds mechanism-level choices and session handoffs
for this phase only. First child of epic paparazzi#grm9; `pz_open()`
integration with `pz_app()` handles belongs to a later task.

## Decisions

- **Signature.** `pz_app(app_dir, ..., envvars = NULL,
  shiny_options = list(), timeout = NULL)`. `...` is checked empty
  (`rlang::check_dots_empty()`): `pz_open()`'s dots go to `pz_device()`,
  but a headless background app has no device to configure, and a
  reserved-argument error now beats a silent typo later.
- **Handle.** Internal R6 class `PaparazziApp` (undocumented, like the
  other internals; only `pz_app()` gets a man page). Public: fields
  `url` and `port` (plain, set once at start), methods `stop()`,
  `logs()`, `is_running()`, and `print()`. R6's built-in print dispatch
  covers `print()`. Private: `process_` (processx), `log_file_`,
  `stopped_` flag. `stop()` is the only mutator; idempotent.
- **Process.** `processx::process$new(Rscript, c("-e", expr, config),
  stdout = log_file, stderr = log_file, env = c("current", envvars),
  cleanup = TRUE, cleanup_tree = TRUE)`. processx joins Imports (used
  directly). One temp log file for both streams -- never pipes (the
  known undrained-pipe Shiny bug class); `$logs()` `readLines()` it and
  works after stop. The child runs
  `do.call(shiny::runApp, readRDS(commandArgs(TRUE)[[1]]))` with the
  config saved to a tempfile, so arbitrary `shiny_options` survive
  without quoting games.
- **app_dir.** A string naming an existing directory, or an existing
  `.R` app file (`shiny::runApp()` accepts both); the path is passed
  through as `appDir`. Anything else is a `paparazzi_error_input`.
- **shiny_options.** Passed to `shiny::runApp()` merged over
  `list(launch.browser = FALSE)`. `host` and `port` are managed:
  `host` defaults to `"127.0.0.1"`; `shiny_options$port` is honored as
  the *initial* port (this is also how tests force the port-taken
  path) and a random free one is picked otherwise.
- **Port picker.** Base R only: try `serverSocket(port)` on a random
  draw from 3000:8000 minus Chrome's unsafe ports in that range (3659,
  4045, 5060, 5061, 6000, 6566, 6665:6669, 6697 -- pages are opened in
  Chrome later, so these would fail at navigation, not at bind), close
  on success. Up to 100 draws before aborting.
- **Readiness.** Poll a loopback `socketConnection()` to
  `host:port` until it connects or the startup budget
  (`timeout = NULL` -> 10 s) expires. Socket-based, not log-based, so
  `shiny_options = list(quiet = TRUE)` can't blind it. Each poll first
  checks `process_$is_alive()`: a dead child ends the wait immediately
  with the log tail in the error.
- **Port-taken retry.** If the child dies and the log matches
  "address already in use" or "failed to create server", pick a new
  port and relaunch, up to 5 attempts total. The race is real (the
  picker closes its probe socket before httpuv binds), so retry is
  unconditional, not only for user-specified ports.
- **Shutdown ladder.** `stop()`: no-op if already stopped or the
  process is dead; otherwise `interrupt()`, `wait(2000)` ms, then
  `kill()` if still alive. `private$finalize` calls `stop()` under
  `try(silent = TRUE)` as the last resort; processx's `cleanup = TRUE`
  is the belt to that suspender. No timers, queues, or second flags:
  one `stopped_` flag plus process liveness is the whole state.
- **Validation/errors.** rlang checkers throughout
  (`check_string()`, `check_number_decimal()`, `stop_input_type()`);
  `envvars` must be a named character vector without `NA`s (via
  `check_character()` from `R/utils-check.R` plus a names check).
  `rlang::check_installed("shiny")` runs only inside `pz_app()`.
  Startup failure is classed `paparazzi_error_app_startup` and carries
  the log tail; bad input is `paparazzi_error_input`.
- **print().** cli cat_line summary, e.g.
  `<paparazzi app> http://127.0.0.1:4821/ -- running (pid 12345)`;
  `stopped`/`exited (status N)` when not running. URL, port, status
  per SPEC.
- **Files owned by this task.** `R/app.R`,
  `tests/testthat/test-app.R`, `tests/testthat/helper-shiny-app.R`,
  `tests/testthat/fixtures/shiny-app-lifecycle/` (new dir; shared
  fixtures untouched), DESCRIPTION (processx in Imports), generated
  NAMESPACE/man/pz_app.Rd, this note. `R/open.R` and its helpers
  (`is_shiny_app_file()` etc.) are read-only here.

## Targeted tests

Run: `Rscript -e 'testthat::test_local(filter = "app")'`.
Seam tests beyond `test-app.R`: none -- `pz_open()` doesn't know about
`pz_app()` yet (later task), and no shared source changes.

Fixtures (all under `tests/testthat/fixtures/shiny-app-lifecycle/`):

- `app-dir/` -- minimal app: `cat()`s a startup marker and
  `Sys.getenv("PAPARAZZI_TEST_MARKER")` so envvar pass-through is
  observable in the log.
- `app-file.R` -- single-file app for the file-path form.
- `app-broken/` -- errors at startup ("boom"), proving startup
  failure surfaces the log and that the harness discriminates.

Cases: dir and file forms start and serve (URL reachable);
`print()` shows URL/port/status; `$logs()` readable mid-run (contains
"Listening on"); envvars reach the child; `shiny_options` reach
`runApp()` (quiet = TRUE suppresses the log banner while the app still
starts); `stop()` idempotent and kills the process; withr defer
cleanup; finalizer stops the process after `rm()` + `gc()` (observed
via port reachability, polled); broken app -> classed error with log
tail; port-taken retry under a pre-bound `serverSocket()`; input
validation errors.

## Handoff log

(newest first; three lines per session: landed / next / provisional)

- 2026-09-25 (start): claimed k2dr. Harness green at 4168bc7
  (main baseline: full suite 1780 passes per coordinator; local
  targeted `filter = "open"` verified before feature code). Decisions
  above resolved. Next: fixtures + helper + failing tests, then
  `R/app.R`. Provisional: none yet.

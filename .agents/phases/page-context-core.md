# Phase note: page/context R6 core (kata paparazzi#qtpz)

Mechanism decisions for the core task, resolved before code. Durable
requirements live in `.agents/SPEC.md`; this note holds mechanism-level
choices and session handoffs for this phase only.

## Decisions

- **Classes.** `PaparazziContext` (R6) is the base context: public fields
  `page` (the `PaparazziPage`; self-reference for the root) and `scope`
  (a list used as a stack, empty for the root; populated by the scoping
  task). `PaparazziPage` inherits `PaparazziContext` and owns the
  `ChromoteSession` plus session-level state (private: `chromote_`,
  `closed_`, `default_timeout_`, `staging_`, `recorder_`). Public methods
  on the page: `close()`, `view()`, `is_closed()`.
- **File layout.** `R/context.R` (both R6 classes), `R/open.R`
  (`pz_open()` + dispatch + `pz_close()`/`pz_with_page()`/`pz_local_page()`),
  `R/js.R` (`pz_js()`), `R/wait.R` (poll primitive + `pz_wait()`),
  `R/utils.R` (shared checks).
- **Wait/poll primitive.** `pz_poll(fn, timeout, interval, loop)` in
  `R/wait.R`: checks `fn()`, and between checks calls
  `later::run_now(timeoutSecs = interval, loop = loop)` so recording
  timers on chromote's child loop keep firing during waits. All times in
  **seconds** in R land; conversion to ms for JS happens explicitly at
  the boundary. `pz_wait(ctx, seconds)` drives the same loop until the
  deadline; it never sleeps without pumping.
- **Default timeout.** 10 seconds (provisional), settable via
  `pz_open(..., timeout =)`; `timeout = NULL` on any call means "session
  default". Resolution helper: `resolve_timeout(timeout, page)`.
- **`pz_open()` dispatch on `x`.** string matching `^[a-zA-Z][a-zA-Z0-9+.-]*:`
  (URL scheme, incl. `about:`, `data:`, `file://`) -> navigate; existing
  local path -> `normalizePath()` + `file://`; `ChromoteSession` -> wrap
  as-is (no navigation, we do not own the browser); `shiny.appobj` ->
  error advising to run in another process and pass the URL; directory
  or `app.R` -> "not yet supported" error pointing at the Shiny task;
  anything else -> error.
- **`wait` argument.** `match.arg`; `"auto"` resolves to `"load"` for now,
  `"shiny"` errors (Shiny-integration task), `"none"` skips. `"load"`
  polls `document.readyState == "complete"` with the session timeout.
- **`pz_js(ctx, expr, ..., await = TRUE)`.** `...` checked empty
  (`rlang::check_dots_empty`). `Runtime$evaluate(expr, awaitPromise =
  await, returnByValue = TRUE)`; `exceptionDetails` becomes an
  `rlang::abort` carrying the JS message. Returns the value; ends the
  chain (not invisible ctx).
- **Errors.** Classed via `rlang::abort(class = "paparazzi_error_*")`
  so tests can match on class.
- **Lifecycle forms.** `pz_with_page(x, code, ...)` evaluates the
  embraced `code` and closes the page on exit (`on.exit`), returning
  invisibly. `pz_local_page(x, ..., .env = caller_env())` opens and
  defers `pz_close()` in `.env` via `withr::defer()`. Both always close,
  even when handed an already-open page (withr semantics: the block
  owns the resource).
- **Tests.** Static fixture `tests/testthat/fixtures/page.html`; helper
  `local_page()` opens it via `file://` and skips if no Chrome is
  available (session creation error). No network dependency in tests.

## Handoff log

(newest first; three lines per session: landed / next / provisional)

- 2026-09-24 (start): claimed qtpz. Harness verified green at df2777d
  (devtools::test passes; a deliberately broken fixture fails). Found
  DESCRIPTION missing the deps from closed paparazzi#1y9n — fixed
  separately. Next: implement per decisions above. Provisional: default
  timeout 10 s.

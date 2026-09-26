test_that("pz_app starts an app from a directory", {
  app <- local_shiny_app(shiny_app_fixture_dir())

  expect_s3_class(app, "PaparazziApp")
  expect_true(app$is_running())
  expect_match(app$url, "^http://127[.]0[.]0[.]1:[0-9]+/$")
  expect_equal(sub(".*:([0-9]+)/$", "\\1", app$url), as.character(app$port))
  expect_true(app_port_reachable(app$port))
})

test_that("pz_app starts an app from an app file", {
  app <- local_shiny_app(shiny_app_fixture_file())

  expect_true(app$is_running())
  expect_true(app_port_reachable(app$port))
  expect_true(any(grepl("PAPARAZZI_FIXTURE_APP_FILE", app$logs())))
})

test_that("app stdout and stderr share readable logs mid-run and after stop", {
  app <- local_shiny_app(shiny_app_fixture_dir())
  markers <- c("PAPARAZZI_FIXTURE_STDOUT", "PAPARAZZI_FIXTURE_STDERR")
  has_markers <- function(logs) {
    all(vapply(
      markers,
      function(marker) any(grepl(marker, logs, fixed = TRUE)),
      logical(1)
    ))
  }

  expect_true(wait_until(function() has_markers(app$logs())))
  logs <- app$logs()
  expect_type(logs, "character")
  expect_true(any(grepl("Listening on", logs, fixed = TRUE)))
  app$stop()
  expect_true(has_markers(app$logs()))
})

test_that("envvars reach the app process", {
  app <- local_shiny_app(
    shiny_app_fixture_dir(),
    envvars = c(PAPARAZZI_TEST_MARKER = "marker-123")
  )

  expect_true(any(grepl("marker: marker-123", app$logs(), fixed = TRUE)))
})

test_that("shiny_options are passed to runApp", {
  # quiet = TRUE suppresses shiny's "Listening on" banner; the app must
  # still start, proving readiness doesn't depend on log scraping.
  app <- local_shiny_app(
    shiny_app_fixture_dir(),
    shiny_options = list(quiet = TRUE)
  )

  expect_true(app_port_reachable(app$port))
  expect_false(any(grepl("Listening on", app$logs(), fixed = TRUE)))
})

test_that("appDir in shiny_options is rejected before an app process can start", {
  skip_if_no_shiny()
  app_dir <- shiny_app_fixture_dir()
  options_app <- shiny_app_fixture_file()
  expect_false(identical(app_dir, options_app))
  expect_true(any(grepl(
    'message("PAPARAZZI_FIXTURE_APP")',
    readLines(file.path(app_dir, "app.R")),
    fixed = TRUE
  )))
  expect_true(any(grepl(
    "PAPARAZZI_FIXTURE_APP_FILE",
    readLines(options_app),
    fixed = TRUE
  )))

  spawn_calls <- 0L
  local_mocked_bindings(new_app = function(...) {
    spawn_calls <<- spawn_calls + 1L
    NULL
  })

  err <- expect_error(
    pz_app(app_dir, shiny_options = list(appDir = options_app)),
    class = "paparazzi_error_input"
  )
  expect_match(conditionMessage(err), "appDir", fixed = TRUE)
  expect_equal(spawn_calls, 0L)
})

test_that("print shows URL, port, and status", {
  app <- local_shiny_app(shiny_app_fixture_dir())

  out <- capture.output(print(app))
  expect_true(any(grepl(app$url, out, fixed = TRUE)))
  expect_true(any(grepl(as.character(app$port), out, fixed = TRUE)))
  expect_true(any(grepl("running", out, fixed = TRUE)))

  app$stop()
  out <- capture.output(print(app))
  expect_true(any(grepl("stopped", out, fixed = TRUE)))
})

test_that("stop shuts the app down and is idempotent", {
  skip_if_no_shiny()
  app <- pz_app(shiny_app_fixture_dir())
  port <- app$port

  expect_invisible(app$stop())
  expect_false(app$is_running())
  expect_no_error(app$stop())
  expect_true(wait_until(function() !app_port_reachable(port)))
})

test_that("logs stay readable after stop", {
  skip_if_no_shiny()
  app <- pz_app(shiny_app_fixture_dir())
  app$stop()

  expect_true(any(grepl("PAPARAZZI_FIXTURE_APP", app$logs(), fixed = TRUE)))
})

test_that("withr::defer(app$stop()) cleans up on scope exit", {
  skip_if_no_shiny()
  port <- local({
    app <- pz_app(shiny_app_fixture_dir())
    withr::defer(app$stop())
    app$port
  })
  expect_true(wait_until(function() !app_port_reachable(port)))
})

test_that("the finalizer stops the app as a last resort", {
  skip_if_no_shiny()
  port <- pz_app(shiny_app_fixture_dir())$port
  # Two passes: the first marks the handle unreachable, the second
  # guarantees its finalizer has actually run.
  gc()
  gc()
  expect_true(wait_until(function() !app_port_reachable(port)))
})

test_that("a broken app fails loudly with its log output", {
  skip_if_no_shiny()
  err <- expect_error(
    pz_app(shiny_app_fixture_broken()),
    class = "paparazzi_error_app_startup"
  )
  expect_match(
    conditionMessage(err),
    "boom: fixture app refuses to start",
    fixed = TRUE
  )
})

test_that("a taken port triggers a retry on a new port", {
  skip_if_no_shiny()
  # Occupy the port with a live listener. pz_app() must notice the port
  # already answers and start on a new one -- relying on the child's
  # bind failing is not portable (see app-port-taken's comment).
  taken_port <- free_port()
  server <- httpuv::startServer("127.0.0.1", taken_port, list())
  withr::defer(httpuv::stopServer(server))

  app <- local_shiny_app(
    shiny_app_fixture_dir(),
    shiny_options = list(port = taken_port)
  )
  expect_false(identical(app$port, taken_port))
  expect_true(app_port_reachable(app$port))
})

test_that("a child that dies from a taken port exhausts its retries", {
  skip_if_no_shiny()
  err <- expect_error(
    pz_app(shiny_app_fixture_port_taken(), timeout = 5),
    class = "paparazzi_error_app_startup",
    regexp = "could not bind a port"
  )
  expect_match(conditionMessage(err), "Failed to create server", fixed = TRUE)
})

test_that("preflight exhaustion reports no nonexistent child log", {
  skip_if_no_shiny()
  taken_port <- free_port()
  server <- httpuv::startServer("127.0.0.1", taken_port, list())
  withr::defer(httpuv::stopServer(server))
  local_mocked_bindings(random_port = function(...) taken_port)

  err <- expect_error(
    pz_app(shiny_app_fixture_dir(), shiny_options = list(port = taken_port)),
    class = "paparazzi_error_app_startup",
    regexp = "could not bind a port"
  )
  expect_false(grepl("\n", conditionMessage(err), fixed = TRUE))
})

test_that("startup error only includes an escaped, bounded log tail", {
  err <- expect_error(
    app_startup_error(
      list(
        kind = "exited",
        port_taken = TRUE,
        log = c(
          "OLD_SENTINEL",
          rep("padding", 2000),
          "Failed to create server {tail}"
        )
      ),
      "fixture",
      1,
      call = current_env()
    ),
    class = "paparazzi_error_app_startup"
  )
  expect_match(
    conditionMessage(err),
    "Failed to create server {tail}",
    fixed = TRUE
  )
  expect_false(grepl("OLD_SENTINEL", conditionMessage(err), fixed = TRUE))
  expect_lt(nchar(conditionMessage(err)), 4200)
})

test_that("app_dir is validated", {
  skip_if_no_shiny()
  expect_error(pz_app(42), class = "paparazzi_error_input")
  expect_error(pz_app("does/not/exist"), class = "paparazzi_error_input")
  expect_error(pz_app(fixture_file()), class = "paparazzi_error_input")
})

test_that("shiny_options, envvars, timeout, and dots are validated", {
  skip_if_no_shiny()
  expect_error(
    pz_app(shiny_app_fixture_dir(), shiny_options = "quiet"),
    "must be a list"
  )
  expect_error(
    pz_app(shiny_app_fixture_dir(), envvars = "MOCK=1"),
    class = "paparazzi_error_input"
  )
  expect_error(
    pz_app(shiny_app_fixture_dir(), envvars = c("1")),
    class = "paparazzi_error_input"
  )
  expect_error(
    pz_app(shiny_app_fixture_dir(), timeout = -1),
    "must be a number"
  )
  expect_error(pz_app(shiny_app_fixture_dir(), width = 390), "must be empty")
})

test_that("an app that never listens times out and is cleaned up", {
  skip_if_no_shiny()
  err <- expect_error(
    pz_app(shiny_app_fixture_slow(), timeout = 0.5),
    class = "paparazzi_error_app_startup",
    regexp = "did not start"
  )
  expect_match(conditionMessage(err), "within 0.5 seconds", fixed = TRUE)
  expect_false(grepl("{.val", conditionMessage(err), fixed = TRUE))
})

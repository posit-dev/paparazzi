test_that("pz_serve_shiny starts an app from a directory", {
  app <- local_shiny_app(shiny_app_fixture_dir())

  expect_s3_class(app, "PaparazziServe")
  expect_true(app$is_running())
  expect_match(app$url, "^http://127[.]0[.]0[.]1:[0-9]+/$")
  expect_equal(sub(".*:([0-9]+)/$", "\\1", app$url), as.character(app$port))
  expect_true(app_port_reachable(app$port))
})

test_that("pz_serve_shiny starts an app from an app file", {
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
    pz_serve_shiny(app_dir, shiny_options = list(appDir = options_app)),
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
  app <- pz_serve_shiny(shiny_app_fixture_dir())
  port <- app$port

  expect_invisible(app$stop())
  expect_false(app$is_running())
  expect_no_error(app$stop())
  expect_true(wait_until(function() !app_port_reachable(port)))
})

test_that("logs stay readable after stop", {
  skip_if_no_shiny()
  app <- pz_serve_shiny(shiny_app_fixture_dir())
  app$stop()

  expect_true(any(grepl("PAPARAZZI_FIXTURE_APP", app$logs(), fixed = TRUE)))
})

test_that("withr::defer(app$stop()) cleans up on scope exit", {
  skip_if_no_shiny()
  port <- local({
    app <- pz_serve_shiny(shiny_app_fixture_dir())
    withr::defer(app$stop())
    app$port
  })
  expect_true(wait_until(function() !app_port_reachable(port)))
})

test_that("the finalizer stops the app as a last resort", {
  skip_if_no_shiny()
  port <- pz_serve_shiny(shiny_app_fixture_dir())$port
  # Two passes: the first marks the handle unreachable, the second
  # guarantees its finalizer has actually run.
  gc()
  gc()
  expect_true(wait_until(function() !app_port_reachable(port)))
})

test_that("a broken app fails loudly with its log output", {
  skip_if_no_shiny()
  err <- expect_error(
    pz_serve_shiny(shiny_app_fixture_broken()),
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
  # Occupy the port with a live listener. pz_serve_shiny() must notice the port
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

test_that("new_app constructs even when its port already has a listener", {
  skip_if_no_shiny()
  taken_port <- free_port()
  listener <- httpuv::startServer("127.0.0.1", taken_port, list())
  withr::defer(httpuv::stopServer(listener))

  app <- new_app(
    list(
      appDir = shiny_app_fixture_dir(),
      host = "127.0.0.1",
      port = taken_port,
      launch.browser = FALSE
    ),
    taken_port,
    NULL
  )
  withr::defer(if (inherits(app, "PaparazziServe")) app$stop())

  expect_s3_class(app, "PaparazziServe")
})

test_that("a child that dies from a taken port exhausts its retries", {
  skip_if_no_shiny()
  err <- expect_error(
    pz_serve_shiny(shiny_app_fixture_port_taken(), timeout = 5),
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
    pz_serve_shiny(
      shiny_app_fixture_dir(),
      shiny_options = list(port = taken_port)
    ),
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
  expect_error(pz_serve_shiny(42), class = "paparazzi_error_input")
  expect_error(
    pz_serve_shiny("does/not/exist"),
    class = "paparazzi_error_input"
  )
  expect_error(pz_serve_shiny(fixture_file()), class = "paparazzi_error_input")
})

test_that("shiny_options, envvars, timeout, and dots are validated", {
  skip_if_no_shiny()
  expect_error(
    pz_serve_shiny(shiny_app_fixture_dir(), shiny_options = "quiet"),
    "must be a list"
  )
  expect_error(
    pz_serve_shiny(shiny_app_fixture_dir(), envvars = "MOCK=1"),
    class = "paparazzi_error_input"
  )
  expect_error(
    pz_serve_shiny(shiny_app_fixture_dir(), envvars = c("1")),
    class = "paparazzi_error_input"
  )
  expect_error(
    pz_serve_shiny(shiny_app_fixture_dir(), timeout = -1),
    "must be a number"
  )
  expect_error(
    pz_serve_shiny(shiny_app_fixture_dir(), width = 390),
    "must be empty"
  )
})

test_that("an app that never listens times out and is cleaned up", {
  skip_if_no_shiny()
  err <- expect_error(
    pz_serve_shiny(shiny_app_fixture_slow(), timeout = 0.5),
    class = "paparazzi_error_app_startup",
    regexp = "did not start"
  )
  expect_match(conditionMessage(err), "within 0.5 seconds", fixed = TRUE)
  expect_false(grepl("{.val", conditionMessage(err), fixed = TRUE))
})

test_that("app timeout has a visible ten-second default and rejects NULL", {
  expect_equal(formals(pz_serve_shiny)$timeout, 10)
  expect_error(
    pz_serve_shiny(shiny_app_fixture_dir(), timeout = NULL),
    "timeout"
  )
})

test_that("static directories and single HTML files share the handle contract", {
  skip_if_no_chrome()
  skip_if_not_installed("httpuv")
  dir <- withr::local_tempdir()
  html <- file.path(dir, "hello world.html")
  writeLines('<html><body><h1>Static capture</h1></body></html>', html)
  file.copy(html, file.path(dir, "index.html"))

  for (path in c(dir, html)) {
    servers <- httpuv::listServers()
    server <- pz_serve_static(path)
    withr::defer(server$stop())
    expect_s3_class(server, "PaparazziServe")
    expect_true(server$is_running())
    expect_true(app_port_reachable(server$port))
    expect_identical(server$logs(), character())
    if (identical(path, html)) {
      expect_match(server$url, "/hello%20world[.]html$")
    }
    page <- local_page(server)
    expect_identical(pz_get_text(page, target = "h1"), "Static capture")
    pz_close(page)
    expect_true(server$is_running())
    expect_invisible(server$stop())
    expect_no_error(server$stop())
    expect_false(server$is_running())
    # A parallel worker can bind the freed port; observe our httpuv servers.
    expect_identical(httpuv::listServers(), servers)

    owned <- local_page(path)
    owned_server <- owned$app
    expect_identical(pz_get_text(owned, target = "h1"), "Static capture")
    pz_nav_reload(owned)
    expect_identical(pz_get_text(owned, target = "h1"), "Static capture")
    pz_close(owned)
    expect_false(owned_server$is_running())
    expect_identical(httpuv::listServers(), servers)
  }
})

test_that("static handles stop on scope exit and finalization", {
  skip_if_not_installed("httpuv")
  servers <- httpuv::listServers()
  local({
    server <- pz_serve_static(dirname(fixture_file()))
    withr::defer(server$stop())
    expect_true(server$is_running())
  })
  expect_identical(httpuv::listServers(), servers)
  server <- pz_serve_static(fixture_file())
  expect_length(httpuv::listServers(), length(servers) + 1L)
  rm(server)
  gc()
  gc()
  expect_identical(httpuv::listServers(), servers)
})

test_that("static inputs and reserved dots are validated", {
  expect_error(pz_serve_static(42), "must be a single string")
  expect_error(
    pz_serve_static("does/not/exist"),
    class = "paparazzi_error_input"
  )
  expect_error(
    pz_serve_static(shiny_app_fixture_file()),
    class = "paparazzi_error_input"
  )
  expect_error(pz_serve_static(fixture_file(), port = 1234), "must be empty")
})

test_that("Quarto document handles own independent processes and shared pages", {
  skip_if_no_chrome()
  skip_if(
    is.null(tryCatch(quarto_cli(), error = function(e) NULL)),
    "Quarto CLI not available"
  )
  dir <- withr::local_tempdir()
  path <- file.path(dir, "document.qmd")
  file.copy(test_path("fixtures", "quarto", "document.qmd"), path)
  other_dir <- withr::local_tempdir()
  other_path <- file.path(other_dir, "document.qmd")
  file.copy(path, other_path)

  server <- pz_serve_quarto(path, render = TRUE)
  withr::defer(server$stop())
  other <- pz_serve_quarto(other_path)
  withr::defer(other$stop())
  expect_s3_class(server, "PaparazziServe")
  expect_true(server$is_running())
  expect_true(other$is_running())
  expect_false(identical(server$port, other$port))
  expect_true(any(grepl("Output created", server$logs(), fixed = TRUE)))

  page <- local_page(server)
  second <- local_page(server)
  expect_identical(
    pz_get_text(page, target = "#document-marker"),
    "Quarto capture"
  )
  expect_identical(
    pz_get_text(second, target = "#document-marker"),
    "Quarto capture"
  )
  pz_close(page)
  pz_close(second)
  expect_true(server$is_running())
  expect_invisible(server$stop())
  expect_no_error(server$stop())
  expect_false(server$is_running())
  expect_true(wait_until(function() !app_port_reachable(server$port)))
  expect_true(other$is_running())
  expect_type(server$logs(), "character")
  expect_gt(length(server$logs()), 0)
})

test_that("pz_open owns a one-off Quarto document preview", {
  skip_if_no_chrome()
  skip_if(
    is.null(tryCatch(quarto_cli(), error = function(e) NULL)),
    "Quarto CLI not available"
  )
  dir <- withr::local_tempdir()
  path <- file.path(dir, "document.qmd")
  file.copy(test_path("fixtures", "quarto", "document.qmd"), path)
  page <- local_page(path)
  port <- page$app$port
  expect_identical(
    pz_get_text(page, target = "#document-marker"),
    "Quarto capture"
  )
  pz_nav_reload(page)
  expect_identical(
    pz_get_text(page, target = "#document-marker"),
    "Quarto capture"
  )
  pz_close(page)
  expect_true(wait_until(function() !app_port_reachable(port)))
})

test_that("Quarto renders R Markdown with knitr", {
  skip_if_no_chrome()
  skip_if_not_installed("knitr")
  skip_if_not_installed("rmarkdown")
  skip_if(
    is.null(tryCatch(quarto_cli(), error = function(e) NULL)),
    "Quarto CLI not available"
  )
  dir <- withr::local_tempdir()
  path <- file.path(dir, "document.Rmd")
  writeLines(
    c(
      "---",
      "format: html",
      "---",
      "",
      "```{r}",
      "cat('R Markdown marker')",
      "```"
    ),
    path
  )
  server <- pz_serve_quarto(path)
  withr::defer(server$stop())
  page <- local_page(server)
  expect_match(
    pz_get_text(page, target = "body"),
    "R Markdown marker",
    fixed = TRUE
  )
})

test_that("Quarto projects use their output URL", {
  skip_if_no_chrome()
  skip_if(
    is.null(tryCatch(quarto_cli(), error = function(e) NULL)),
    "Quarto CLI not available"
  )
  dir <- withr::local_tempdir()
  writeLines(
    c("project:", "  type: website", "format: html"),
    file.path(dir, "_quarto.yml")
  )
  path <- file.path(dir, "index.qmd")
  file.copy(test_path("fixtures", "quarto", "document.qmd"), path)
  server <- pz_serve_quarto(dir, render = TRUE)
  withr::defer(server$stop())
  page <- local_page(server)
  expect_identical(
    pz_get_text(page, target = "#document-marker"),
    "Quarto capture"
  )
})

test_that("Quarto finalizers stop the process tree", {
  skip_if(
    is.null(tryCatch(quarto_cli(), error = function(e) NULL)),
    "Quarto CLI not available"
  )
  dir <- withr::local_tempdir()
  path <- file.path(dir, "document.qmd")
  file.copy(test_path("fixtures", "quarto", "document.qmd"), path)
  port <- pz_serve_quarto(path)$port
  gc()
  gc()
  expect_true(wait_until(function() !app_port_reachable(port)))
})

test_that("Quarto CLI lookup respects QUARTO_PATH and fails with advice", {
  dir <- withr::local_tempdir()
  executable <- file.path(dir, "quarto")
  file.create(executable)
  withr::local_envvar(QUARTO_PATH = executable)
  expect_identical(quarto_cli(), executable)
  withr::local_envvar(QUARTO_PATH = "", PATH = "")
  err <- expect_error(quarto_cli(), class = "paparazzi_error_quarto_not_found")
  expect_match(conditionMessage(err), "Install Quarto", fixed = TRUE)
  withr::local_envvar(QUARTO_PATH = file.path(dir, "missing"))
  expect_error(quarto_cli(), class = "paparazzi_error_quarto_not_found")
})

test_that("Quarto paths, rendering, and dots are validated", {
  path <- test_path("fixtures", "quarto", "document.qmd")
  expect_error(pz_serve_quarto(42), "must be a single string")
  expect_error(
    pz_serve_quarto("does/not/exist"),
    class = "paparazzi_error_input"
  )
  expect_error(pz_serve_quarto(fixture_file()), class = "paparazzi_error_input")
  expect_error(pz_serve_quarto(dirname(path)), class = "paparazzi_error_input")
  expect_error(pz_serve_quarto(path, render = NA), "render")
  expect_error(pz_serve_quarto(path, render = "all"), "render")
  expect_error(pz_serve_quarto(path, port = 1234), "must be empty")
})

test_that("Quarto startup failures include logs and release the port", {
  skip_if(
    is.null(tryCatch(quarto_cli(), error = function(e) NULL)),
    "Quarto CLI not available"
  )
  dir <- withr::local_tempdir()
  path <- file.path(dir, "broken.qmd")
  writeLines(c("---", "format: nonexistent-format", "---", "Broken"), path)
  port <- random_port()
  local_mocked_bindings(random_port = function(...) port)
  expect_error(
    pz_serve_quarto(path),
    class = "paparazzi_error_quarto_startup",
    regexp = "exited during startup"
  )
  expect_true(wait_until(function() !app_port_reachable(port)))
})

test_that("new_quarto constructs even when its port already has a listener", {
  skip_if_not_installed("httpuv")
  skip_if(
    is.null(tryCatch(quarto_cli(), error = function(e) NULL)),
    "Quarto CLI not available"
  )
  dir <- withr::local_tempdir()
  path <- file.path(dir, "document.qmd")
  file.copy(test_path("fixtures", "quarto", "document.qmd"), path)
  taken <- random_port()
  listener <- httpuv::startServer("127.0.0.1", taken, list())
  withr::defer(httpuv::stopServer(listener))

  preview <- new_quarto(path, FALSE, quarto_cli(), taken)
  withr::defer(if (inherits(preview, "PaparazziServe")) preview$stop())

  expect_s3_class(preview, "PaparazziServe")
})

test_that("Quarto preflight exhaustion reports no nonexistent child log", {
  skip_if_not_installed("httpuv")
  skip_if(
    is.null(tryCatch(quarto_cli(), error = function(e) NULL)),
    "Quarto CLI not available"
  )
  dir <- withr::local_tempdir()
  path <- file.path(dir, "document.qmd")
  file.copy(test_path("fixtures", "quarto", "document.qmd"), path)
  taken <- random_port()
  listener <- httpuv::startServer("127.0.0.1", taken, list())
  withr::defer(httpuv::stopServer(listener))
  local_mocked_bindings(random_port = function(...) taken)

  err <- expect_error(
    pz_serve_quarto(path),
    class = "paparazzi_error_quarto_startup",
    regexp = "could not bind a port"
  )
  expect_false(grepl("\n", conditionMessage(err), fixed = TRUE))
})

test_that("Quarto preflight retries a port takeover", {
  skip_if_not_installed("httpuv")
  skip_if(
    is.null(tryCatch(quarto_cli(), error = function(e) NULL)),
    "Quarto CLI not available"
  )
  dir <- withr::local_tempdir()
  path <- file.path(dir, "document.qmd")
  file.copy(test_path("fixtures", "quarto", "document.qmd"), path)
  taken <- random_port()
  listener <- httpuv::startServer("127.0.0.1", taken, list())
  withr::defer(httpuv::stopServer(listener))
  picker <- random_port
  attempts <- 0L
  local_mocked_bindings(random_port = function(...) {
    attempts <<- attempts + 1L
    if (attempts == 1L) taken else picker()
  })
  server <- pz_serve_quarto(path)
  withr::defer(server$stop())
  expect_false(identical(server$port, taken))
  expect_true(server$is_running())
})

test_that("automatic serving detection prioritizes Shiny, then Quarto, then static", {
  dir <- withr::local_tempdir()
  expect_identical(serve_kind(dir), "static")
  file.create(file.path(dir, "_quarto.yml"))
  expect_identical(serve_kind(dir), "quarto")
  file.create(file.path(dir, "app.R"))
  expect_identical(serve_kind(dir), "shiny")
  unlink(file.path(dir, "app.R"))
  file.create(file.path(dir, "server.R"))
  expect_identical(serve_kind(dir), "shiny")
  file.create(file.path(dir, "ui.R"))
  expect_identical(serve_kind(dir), "shiny")
  expect_null(serve_kind(file.path(dir, "ui.R")))
  expect_null(serve_kind(file.path(dir, "server.R")))
  expect_identical(serve_kind(shiny_app_fixture_file()), "shiny")
  # pz_open() opens .html files as file://; only directories are served.
  expect_null(serve_kind(fixture_file()))
  doc <- file.path(dir, "document.Rmd")
  file.create(doc)
  expect_identical(serve_kind(doc), "quarto")
  expect_identical(
    serve_kind(test_path("fixtures", "quarto", "document.qmd")),
    "quarto"
  )
  expect_null(serve_kind(42))
  expect_null(serve_kind("does/not/exist"))
})

test_that("static servers retry when the port is taken", {
  skip_if_not_installed("httpuv")
  dir <- withr::local_tempdir()
  writeLines("<p>hi</p>", file.path(dir, "index.html"))
  calls <- 0
  real <- httpuv::runStaticServer
  local_mocked_bindings(
    runStaticServer = function(...) {
      calls <<- calls + 1
      if (calls == 1) {
        stop("Failed to create server")
      }
      real(...)
    },
    .package = "httpuv"
  )
  server <- pz_serve_static(dir)
  withr::defer(server$stop())
  expect_identical(calls, 2)
  expect_true(server$is_running())

  local_mocked_bindings(
    runStaticServer = function(...) stop("Failed to create server"),
    .package = "httpuv"
  )
  expect_error(pz_serve_static(dir), class = "paparazzi_error_app_startup")
})

test_that("static file URLs encode literal percent signs and reserved characters", {
  skip_if_no_chrome()
  skip_if_not_installed("httpuv")
  dir <- withr::local_tempdir()
  path <- file.path(dir, "a%20b #1.html")
  writeLines('<html><body><h1>Encoded filename</h1></body></html>', path)
  server <- pz_serve_static(path)
  withr::defer(server$stop())
  expect_match(server$url, "a%2520b%20%231.html", fixed = TRUE)
  page <- local_page(server)
  expect_identical(pz_get_text(page, target = "h1"), "Encoded filename")
})

test_that("Quarto startup timeouts clean up the process tree", {
  skip_if(
    is.null(tryCatch(quarto_cli(), error = function(e) NULL)),
    "Quarto CLI not available"
  )
  dir <- withr::local_tempdir()
  path <- file.path(dir, "document.qmd")
  file.copy(test_path("fixtures", "quarto", "document.qmd"), path)
  port <- random_port()
  local_mocked_bindings(random_port = function(...) port)
  expect_error(
    quarto_start(path, FALSE, quarto_cli(), timeout = 0),
    class = "paparazzi_error_quarto_startup",
    regexp = "did not start within"
  )
  expect_true(wait_until(function() !app_port_reachable(port)))
})

test_that("pz_serve_shiny starts an app from a directory", {
  app <- local_shiny_app(shiny_app_fixture_dir())

  expect_s3_class(app, "PaparazziServe")
  expect_true(app$is_running())
  expect_match(app$url, "^http://127[.]0[.]0[.]1:[0-9]+/$")
  expect_equal(sub(".*:([0-9]+)/$", "\\1", app$url), as.character(app$port))
  expect_true(app_port_reachable(app$port))
})

test_that("pz_serve_shiny starts an app from an app file", {
  # quiet = TRUE suppresses shiny's own banner but not the app's output.
  app <- local_shiny_app(
    shiny_app_fixture_file(),
    shiny_options = list(quiet = TRUE)
  )

  expect_true(app$is_running())
  expect_true(app_port_reachable(app$port))
  expect_true(any(grepl("PAPARAZZI_FIXTURE_APP_FILE", app$logs())))
  expect_false(any(grepl("Listening on", app$logs(), fixed = TRUE)))
})

test_that("app stdout and stderr share readable logs mid-run and after stop", {
  app <- local_shiny_app(shiny_app_fixture_dir())
  markers <- c(
    "PAPARAZZI_FIXTURE_STDOUT",
    "PAPARAZZI_FIXTURE_STDERR",
    "PAPARAZZI_FIXTURE_APP"
  )
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
  blocker <- local_blocker_server()
  taken_port <- blocker$port

  app <- local_shiny_app(
    shiny_app_fixture_dir(),
    shiny_options = list(port = taken_port)
  )
  expect_false(identical(app$port, taken_port))
  expect_true(app_port_reachable(app$port))
})

test_that("new_app constructs even when its port already has a listener", {
  skip_if_no_shiny()
  blocker <- local_blocker_server()
  taken_port <- blocker$port

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

test_that("an invalid max_attempts option fails with the option named", {
  withr::local_options(paparazzi.serve.max_attempts = 0)

  expect_snapshot(error = TRUE, {
    pz_serve_shiny(shiny_app_fixture_dir())
  })
})

test_that("a child that dies from a taken port exhausts its retries", {
  skip_if_no_shiny()
  # Two attempts prove the retry loop; the production default is five.
  withr::local_options(paparazzi.serve.max_attempts = 2)

  err <- expect_error(
    pz_serve_shiny(shiny_app_fixture_port_taken(), timeout = 5),
    class = "paparazzi_error_app_startup",
    regexp = "could not bind a port"
  )
  expect_match(conditionMessage(err), "Failed to create server", fixed = TRUE)
})

test_that("preflight exhaustion reports no nonexistent child log", {
  skip_if_no_shiny()
  blocker <- local_blocker_server()
  taken_port <- blocker$port
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
    pz_serve_shiny(shiny_app_fixture_dir(), wait = "settled"),
    "must be one of"
  )
  expect_error(
    pz_serve_shiny(shiny_app_fixture_dir(), width = 390),
    "must be empty"
  )
})

test_that("the wait declaration lands on the shiny handle", {
  skip_if_no_shiny()
  app <- local_shiny_app(shiny_app_fixture_dir())
  expect_identical(app$wait, "shiny")

  load_app <- local_shiny_app(shiny_app_fixture_dir(), wait = "load")
  expect_identical(load_app$wait, "load")
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

test_that("app timeout rejects NULL", {
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
    gc()
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
  }

  gc()
  servers <- httpuv::listServers()

  owned <- local_page(dir)
  owned_server <- owned$app
  expect_s3_class(owned_server, "PaparazziServe")
  expect_true(owned_server$is_running())
  expect_identical(pz_get_text(owned, target = "h1"), "Static capture")

  pz_nav_reload(owned)
  expect_identical(pz_get_text(owned, target = "h1"), "Static capture")

  pz_close(owned)
  expect_false(owned_server$is_running())
  expect_identical(httpuv::listServers(), servers)
})

test_that("static handles stop on scope exit and finalization", {
  skip_if_not_installed("httpuv")
  # Collect unrelated finalizers before snapshotting the running servers.
  gc()
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
  skip_if_no_quarto()
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

  page <- local_page(server, timeout = 30)
  second <- local_page(server, timeout = 30)
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
  skip_if_no_quarto()
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
  skip_if_no_quarto()
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

  page <- local_page(server, timeout = 30)
  expect_match(
    pz_get_text(page, target = "body"),
    "R Markdown marker",
    fixed = TRUE
  )
})

test_that("Quarto projects use their output URL", {
  skip_if_no_chrome()
  skip_if_no_quarto()
  dir <- withr::local_tempdir()
  writeLines(
    c("project:", "  type: website", "format: html"),
    file.path(dir, "_quarto.yml")
  )
  path <- file.path(dir, "index.qmd")
  file.copy(test_path("fixtures", "quarto", "document.qmd"), path)

  # render = TRUE on a project: the only project-level full render in
  # the suite (standalone documents render on startup either way).
  server <- pz_serve_quarto(dir, render = TRUE)
  withr::defer(server$stop())

  page <- local_page(server, timeout = 30)
  expect_identical(
    pz_get_text(page, target = "#document-marker"),
    "Quarto capture"
  )
})

test_that("Quarto finalizers stop the process tree", {
  skip_if_no_quarto()
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
  skip_if_no_quarto()
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
  skip_if_no_quarto()
  dir <- withr::local_tempdir()
  path <- file.path(dir, "document.qmd")
  file.copy(test_path("fixtures", "quarto", "document.qmd"), path)
  taken <- local_blocker_server()$port

  preview <- new_quarto(path, FALSE, quarto_cli(), taken)
  withr::defer(if (inherits(preview, "PaparazziServe")) preview$stop())

  expect_s3_class(preview, "PaparazziServe")
})

test_that("Quarto preflight exhaustion reports no nonexistent child log", {
  skip_if_not_installed("httpuv")
  skip_if_no_quarto()
  dir <- withr::local_tempdir()
  path <- file.path(dir, "document.qmd")
  file.copy(test_path("fixtures", "quarto", "document.qmd"), path)
  taken <- local_blocker_server()$port
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
  skip_if_no_quarto()
  dir <- withr::local_tempdir()
  path <- file.path(dir, "document.qmd")
  file.copy(test_path("fixtures", "quarto", "document.qmd"), path)
  taken <- local_blocker_server()$port
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

  # Mocked so the assertion is deterministic where httpuv isn't installed.
  local_mocked_bindings(httpuv_available = function() TRUE)
  # pz_open() serves .html files over HTTP when httpuv is available; other
  # files keep opening as file://.
  expect_identical(serve_kind(fixture_file()), "static")
  file.create(file.path(dir, "page.htm"))
  expect_null(serve_kind(file.path(dir, "page.htm")))

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

test_that(".html files fall back to file:// without httpuv", {
  local_mocked_bindings(httpuv_available = function() FALSE)
  expect_null(serve_kind(fixture_file()))
})

test_that("pz_serve_static() validates root", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "sub"))
  file.create(file.path(root, "sub", "my page.html"))
  outside <- withr::local_tempdir()

  expect_error(
    pz_serve_static(root, root = root),
    "only supported",
    class = "paparazzi_error_input"
  )
  expect_error(
    pz_serve_static(file.path(root, "sub", "my page.html"), root = outside),
    "inside",
    class = "paparazzi_error_input"
  )
  expect_error(
    pz_serve_static(
      file.path(root, "sub", "my page.html"),
      root = "does/not/exist"
    ),
    "existing directory",
    class = "paparazzi_error_input"
  )
})

test_that("pz_serve_static() rejects the filesystem root", {
  skip_if_not_installed("httpuv")
  file <- file.path(tempdir(), "root-test.html")
  file.create(file)
  withr::defer(unlink(file))

  expect_error(
    pz_serve_static(file, root = "/"),
    "filesystem root",
    class = "paparazzi_error_input"
  )
})

test_that("pz_serve_static() serves a custom root and points the URL at the file", {
  skip_if_not_installed("httpuv")
  root <- withr::local_tempdir()
  dir.create(file.path(root, "sub"))
  writeLines("<p>hi</p>", file.path(root, "sub", "my page.html"))

  server <- pz_serve_static(file.path(root, "sub", "my page.html"), root = root)
  withr::defer(server$stop())
  expect_match(server$url, "/sub/my%20page[.]html$")
  expect_true(server$is_running())

  same_root <- pz_serve_static(
    file.path(root, "sub", "my page.html"),
    root = file.path(root, "sub")
  )
  withr::defer(same_root$stop())
  expect_match(same_root$url, "/my%20page[.]html$")
})

test_that("a custom root resolves assets outside the page's directory", {
  skip_if_no_chrome()
  skip_if_not_installed("httpuv")
  root <- withr::local_tempdir()
  dir.create(file.path(root, "deps"))
  dir.create(file.path(root, "reference"))
  writeLines("body { color: red; }", file.path(root, "deps", "styles.css"))
  writeLines(
    paste(
      "<html><head>",
      '<link rel="stylesheet" href="../deps/styles.css">',
      "</head><body><h1>Styled page</h1></body></html>"
    ),
    file.path(root, "reference", "index.html")
  )

  server <- pz_serve_static(
    file.path(root, "reference", "index.html"),
    root = root
  )
  withr::defer(server$stop())
  expect_match(server$url, "/reference/index[.]html$")

  page <- local_page(server)
  status <- pz_evaluate(page, "fetch('../deps/styles.css').then(r => r.status)")
  expect_identical(status, 200L)
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
  # calls can exceed 2 without a bug: with parallel test workers another
  # worker can bind the port random_port() probed free, and the retry
  # loop then does its job a second time.
  expect_gte(calls, 2)
  expect_lte(calls, 3)
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
  skip_if_no_quarto()
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

test_that("pz_serve_command serves an external command and shares the handle contract", {
  skip_if_no_chrome()
  skip_if_no_command_server()
  server <- command_server()
  withr::defer(server$stop())

  expect_s3_class(server, "PaparazziServe")
  expect_true(server$is_running())
  expect_match(server$url, "^http://127[.]0[.]0[.]1:[0-9]+/$")
  expect_identical(server$wait, "load")

  page <- local_page(server)
  pz_expect_text(page, "command served", target = "body")
  pz_close(page)
  expect_true(server$is_running())

  expect_invisible(server$stop())
  expect_no_error(server$stop())
  expect_false(server$is_running())
  expect_true(wait_until(function() !app_port_reachable(server$port)))
  expect_type(server$logs(), "character")
})

test_that("{port} is substituted in args and envvars", {
  skip_if_no_chrome()
  skip_if_no_command_server()
  server <- command_server(envvars = c(COMMAND_PORT = "{port}"))
  withr::defer(server$stop())

  page <- local_page(server)
  # The server heard the port in its args (it listens) and in its
  # environment (the body reports it).
  pz_expect_text(
    page,
    paste0("command served on ", server$port),
    target = "body",
    match = "exact"
  )
})

test_that("an explicit port is kept, and a taken one fails instead of re-picking", {
  skip_if_no_chrome()
  skip_if_no_command_server()
  server <- command_server(port = random_port())
  withr::defer(server$stop())

  page <- local_page(server)
  pz_expect_text(page, "command served", target = "body")

  expect_error(
    command_server(port = server$port, timeout = 1),
    class = "paparazzi_error_command_startup"
  )
})

test_that("a command that exits during startup fails with its log", {
  skip_if_no_command_server()
  expect_error(
    pz_serve_command(
      file.path(R.home("bin"), "Rscript"),
      c("-e", "cat('command boom\n'); quit(status = 1)"),
      timeout = 5
    ),
    "command boom",
    class = "paparazzi_error_command_startup"
  )
})

test_that("a command that never listens times out and is cleaned up", {
  skip_if_no_command_server()
  port <- random_port()
  err <- expect_error(
    pz_serve_command(
      file.path(R.home("bin"), "Rscript"),
      c(
        "-e",
        "Sys.sleep(3); httpuv::runServer('127.0.0.1', {port}, list(call = function(req) list(status = 200L, body = 'late')))"
      ),
      port = port,
      timeout = 0.5
    ),
    class = "paparazzi_error_command_startup",
    regexp = "did not start"
  )
  expect_match(conditionMessage(err), "within 0.5 seconds", fixed = TRUE)
  # The would-be server binds at 3 seconds if it survived the timeout.
  Sys.sleep(3.5)
  expect_false(app_port_reachable(port))
})

test_that("an unstartable command fails with a paparazzi startup error", {
  skip_if_no_command_server()
  expect_error(
    pz_serve_command("paparazzi-no-such-command", timeout = 1),
    "could not be started",
    class = "paparazzi_error_command_startup"
  )
})

test_that("nav auto waits follow the handle's wait declaration", {
  skip_if_no_chrome()
  skip_if_no_command_server()
  server <- command_server(wait = "shiny")
  withr::defer(server$stop())

  page <- pz_open(server, wait = "load")
  withr::defer(pz_close(page))
  # auto resolves to a Shiny wait, which refuses this non-Shiny page
  expect_error(
    pz_nav_reload(page),
    "not a Shiny page",
    class = "paparazzi_error_unsupported"
  )

  plain <- command_server()
  withr::defer(plain$stop())
  plain_page <- pz_open(plain, wait = "load")
  withr::defer(pz_close(plain_page))
  expect_no_error(pz_nav_reload(plain_page))
})

test_that("the handle's wait declaration routes pz_open's auto wait", {
  skip_if_no_chrome()
  skip_if_no_command_server()
  server <- command_server(wait = "shiny")
  withr::defer(server$stop())

  expect_identical(server$wait, "shiny")
  # auto resolves to a Shiny wait, which refuses a non-Shiny page
  expect_error(
    pz_open(server, timeout = 2),
    "not a Shiny page",
    class = "paparazzi_error_unsupported"
  )
})

test_that("pz_serve_command validates its inputs", {
  expect_error(pz_serve_command(command = 1), "must be a single string")
  expect_error(pz_serve_command("true", args = 1), "must be a character vector")
  expect_error(
    pz_serve_command("true", wd = file.path("no", "such", "dir")),
    class = "paparazzi_error_input"
  )
  expect_error(pz_serve_command("true", port = 0), "must be a whole number")
  expect_error(
    pz_serve_command("true", envvars = "A=1"),
    class = "paparazzi_error_input"
  )
  expect_error(
    pz_serve_command("true", path = "relative"),
    class = "paparazzi_error_input"
  )
  expect_error(pz_serve_command("true", wait = "settled"), "must be one of")
  expect_error(pz_serve_command("true", timeout = -1), "must be a number")
  expect_error(pz_serve_command("true", extra = 1), "must be empty")
})

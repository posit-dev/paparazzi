test_that("pz_open opens a local file as file://", {
  page <- local_page()
  expect_s3_class(page, "PaparazziPage")
  expect_s3_class(page, "PaparazziContext")
  expect_false(page$is_closed())
  expect_match(pz_js(page, "location.protocol"), "file:")
  expect_identical(pz_js(page, "document.title"), "paparazzi fixture")
})

test_that("pz_open opens a URL with a scheme", {
  page <- local_page("about:blank")
  expect_identical(pz_js(page, "location.href"), "about:blank")
})

test_that("pz_open wraps an existing ChromoteSession", {
  skip_if_no_chrome()
  session <- chromote::ChromoteSession$new()
  withr::defer(session$close())

  page <- pz_open(session, timeout = 3)
  expect_s3_class(page, "PaparazziPage")
  expect_identical(pz_chromote(page), session)
  expect_equal(page$default_timeout, 3)

  pz_close(page)
  expect_true(page$is_closed())
})

test_that("pz_open waits for load by default", {
  page <- local_page()
  expect_identical(pz_js(page, "document.readyState"), "complete")
  expect_true(pz_js(page, "window.fixtureReady"))
})

test_that("new-session load waits anchor to the destination commit", {
  skip_if_no_chrome()
  blank <- chromote::ChromoteSession$new()
  withr::defer(blank$close())
  expect_identical(
    blank$Runtime$evaluate("document.readyState")$result$value,
    "complete"
  )

  url <- nav_fixture_url("slow")
  await <- nav_await
  commits <- character()
  local_mocked_bindings(nav_await = function(page, p, what, ...) {
    await(page, p, what, ...)
    hist <- page$session$Page$getNavigationHistory()
    commits <<- c(commits, hist$entries[[hist$currentIndex + 1]]$url)
  })
  for (wait in c("load", "auto")) {
    pz_with_page(
      url,
      function(page) {
        expect_identical(pz_js(page, "document.readyState"), "complete")
      },
      wait = wait,
      timeout = 5
    )
  }
  expect_identical(commits, rep(url, 2))
})

test_that("opening a same-document fragment returns without a new commit", {
  skip_if_no_chrome()
  pz_with_page(
    "about:blank#fragment",
    function(page) {
      expect_identical(pz_js(page, "location.href"), "about:blank#fragment")
    },
    wait = "load"
  )
})

test_that("wait = 'none' and wait = 'load' both open", {
  for (w in c("none", "load", "auto")) {
    page <- local_page(wait = w)
    expect_false(page$is_closed())
  }
})

test_that("Shiny auto resolves at the open seam", {
  expect_identical(open_wait_mode("auto", TRUE), "shiny")
  expect_identical(open_wait_mode("auto", FALSE), "load")
  expect_identical(open_wait_mode("none", TRUE), "none")
  expect_identical(open_wait_mode("shiny", FALSE), "shiny")
})

test_that("explicit Shiny wait rejects non-Shiny pages promptly", {
  skip_if_no_chrome()
  start <- Sys.time()
  expect_error(
    pz_open(fixture_file(), wait = "shiny", timeout = 3),
    "not a Shiny page",
    class = "paparazzi_error_unsupported"
  )
  expect_lt(as.numeric(difftime(Sys.time(), start, units = "secs")), 2)
})

test_that("explicit Shiny wait on a wrapped non-Shiny session fails without closing it", {
  skip_if_no_chrome()
  session <- chromote::ChromoteSession$new()
  withr::defer(session$close())
  expect_error(
    pz_open(session, wait = "shiny", timeout = 2),
    "not a Shiny page"
  )
  expect_no_error(session$Runtime$evaluate("1 + 1"))
})

test_that("explicit and auto Shiny waits settle after the slow output", {
  skip_if_no_chrome()
  skip_if_no_shiny()
  for (wait in c("shiny", "auto")) {
    start <- Sys.time()
    page <- pz_open(shiny_idle_fixture(), wait = wait, timeout = 5)
    expect_true(shiny_idle_state(page)$connected)
    expect_false(shiny_idle_state(page)$busy)
    expect_equal(shiny_idle_state(page)$recalculating, 0)
    expect_equal(shiny_idle_state(page)$text, "reactive ready")
    expect_gte(as.numeric(difftime(Sys.time(), start, units = "secs")), 0.9)
    pz_close(page)
  }
})

test_that("new-session Shiny waits anchor to the destination commit", {
  skip_if_no_chrome()
  skip_if_no_shiny()
  blank <- chromote::ChromoteSession$new()
  withr::defer(blank$close())
  # The outgoing document is already complete before the app navigation.
  expect_identical(
    blank$Runtime$evaluate("document.readyState")$result$value,
    "complete"
  )

  app <- local_shiny_app(shiny_idle_fixture())
  await <- nav_await
  commits <- character()
  local_mocked_bindings(nav_await = function(page, p, what, ...) {
    await(page, p, what, ...)
    hist <- page$session$Page$getNavigationHistory()
    commits <<- c(commits, hist$entries[[hist$currentIndex + 1]]$url)
  })
  for (wait in c("shiny", "auto")) {
    page <- pz_open(app, wait = wait, timeout = 5)
    expect_equal(shiny_idle_state(page)$text, "reactive ready")
    pz_close(page)
  }
  expect_identical(commits, rep(app$url, 2))
})

test_that("auto routes Shiny app files and shared handles to idle wait", {
  skip_if_no_chrome()
  skip_if_no_shiny()
  app_file <- file.path(shiny_idle_fixture(), "app.R")
  app <- local_shiny_app(shiny_idle_fixture())
  for (x in list(app_file, app)) {
    page <- pz_open(x, timeout = 5)
    expect_true(shiny_idle_state(page)$connected)
    expect_equal(shiny_idle_state(page)$text, "reactive ready")
    pz_close(page)
  }
})

test_that("pz_open errors on a Shiny app object with advice", {
  skip_if_no_chrome()
  app_obj <- structure(list(), class = "shiny.appobj")
  expect_error(
    pz_open(app_obj),
    regexp = "another process",
    class = "paparazzi_error_unsupported"
  )
})

test_that("pz_open owns an app started from a directory", {
  skip_if_no_chrome()
  skip_if_no_shiny()
  page <- pz_open(
    shiny_app_fixture_dir(),
    width = 390,
    shiny_options = list(quiet = TRUE),
    envvars = c(PAPARAZZI_TEST_MARKER = "open-owned")
  )
  withr::defer(pz_close(page))
  port <- as.integer(pz_js(page, "location.port"))
  expect_true(app_port_reachable(port))
  owned <- page$.__enclos_env__$private$owned_app_
  expect_true(any(grepl("marker: open-owned", owned$logs(), fixed = TRUE)))
  expect_false(any(grepl("Listening on", owned$logs(), fixed = TRUE)))
  expect_equal(pz_js(page, "innerWidth"), 390)
  expect_true(wait_until(function() {
    grepl("hello paparazzi", pz_js(page, "document.body.innerText"))
  }))
  pz_close(page)
  expect_true(page$is_closed())
  expect_true(wait_until(function() !app_port_reachable(port)))
  expect_no_error(pz_close(page))
})

test_that("pz_open owns an app.R file", {
  skip_if_no_chrome()
  skip_if_no_shiny()
  dir <- withr::local_tempdir()
  app_file <- file.path(dir, "app.R")
  file.copy(shiny_app_fixture_file(), app_file)
  page <- pz_open(app_file)
  withr::defer(pz_close(page))
  port <- as.integer(pz_js(page, "location.port"))
  expect_true(app_port_reachable(port))
  pz_close(page)
  expect_true(wait_until(function() !app_port_reachable(port)))
})

test_that("a page opened on a handle does not own the app", {
  skip_if_no_chrome()
  skip_if_no_shiny()
  app <- local_shiny_app(shiny_app_fixture_dir())
  page <- pz_open(app)
  withr::defer(pz_close(page))
  expect_true(wait_until(function() {
    grepl("hello paparazzi", pz_js(page, "document.body.innerText"))
  }))
  gc()
  pz_close(page)
  expect_true(app$is_running())
  expect_true(app_port_reachable(app$port))
  second <- pz_open(app)
  withr::defer(pz_close(second))
  expect_true(wait_until(function() {
    grepl("hello paparazzi", pz_js(second, "document.body.innerText"))
  }))
})

test_that("a temporary app handle survives GC while its page is open", {
  skip_if_no_chrome()
  skip_if_no_shiny()
  page <- pz_open(pz_serve_shiny(shiny_app_fixture_dir()))
  withr::defer({
    pz_close(page)
    page$.__enclos_env__$private$shared_app_$stop()
  })
  port <- as.integer(pz_js(page, "location.port"))
  gc()
  expect_true(app_port_reachable(port))
  expect_true(wait_until(function() {
    grepl("hello paparazzi", pz_js(page, "document.body.innerText"))
  }))
})

test_that("an opening failure stops the newly owned app", {
  skip_if_no_chrome()
  skip_if_no_shiny()
  port <- free_port()
  expect_error(
    pz_open(
      shiny_app_fixture_dir(),
      shiny_options = list(port = port),
      timezone = "Mars/Olympus"
    ),
    regexp = "Invalid timezone"
  )
  expect_true(wait_until(function() !app_port_reachable(port)))
})

test_that("an opening failure leaves a shared app running", {
  skip_if_no_chrome()
  skip_if_no_shiny()
  app <- local_shiny_app(shiny_app_fixture_dir())
  expect_error(
    pz_open(app, timezone = "Mars/Olympus"),
    regexp = "Invalid timezone"
  )
  expect_true(app$is_running())
  expect_true(app_port_reachable(app$port))
})

test_that("block helpers close pages but not shared apps", {
  skip_if_no_chrome()
  skip_if_no_shiny()
  app <- local_shiny_app(shiny_app_fixture_dir())
  captured <- NULL
  expect_error(
    pz_with_page(app, function(page) {
      captured <<- page
      stop("boom")
    }),
    "boom"
  )
  expect_true(captured$is_closed())
  expect_true(app$is_running())

  local({
    page <- pz_local_page(app)
    captured <<- page
    expect_false(page$is_closed())
  })
  expect_true(captured$is_closed())
  expect_true(app_port_reachable(app$port))
})

test_that("block helpers stop owned apps on exit and error", {
  skip_if_no_chrome()
  skip_if_no_shiny()
  port <- NULL
  expect_error(
    pz_with_page(shiny_app_fixture_dir(), function(page) {
      port <<- as.integer(pz_js(page, "location.port"))
      stop("boom")
    }),
    "boom"
  )
  expect_true(wait_until(function() !app_port_reachable(port)))
  local({
    page <- pz_local_page(shiny_app_fixture_dir())
    port <<- as.integer(pz_js(page, "location.port"))
    expect_true(app_port_reachable(port))
  })
  expect_true(wait_until(function() !app_port_reachable(port)))
})

test_that("pz_open errors on bad input", {
  skip_if_no_chrome()
  expect_error(pz_open(42), class = "paparazzi_error_input")
  expect_error(
    pz_open("no-scheme-no-file.xyz"),
    class = "paparazzi_error_input"
  )
})

test_that("pz_open validates shiny_options and envvars types", {
  expect_error(
    pz_open(fixture_file(), shiny_options = "nope"),
    "must be a list"
  )
  expect_error(
    pz_open(fixture_file(), envvars = 42),
    "must be a character vector"
  )
})

test_that("pz_open forwards dots to pz_device", {
  skip_if_no_chrome()
  page <- local_page(width = 390)
  expect_equal(pz_js(page, "innerWidth"), 390)
})

test_that("session default timeout is 10s, configurable at open", {
  page <- local_page()
  expect_equal(page$default_timeout, 10)

  page2 <- local_page(timeout = 2.5)
  expect_equal(page2$default_timeout, 2.5)

  page2$default_timeout <- 5
  expect_equal(page2$default_timeout, 5)
})

test_that("pz_close is idempotent and functions reject closed pages", {
  skip_if_no_chrome()
  page <- pz_open(fixture_file())
  pz_close(page)
  expect_true(page$is_closed())
  expect_no_error(pz_close(page))

  expect_error(pz_js(page, "1 + 1"), class = "paparazzi_error_closed")
  expect_error(pz_wait(page, 0), class = "paparazzi_error_closed")
})

test_that("pz_close closes the page behind a context", {
  skip_if_no_chrome()
  page <- pz_open(fixture_file())
  closed <- pz_find(page, "body") |> pz_close()
  expect_identical(closed, page)
  expect_true(page$is_closed())

  skip_if_not_installed("av")
  page <- pz_open(fixture_file())
  out <- withr::local_tempfile(fileext = ".mp4")
  pz_record_start(page, out, fps = 5, hold = c(0, 0)) |>
    pz_wait(0.1) |>
    pz_close()
  expect_true(file.exists(out))
  expect_true(page$is_closed())

  page <- pz_open(fixture_file())
  chain <- pz_record_start(page, withr::local_tempfile(fileext = ".mp4"))
  testthat::local_mocked_bindings(
    record_encode = function(...) stop("encode failed")
  )
  expect_error(pz_close(chain), "encode failed")
  expect_true(page$is_closed())
})

test_that("a failed device setting after page creation closes the new session", {
  skip_if_no_chrome()
  browser <- chromote::default_chromote_object()
  page_targets <- function() {
    targets <- browser$Target$getTargets()$targetInfos
    vapply(
      Filter(function(target) identical(target$type, "page"), targets),
      function(target) target$targetId,
      character(1)
    )
  }
  before <- page_targets()
  # Invalid timezone fails after the new page target has been created.
  expect_error(
    pz_open(fixture_file(), timezone = "Mars/Olympus"),
    regexp = "Invalid timezone"
  )
  # pz_open() looks the default browser up itself; a replaced browser
  # would make the target diff below vacuous.
  expect_identical(chromote::default_chromote_object(), browser)
  deadline <- Sys.time() + 3
  repeat {
    new_ids <- setdiff(page_targets(), before)
    if (length(new_ids) == 0L || Sys.time() >= deadline) {
      break
    }
    Sys.sleep(0.05)
  }
  expect_length(new_ids, 0L)
})

test_that("a failed device setting on a wrapped session leaves it open", {
  skip_if_no_chrome()
  session <- chromote::ChromoteSession$new()
  withr::defer(session$close())

  expect_error(
    pz_open(session, timezone = "Mars/Olympus"),
    regexp = "Invalid timezone"
  )
  # The caller owns this session; the failure must not close it.
  expect_no_error(session$Page$getNavigationHistory())
})

test_that("pz_open aborts when navigation fails", {
  skip_if_no_chrome()
  expect_error(
    pz_open("http://127.0.0.1:1/"),
    class = "paparazzi_error_navigation"
  )
})

test_that("is_shiny_app_file recognizes Shiny app file names", {
  shiny_files <- c(
    "app.R",
    "app.r",
    "app-main.R",
    "app_ui.R",
    "app-old-server.R",
    "my-app.R",
    "my_app.R",
    "my-shiny-app.R"
  )
  for (f in shiny_files) {
    expect_true(is_shiny_app_file(f), info = f)
  }

  plain_files <- c(
    "ui.R",
    "server.R",
    "webapp.R",
    "snapp.R",
    "utils.R",
    "my-utils.R",
    "screenshot.R",
    "app.Rmd",
    "appR.R",
    "ui.R.bak",
    "foo_.R",
    "foo-.R",
    "application.R"
  )
  for (f in plain_files) {
    expect_false(is_shiny_app_file(f), info = f)
  }
})

test_that("pz_open starts recognized Shiny app file names", {
  skip_if_no_chrome()
  skip_if_no_shiny()
  dir <- withr::local_tempdir()
  for (f in c("app-main.R", "user_app.R")) {
    path <- file.path(dir, f)
    file.copy(shiny_app_fixture_file(), path)
    page <- pz_open(path)
    port <- as.integer(pz_js(page, "location.port"))
    expect_true(app_port_reachable(port), info = f)
    pz_close(page)
    expect_true(wait_until(function() !app_port_reachable(port)), info = f)
  }
})

test_that("split app files open as files, while their directory runs as an app", {
  skip_if_no_chrome()
  skip_if_no_shiny()
  dir <- withr::local_tempdir()
  ui <- file.path(dir, "ui.R")
  server <- file.path(dir, "server.R")
  writeLines("shiny::fluidPage(shiny::textOutput('out'))", ui)
  writeLines(
    paste(
      "function(input, output, session) {",
      "  output$out <- shiny::renderText('hello split app')",
      "}"
    ),
    server
  )

  for (file in c(ui, server)) {
    page <- pz_open(file)
    expect_identical(pz_js(page, "location.protocol"), "file:")
    pz_close(page)
  }

  page <- pz_open(dir)
  withr::defer(pz_close(page))
  expect_identical(pz_js(page, "location.protocol"), "http:")
  expect_true(wait_until(function() {
    grepl("hello split app", pz_js(page, "document.body.innerText"))
  }))
})

test_that("files whose names end in app.R variants open fine", {
  skip_if_no_chrome()
  r_file <- withr::local_tempfile(fileext = "webapp.R")
  writeLines("# not a shiny app", r_file)
  page <- pz_open(r_file)
  withr::defer(pz_close(page))
  expect_match(pz_js(page, "location.protocol"), "file:")
})

test_that("file_url percent-encodes special characters", {
  dir <- withr::local_tempdir()
  weird <- file.path(dir, "my page #1?.html")
  file.create(weird)
  url <- file_url(weird)
  expect_match(url, "^file:///")
  expect_match(url, "my%20page%20%231%3F.html", fixed = TRUE)
  expect_no_match(url, "#")

  skip_if_no_chrome()
  page <- pz_open(weird)
  withr::defer(pz_close(page))
  expect_match(pz_js(page, "location.protocol"), "file:")
})

test_that("file_url encodes literal percent signs in file names", {
  dir <- withr::local_tempdir()
  pct <- file.path(dir, "a%20b #1.html")
  file.create(pct)
  url <- file_url(pct)
  expect_match(url, "a%2520b%20%231.html", fixed = TRUE)

  skip_if_no_chrome()
  page <- pz_open(pct)
  withr::defer(pz_close(page))
  expect_match(pz_js(page, "location.pathname"), "a%2520b", fixed = TRUE)
})

test_that("print() works on open and closed pages", {
  skip_if_no_chrome()
  page <- pz_open(fixture_file())
  expect_output(print(page), "── paparazzi page")
  expect_output(print(page), "URL        file:")
  pz_close(page)
  expect_output(print(page), "<paparazzi page> \\(closed\\)")
})

test_that("Windows drive paths are not mistaken for URL schemes", {
  expect_error(
    open_target_url("C:/definitely/not/here.html"),
    class = "paparazzi_error_input"
  )
})

test_that("pz_close rejects non-pages", {
  expect_error(pz_close("nope"), class = "paparazzi_error_input")
})

test_that("check_context rejects non-contexts", {
  expect_error(pz_js("nope", "1"), class = "paparazzi_error_context")
  expect_error(pz_wait(list(), 1), class = "paparazzi_error_context")
})

test_that("pz_with_page returns the page invisibly and closes it", {
  skip_if_no_chrome()
  res <- withVisible(pz_with_page(fixture_file(), function(page) {
    expect_false(page$is_closed())
    1 + 1
  }))
  expect_false(res$visible)
  expect_s3_class(res$value, "PaparazziPage")
  expect_true(res$value$is_closed())
})

test_that("pz_with_page closes even when the block errors", {
  skip_if_no_chrome()
  captured <- NULL
  expect_error(
    pz_with_page(fixture_file(), function(page) {
      captured <<- page
      stop("boom")
    }),
    "boom"
  )
  expect_true(captured$is_closed())
})

test_that("pz_with_page evaluates plain expressions", {
  skip_if_no_chrome()
  ran <- FALSE
  pz_with_page(fixture_file(), {
    ran <- TRUE
  })
  expect_true(ran)
})

test_that("pz_with_page accepts an already-open page and closes it", {
  skip_if_no_chrome()
  page <- pz_open(fixture_file())
  pz_with_page(page, {
    expect_false(page$is_closed())
  })
  expect_true(page$is_closed())
})

test_that("a braced block is never called, even if it returns a function", {
  skip_if_no_chrome()
  called <- FALSE
  pz_with_page(fixture_file(), {
    function(page) called <<- TRUE
  })
  expect_false(called)
})

test_that("pz_local_page closes when the calling frame exits", {
  skip_if_no_chrome()
  page <- local({
    p <- pz_local_page(fixture_file())
    expect_false(p$is_closed())
    p
  })
  expect_true(page$is_closed())
})

test_that("pz_local_page accepts an already-open page and closes it", {
  skip_if_no_chrome()
  page <- pz_open(fixture_file())
  local(pz_local_page(page))
  expect_true(page$is_closed())
})

test_that("pz_local_page forwards ... to pz_open", {
  skip_if_no_chrome()
  page <- local(pz_local_page(fixture_file(), timeout = 7))
  expect_equal(page$default_timeout, 7)
  expect_true(page$is_closed())
})

test_that("open timeout defaults to ten seconds and rejects NULL", {
  expect_error(pz_open("about:blank", timeout = NULL), "timeout")
  page <- pz_local_page("about:blank")
  expect_equal(page$default_timeout, 10)
})

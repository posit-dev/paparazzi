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

test_that("wait = 'none' and wait = 'load' both open", {
  for (w in c("none", "load", "auto")) {
    page <- local_page(wait = w)
    expect_false(page$is_closed())
  }
})

test_that("wait = 'shiny' errors for now", {
  skip_if_no_chrome()
  expect_error(
    pz_open(fixture_file(), wait = "shiny"),
    class = "paparazzi_error_unsupported"
  )
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

test_that("pz_open errors on app directories and app.R", {
  skip_if_no_chrome()
  dir <- withr::local_tempdir()
  expect_error(pz_open(dir), class = "paparazzi_error_unsupported")
  app_r <- file.path(dir, "app.R")
  file.create(app_r)
  expect_error(pz_open(app_r), class = "paparazzi_error_unsupported")
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
    "ui.R",
    "server.R",
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

test_that("pz_open rejects Shiny app file names with advice", {
  skip_if_no_chrome()
  dir <- withr::local_tempdir()
  for (f in c("ui.R", "server.R", "app-main.R")) {
    path <- file.path(dir, f)
    file.create(path)
    expect_error(
      pz_open(path),
      regexp = "another process",
      class = "paparazzi_error_unsupported",
      info = f
    )
  }
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
  expect_output(print(page), "PaparazziPage: closed")
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

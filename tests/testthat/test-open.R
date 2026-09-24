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

test_that("pz_open checks dots empty", {
  skip_if_no_chrome()
  expect_error(pz_open(fixture_file(), width = 100), "empty")
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

test_that("pz_close rejects non-pages", {
  expect_error(pz_close("nope"), class = "paparazzi_error_input")
})

test_that("check_context rejects non-contexts", {
  expect_error(pz_js("nope", "1"), class = "paparazzi_error_context")
  expect_error(pz_wait(list(), 1), class = "paparazzi_error_context")
})

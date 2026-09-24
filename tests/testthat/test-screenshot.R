# The page's device pixel ratio at capture time: PNG pixel dimensions
# are round(css_size * dpr). Read live per test so the expectations stay
# dpr-agnostic even though headless CI runs at dpr 1.
local_dpr <- function(page) {
  pz_js(page, "window.devicePixelRatio")
}

test_that("pz_screenshot captures the viewport from the root context", {
  page <- local_screenshot_page()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- local_dpr(page)
  # pz_js() turns JS arrays into R lists; flatten for the arithmetic.
  inner <- unlist(pz_js(page, "[window.innerWidth, window.innerHeight]"))

  pz_screenshot(page, path)
  expect_identical(png_dimensions(path), as.integer(round(inner * dpr)))
})

test_that("pz_screenshot captures a single element's bounding box", {
  page <- local_screenshot_page()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- local_dpr(page)

  # #shot-a: left 40, top 30, 100x60
  pz_screenshot(page, path, target = "#shot-a")
  expect_identical(png_dimensions(path), as.integer(round(c(100, 60) * dpr)))
})

test_that("pz_screenshot captures the union of a list of targets", {
  page <- local_screenshot_page()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- local_dpr(page)

  # #shot-b sits right of AND below #shot-a, so the union is
  # x=40 y=30 w=300 h=170: the prior-art bug (mutating x before
  # computing width) would report the wrong width here.
  pz_screenshot(page, path, target = list("#shot-a", "#shot-b"))
  expect_identical(png_dimensions(path), as.integer(round(c(300, 170) * dpr)))
})

test_that("pz_screenshot unions every element a multi-match selector finds", {
  page <- local_screenshot_page()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- local_dpr(page)

  # .multi matches #multi-1 (40, 260, 80x50) and #multi-2
  # (180, 300, 80x50); the union is x=40 y=260 w=220 h=90. No strict
  # argument: several matches are a union, not an error.
  pz_screenshot(page, path, target = ".multi")
  expect_identical(png_dimensions(path), as.integer(round(c(220, 90) * dpr)))
})

test_that("pz_screenshot accepts a mixed list of pz_loc() specs and strings", {
  page <- local_screenshot_page()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- local_dpr(page)

  pz_screenshot(page, path, target = list(pz_loc("#shot-a"), "#shot-b"))
  expect_identical(png_dimensions(path), as.integer(round(c(300, 170) * dpr)))
})

test_that("pz_screenshot captures a below-fold element without scrolling", {
  page <- local_screenshot_page()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- local_dpr(page)

  # #below-fold: left 60, top 2400, 200x100 -- far beyond the default
  # viewport, so this exercises the captureBeyondViewport path. The
  # capture must not scroll the page as a side effect.
  pz_screenshot(page, path, target = "#below-fold")
  expect_identical(png_dimensions(path), as.integer(round(c(200, 100) * dpr)))
  expect_equal(pz_js(page, "window.scrollY"), 0)
})

test_that("frame = FALSE captures without framing, like frame = NULL", {
  page <- local_screenshot_page()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- local_dpr(page)
  inner <- unlist(pz_js(page, "[window.innerWidth, window.innerHeight]"))

  pz_screenshot(page, path, frame = FALSE)
  expect_identical(png_dimensions(path), as.integer(round(inner * dpr)))
})

test_that("frame = TRUE is not supported yet", {
  page <- local_screenshot_page()
  path <- withr::local_tempfile(fileext = ".png")

  expect_error(
    pz_screenshot(page, path, frame = TRUE),
    class = "paparazzi_error_unsupported"
  )
  # Nothing was written before the error.
  expect_false(file.exists(path))
})

test_that("pz_screenshot returns its context invisibly", {
  page <- local_screenshot_page()
  path <- withr::local_tempfile(fileext = ".png")

  expect_invisible(pz_screenshot(page, path))
  expect_identical(withVisible(pz_screenshot(page, path))$value, page)
})

test_that("pz_screenshot validates its inputs", {
  page <- local_screenshot_page()
  path <- withr::local_tempfile(fileext = ".png")

  expect_error(
    pz_screenshot(page, path, target = list()),
    class = "paparazzi_error_target"
  )
  expect_error(pz_screenshot(page, path, target = 42), class = "rlang_error")
  expect_error(pz_screenshot(page, path, extra = 1), "empty")
  expect_error(pz_screenshot(page, 42), class = "rlang_error")
})

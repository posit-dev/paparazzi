# The page's device pixel ratio at capture time: PNG pixel dimensions
# are round(css_size * dpr). Read live per test so the expectations stay
# dpr-agnostic even though headless CI runs at dpr 1.
local_dpr <- function(page) {
  pz_js(page, "window.devicePixelRatio")
}

# Sample the [r, g, b, a] of one device pixel from a written PNG by
# decoding it in the page: base64 the file, load it into an Image, and
# read the pixel through a canvas via getImageData. Coordinates are CSS
# offsets within the capture, converted to device px with the dpr.
png_pixel <- function(page, path, css_x, css_y, dpr) {
  raw <- readBin(path, "raw", n = file.info(path)$size)
  # base64_enc wraps its output every 76 chars; the newlines would break
  # the JS string literal below.
  b64 <- gsub("[\r\n]", "", jsonlite::base64_enc(raw))
  js <- sprintf(
    paste0(
      "(async () => {",
      "const img = new Image();",
      "img.src = 'data:image/png;base64,%s';",
      "await img.decode();",
      "const c = document.createElement('canvas').getContext('2d');",
      "c.canvas.width = img.width; c.canvas.height = img.height;",
      "c.drawImage(img, 0, 0);",
      "return Array.from(c.getImageData(%d, %d, 1, 1).data);",
      "})()"
    ),
    b64,
    round(css_x * dpr),
    round(css_y * dpr)
  )
  unlist(pz_js(page, js))
}

# Assert a pixel equals an expected RGB within a per-channel tolerance
# that survives canvas color management.
expect_pixel <- function(page, path, css_x, css_y, dpr, expected) {
  got <- png_pixel(page, path, css_x, css_y, dpr)
  expect_true(
    all(abs(got[1:3] - expected) <= 2),
    info = sprintf(
      "pixel at css (%g, %g): got [%s], expected [%s]",
      css_x, css_y,
      paste(got[1:3], collapse = ", "),
      paste(expected, collapse = ", ")
    )
  )
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

test_that("pz_screenshot clamps the viewport clip origin on negative RTL scroll", {
  page <- local_screenshot_page()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- local_dpr(page)

  # Go RTL and widen the body so horizontal scroll exists; scrolling
  # left of the origin makes window.scrollX negative, which CDP would
  # reject as a clip origin.
  pz_js(page, "document.documentElement.dir = 'rtl'")
  pz_js(page, "document.body.style.width = '3000px'")
  pz_js(page, "window.scrollTo(-100, 0)")
  skip_if(pz_js(page, "window.scrollX") >= 0, "browser won't scroll negative in RTL")

  expect_no_error(pz_screenshot(page, path))
  inner <- unlist(pz_js(page, "[window.innerWidth, window.innerHeight]"))
  expect_identical(png_dimensions(path), as.integer(round(inner * dpr)))
})

test_that("pz_screenshot captures the right pixels", {
  page <- local_screenshot_page()
  dpr <- local_dpr(page)

  # #shot-a: 100x60 red at (40, 30); center of the capture.
  path_a <- withr::local_tempfile(fileext = ".png")
  pz_screenshot(page, path_a, target = "#shot-a")
  expect_pixel(page, path_a, 50, 30, dpr, c(255, 0, 0))

  # Union of #shot-a + #shot-b: origin (40, 30), so offsets are relative
  # to the union box.
  path_u <- withr::local_tempfile(fileext = ".png")
  pz_screenshot(page, path_u, target = list("#shot-a", "#shot-b"))
  expect_pixel(page, path_u, 10, 15, dpr, c(255, 0, 0))
  # CSS "green" is #008000, not (0, 255, 0).
  expect_pixel(page, path_u, 230, 130, dpr, c(0, 128, 0))
  # Inside the union box but over neither element: the page background.
  expect_pixel(page, path_u, 110, 5, dpr, c(255, 255, 255))

  # #below-fold: 200x100 purple at (60, 2400); center of the capture.
  path_f <- withr::local_tempfile(fileext = ".png")
  pz_screenshot(page, path_f, target = "#below-fold")
  expect_pixel(page, path_f, 100, 50, dpr, c(128, 0, 128))
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

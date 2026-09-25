frame_fixture_file <- function() {
  test_path("fixtures", "frame.html")
}

local_frame_page <- function(.env = parent.frame()) {
  local_page(frame_fixture_file(), .env = .env)
}

frame_rtl_fixture_file <- function() {
  test_path("fixtures", "frame-rtl.html")
}

local_rtl_frame_page <- function(.env = parent.frame()) {
  local_page(frame_rtl_fixture_file(), .env = .env)
}

# The page's device pixel ratio at capture time; PNG pixel dimensions
# are round(css_size * dpr).
frame_dpr <- function(page) {
  pz_js(page, "window.devicePixelRatio")
}

# Sample the [r, g, b, a] of one CSS point of a written PNG by
# decoding it in the page (base64 the file, load it into an Image, read
# the pixel through a canvas). Frame tests own this copy because
# helper-page.R is shared and belongs to no single task.
frame_png_pixel <- function(page, path, css_x, css_y, dpr) {
  raw <- readBin(path, "raw", n = file.info(path)$size)
  # base64_enc wraps its output every 76 chars; the newlines would
  # break the JS string literal below.
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

expect_frame_pixel <- function(page, path, css_x, css_y, dpr, expected) {
  got <- frame_png_pixel(page, path, css_x, css_y, dpr)
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

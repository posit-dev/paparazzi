# The page's device pixel ratio at capture time: PNG pixel dimensions
# are round(css_size * dpr). Read live so expectations stay dpr-agnostic.
page_dpr <- function(page) {
  pz_js(page, "window.devicePixelRatio")
}

# Decode a PNG file in the page and run `body` (JS statements) with the
# decoded `img` and a 2d context `c` holding it; `body` must `return`.
png_canvas_eval <- function(page, path, body) {
  raw <- readBin(path, "raw", n = file.info(path)$size)
  # base64_enc wraps its output every 76 chars; the newlines would break
  # the JS string literal.
  b64 <- gsub("[\r\n]", "", jsonlite::base64_enc(raw))
  js <- paste0(
    "(async () => {",
    "const img = new Image();",
    "img.src = 'data:image/png;base64,",
    b64,
    "';",
    "await img.decode();",
    "const c = document.createElement('canvas').getContext('2d');",
    "c.canvas.width = img.width; c.canvas.height = img.height;",
    "c.drawImage(img, 0, 0);",
    body,
    "})()"
  )
  pz_js(page, js)
}

# One device pixel of a PNG as c(r, g, b, a), at a CSS point.
png_pixel <- function(page, path, css_x, css_y, dpr = page_dpr(page)) {
  unlist(png_canvas_eval(
    page,
    path,
    sprintf(
      "return Array.from(c.getImageData(%d, %d, 1, 1).data);",
      round(css_x * dpr),
      round(css_y * dpr)
    )
  ))
}

# Assert a pixel's RGB within a per-channel tolerance that survives
# canvas color management.
expect_png_pixel <- function(
  page,
  path,
  css_x,
  css_y,
  expected,
  dpr = page_dpr(page)
) {
  got <- png_pixel(page, path, css_x, css_y, dpr)
  expect_true(
    all(abs(got[1:3] - expected) <= 2),
    info = sprintf(
      "pixel at css (%g, %g): got [%s], expected [%s]",
      css_x,
      css_y,
      paste(got[1:3], collapse = ", "),
      paste(expected, collapse = ", ")
    )
  )
}

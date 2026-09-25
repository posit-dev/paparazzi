cursor_fixture_file <- function() {
  test_path("fixtures", "cursor.html")
}

local_cursor_page <- function(.env = parent.frame()) {
  local_page(cursor_fixture_file(), .env = .env)
}

# The overlay cursor's drawn state as c(opacity, x, y, hand): opacity of
# the inner layer, the glide translate (viewport CSS px), and whether
# the hand shape is showing. NULL when no cursor layer exists.
cursor_overlay_state <- function(page) {
  v <- pz_js(
    page,
    paste0(
      "(() => {",
      "const h = document.getElementById('paparazzi-overlay-root');",
      "if (!h || !h.shadowRoot) return null;",
      "const l = h.shadowRoot.querySelector('.pz-cursor');",
      "if (!l) return null;",
      "const g = l.firstElementChild, i = g.firstElementChild;",
      "const m = /translate\\((-?[\\d.]+)px,\\s*(-?[\\d.]+)px\\)/.exec(g.style.transform);",
      "return [",
      "parseFloat(i.style.opacity || '1'),",
      "m ? parseFloat(m[1]) : 0,",
      "m ? parseFloat(m[2]) : 0,",
      "l.querySelector('.pz-hand').style.display !== 'none' ? 1 : 0",
      "];})()"
    )
  )
  if (is.null(v)) {
    return(NULL)
  }
  unlist(v)
}

# The page's device pixel ratio (PNG pixels per CSS pixel in captures).
cursor_dpr <- function(page) {
  pz_js(page, "window.devicePixelRatio")
}

# Scan a PNG for near-black pixels (the cursor ink; the fixture keeps
# everything else lighter than the threshold): count, CSS-pixel
# centroid, and ink height (max - min y), optionally restricted to a
# horizontal band (CSS y range). Decoding happens in the page (helper-
# frame.R's canvas technique; helper-page.R is shared and untouched).
cursor_png_ink <- function(page, path, band = NULL, dpr = cursor_dpr(page)) {
  raw <- readBin(path, "raw", n = file.info(path)$size)
  # base64_enc wraps every 76 chars; the newlines would break the JS.
  b64 <- gsub("[\r\n]", "", jsonlite::base64_enc(raw))
  region <- if (is.null(band)) {
    "0, 0, img.width, img.height"
  } else {
    sprintf(
      "0, %d, img.width, %d",
      floor(band[[1]] * dpr),
      ceiling((band[[2]] - band[[1]]) * dpr)
    )
  }
  # Pixel rows are region-relative; yoff shifts them back to absolute.
  yoff <- if (is.null(band)) 0 else floor(band[[1]] * dpr)
  js <- sprintf(
    paste0(
      "(async () => {",
      "const img = new Image();",
      "img.src = 'data:image/png;base64,%s';",
      "await img.decode();",
      "const c = document.createElement('canvas').getContext('2d');",
      "c.canvas.width = img.width; c.canvas.height = img.height;",
      "c.drawImage(img, 0, 0);",
      "const d = c.getImageData(%s).data;",
      "let n = 0, sx = 0, sy = 0, minY = Infinity, maxY = -Infinity;",
      "const w = img.width;",
      "for (let p = 0; p < d.length; p += 4) {",
      "  if (d[p] < 60 && d[p + 1] < 60 && d[p + 2] < 60 && d[p + 3] > 200) {",
      "    const px = (p / 4) %% w, py = Math.floor(p / 4 / w) + ",
      sprintf("%d;", yoff),
      "    n++; sx += px; sy += py;",
      "    if (py < minY) minY = py;",
      "    if (py > maxY) maxY = py;",
      "  }",
      "}",
      "if (!n) return [0, 0, 0, 0];",
      "return [n, sx / n / %s, sy / n / %s, (maxY - minY + 1) / %s];",
      "})()"
    ),
    b64, region, dpr, dpr, dpr
  )
  v <- unlist(pz_js(page, js))
  list(count = v[[1]], x = v[[2]], y = v[[3]], height = v[[4]])
}

# One pixel of a PNG, as c(r, g, b, a), at a CSS point.
cursor_png_pixel <- function(page, path, css_x, css_y, dpr = cursor_dpr(page)) {
  raw <- readBin(path, "raw", n = file.info(path)$size)
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

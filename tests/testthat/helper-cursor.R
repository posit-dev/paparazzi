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

cursor_overlay_scale <- function(page) {
  pz_js(
    page,
    paste0(
      "parseFloat(document.getElementById('paparazzi-overlay-root')",
      ".shadowRoot.querySelector('.pz-inner').style.transform.slice(6))"
    )
  )
}

# Scan a PNG for near-black pixels (the cursor ink; the fixture keeps
# everything else lighter than the threshold): count, CSS-pixel
# centroid, and ink height (max - min y), optionally restricted to a
# horizontal band (CSS y range).
cursor_png_ink <- function(page, path, band = NULL, dpr = page_dpr(page)) {
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
  body <- paste0(
    "const d = c.getImageData(",
    region,
    ").data;",
    "let n = 0, sx = 0, sy = 0, minY = Infinity, maxY = -Infinity;",
    "const w = img.width;",
    "for (let p = 0; p < d.length; p += 4) {",
    "  if (d[p] < 60 && d[p + 1] < 60 && d[p + 2] < 60 && d[p + 3] > 200) {",
    "    const px = (p / 4) % w, py = Math.floor(p / 4 / w) + ",
    yoff,
    ";",
    "    n++; sx += px; sy += py;",
    "    if (py < minY) minY = py;",
    "    if (py > maxY) maxY = py;",
    "  }",
    "}",
    "if (!n) return [0, 0, 0, 0];",
    "return [n, sx / n / ",
    dpr,
    ", sy / n / ",
    dpr,
    ", (maxY - minY + 1) / ",
    dpr,
    "];"
  )
  v <- unlist(png_canvas_eval(page, path, body))
  list(count = v[[1]], x = v[[2]], y = v[[3]], height = v[[4]])
}

cursor_fixture_file <- function() {
  test_path("fixtures", "cursor.html")
}

local_cursor_page <- function(.env = parent.frame()) {
  local_page(cursor_fixture_file(), .env = .env)
}

# The overlay cursor's drawn state as numeric c(opacity, x, y), with an icon attribute: opacity of
# the inner layer, the glide translate (viewport CSS px), and whether
# the visible icon keyword. NULL when no cursor layer exists.
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
      "[...l.querySelectorAll('.pz-icon')].find(svg => getComputedStyle(svg).visibility === 'visible')?.classList[1].slice('pz-icon-'.length) || null",
      "];})()"
    )
  )
  if (is.null(v)) {
    return(NULL)
  }
  structure(unlist(v[1:3]), icon = v[[4]])
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
# everything else lighter than the threshold), or near-white pixels on a
# dark target. Return count, CSS-pixel centroid, and ink height, optionally
# restricted to a horizontal band and x range.
cursor_png_ink <- function(
  page,
  path,
  band = NULL,
  dpr = page_dpr(page),
  x_range = NULL,
  tone = "dark"
) {
  tone <- match.arg(tone, c("dark", "light"))
  x0 <- if (is.null(x_range)) 0 else floor(x_range[[1]] * dpr)
  x1 <- if (is.null(x_range)) NULL else ceiling(x_range[[2]] * dpr)
  y0 <- if (is.null(band)) 0 else floor(band[[1]] * dpr)
  y1 <- if (is.null(band)) NULL else ceiling(band[[2]] * dpr)
  region <- paste(
    x0,
    y0,
    if (is.null(x1)) "img.width" else x1 - x0,
    if (is.null(y1)) "img.height" else y1 - y0,
    sep = ", "
  )
  threshold <- if (tone == "dark") {
    "d[p] < 60 && d[p + 1] < 60 && d[p + 2] < 60"
  } else {
    "d[p] > 220 && d[p + 1] > 220 && d[p + 2] > 220"
  }
  body <- paste0(
    "const d = c.getImageData(",
    region,
    ").data;",
    "let n = 0, sx = 0, sy = 0, minY = Infinity, maxY = -Infinity;",
    "const w = img.width;",
    "for (let p = 0; p < d.length; p += 4) {",
    "  if (",
    threshold,
    " && d[p + 3] > 200) {",
    "    const px = (p / 4) % ",
    if (is.null(x1)) "w" else x1 - x0,
    " + ",
    x0,
    ", py = Math.floor(p / 4 / ",
    if (is.null(x1)) "w" else x1 - x0,
    ") + ",
    y0,
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

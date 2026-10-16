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
  v <- pz_evaluate(
    page,
    r"[
(() => {
  const host = document.getElementById('paparazzi-overlay-root');
  if (!host || !host.shadowRoot) return null;
  const layer = host.shadowRoot.querySelector('.pz-cursor');
  if (!layer) return null;
  const group = layer.firstElementChild, icon = group.firstElementChild;
  const match = /translate\((-?[\d.]+)px,\s*(-?[\d.]+)px\)/.exec(group.style.transform);
  return [
    parseFloat(icon.style.opacity || '1'),
    match ? parseFloat(match[1]) : 0,
    match ? parseFloat(match[2]) : 0,
    [...layer.querySelectorAll('.pz-icon')].find(svg => getComputedStyle(svg).visibility === 'visible')?.classList[1].slice('pz-icon-'.length) || null
  ];
})()
]"
  )
  if (is.null(v)) {
    return(NULL)
  }
  structure(unlist(v[1:3]), icon = v[[4]])
}

# Expect the overlay cursor's visible icon to settle on `icon`. During a
# recording an automatic icon flip applies at 100% of the entrance or glide
# animation, which can land a frame after the pump's grace on a loaded
# runner, so poll for the settled icon and keep the sample as the final
# assertion.
expect_cursor_icon <- function(page, icon) {
  expect_retry(
    function() {
      list(pass = identical(attr(cursor_overlay_state(page), "icon"), icon))
    },
    timeout = 2,
    loop = page$child_loop
  )
  expect_identical(attr(cursor_overlay_state(page), "icon"), icon)
}

# Count PNG pixels where `color`'s dominant RGB channel dominates by
# `margin`, for spotting the click ring in recorded frames. A
# dominance test (not per-channel distance) keeps ring pixels that have
# faded partway toward the background. Same band and x_range cropping
# as cursor_png_ink().
cursor_png_color <- function(
  page,
  path,
  color,
  band = NULL,
  dpr = page_dpr(page),
  x_range = NULL,
  margin = 40,
  min_level = 100
) {
  rgb <- as.integer(grDevices::col2rgb(color))
  dominant <- which.max(rgb) - 1L
  others <- setdiff(0:2, dominant)
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
  body <- sprintf(
    r"[
const data = c.getImageData(%s).data;
let count = 0;
for (let p = 0; p < data.length; p += 4) {
  if (data[p + 3] > 200 && data[p + %d] >= %d && data[p + %d] - Math.max(data[p + %d], data[p + %d]) >= %d) count++;
}
return count;
]",
    region,
    dominant,
    min_level,
    dominant,
    others[[1]],
    others[[2]],
    margin
  )
  as.numeric(png_canvas_eval(page, path, body))
}

cursor_overlay_scale <- function(page) {
  pz_evaluate(
    page,
    r"[parseFloat(document.getElementById('paparazzi-overlay-root').shadowRoot.querySelector('.pz-inner').style.transform.slice(6))]"
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
  w_expr <- if (is.null(x1)) "w" else x1 - x0
  body <- sprintf(
    r"[
const d = c.getImageData(%s).data;
let count = 0, sumX = 0, sumY = 0, minY = Infinity, maxY = -Infinity;
const w = img.width;
for (let p = 0; p < d.length; p += 4) {
  if (
    %s
    && d[p + 3] > 200
  ) {
    const px = (p / 4) %% %s + %s, py = Math.floor(p / 4 / %s) + %s;
    count++;
    sumX += px;
    sumY += py;
    if (py < minY) minY = py;
    if (py > maxY) maxY = py;
  }
}
if (!count) return [0, 0, 0, 0];
return [count, sumX / count / %s, sumY / count / %s, (maxY - minY + 1) / %s];
]",
    region,
    threshold,
    w_expr,
    x0,
    w_expr,
    y0,
    dpr,
    dpr,
    dpr
  )
  v <- unlist(png_canvas_eval(page, path, body))
  list(count = v[[1]], x = v[[2]], y = v[[3]], height = v[[4]])
}

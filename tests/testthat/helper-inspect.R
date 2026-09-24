inspect_fixture_file <- function() {
  test_path("fixtures", "inspect.html")
}

local_inspect_page <- function(.env = parent.frame()) {
  local_page(inspect_fixture_file(), .env = .env)
}

# Capture a pz_inspect()/print() call: the summary block (stdout,
# cat_line) into `out`, cli_inform() warnings (message conditions) into
# `msgs`, and the withVisible() result into `visible`/`value`. The box
# indirection is needed because capture.output() forces its dots in its
# own frame, so <<- there escapes to the global env.
inspect_capture <- function(code) {
  box <- new.env(parent = emptyenv())
  box$msgs <- character()
  out <- capture.output(
    withCallingHandlers(
      box$v <- withVisible(code()),
      message = function(m) {
        box$msgs <- c(box$msgs, conditionMessage(m))
        invokeRestart("muffleMessage")
      }
    )
  )
  list(out = out, msgs = box$msgs, visible = box$v$visible, value = box$v$value)
}

# Overlay state, read straight from the page: does the overlay host
# exist, how many outline boxes does its shadow root hold, and what
# inline display does the host have?
inspect_overlay_count <- function(page) {
  pz_js(
    page,
    paste0(
      "(() => { const h = document.getElementById('paparazzi-overlay-root'); ",
      "if (!h || !h.shadowRoot) return 0; ",
      "return h.shadowRoot.querySelectorAll('.pz-inspect > div').length; })()"
    )
  )
}
inspect_overlay_display <- function(page) {
  pz_js(
    page,
    paste0(
      "(() => { const h = document.getElementById('paparazzi-overlay-root'); ",
      "if (!h) return null; return h.style.display; })()"
    )
  )
}

# Count the pixels of each given color in a written PNG, by decoding it
# in the page and scanning the whole canvas (the png package isn't
# available). Tolerance is per channel, matching the pixel assertions in
# test-screenshot.R.
inspect_png_colors <- function(page, path, colors) {
  raw <- readBin(path, "raw", n = file.info(path)$size)
  b64 <- gsub("[\r\n]", "", jsonlite::base64_enc(raw))
  spec <- jsonlite::toJSON(colors, dataframe = "values")
  js <- sprintf(
    paste0(
      "(async () => {",
      "const img = new Image();",
      "img.src = 'data:image/png;base64,%s';",
      "await img.decode();",
      "const c = document.createElement('canvas').getContext('2d');",
      "c.canvas.width = img.width; c.canvas.height = img.height;",
      "c.drawImage(img, 0, 0);",
      "const d = c.getImageData(0, 0, img.width, img.height).data;",
      "const wanted = %s;",
      "return wanted.map(([r, g, b]) => {",
      "let n = 0;",
      "for (let i = 0; i < d.length; i += 4) {",
      "if (Math.abs(d[i] - r) <= 2 && Math.abs(d[i+1] - g) <= 2 && Math.abs(d[i+2] - b) <= 2) n++;",
      "}",
      "return n;",
      "});",
      "})()"
    ),
    b64,
    spec
  )
  unlist(pz_js(page, js))
}

# The outline colors, shared by the draw code and the tests.
inspect_color_scope <- c(245, 158, 11) # amber, dashed scope outlines
inspect_color_target <- c(225, 29, 72) # rose, solid target outlines + badges

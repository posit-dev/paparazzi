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

# A pz_frame() with its NULL fields resolved to built-in defaults, for
# pure-geometry tests that call frame_apply() directly.
filled_frame <- function(...) {
  frame_fill(pz_frame(...))
}

# A page with a 200x200 red square (#mid) centered in the 800x600
# viewport, for zoom-geometry tests.
local_zoom_page <- function(.env = parent.frame()) {
  html <- withr::local_tempfile(
    lines = '<!doctype html><style>html,body{margin:0}body{height:2000px}#mid{position:absolute;left:300px;top:200px;width:200px;height:200px;background:rgb(200,30,30)}</style><div id="mid"></div>',
    fileext = ".html",
    .local_envir = .env
  )
  local_page(html, width = 800, height = 600, .env = .env)
}

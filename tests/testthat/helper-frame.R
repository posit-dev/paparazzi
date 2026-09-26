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

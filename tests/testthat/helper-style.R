style_fixture_file <- function() {
  test_path("fixtures", "style.html")
}

local_style_page <- function(.env = parent.frame()) {
  local_page(style_fixture_file(), .env = .env)
}

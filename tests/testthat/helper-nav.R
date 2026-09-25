# Helpers for the device and navigation tests (nav fixtures, device
# fixture). local_page() itself lives in the shared helper-page.R.

device_fixture_file <- function() {
  test_path("fixtures", "device.html")
}

local_device_page <- function(..., .env = parent.frame()) {
  local_page(device_fixture_file(), ..., .env = .env)
}

device_zoom_fixture_file <- function() {
  test_path("fixtures", "device-zoom.html")
}

nav_fixture_url <- function(name) {
  # file_url() is internal: tests run in the package namespace, like
  # test-open.R already does.
  file_url(test_path("fixtures", paste0("nav-", name, ".html")))
}

local_nav_page <- function(.env = parent.frame()) {
  local_page(nav_fixture_url("a"), .env = .env)
}

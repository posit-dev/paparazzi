# Pages for the expectation/waits catalog (kata expectations-waits):
# state.html holds the state and content fixtures, waits.html the
# animating and navigation ones, nav-target.html the navigation landing.

state_fixture_file <- function() {
  test_path("fixtures", "state.html")
}

local_state_page <- function(.env = parent.frame()) {
  local_page(state_fixture_file(), .env = .env)
}

waits_fixture_file <- function() {
  test_path("fixtures", "waits.html")
}

local_waits_page <- function(.env = parent.frame()) {
  local_page(waits_fixture_file(), .env = .env)
}

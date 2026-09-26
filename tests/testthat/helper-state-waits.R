# Shared state and wait fixtures: state.html covers state/content;
# waits.html covers animations/navigation; nav-target.html is the landing page.

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

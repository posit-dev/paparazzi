form_fixture_file <- function() {
  test_path("fixtures", "form.html")
}

local_form_page <- function(.env = parent.frame()) {
  local_page(form_fixture_file(), .env = .env)
}

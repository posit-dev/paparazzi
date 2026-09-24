skip_if_no_chrome <- function() {
  testthat::skip_if(
    is.null(tryCatch(chromote::find_chrome(), error = function(e) NULL)),
    "Chrome not available"
  )
}

fixture_file <- function() {
  test_path("fixtures", "page.html")
}

# Open the static fixture (or another pz_open() target) and close it when the
# calling test exits.
local_page <- function(x = fixture_file(), ..., .env = parent.frame()) {
  skip_if_no_chrome()
  pz_local_page(x, ..., .env = .env)
}

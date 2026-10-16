skip_if_no_chrome <- function() {
  testthat::skip_on_cran()
  testthat::skip_if(
    is.null(tryCatch(chromote::find_chrome(), error = function(e) NULL)),
    "Chrome not available"
  )
}

fixture_file <- function() {
  test_path("fixtures", "page.html")
}

# One static server per fixture file per worker process: pz_open() on an
# .html path would otherwise start (and stop) a fresh httpuv server for
# every page. Only package fixtures and shipped examples are cached; pages
# built in per-test tempdirs keep their own short-lived servers so their
# ports are released when the page closes.
the_fixture_servers <- new.env(parent = emptyenv())

fixture_server <- function(path) {
  key <- normalizePath(path, winslash = "/", mustWork = TRUE)
  server <- mget(key, envir = the_fixture_servers, ifnotfound = list(NULL))[[1]]
  if (is.null(server)) {
    testthat::skip_if_not_installed("httpuv")
    server <- pz_serve_static(path)
    # teardown_env() only exists while testthat runs a suite; in an
    # interactive load_all() session skip the cache (the server handle's
    # finalizer is the cleanup).
    if (!testthat::is_testing()) {
      return(server)
    }
    assign(key, server, envir = the_fixture_servers)
    withr::defer(server$stop(), envir = testthat::teardown_env())
  }
  server
}

fixture_roots <- function() {
  roots <- mget("roots", envir = the_fixture_servers, ifnotfound = list(NULL))[[
    1
  ]]
  if (is.null(roots)) {
    roots <- normalizePath(
      c(test_path("fixtures"), dirname(pz_example("tasks"))),
      winslash = "/"
    )
    assign("roots", roots, envir = the_fixture_servers)
  }
  roots
}

# Route an .html fixture/example path through the cached server; pass
# everything else (handles, URLs, directories, tempfile pages) through.
as_shared_fixture <- function(x) {
  if (
    !httpuv_available() ||
      !is.character(x) ||
      length(x) != 1 ||
      dir.exists(x) ||
      !file.exists(x) ||
      !grepl("[.]html$", x, ignore.case = TRUE)
  ) {
    return(x)
  }
  dir <- normalizePath(dirname(x), winslash = "/")
  if (!dir %in% fixture_roots()) {
    return(x)
  }
  fixture_server(x)
}

elements_fixture_file <- function() {
  test_path("fixtures", "elements.html")
}

# Open the static fixture (or another pz_open() target) and close it when the
# calling test exits.
local_page <- function(x = fixture_file(), ..., .env = parent.frame()) {
  skip_if_no_chrome()
  pz_local_page(as_shared_fixture(x), ..., .env = .env)
}

local_task_page <- function(..., .env = parent.frame()) {
  skip_if_no_chrome()
  testthat::skip_if_not_installed("httpuv")
  page <- local_page(fixture_server(pz_example("tasks")), ..., .env = .env)
  testthat::expect_true(pz_evaluate(
    page,
    "Array.from(document.styleSheets).every(sheet => { void sheet.cssRules; return true; })"
  ))
  page
}

local_elements_page <- function(.env = parent.frame()) {
  local_page(elements_fixture_file(), .env = .env)
}

geometry_fixture_file <- function() {
  test_path("fixtures", "geometry.html")
}

local_geometry_page <- function(.env = parent.frame()) {
  local_page(geometry_fixture_file(), .env = .env)
}

getters_fixture_file <- function() {
  test_path("fixtures", "getters.html")
}

local_getters_page <- function(.env = parent.frame()) {
  local_page(getters_fixture_file(), .env = .env)
}

screenshot_fixture_file <- function() {
  test_path("fixtures", "screenshot.html")
}

local_screenshot_page <- function(.env = parent.frame()) {
  local_page(screenshot_fixture_file(), .env = .env)
}

# PNG pixel dimensions parsed straight from the IHDR chunk (the png
# package isn't available): the first 24 bytes are the 8-byte
# signature, the 4-byte chunk length, "IHDR" (bytes 13-16), then
# big-endian uint32 width (bytes 17-20) and height (bytes 21-24).
# Returns c(width, height) as integers.
png_dimensions <- function(path) {
  png <- readBin(path, "raw", n = 24)
  signature <- as.raw(c(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a))
  stopifnot(
    identical(png[1:8], signature),
    identical(png[13:16], charToRaw("IHDR"))
  )
  width <- readBin(png[17:20], "integer", size = 4, endian = "big")
  height <- readBin(png[21:24], "integer", size = 4, endian = "big")
  c(as.integer(width), as.integer(height))
}

actions_fixture_file <- function() {
  test_path("fixtures", "actions.html")
}

local_actions_page <- function(.env = parent.frame()) {
  local_page(actions_fixture_file(), .env = .env)
}

actionability_fixture_file <- function() {
  test_path("fixtures", "actionability.html")
}

local_actionability_page <- function(.env = parent.frame()) {
  local_page(actionability_fixture_file(), .env = .env)
}

scopes_fixture_file <- function() {
  test_path("fixtures", "scopes.html")
}

local_scopes_page <- function(.env = parent.frame()) {
  local_page(scopes_fixture_file(), .env = .env)
}

# Quarto renders in a fresh R process: load the source tree when the tests
# run from a checkout, or the installed package under R CMD check.
quarto_load_package <- function(package_root) {
  if (file.exists(file.path(package_root, "DESCRIPTION"))) {
    sprintf("pkgload::load_all(%s, quiet = TRUE)", deparse(package_root))
  } else {
    "library(paparazzi)"
  }
}

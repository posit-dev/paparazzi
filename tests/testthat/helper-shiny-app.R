skip_if_no_shiny <- function() {
  testthat::skip_if_not_installed("shiny")
  testthat::skip_if_not_installed("httpuv")
}

shiny_app_fixture_dir <- function() {
  test_path("fixtures", "shiny-app-lifecycle", "app-dir")
}

shiny_app_fixture_file <- function() {
  test_path("fixtures", "shiny-app-lifecycle", "app-file.R")
}

shiny_app_fixture_broken <- function() {
  test_path("fixtures", "shiny-app-lifecycle", "app-broken")
}

shiny_app_fixture_slow <- function() {
  test_path("fixtures", "shiny-app-lifecycle", "app-slow")
}

shiny_app_fixture_port_taken <- function() {
  test_path("fixtures", "shiny-app-lifecycle", "app-port-taken")
}

# A port nothing is listening on, found by trial bind. Used to hand
# httpuv a known-free port when a test needs to occupy one.
free_port <- function() {
  for (i in 1:100) {
    port <- sample(3000:8000, 1)
    probe <- tryCatch(serverSocket(port), error = function(e) NULL)
    if (!is.null(probe)) {
      close(probe)
      return(port)
    }
  }
  testthat::skip("no free port found")
}

# Start an app and stop it when the calling test exits.
local_shiny_app <- function(..., .env = parent.frame()) {
  skip_if_no_shiny()
  app <- pz_serve_shiny(...)
  withr::defer(app$stop(), envir = .env)
  app
}

# Loopback-connect probe matching the one pz_serve_shiny() uses for readiness;
# tests use it to observe stop/finalizer effects from the outside.
app_port_reachable <- function(port, host = "127.0.0.1") {
  con <- suppressWarnings(tryCatch(
    socketConnection(
      host = host,
      port = port,
      open = "r+",
      blocking = TRUE,
      timeout = 1
    ),
    error = function(e) NULL
  ))
  if (is.null(con)) {
    return(FALSE)
  }
  close(con)
  TRUE
}

# Poll `fn()` until it returns TRUE or `timeout` seconds pass. For
# post-condition checks (port released after stop/GC) where testthat
# can't retry on its own.
wait_until <- function(fn, timeout = 10, interval = 0.1) {
  deadline <- Sys.time() + timeout
  while (Sys.time() < deadline) {
    if (isTRUE(fn())) {
      return(TRUE)
    }
    Sys.sleep(interval)
  }
  FALSE
}

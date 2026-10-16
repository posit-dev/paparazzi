skip_if_no_py_shiny <- function() {
  testthat::skip_on_cran()
  testthat::skip_if(
    !nzchar(Sys.which("shiny")),
    "Shiny for Python CLI not available"
  )
}

# Test-side server for external app processes; paparazzi has no product API
# for serving a command yet. Starts `shiny run` on a free port, waits for
# the socket, and returns the pieces the test needs to clean up.
serve_py_shiny <- function(app_file, timeout = 15) {
  port <- random_port()
  log_file <- tempfile(pattern = "paparazzi-py-shiny-", fileext = ".log")
  process <- processx::process$new(
    unname(Sys.which("shiny")),
    args = c(
      "run",
      app_file,
      "--host",
      "127.0.0.1",
      "--port",
      as.character(port)
    ),
    stdout = log_file,
    stderr = "2>&1",
    cleanup = TRUE,
    cleanup_tree = TRUE
  )
  deadline <- Sys.time() + timeout
  repeat {
    if (!process$is_alive()) {
      cli::cli_abort(c(
        "The Shiny for Python app at {.path {app_file}} exited during startup.",
        x = paste(readLines(log_file, warn = FALSE), collapse = "\n")
      ))
    }
    if (app_port_connectable(port)) {
      break
    }
    if (Sys.time() >= deadline) {
      process$kill()
      cli::cli_abort(
        "The Shiny for Python app at {.path {app_file}} did not start listening within {timeout} seconds."
      )
    }
    Sys.sleep(0.05)
  }
  list(
    process = process,
    url = sprintf("http://127.0.0.1:%d/", port),
    log_file = log_file
  )
}

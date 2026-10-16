skip_if_no_py_shiny <- function() {
  testthat::skip_on_cran()
  testthat::skip_if(
    !nzchar(Sys.which("shiny")),
    "Shiny for Python CLI not available"
  )
}

# Serves a Shiny for Python app with the `shiny` CLI. wait = "shiny" makes
# pz_open(wait = "auto") wait for Shiny idle on the handle's pages.
serve_py_shiny <- function(app_file, timeout = 15) {
  pz_serve_command(
    unname(Sys.which("shiny")),
    c("run", app_file, "--host", "127.0.0.1", "--port", "{port}"),
    wait = "shiny",
    timeout = timeout
  )
}

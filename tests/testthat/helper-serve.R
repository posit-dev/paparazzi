skip_if_no_quarto <- function() {
  testthat::skip_on_cran()
  testthat::skip_if(
    is.null(tryCatch(quarto_cli(), error = function(e) NULL)),
    "Quarto CLI not available"
  )
}

skip_if_no_command_server <- function() {
  testthat::skip_on_cran()
  testthat::skip_if_not_installed("httpuv")
}

# A blocking httpuv server run as an external command. The args leave
# {port} for pz_serve_command() to substitute; the body reports the
# COMMAND_PORT environment variable so tests can check substitution in
# envvars as well as in args.
command_server <- function(..., envvars = NULL) {
  pz_serve_command(
    file.path(R.home("bin"), "Rscript"),
    c(
      "-e",
      paste0(
        "httpuv::runServer('127.0.0.1', {port}, list(call = function(req) ",
        "list(status = 200L, headers = list('Content-Type' = 'text/html'), ",
        "body = paste0('command served on ', Sys.getenv('COMMAND_PORT')))))"
      )
    ),
    ...,
    envvars = envvars
  )
}

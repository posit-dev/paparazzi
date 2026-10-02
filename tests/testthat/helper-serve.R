skip_if_no_quarto <- function() {
  testthat::skip_on_cran()
  testthat::skip_if(
    is.null(tryCatch(quarto_cli(), error = function(e) NULL)),
    "Quarto CLI not available"
  )
}

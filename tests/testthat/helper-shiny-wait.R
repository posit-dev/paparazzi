local_shiny_idle_spy <- function(.env = parent.frame()) {
  calls <- new.env(parent = emptyenv())
  calls$urls <- character()
  wait_for_idle <- pz_wait_for_shiny_idle
  testthat::local_mocked_bindings(
    pz_wait_for_shiny_idle = function(ctx, ...) {
      calls$urls <- c(calls$urls, pz_get_url(ctx))
      wait_for_idle(ctx, ...)
    },
    .package = "paparazzi",
    .env = .env
  )
  calls
}

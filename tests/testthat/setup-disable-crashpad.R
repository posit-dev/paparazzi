if (
  isTRUE(as.logical(Sys.getenv("CI"))) ||
    !identical(Sys.getenv("NOT_CRAN"), "true")
) {
  .chrome_args_before_tests <- chromote::get_chrome_args()
  chromote::set_chrome_args(unique(c(
    "--disable-crash-reporter",
    .chrome_args_before_tests
  )))
  withr::defer(
    chromote::set_chrome_args(.chrome_args_before_tests),
    envir = testthat::teardown_env()
  )
}

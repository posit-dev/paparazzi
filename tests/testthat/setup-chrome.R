# Chrome deletes its default headless profile (a scoped_dir* under the
# user's Chrome-headless directory) only on a graceful Browser.close, never on
# SIGTERM or SIGKILL, so any worker that exits without one leaks it forever. A
# profile inside tempdir() is removed with the R session instead, and closes
# ~10x faster, well within testthat's one-second parallel teardown grace.
old_chrome_args <- chromote::get_chrome_args()
chrome_profile <- file.path(tempdir(), "chrome-profile")
chromote::set_chrome_args(
  c(old_chrome_args, paste0("--user-data-dir=", chrome_profile))
)

withr::defer(
  {
    if (chromote::has_default_chromote_object()) {
      try(chromote::default_chromote_object()$close(), silent = TRUE)
    }
    chromote::set_chrome_args(old_chrome_args)
    unlink(chrome_profile, recursive = TRUE)
  },
  envir = testthat::teardown_env()
)

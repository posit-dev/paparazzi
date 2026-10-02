withr::defer(
  {
    if (chromote::has_default_chromote_object()) {
      try(chromote::default_chromote_object()$close(), silent = TRUE)
    }
    gc()
    unlink(file.path(tempdir(), "Crashpad"), recursive = TRUE)
  },
  envir = testthat::teardown_env()
)

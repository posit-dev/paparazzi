# Active only when tests run as they would on CRAN (NOT_CRAN != "true").
# Browser and system-tool tests must skip on CRAN (see skip_if_no_chrome(),
# skip_if_no_quarto(), and friends); this file turns a missed skip into a
# loud failure. find_chrome() trusts CHROMOTE_CHROME verbatim and quarto_cli()
# requires QUARTO_PATH to exist, so pointing both at paths that do not exist
# makes any launch attempt error inside the offending test. The teardown
# sweep then fails the whole run if Chrome or Quarto still left a trace.
if (!identical(Sys.getenv("NOT_CRAN"), "true")) {
  .pz_guard_root <- file.path(tempdir(), "paparazzi-cran-guard")
  withr::local_envvar(
    .local_envir = testthat::teardown_env(),
    CHROMOTE_CHROME = file.path(.pz_guard_root, "chrome"),
    QUARTO_PATH = file.path(.pz_guard_root, "quarto")
  )
  withr::defer(
    {
      if (chromote::has_default_chromote_object()) {
        cli::cli_abort(c(
          "Chrome was launched while tests were running as on CRAN.",
          i = "Browser tests must skip on CRAN; see {.fn skip_if_no_chrome}."
        ))
      }
      detritus <- unlist(lapply(
        c(tempdir(), file.path(tempdir(), "paparazzi-subprocess")),
        list.files,
        pattern = "^(com\\.google\\.Chrome|quarto-session|Crashpad)",
        include.dirs = TRUE
      ))
      if (length(detritus)) {
        cli::cli_abort(c(
          "Tests running as on CRAN left temp-directory detritus.",
          x = "Found: {.val {detritus}}"
        ))
      }
    },
    envir = testthat::teardown_env()
  )
}

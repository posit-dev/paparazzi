# Active only when tests run as they would on CRAN (NOT_CRAN != "true").
# Browser and system-tool tests must skip on CRAN (see skip_if_no_chrome(),
# skip_if_no_quarto(), and friends); this file turns a missed skip into a
# loud failure. find_chrome() trusts CHROMOTE_CHROME verbatim and quarto_cli()
# requires QUARTO_PATH to exist, so pointing both at paths that do not exist
# makes any launch attempt error inside the offending test. Combined with
# has_default_chromote_object(), that is the whole guard: a launch either
# fails in place or is detected after the fact, so no detritus sweep is
# needed (one scoped to tempdir() could not see the check-level TMPDIR that
# R CMD check flags, and a wider scan risks flagging unrelated files).
if (!identical(Sys.getenv("NOT_CRAN"), "true")) {
  .pz_guard_root <- file.path(tempdir(), "paparazzi-cran-guard")
  withr::local_envvar(
    .local_envir = testthat::teardown_env(),
    CHROMOTE_CHROME = file.path(.pz_guard_root, "chrome"),
    QUARTO_PATH = file.path(.pz_guard_root, "quarto")
  )
  withr::defer(
    if (chromote::has_default_chromote_object()) {
      cli::cli_abort(c(
        "Chrome was launched while tests were running as on CRAN.",
        i = "Browser tests must skip on CRAN; see {.fn skip_if_no_chrome}."
      ))
    },
    envir = testthat::teardown_env()
  )
}

# Route temp usage of subprocesses (Chrome, Quarto, child R sessions) into a
# directory this test session owns, and remove it when tests finish. R CMD
# check --as-cran flags anything external tools leave directly in TMPDIR
# ("detritus in the temp directory"). R's own tempdir() is fixed at process
# startup, so this redirect only affects processes launched by the tests.
# This file sorts first so its teardown runs last: the browser-close defer in
# setup-chrome.R must run before this directory is removed.
.pz_subprocess_tmp <- file.path(tempdir(), "paparazzi-subprocess")
dir.create(.pz_subprocess_tmp)
withr::local_envvar(
  .local_envir = testthat::teardown_env(),
  TMPDIR = .pz_subprocess_tmp,
  TEMP = .pz_subprocess_tmp,
  TMP = .pz_subprocess_tmp
)
withr::defer(
  unlink(.pz_subprocess_tmp, recursive = TRUE, force = TRUE),
  envir = testthat::teardown_env()
)

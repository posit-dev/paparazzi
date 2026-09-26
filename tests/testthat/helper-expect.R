# Inside testthat, the bridge routes failures through testthat::expect() so
# they register as test failures. These tests override the env var(s)
# testthat::is_testing() consults to exercise the outside-tests path,
# where the same calls abort with the classed error instead. The set is
# immediate and the restore is deferred on the caller, because
# withr::local_envvar()'s envir argument was renamed in withr 3 and a
# helper-wrapped call would otherwise restore when the helper returns.
local_outside_testthat <- function(env = parent.frame()) {
  old <- Sys.getenv(c("TESTTHAT", "TESTTHAT_IS_TESTING"))
  Sys.setenv(TESTTHAT = "", TESTTHAT_IS_TESTING = "")
  withr::defer(do.call(Sys.setenv, as.list(old)), envir = env)
}

test_that("cdp_call maps only timeout errors and retains the cause", {
  cause <- simpleError("Command TIMED OUT waiting for Chrome")
  err <- tryCatch(
    cdp_call(stop(cause), 0.5, "reading elements matching {button}"),
    error = identity
  )
  expect_s3_class(err, "paparazzi_error_timeout")
  expect_match(conditionMessage(err), "0.5s reading elements matching {button}", fixed = TRUE)
  expect_identical(err$parent, cause)

  other <- simpleError("connection closed")
  expect_identical(tryCatch(cdp_call(stop(other), 1, "reading"), error = identity), other)
})

test_that("cdp_check_exception returns responses invisibly without exceptions", {
  res <- list(result = list(value = 3))
  expect_identical(withVisible(cdp_check_exception(res)), list(value = res, visible = FALSE))
})

test_that("cdp_check_exception reports JavaScript errors with and without context", {
  res <- list(exceptionDetails = list(exception = list(description = "boom")))
  expect_snapshot(error = TRUE, cdp_check_exception(res, "validating CSS"))
  expect_snapshot(error = TRUE, cdp_check_exception(res))

  fallback <- list(exceptionDetails = list(text = "from text"))
  expect_error(cdp_check_exception(fallback), "JavaScript error: from text.", fixed = TRUE)
  unknown <- list(exceptionDetails = list())
  expect_error(cdp_check_exception(unknown, "reading"), "JavaScript error reading: unknown error.", fixed = TRUE)
})

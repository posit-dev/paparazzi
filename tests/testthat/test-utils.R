test_that("cdp_call maps only timeout errors and retains the cause", {
  cause <- simpleError("Command TIMED OUT waiting for Chrome")
  err <- tryCatch(
    cdp_call(stop(cause), 0.5, "reading elements matching {button}"),
    error = identity
  )
  expect_s3_class(err, "paparazzi_error_timeout")
  expect_match(
    conditionMessage(err),
    "0.5s reading elements matching {button}",
    fixed = TRUE
  )
  expect_identical(err$parent, cause)

  other <- simpleError("connection closed")
  expect_identical(
    tryCatch(cdp_call(stop(other), 1, "reading"), error = identity),
    other
  )
})

test_that("cdp_check_exception returns responses invisibly without exceptions", {
  res <- list(result = list(value = 3))
  expect_identical(
    withVisible(cdp_check_exception(res)),
    list(value = res, visible = FALSE)
  )
})

test_that("cdp_check_exception reports JavaScript errors with and without context", {
  res <- list(exceptionDetails = list(exception = list(description = "boom")))
  expect_snapshot(error = TRUE, cdp_check_exception(res, "validating CSS"))
  expect_snapshot(error = TRUE, cdp_check_exception(res))

  fallback <- list(exceptionDetails = list(text = "from text"))
  expect_error(
    cdp_check_exception(fallback),
    "JavaScript error: from text.",
    fixed = TRUE
  )
  unknown <- list(exceptionDetails = list())
  expect_error(
    cdp_check_exception(unknown, "reading"),
    "JavaScript error reading: unknown error.",
    fixed = TRUE
  )
})

test_that("js_literal returns escaped JSON as JavaScript source text", {
  value <- "quote: \" and '; slash: /; backslash: \\; newline:\nUnicode: café ☃"
  literal <- js_literal(value)

  expect_type(literal, "character")
  expect_length(literal, 1)
  expect_identical(jsonlite::fromJSON(literal), value)
})

test_that("js_literal preserves unboxing, array shape, and JSON options", {
  expect_identical(js_literal("one"), '"one"')
  expect_identical(js_literal("one", auto_unbox = FALSE), '["one"]')
  expect_identical(js_literal(character(), auto_unbox = FALSE), "[]")
  expect_identical(
    jsonlite::fromJSON(
      js_literal("one", auto_unbox = FALSE),
      simplifyVector = FALSE
    ),
    list("one")
  )
  expect_identical(
    jsonlite::fromJSON(
      js_literal(character(), auto_unbox = FALSE),
      simplifyVector = FALSE
    ),
    list()
  )
  expect_identical(js_literal(NULL, null = "null"), "null")
  expect_identical(js_literal(NA_character_), "null")
  expect_identical(js_literal(1.23456789, digits = NA), "1.23456789")
})

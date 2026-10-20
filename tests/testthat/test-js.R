test_that("pz_js wraps source without executing it or opening Chrome", {
  source <- "el => el.querySelector('.status') !== null"
  js <- pz_js(source)
  expect_s3_class(js, "paparazzi_js")
  expect_identical(js$source, source)
  expect_identical(pz_js("[")$source, "[")
  expect_identical(
    capture.output(out <- print(js)),
    paste0("<paparazzi_js> ", format_js(js))
  )
  expect_identical(out, js)
})

test_that("pz_js validates a single source string", {
  expect_error(pz_js(function(el) TRUE), "source")
  expect_error(pz_js(NA_character_), "source")
  expect_error(pz_js(c("a", "b")), "source")
  expect_error(pz_js("el => true", extra = TRUE), "unused argument")
})

test_that("pz_evaluate evaluates JS and returns values", {
  page <- local_page()
  expect_identical(pz_evaluate(page, "1 + 1"), 2L)
  expect_identical(pz_evaluate(page, "'a' + 'b'"), "ab")
  expect_equal(
    pz_evaluate(page, "({x: 1, y: [2, 3]})"),
    list(x = 1, y = list(2, 3))
  )
})

test_that("pz_evaluate awaits promises by default", {
  page <- local_page()
  expect_identical(pz_evaluate(page, "Promise.resolve(42)"), 42L)
})

test_that("pz_evaluate(await = FALSE) does not await", {
  page <- local_page()
  res <- pz_evaluate(page, "Promise.resolve(42)", await = FALSE)
  expect_false(identical(res, 42L))
})

test_that("pz_evaluate timeout errors are attributed to pz_evaluate", {
  page <- local_page()
  err <- tryCatch(
    pz_evaluate(
      page,
      "new Promise(r => setTimeout(() => r(1), 2000))",
      timeout = 0.2
    ),
    error = function(e) e
  )
  expect_s3_class(err, "paparazzi_error_timeout")
  expect_true(is_call(conditionCall(err), "pz_evaluate"))
})

test_that("pz_evaluate aborts on JS errors", {
  page <- local_page()
  expect_error(
    pz_evaluate(page, "throw new Error('boom')"),
    regexp = "boom",
    class = "paparazzi_error_js"
  )
})

test_that("pz_evaluate ends the chain (returns value, not ctx)", {
  page <- local_page()
  res <- page |> pz_evaluate("2")
  expect_identical(res, 2L)
})

test_that("pz_evaluate checks dots empty", {
  page <- local_page()
  expect_error(pz_evaluate(page, "1", extra = TRUE), "empty")
})

test_that("pz_evaluate respects the per-call timeout", {
  page <- local_page()
  expect_error(
    pz_evaluate(
      page,
      "new Promise(r => setTimeout(() => r(1), 2000))",
      timeout = 0.2
    ),
    class = "paparazzi_error_timeout"
  )
})

test_that("pz_evaluate uses the session default timeout", {
  page <- local_page(timeout = 15)
  expect_identical(
    pz_evaluate(page, "new Promise(r => setTimeout(() => r(42), 500))"),
    42L
  )

  page_short <- local_page()
  page_short$default_timeout <- 0.2
  expect_error(
    pz_evaluate(page_short, "new Promise(r => setTimeout(() => r(1), 2000))"),
    class = "paparazzi_error_timeout"
  )
})

test_that("pz_evaluate maps unserializable values", {
  page <- local_page()
  expect_identical(pz_evaluate(page, "1/0"), Inf)
  expect_identical(pz_evaluate(page, "-1/0"), -Inf)
  expect_true(is.nan(pz_evaluate(page, "0/0")))
  expect_identical(1 / pz_evaluate(page, "-0"), -Inf)
  expect_identical(pz_evaluate(page, "undefined"), NULL)
})

test_that("pz_evaluate reports thrown non-Error values", {
  page <- local_page()
  expect_error(
    pz_evaluate(page, "throw 'boom'"),
    "boom",
    class = "paparazzi_error_js"
  )
  expect_error(
    pz_evaluate(page, "Promise.reject('nope')"),
    "nope",
    class = "paparazzi_error_js"
  )
})

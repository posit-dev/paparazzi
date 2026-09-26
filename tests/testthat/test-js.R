test_that("pz_js evaluates JS and returns values", {
  page <- local_page()
  expect_identical(pz_js(page, "1 + 1"), 2L)
  expect_identical(pz_js(page, "'a' + 'b'"), "ab")
  expect_equal(pz_js(page, "({x: 1, y: [2, 3]})"), list(x = 1, y = list(2, 3)))
})

test_that("pz_js awaits promises by default", {
  page <- local_page()
  expect_identical(pz_js(page, "Promise.resolve(42)"), 42L)
})

test_that("pz_js(await = FALSE) does not await", {
  page <- local_page()
  res <- pz_js(page, "Promise.resolve(42)", await = FALSE)
  expect_false(identical(res, 42L))
})

test_that("pz_js timeout errors are attributed to pz_js", {
  page <- local_page()
  err <- tryCatch(
    pz_js(
      page,
      "new Promise(r => setTimeout(() => r(1), 2000))",
      timeout = 0.2
    ),
    error = function(e) e
  )
  expect_s3_class(err, "paparazzi_error_timeout")
  expect_true(is_call(conditionCall(err), "pz_js"))
})

test_that("pz_js aborts on JS errors", {
  page <- local_page()
  expect_error(
    pz_js(page, "throw new Error('boom')"),
    regexp = "boom",
    class = "paparazzi_error_js"
  )
})

test_that("pz_js ends the chain (returns value, not ctx)", {
  page <- local_page()
  res <- page |> pz_js("2")
  expect_identical(res, 2L)
})

test_that("pz_js checks dots empty", {
  page <- local_page()
  expect_error(pz_js(page, "1", extra = TRUE), "empty")
})

test_that("pz_js respects the per-call timeout", {
  page <- local_page()
  expect_error(
    pz_js(
      page,
      "new Promise(r => setTimeout(() => r(1), 2000))",
      timeout = 0.2
    ),
    class = "paparazzi_error_timeout"
  )
})

test_that("pz_js uses the session default timeout", {
  page <- local_page(timeout = 15)
  expect_identical(
    pz_js(page, "new Promise(r => setTimeout(() => r(42), 500))"),
    42L
  )

  page_short <- local_page()
  page_short$default_timeout <- 0.2
  expect_error(
    pz_js(page_short, "new Promise(r => setTimeout(() => r(1), 2000))"),
    class = "paparazzi_error_timeout"
  )
})

test_that("pz_js maps unserializable values", {
  page <- local_page()
  expect_identical(pz_js(page, "1/0"), Inf)
  expect_identical(pz_js(page, "-1/0"), -Inf)
  expect_true(is.nan(pz_js(page, "0/0")))
  expect_identical(1 / pz_js(page, "-0"), -Inf)
  expect_identical(pz_js(page, "undefined"), NULL)
})

test_that("pz_js reports thrown non-Error values", {
  page <- local_page()
  expect_error(
    pz_js(page, "throw 'boom'"),
    "boom",
    class = "paparazzi_error_js"
  )
  expect_error(
    pz_js(page, "Promise.reject('nope')"),
    "nope",
    class = "paparazzi_error_js"
  )
})

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

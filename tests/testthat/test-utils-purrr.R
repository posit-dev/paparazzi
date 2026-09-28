# Vendored from rlang standalone-purrr.R: behavior is upstream's concern, so
# only smoke-test that the vendoring resolved and basic dispatch works.
test_that("vendored purrr helpers smoke test", {
  expect_identical(map_chr(c("a", "b"), identity), c("a", "b"))
  expect_identical(map_lgl(1:3, ~ .x > 2), c(FALSE, FALSE, TRUE))
  expect_identical(
    imap(list(a = 1), function(x, y) paste0(y, x)),
    list(a = "a1")
  )
  expect_true(every(1:3, ~ .x > 0))
  expect_false(some(1:3, ~ .x > 5))
})

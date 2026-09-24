test_that("check_character passes valid input invisibly", {
  expect_invisible(check_character("a"))
  expect_invisible(check_character(c("a", "b")))
  expect_invisible(check_character(character(), min = 0))
  expect_invisible(check_character(NULL, allow_null = TRUE))
})

test_that("check_character aborts on wrong type", {
  expect_error(check_character(1), "must be a character vector")
  expect_error(check_character(NULL), "must be a character vector")
})

test_that("check_character aborts on too-short input", {
  expect_error(
    check_character(character()),
    "must have at least 1 element"
  )
  expect_error(
    check_character(character(), arg = "key"),
    "must have at least 1 element"
  )
})

test_that("check_character aborts on NA", {
  expect_error(check_character(NA_character_), "can't be `NA`")
  expect_error(check_character(c("a", NA)), "can't be `NA`")
})

test_that("is_pz_page identifies pages", {
  expect_true(is_pz_page(structure(list(), class = "PaparazziPage")))
  expect_false(is_pz_page("page"))
  expect_false(is_pz_page(NULL))
})

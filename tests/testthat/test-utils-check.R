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

test_that("annotation label, text, id, and font size checkers retain contracts", {
  expect_null(check_annotation_label(NULL))
  expect_true(check_annotation_label(TRUE))
  expect_identical(check_annotation_label(7), "7")
  expect_identical(check_annotation_label(""), "")
  for (bad in list(FALSE, NA, NA_character_, c("a", "b"), list("a"))) {
    expect_error(check_annotation_label(bad), "label")
  }
  expect_invisible(check_annotation_text(" "))
  expect_error(check_annotation_text(""), "text.*empty string")
  expect_invisible(check_annotation_id(NULL))
  expect_error(check_annotation_id("spotlight"), "reserved|cannot be")
  expect_error(check_annotation_id("caption"), "cannot be")
  expect_invisible(check_annotation_id("caption", allow_reserved = TRUE))
  expect_invisible(check_annotation_id("spotlight", allow_reserved = TRUE))
  expect_error(check_annotation_id("", allow_reserved = TRUE), "id.*nonempty")
  expect_invisible(check_annotation_font_size(14))
  expect_error(
    check_annotation_font_size(0, arg = "font_size"),
    "font_size.*greater than 0"
  )
})

test_that("is_pz_page identifies pages", {
  expect_true(is_pz_page(structure(list(), class = "PaparazziPage")))
  expect_false(is_pz_page("page"))
  expect_false(is_pz_page(NULL))
})

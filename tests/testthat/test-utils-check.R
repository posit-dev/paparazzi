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

test_that("annotation label and id checkers retain contracts", {
  expect_null(check_annotation_label(NULL))
  expect_true(check_annotation_label(TRUE))
  expect_identical(check_annotation_label(7), "7")
  expect_identical(check_annotation_label(""), "")
  for (bad in list(FALSE, NA, NA_character_, c("a", "b"), list("a"))) {
    expect_error(check_annotation_label(bad), "label")
  }
  expect_invisible(check_annotation_id(NULL))
  expect_error(check_annotation_id("spotlight"), "reserved|cannot be")
  expect_error(check_annotation_id("caption"), "cannot be")
  expect_invisible(check_annotation_id("caption", allow_reserved = TRUE))
  expect_invisible(check_annotation_id("spotlight", allow_reserved = TRUE))
  expect_error(check_annotation_id("", allow_reserved = TRUE), "empty string")
  expect_error(check_annotation_id(""), "empty string")
})

test_that("positive CSS pixels retain their value invisibly", {
  expect_identical(
    withVisible(check_positive_css_px(14L)),
    list(value = 14L, visible = FALSE)
  )
  expect_identical(
    withVisible(check_positive_css_px(0.5)),
    list(value = 0.5, visible = FALSE)
  )
})

test_that("positive CSS pixels reject non-positive, missing, or non-scalar values", {
  for (bad in list(
    0,
    -1,
    Inf,
    -Inf,
    NA_real_,
    NaN,
    NULL,
    numeric(),
    c(1, 2),
    TRUE,
    "14"
  )) {
    expect_error(
      check_positive_css_px(bad, arg = "font_size"),
      "font_size",
      class = "rlang_error"
    )
  }
})

test_that("positive CSS pixel errors retain caller argument and call", {
  validate_font_size <- function(font_size) check_positive_css_px(font_size)
  error <- expect_error(
    validate_font_size(0),
    "font_size.*greater than 0",
    class = "rlang_error"
  )
  expect_identical(conditionCall(error), quote(validate_font_size(0)))

  call <- quote(pz_annotate_caption(page, font_size = 0))
  error <- expect_error(
    check_positive_css_px(0, arg = "font_size", call = call),
    "font_size.*greater than 0",
    class = "rlang_error"
  )
  expect_identical(conditionCall(error), call)
})

test_that("is_pz_page identifies pages", {
  expect_true(is_pz_page(structure(list(), class = "PaparazziPage")))
  expect_false(is_pz_page("page"))
  expect_false(is_pz_page(NULL))
})

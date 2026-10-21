test_that("regex values preserve source and construct without a browser", {
  source <- "  ^{quoted} \\d+ `雪`  $"
  regex <- pz_regex(source, ignore_case = TRUE)
  expect_s3_class(regex, "paparazzi_regex")
  expect_identical(regex$pattern, source)
  expect_true(regex$ignore_case)
  expect_false(regex$fixed)
  expect_identical(pz_regex("")$pattern, "")
  expect_identical(pz_regex("[")$pattern, "[")
  literal <- pz_regex("  C++ [preview]  ", fixed = TRUE)
  expect_identical(literal$pattern, "  C++ [preview]  ")
  expect_true(literal$fixed)
})

test_that("regex values validate scalar inputs and boolean options", {
  expect_error(pz_regex(NA_character_), "pattern")
  expect_error(pz_regex(c("a", "b")), "pattern")
  expect_error(pz_regex(1), "pattern")
  expect_error(pz_regex("a", ignore_case = NA), "ignore_case")
  expect_error(pz_regex("a", ignore_case = c(TRUE, FALSE)), "ignore_case")
  expect_error(pz_regex("a", ignore_case = "yes"), "ignore_case")
  expect_error(pz_regex("a", fixed = NA), "fixed")
  expect_error(pz_regex("a", fixed = c(TRUE, FALSE)), "fixed")
  expect_error(pz_regex("a", fixed = 1), "fixed")
})

test_that("regex values reject old flags and unsupported mode switches", {
  expect_error(pz_regex("a", "i"), "empty")
  expect_error(pz_regex("a", flags = "i"), "empty")
  expect_error(pz_regex("a", unicode = FALSE), "empty")
  expect_error(pz_regex("a", multiline = TRUE), "empty")
  expect_error(pz_regex("a", dot_all = TRUE), "empty")
  expect_error(pz_regex("a", raw = TRUE), "empty")
})

test_that("regex printing quotes source and names non-default options", {
  regex <- pz_regex('^"save"\\d+$', ignore_case = TRUE, fixed = TRUE)
  printed <- capture.output(out <- print(regex))
  expect_identical(out, regex)
  expect_identical(
    printed,
    '<paparazzi_regex> pz_regex("^\\"save\\"\\\\d+$", ignore_case = TRUE, fixed = TRUE)'
  )
  expect_identical(format_regex(pz_regex("Save")), 'pz_regex("Save")')
})

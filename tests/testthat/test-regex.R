test_that("regex values preserve source and construct without a browser", {
  source <- "  ^{quoted} \\d+ `雪`  $"
  regex <- pz_regex(source, "ims")
  expect_s3_class(regex, "paparazzi_regex")
  expect_identical(regex$pattern, source)
  expect_identical(regex$flags, "ims")
  expect_identical(pz_regex("")$pattern, "")
  expect_identical(pz_regex("[")$pattern, "[")
  expect_identical(pz_regex("x", "v")$flags, "v")
})

test_that("regex values validate scalar inputs and flag policy", {
  expect_error(pz_regex(NA_character_), "pattern")
  expect_error(pz_regex(c("a", "b")), "pattern")
  expect_error(pz_regex(1), "pattern")
  expect_error(pz_regex("a", NA_character_), "flags")
  expect_error(pz_regex("a", c("i", "m")), "flags")
  expect_error(pz_regex("a", "g"), "stateful")
  expect_error(pz_regex("a", "y"), "stateful")
  expect_error(pz_regex("a", "ii"), "duplicate")
  expect_error(pz_regex("a", "uv"), "combine")
  expect_error(pz_regex("a", "q"), "flags")
  expect_error(pz_regex("a", "I"), "flags")
})

test_that("regex printing quotes source and flags without changing the value", {
  regex <- pz_regex('^"save"\\d+$', "i")
  printed <- capture.output(out <- print(regex))
  expect_identical(out, regex)
  expect_identical(
    printed,
    '<paparazzi_regex> pz_regex("^\\"save\\"\\\\d+$", flags = "i")'
  )
})

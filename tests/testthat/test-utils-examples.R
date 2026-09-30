test_that("examples_run is false when not interactive", {
  rlang::local_interactive(FALSE)
  expect_false(examples_run())
})

test_that("examples_run requires Chrome and every named package", {
  rlang::local_interactive(TRUE)
  local_mocked_bindings(
    find_chrome = function() "/path/to/chrome",
    .package = "chromote"
  )
  expect_true(examples_run())
  expect_true(examples_run("rlang"))
  expect_false(examples_run("rlang", "paparazzi_package_that_does_not_exist"))

  local_mocked_bindings(find_chrome = function() NULL, .package = "chromote")
  expect_false(examples_run())
})

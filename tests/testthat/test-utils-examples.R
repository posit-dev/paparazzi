test_that("examples_run is false when not interactive", {
  rlang::local_interactive(FALSE)
  expect_false(examples_run())
})

test_that("examples_run is false for an uninstalled package when interactive", {
  rlang::local_interactive(TRUE)
  expect_false(examples_run("paparazzi_package_that_does_not_exist"))
})

test_that("examples_run is true when interactive and Chrome is available", {
  skip_if(is.null(suppressMessages(chromote::find_chrome())))
  rlang::local_interactive(TRUE)
  expect_true(examples_run())
})

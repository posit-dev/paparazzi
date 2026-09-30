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

test_that("site examples opt in to pkgdown and still require Chrome and packages", {
  skip_if_not_installed("pkgdown")
  rlang::local_interactive(FALSE)
  local_mocked_bindings(in_pkgdown = function() TRUE, .package = "pkgdown")
  local_mocked_bindings(
    find_chrome = function() "/path/to/chrome",
    .package = "chromote"
  )

  expect_false(examples_run())
  expect_true(examples_run(site = TRUE))
  expect_true(examples_run("rlang", site = TRUE))
  expect_false(examples_run(
    "paparazzi_package_that_does_not_exist",
    site = TRUE
  ))

  local_mocked_bindings(find_chrome = function() NULL, .package = "chromote")
  expect_false(examples_run(site = TRUE))
})

test_that("site opt-in does not run examples outside pkgdown", {
  skip_if_not_installed("pkgdown")
  rlang::local_interactive(FALSE)
  local_mocked_bindings(in_pkgdown = function() FALSE, .package = "pkgdown")
  expect_false(examples_run(site = TRUE))
})

test_that("pkgdown is optional and not checked for interactive examples", {
  rlang::local_interactive(FALSE)
  local_mocked_bindings(is_installed = function(...) FALSE, .package = "rlang")
  expect_false(in_pkgdown())
  expect_false(examples_run(site = TRUE))

  rlang::local_interactive(TRUE)
  local_mocked_bindings(in_pkgdown = function() stop("Must not be called"))
  local_mocked_bindings(
    find_chrome = function() "/path/to/chrome",
    .package = "chromote"
  )
  expect_true(examples_run())
  expect_true(examples_run(site = TRUE))
})

test_that("site must be a single boolean", {
  expect_error(examples_run(site = NA), "site")
  expect_error(examples_run(site = "yes"), "site")
})

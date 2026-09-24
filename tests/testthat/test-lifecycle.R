test_that("pz_with_page returns the page invisibly and closes it", {
  skip_if_no_chrome()
  res <- withVisible(pz_with_page(fixture_file(), function(page) {
    expect_false(page$is_closed())
    1 + 1
  }))
  expect_false(res$visible)
  expect_s3_class(res$value, "PaparazziPage")
  expect_true(res$value$is_closed())
})

test_that("pz_with_page closes even when the block errors", {
  skip_if_no_chrome()
  captured <- NULL
  expect_error(
    pz_with_page(fixture_file(), function(page) {
      captured <<- page
      stop("boom")
    }),
    "boom"
  )
  expect_true(captured$is_closed())
})

test_that("pz_with_page evaluates plain expressions", {
  skip_if_no_chrome()
  ran <- FALSE
  pz_with_page(fixture_file(), {
    ran <- TRUE
  })
  expect_true(ran)
})

test_that("pz_with_page accepts an already-open page and closes it", {
  skip_if_no_chrome()
  page <- pz_open(fixture_file())
  pz_with_page(page, {
    expect_false(page$is_closed())
  })
  expect_true(page$is_closed())
})

test_that("pz_local_page closes when the calling frame exits", {
  skip_if_no_chrome()
  page <- local({
    p <- pz_local_page(fixture_file())
    expect_false(p$is_closed())
    p
  })
  expect_true(page$is_closed())
})

test_that("pz_local_page accepts an already-open page and closes it", {
  skip_if_no_chrome()
  page <- pz_open(fixture_file())
  local(pz_local_page(page))
  expect_true(page$is_closed())
})

test_that("pz_local_page forwards ... to pz_open", {
  skip_if_no_chrome()
  page <- local(pz_local_page(fixture_file(), timeout = 7))
  expect_equal(page$default_timeout, 7)
  expect_true(page$is_closed())
})

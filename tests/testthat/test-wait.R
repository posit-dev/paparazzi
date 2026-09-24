test_that("pz_wait pauses and returns ctx invisibly", {
  page <- local_page()
  start <- Sys.time()
  res <- withVisible(pz_wait(page, 0.3))
  elapsed <- as.numeric(difftime(Sys.time(), start, units = "secs"))

  expect_gte(elapsed, 0.25)
  expect_false(res$visible)
  expect_identical(res$value, page)
})

test_that("pz_wait pumps the child loop so timers fire during waits", {
  page <- local_page()
  fired <- FALSE
  later::later(function() fired <<- TRUE, delay = 0.1, loop = page$child_loop)
  pz_wait(page, 0.5)
  expect_true(fired)
})

test_that("pz_poll times out with a classed error", {
  page <- local_page()
  err <- expect_error(
    pz_poll(
      function() FALSE,
      timeout = 0.2,
      loop = page$child_loop,
      what = "never"
    ),
    class = "paparazzi_error_timeout"
  )
  # `what` is interpolated as plain text, not wrapped in {.val}.
  expect_match(
    conditionMessage(err),
    "Timed out after 0.2s waiting for never.",
    fixed = TRUE
  )
})

test_that("pz_poll returns as soon as the condition holds", {
  page <- local_page()
  n <- 0
  start <- Sys.time()
  pz_poll(
    function() {
      n <<- n + 1
      n >= 2
    },
    timeout = 5,
    loop = page$child_loop
  )
  expect_lt(as.numeric(difftime(Sys.time(), start, units = "secs")), 2)
})

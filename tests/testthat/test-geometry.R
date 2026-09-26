test_that("el_rects returns one row per element with CSS-pixel geometry", {
  page <- local_geometry_page()
  els <- loc_resolve(page, ".box", multiple = "all")
  withr::defer(release_elements(els))

  rects <- el_rects(els)
  expect_s3_class(rects, "tbl_df")
  expect_identical(nrow(rects), 2L)
  expect_named(rects, c("x", "y", "width", "height"))
  expect_equal(rects$x[1], 20)
  expect_equal(rects$y[1], 30)
  expect_equal(rects$width[1], 100)
  expect_equal(rects$height[1], 50)
  expect_equal(rects$y[2], 80)
})

test_that("el_rects on a zero-count set returns a zero-row tibble", {
  page <- local_geometry_page()
  els <- new_elements(page, NULL, 0L, "empty")
  rects <- el_rects(els)
  expect_equal(
    rects,
    tibble::tibble(
      x = numeric(),
      y = numeric(),
      width = numeric(),
      height = numeric()
    )
  )
})

test_that("el_rects checks its input", {
  expect_error(el_rects("nope"), class = "rlang_error")
})

test_that("el_scroll_into_view brings an off-screen element into the viewport", {
  page <- local_geometry_page()
  els <- loc_resolve(page, "#below-fold", multiple = "all")
  withr::defer(release_elements(els))

  inner_height <- pz_js(page, "window.innerHeight")
  expect_gt(el_rects(els)$y, inner_height)

  el_scroll_into_view(els)
  y <- el_rects(els)$y
  expect_gte(y, 0)
  expect_lt(y, inner_height)
})

test_that("el_scroll_into_view scrolls the FIRST element, instantly", {
  page <- local_geometry_page()
  # The fixture sets scroll-behavior: smooth; the helper must still
  # land immediately (no animation), on the first match in DOM order.
  els <- loc_resolve(page, "[id^='below-fold']", multiple = "all")
  withr::defer(release_elements(els))
  expect_identical(els$count, 2L)

  inner_height <- pz_js(page, "window.innerHeight")
  el_scroll_into_view(els)
  y <- el_rects(els)$y
  expect_gte(y[1], 0)
  expect_lt(y[1], inner_height)
})

test_that("el_scroll_into_view on a zero-count set is a no-op", {
  page <- local_geometry_page()
  expect_invisible(el_scroll_into_view(new_elements(page, NULL, 0L, "empty")))
})

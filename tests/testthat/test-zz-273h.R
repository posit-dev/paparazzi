# Temporary diagnostics for the Windows CI hang in test-frame.R's "a
# staged frame does not leak to other pages": the second framed capture
# (on the staging source page) times out waiting on
# Page.captureScreenshot, 2/2 runs. These variants separate the
# hypotheses in one CI cycle. Delete before merging; the real fix
# lands in test-frame.R.

test_that("273h-A: reordered — staging source captured first", {
  page <- local_frame_page()
  other <- local_frame_page()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- page_dpr(other)

  staged <- pz_stage_frame(page, pad = 32)
  cat("273h-A capture 1: staging source page\n")
  print(system.time(pz_screenshot(page, path, frame = "#card")))
  expect_identical(png_dimensions(path), as.integer(round(c(120, 90) * dpr)))
  cat("273h-A capture 2: unstaged other page\n")
  print(system.time(pz_screenshot(other, path, frame = "#card")))
  expect_identical(png_dimensions(path), as.integer(round(c(120, 90) * dpr)))
})

test_that("273h-B: no staging — two framed captures on fresh pages", {
  page <- local_frame_page()
  other <- local_frame_page()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- page_dpr(other)

  cat("273h-B capture 1: first fresh page\n")
  print(system.time(pz_screenshot(page, path, frame = "#card")))
  expect_identical(png_dimensions(path), as.integer(round(c(120, 90) * dpr)))
  cat("273h-B capture 2: second fresh page\n")
  print(system.time(pz_screenshot(other, path, frame = "#card")))
  expect_identical(png_dimensions(path), as.integer(round(c(120, 90) * dpr)))
})

test_that("273h-C: original order with a 30s capture timeout", {
  page <- local_frame_page()
  page$default_timeout <- 30
  other <- local_frame_page()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- page_dpr(other)

  staged <- pz_stage_frame(page, pad = 32)
  cat("273h-C capture 1: unstaged other page\n")
  print(system.time(pz_screenshot(other, path, frame = "#card")))
  expect_identical(png_dimensions(path), as.integer(round(c(120, 90) * dpr)))
  cat("273h-C capture 2: staging source page, 30s timeout\n")
  print(system.time(pz_screenshot(page, path, frame = "#card")))
  expect_identical(png_dimensions(path), as.integer(round(c(120, 90) * dpr)))
})

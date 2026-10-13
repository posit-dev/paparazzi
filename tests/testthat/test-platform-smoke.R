# Platform smoke suite: the only browser tests everyday macOS/Windows CI
# runs (PAPARAZZI_SMOKE_ONLY=true makes tests/testthat.R filter to this
# file); rc-v* branches and all ubuntu jobs run it as part of the full
# suite. It covers the seams where platforms genuinely differ —
# scrollbars and layout geometry, DPR, font machinery, process/port
# management, overlay rasterization, and the video encoder — with
# assertions over persistent state only, so a failure here names a
# product problem. Keep it under a few minutes; platform-sensitive
# behavior earns a spot, everything else belongs in the full suite.

test_that("framed element screenshots honor DPR and scrollbar geometry", {
  page <- local_frame_page()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- page_dpr(page)

  pz_screenshot(page, path, frame = "#card")
  expect_identical(png_dimensions(path), as.integer(round(c(120, 90) * dpr)))
})

test_that("a staged frame's pad expands the capture", {
  page <- local_frame_page()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- page_dpr(page)

  staged <- pz_stage_frame(page, pad = 32)
  pz_screenshot(staged, path, frame = "#card")
  expect_identical(png_dimensions(path), as.integer(round(c(184, 154) * dpr)))
})

test_that("the device scale factor round-trips", {
  page <- local_device_page()
  pz_device(page, width = 800, height = 600)

  expect_equal(pz_js(page, "innerWidth"), 800)
  expect_equal(pz_js(page, "devicePixelRatio"), 2)

  pz_device(page, scale = 1)
  expect_equal(pz_js(page, "devicePixelRatio"), 1)
})

test_that("a staged cursor rasterizes into a screenshot", {
  page <- local_cursor_page()
  staged <- page |>
    pz_stage(cursor = TRUE) |>
    pz_cursor_move("#btn")

  shot <- withr::local_tempfile(fileext = ".png")
  staged |> pz_screenshot(shot)
  ink <- cursor_png_ink(page, shot, band = c(280, 370))
  expect_true(ink$count > 50)
  expect_true(abs(ink$x - 660) < 15)
  expect_true(abs(ink$y - 322) < 30)
})

test_that("a staged file font loads into document.fonts", {
  page <- local_page()
  font <- pz_font_file(
    "Silkscreen",
    test_path("fixtures", "fonts", "silkscreen-400.woff2")
  )
  pz_stage_fonts(page, font)

  expect_true(pz_js(
    page,
    "[...document.fonts].some(f => f.family === 'Silkscreen' && f.status === 'loaded')"
  ))
})

test_that("a served Shiny app boots and responds", {
  skip_if_no_shiny()
  page <- pz_open(pz_serve_shiny(shiny_app_fixture_dir()))
  withr::defer({
    pz_close(page)
    page$app$stop()
  })

  expect_true(wait_until(function() {
    grepl("hello paparazzi", pz_js(page, "document.body.innerText"))
  }))
})

test_that("a short recording yields frames and a playable video", {
  skip_if_no_av()
  page <- local_frame_page()
  out <- withr::local_tempfile(fileext = ".mp4")
  page |> pz_record_start(out, fps = 5, hold = c(0.3, 0.3), keep_frames = TRUE)

  rec <- page_recorder(page)
  pz_poll(
    function() length(rec$files) >= 2L,
    timeout = 5,
    loop = page$page$child_loop,
    what = "two frames of the static page"
  )
  page |> pz_record_stop()

  expect_true(file.exists(out))
  info <- recorded_video_info(out)
  expect_true(info$duration >= 0.6)
  frames_dir <- paste0(tools::file_path_sans_ext(out), "_frames")
  on.exit(unlink(frames_dir, recursive = TRUE), add = TRUE)
  expect_gte(length(list.files(frames_dir)), 2L)
})

test_that("pz_record_start/stop record an mp4 with first/last holds", {
  page <- local_record_page()
  skip_if_no_av()

  out <- withr::local_tempfile(fileext = ".mp4")
  start <- withVisible(pz_record_start(page, out, fps = 10, hold = c(0.5, 1)))
  expect_false(start$visible)
  expect_identical(start$value, page)

  pz_wait(page, 0.8)
  stop <- withVisible(pz_record_stop(page))
  expect_false(stop$visible)
  expect_identical(stop$value, page)

  expect_true(file.exists(out))
  info <- recorded_video_info(out)
  expect_equal(info$codec, "h264")
  expect_equal(info$framerate, 10)
  # ~0.8s recorded + 0.5s + 1s holds
  expect_gte(info$duration, 2.0)
  expect_lte(info$duration, 3.2)
  # mp4 dimensions are multiples of 4
  expect_equal(info$width %% 4, 0)
  expect_equal(info$height %% 4, 0)
})

test_that("webm encodes", {
  page <- local_record_page()
  skip_if_no_av()

  out <- withr::local_tempfile(fileext = ".webm")
  page |> pz_record_start(out, fps = 10, hold = c(0, 0))
  pz_wait(page, 0.4)
  page |> pz_record_stop()

  expect_true(file.exists(out))
  info <- recorded_video_info(out)
  expect_match(info$codec, "vp")
  expect_gte(info$duration, 0.2)
  expect_lte(info$duration, 1.0)
})

test_that("pause/resume cuts the paused stretch out of the video", {
  page <- local_record_page()
  skip_if_no_av()

  out <- withr::local_tempfile(fileext = ".mp4")
  page |> pz_record_start(out, fps = 10, hold = c(0, 0))
  pz_wait(page, 0.5)
  page |> pz_record_pause()
  pz_wait(page, 0.7)
  page |> pz_record_resume()
  pz_wait(page, 0.5)
  page |> pz_record_stop()

  info <- recorded_video_info(out)
  # ~1s of active recording; the 0.7s pause leaves no trace
  expect_gte(info$duration, 0.7)
  expect_lte(info$duration, 1.5)
})

test_that("pz_record encodes on error and returns ctx invisibly", {
  page <- local_record_page()
  skip_if_no_av()

  out <- withr::local_tempfile(fileext = ".mp4")
  expect_error(
    pz_record(page, out, {
      pz_wait(page, 0.4)
      stop("boom")
    }),
    "boom",
    class = "simpleError"
  )
  # the recording up to the error was still encoded and written
  expect_true(file.exists(out))
  expect_gt(recorded_video_info(out)$duration, 0)

  out2 <- withr::local_tempfile(fileext = ".mp4")
  res <- withVisible(pz_record(page, out2, pz_wait(page, 0.2)))
  expect_false(res$visible)
  expect_identical(res$value, page)
  expect_true(file.exists(out2))
})

test_that("pz_record_hold extends the video and is a no-op otherwise", {
  page <- local_record_page()
  skip_if_no_av()

  out <- withr::local_tempfile(fileext = ".mp4")
  page |> pz_record_start(out, fps = 10, hold = c(0, 0))
  pz_wait(page, 0.3)
  page |> pz_record_hold(1)
  pz_wait(page, 0.2)
  page |> pz_record_stop()

  info <- recorded_video_info(out)
  # ~0.5s recorded + 1s hold; real time was only ~0.5s
  expect_gte(info$duration, 1.2)
  expect_lte(info$duration, 2.0)

  start <- Sys.time()
  res <- withVisible(pz_record_hold(page, 2))
  elapsed <- as.numeric(difftime(Sys.time(), start, units = "secs"))
  expect_lt(elapsed, 0.5)
  expect_false(res$visible)
  expect_identical(res$value, page)
})

test_that("frames are resampled to the requested constant fps", {
  page <- local_record_page()
  skip_if_no_av()

  out5 <- withr::local_tempfile(fileext = ".mp4")
  page |> pz_record(out5, pz_wait(page, 0.6), fps = 5, hold = c(0, 0))
  info5 <- recorded_video_info(out5)

  out20 <- withr::local_tempfile(fileext = ".mp4")
  page |> pz_record(out20, pz_wait(page, 0.6), fps = 20, hold = c(0, 0))
  info20 <- recorded_video_info(out20)

  # same real time, different output rates: durations agree, frame
  # counts track fps
  expect_gte(info5$duration, 0.4)
  expect_lte(info5$duration, 1.2)
  expect_gte(info20$duration, 0.4)
  expect_lte(info20$duration, 1.2)
  expect_lte(info5$frames, 8)
  expect_gte(info20$frames, 8)
})

test_that("gif encodes via gifski or av", {
  page <- local_record_page()
  testthat::skip_if(
    !rlang::is_installed("gifski") && !rlang::is_installed("av"),
    "neither gifski nor av is installed"
  )

  out <- withr::local_tempfile(fileext = ".gif")
  page |> pz_record(out, pz_wait(page, 0.4), fps = 10, hold = c(0.2, 0.2))

  expect_true(file.exists(out))
  info <- recorded_video_info(out)
  expect_equal(info$codec, "gif")
  expect_gte(info$duration, 0.6)
  expect_lte(info$duration, 1.2)
  expect_equal(info$width %% 2, 0)
  expect_equal(info$height %% 2, 0)
})

test_that("a frame crops the recording at encode time", {
  page <- local_record_page()
  skip_if_no_av()
  dpr <- pz_js(page, "window.devicePixelRatio")

  out <- withr::local_tempfile(fileext = ".mp4")
  page |>
    pz_record(
      out,
      pz_wait(page, 0.3),
      fps = 10,
      hold = c(0, 0),
      frame = pz_frame("#box", pad = 8)
    )

  info <- recorded_video_info(out)
  # #box is 100x60; pad 8 gives 116x76 CSS pixels, converted to device
  # pixels and floored to a multiple of 4
  expect_equal(info$width, floor(round(116 * dpr) / 4) * 4)
  expect_equal(info$height, floor(round(76 * dpr) / 4) * 4)
})

test_that("frame when = start and stop measure at different times", {
  page <- local_record_page()
  skip_if_no_av()
  dpr <- pz_js(page, "window.devicePixelRatio")
  width_at <- function(css) floor(round(css * dpr) / 4) * 4

  out_stop <- withr::local_tempfile(fileext = ".mp4")
  page |>
    pz_record_start(
      out_stop,
      fps = 10,
      hold = c(0, 0),
      frame = pz_frame("#box", pad = 8)
    )
  pz_js(page, "growBox()")
  pz_wait(page, 0.3)
  page |> pz_record_stop()
  # measured against the final layout: the grown 200px-wide box
  expect_equal(recorded_video_info(out_stop)$width, width_at(216))

  out_start <- withr::local_tempfile(fileext = ".mp4")
  page$session$Page$reload()
  pz_wait(page, 0.3)
  page |>
    pz_record_start(
      out_start,
      fps = 10,
      hold = c(0, 0),
      frame = pz_frame("#box", pad = 8, when = "start")
    )
  pz_js(page, "growBox()")
  pz_wait(page, 0.3)
  page |> pz_record_stop()
  # measured at the start: the original 100px-wide box
  expect_equal(recorded_video_info(out_start)$width, width_at(116))
})

test_that("keep_frames keeps the captured PNGs", {
  page <- local_record_page()
  skip_if_no_av()

  out <- withr::local_tempfile(fileext = ".mp4")
  frames_dir <- paste0(tools::file_path_sans_ext(out), "_frames")
  page |> pz_record(out, pz_wait(page, 0.3), fps = 10, keep_frames = TRUE)
  expect_true(dir.exists(frames_dir))
  expect_gte(length(list.files(frames_dir, pattern = "[.]png$")), 1)
  unlink(frames_dir, recursive = TRUE)

  out2 <- withr::local_tempfile(fileext = ".mp4")
  frames_dir2 <- paste0(tools::file_path_sans_ext(out2), "_frames")
  page |> pz_record(out2, pz_wait(page, 0.2), fps = 10)
  expect_false(dir.exists(frames_dir2))
})

test_that("recording input and lifecycle errors are classed", {
  page <- local_record_page()
  skip_if_no_av()

  expect_error(
    pz_record_start(page, withr::local_tempfile(fileext = ".mov")),
    class = "paparazzi_error_input"
  )
  expect_error(
    pz_record_start(
      page,
      withr::local_tempfile(fileext = ".mp4"),
      method = "screencast"
    ),
    class = "paparazzi_error_unsupported"
  )
  expect_error(
    pz_record_start(page, withr::local_tempfile(fileext = ".mp4"), hold = 1),
    class = "paparazzi_error_input"
  )
  expect_error(pz_record_stop(page), class = "paparazzi_error_record")
  expect_error(pz_record_pause(page), class = "paparazzi_error_record")
  expect_error(pz_record_resume(page), class = "paparazzi_error_record")

  out <- withr::local_tempfile(fileext = ".mp4")
  page |> pz_record_start(out, fps = 10, hold = c(0, 0))
  expect_error(
    pz_record_start(page, withr::local_tempfile(fileext = ".mp4")),
    class = "paparazzi_error_record"
  )
  pz_wait(page, 0.2)
  page |> pz_record_stop()
  # the recorder is cleared after a stop
  expect_error(pz_record_stop(page), class = "paparazzi_error_record")
})

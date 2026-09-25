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
  if (rlang::is_installed("av")) {
    info <- recorded_video_info(out)
    expect_equal(info$codec, "gif")
    expect_gte(info$duration, 0.6)
    expect_lte(info$duration, 1.2)
    expect_equal(info$width %% 2, 0)
    expect_equal(info$height %% 2, 0)
  } else {
    dims <- gif_dimensions(out)
    expect_equal(dims[1] %% 2, 0)
    expect_equal(dims[2] %% 2, 0)
  }
})

test_that("an immediate stop still writes a one-frame video", {
  page <- local_record_page()
  skip_if_no_av()

  out <- withr::local_tempfile(fileext = ".mp4")
  page |> pz_record_start(out, fps = 10, hold = c(0, 0))
  page |> pz_record_stop()

  expect_true(file.exists(out))
  expect_gte(recorded_video_info(out)$frames, 1)
})

test_that("stop captures a final frame after a late page change", {
  page <- local_record_page()
  skip_if_no_av()
  testthat::skip_if_not_installed("png")

  out <- withr::local_tempfile(fileext = ".mp4")
  frames_dir <- paste0(tools::file_path_sans_ext(out), "_frames")
  withr::defer(unlink(frames_dir, recursive = TRUE))
  page |> pz_record_start(out, fps = 10, hold = c(0, 0), keep_frames = TRUE)
  pz_wait(page, 0.4)
  # A change right before stop must appear in the final frame; without
  # the stop-time capture the video would end on an older one.
  pz_js(
    page,
    "document.getElementById('box').style.backgroundColor = 'rgb(255, 0, 0)'"
  )
  page |> pz_record_stop()

  files <- sort(list.files(frames_dir, full.names = TRUE, pattern = "[.]png$"))
  expect_gte(length(files), 2L)
  dpr <- pz_js(page, "window.devicePixelRatio")
  # a pixel inside #box (CSS left 40, top 30, 100x60), in device pixels
  pixel <- function(path) {
    img <- png::readPNG(path)
    unname(img[round(40 * dpr) + 1, round(50 * dpr) + 1, 1:3])
  }
  expect_false(isTRUE(all.equal(pixel(files[[1]]), c(1, 0, 0), tolerance = 0.05)))
  expect_equal(pixel(files[[length(files)]]), c(1, 0, 0), tolerance = 0.05)
})

test_that("an immediate block error is not masked by the stop", {
  page <- local_record_page()
  skip_if_no_av()

  out <- withr::local_tempfile(fileext = ".mp4")
  expect_error(
    pz_record(page, out, stop("boom")),
    "boom",
    class = "simpleError"
  )
})

test_that("a quick restart does not double the capture chain", {
  page <- local_record_page()
  skip_if_no_av()

  out1 <- withr::local_tempfile(fileext = ".mp4")
  page |> pz_record_start(out1, fps = 2, hold = c(0, 0))
  pz_wait(page, 0.3)
  # a tick from the first recording is still scheduled when stop runs
  page |> pz_record_stop()

  out2 <- withr::local_tempfile(fileext = ".mp4")
  page |> pz_record_start(out2, fps = 2, hold = c(0, 0))
  rec <- page_recorder(page)
  pz_wait(page, 1.2)
  ticks <- rec$ticks
  page |> pz_record_stop()

  # one chain at 2 fps over 1.2s: a tick every 0.5s, so 3 or so; a
  # second chain left over from the first recording would double it
  expect_gte(ticks, 2L)
  expect_lte(ticks, 4L)
})

test_that("closing the page tears down the recorder synchronously", {
  page <- local_record_page()

  out <- withr::local_tempfile(fileext = ".mp4")
  page |> pz_record_start(out, fps = 10, hold = c(0, 0))
  rec <- page_recorder(page)
  expect_true(rec$active)
  frames_dir <- rec$frames_dir
  expect_true(dir.exists(frames_dir))

  pz_close(page)

  # no tick involved: the close path itself clears the recorder slot,
  # deactivates the recorder, and drops the temp frames dir -- the
  # closed session's loop may never pump again
  expect_null(page_recorder(page))
  expect_false(rec$active)
  expect_false(dir.exists(frames_dir))
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

test_that("a targetless stop frame crops from the start-time scope", {
  page <- local_record_page()
  skip_if_no_av()
  dpr <- pz_js(page, "window.devicePixelRatio")
  width_at <- function(css) floor(round(css * dpr) / 4) * 4

  out <- withr::local_tempfile(fileext = ".mp4")
  page |>
    pz_find("#box") |>
    pz_record_start(out, fps = 10, hold = c(0, 0), frame = pz_frame())
  pz_wait(page, 0.2)
  # stopping from the root context must not swap the crop to the
  # viewport; it still covers the scope the recording started in
  page |> pz_record_stop()

  info <- recorded_video_info(out)
  # #box is 100x60
  expect_equal(info$width, width_at(100))
  expect_equal(info$height, width_at(60))
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

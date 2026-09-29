test_that("captions persist as page state and clearing is selective", {
  page <- local_record_page()
  expect_identical(pz_annotate_caption(page, "First"), page)
  expect_equal(page_caption(page)$text, "First")
  pz_annotate_clear(page, id = "other")
  expect_equal(page_caption(page)$text, "First")
  pz_annotate_clear(page, id = "caption")
  expect_null(page_caption(page))
})

test_that("WebVTT on GIF is rejected at start", {
  page <- local_record_page()
  for (mode in c("vtt", "both")) {
    expect_error(
      pz_record_start(page, tempfile(fileext = ".gif"), captions = mode),
      "WebVTT sidecars need an MP4 or WebM recording"
    )
  }
})

test_that("caption burn overlays two windows after a camera move, with quoted paths", {
  skip_if_no_av()
  skip_if_not_installed("png")
  page <- local_page(
    record_fixture_file(),
    width = 320,
    height = 240,
    scale = 2
  )
  dir <- withr::local_tempdir(pattern = "caption a'b ")
  out <- file.path(dir, "quoted output.mp4")
  pz_record_start(page, out, fps = 10, scale = 0.5, hold = c(0.1, 0.2))
  defer_record_stop(page)
  pz_annotate_caption(page, "FIRST")
  pz_wait(page, 0.35)
  pz_camera(page, "#box", zoom = 1.5, duration = 0.12)
  pz_annotate_caption(page, "SECOND")
  pz_wait(page, 0.35)
  pz_annotate_clear(page, "caption")
  pz_wait(page, 0.3)
  pz_record_stop(page)
  expect_true(file.exists(out))
  decoded <- tempfile("caption-decoded-")
  withr::defer(unlink(decoded, recursive = TRUE))
  frames <- av::av_video_images(out, destdir = decoded, format = "png")
  expect_gt(length(frames), 5)
  first <- png::readPNG(frames[[3]])
  last <- png::readPNG(tail(frames, 1))
  expect_true(any(first[round(dim(first)[1] * 0.8):dim(first)[1], , 1] < 0.4))
  last_rows <- round(dim(last)[1] * 0.8):dim(last)[1]
  expect_true(all(last[last_rows, round(dim(last)[2] * 0.85), 1] > 0.8))
})

test_that("captioned still is transparent outside the pill and opaque inside", {
  skip_if_not_installed("png")
  page <- local_record_page()
  plain <- withr::local_tempfile(fileext = ".png")
  captioned <- withr::local_tempfile(fileext = ".png")
  pz_screenshot(page, plain)
  pz_annotate_caption(page, "CAPTION")
  pz_screenshot(page, captioned)
  a <- png::readPNG(plain)
  b <- png::readPNG(captioned)
  expect_equal(a[2, 2, 1:3], b[2, 2, 1:3])
  expect_true(any(abs(a - b) > 0.2))
  framed <- withr::local_tempfile(fileext = ".png")
  pz_screenshot(page, framed, frame = pz_frame("#box", pad = 80))
  framed_image <- png::readPNG(framed)
  expect_lt(dim(framed_image)[1], dim(b)[1])
  center <- framed_image[, round(dim(framed_image)[2] / 2), 1]
  expect_true(any(center[round(length(center) * 0.7):length(center)] < 0.4))
})

test_that("captioned GIF uses the same relative movie source after scaling", {
  skip_if_no_av()
  skip_if_not_installed("gifski")
  skip_if_not_installed("png")
  page <- local_record_page()
  dir <- withr::local_tempdir(pattern = "gif a'b ")
  out <- file.path(dir, "quoted output.gif")
  pz_annotate_caption(page, "FIRST")
  pz_record_start(page, out, fps = 8, scale = 0.5, hold = c(0.2, 0.2))
  defer_record_stop(page)
  pz_wait(page, 0.3)
  pz_annotate_caption(page, "SECOND")
  pz_wait(page, 0.3)
  pz_annotate_clear(page, "caption")
  pz_wait(page, 0.25)
  pz_record_stop(page)
  expect_true(file.exists(out))
  info <- recorded_video_info(out)
  expect_gt(info$duration, 0.7)
  expect_equal(info$width %% 2, 0)
  decoded <- tempfile("caption-gif-decoded-")
  withr::defer(unlink(decoded, recursive = TRUE))
  frames <- av::av_video_images(out, destdir = decoded, format = "png")
  expect_true(length(frames) >= 2)
  first <- png::readPNG(frames[[1]])
  last <- png::readPNG(tail(frames, 1))
  expect_true(any(first[round(dim(first)[1] * 0.8):dim(first)[1], , 1] < 0.4))
  center <- first[, round(dim(first)[2] / 2), 1]
  pill_rows <- which(center < 0.4 & seq_along(center) > dim(first)[1] * 0.8)
  expect_gt(length(pill_rows), 5)
  expect_lt(length(pill_rows), 45)
  expect_true(all(last[round(dim(last)[1] * 0.8):dim(last)[1], , 1] > 0.8))
})

test_that("caption windows use output ticks through holds and same-time replacements", {
  rec <- new_recorder(
    tempfile(fileext = ".mp4"),
    "mp4",
    10,
    NULL,
    c(0, 0),
    FALSE,
    NULL
  )
  withr::defer(unlink(paste0(tools::file_path_sans_ext(rec$path), ".vtt")))
  rec$captions <- list(
    list(vt = 0, caption = list(text = "Before")),
    list(vt = 0.2, caption = list(text = "Old")),
    list(vt = 0.2, caption = list(text = "New & <tag>\nline")),
    list(vt = 0.3, caption = list(text = "New & <tag>\nline")),
    list(vt = 0.4, caption = NULL)
  )
  sampled <- list(vts = c(0, 0, 0.1, 0.2, 0.2, 0.3, 0.4, 0.4))
  windows <- caption_windows(rec, sampled)
  expect_equal(vapply(windows, `[[`, numeric(1), "start"), c(0, 0.3))
  expect_equal(vapply(windows, `[[`, numeric(1), "end"), c(0.3, 0.6))
  expect_equal(
    vapply(windows, function(w) w$caption$text, character(1)),
    c("Before", "New & <tag>\nline")
  )
  path <- caption_vtt(rec, windows)
  text <- paste(readLines(path, warn = FALSE), collapse = "\n")
  expect_match(text, "00:00:00.000 --> 00:00:00.300", fixed = TRUE)
  expect_match(text, "00:00:00.300 --> 00:00:00.600", fixed = TRUE)
  expect_match(text, "New &amp; &lt;tag&gt;\nline", fixed = TRUE)
  caption_vtt(rec, list())
  expect_equal(readLines(path), c("WEBVTT", ""))
  rec$captions <- list(
    list(vt = 0, caption = list(text = "Again")),
    list(vt = 0.1, caption = NULL),
    list(vt = 0.3, caption = list(text = "Again"))
  )
  separated <- caption_windows(rec, list(vts = c(0, 0.1, 0.2, 0.3)))
  expect_equal(vapply(separated, `[[`, numeric(1), "start"), c(0, 0.3))
  rec$captions <- list(list(vt = 0, caption = list(text = "One tick")))
  one <- caption_windows(rec, list(vts = 0))
  expect_equal(one[[1]]$end, 0.1)
})

test_that("VTT-only output follows pause-aware ticks and does not burn", {
  skip_if_no_av()
  skip_if_not_installed("png")
  page <- local_record_page()
  dir <- withr::local_tempdir()
  out <- file.path(dir, "captions.webm")
  pz_annotate_caption(page, "Initial")
  pz_record_start(page, out, captions = "vtt", fps = 10, hold = c(0.2, 0.3))
  defer_record_stop(page)
  pz_wait(page, 0.3)
  pz_record_hold(page, 0.2)
  pz_record_pause(page)
  pz_annotate_caption(page, "After pause")
  pz_record_resume(page)
  pz_wait(page, 0.3)
  pz_record_stop(page)
  vtt <- file.path(dir, "captions.vtt")
  expect_true(file.exists(vtt))
  cues <- paste(readLines(vtt), collapse = "\n")
  expect_match(cues, "Initial", fixed = TRUE)
  expect_match(cues, "After pause", fixed = TRUE)
  timings <- grep(" --> ", readLines(vtt), value = TRUE, fixed = TRUE)
  expect_length(timings, 2)
  expect_gte(
    as.numeric(sub(".* --> 00:00:([0-9.]+)", "\\1", timings[[1]])),
    0.5
  )
  decoded <- tempfile("caption-vtt-decoded-")
  withr::defer(unlink(decoded, recursive = TRUE))
  frame <- av::av_video_images(out, destdir = decoded, format = "png")[[1]]
  image <- png::readPNG(frame)
  height <- dim(image)[1]
  middle <- round(dim(image)[2] / 2)
  expect_true(all(
    image[(height - 80):(height - 20), (middle - 70):(middle + 70), 1] > 0.8
  ))
})

test_that("caption style is independent of badge style and survives navigation", {
  page <- local_record_page()
  pz_stage(
    page,
    annotate_color = "red",
    annotate_font_family = "monospace",
    annotate_font_size = 7
  )
  pz_annotate_caption(page, "On every page", side = "top")
  expect_equal(page_caption(page)$color, "white")
  expect_equal(page_caption(page)$font_family, "monospace")
  expect_equal(page_caption(page)$font_size, 20)
  pz_stage(page, annotate_font_family = "serif")
  expect_equal(page_caption(page)$font_family, "monospace")
  pz_nav_reload(page)
  expect_equal(page_caption(page)$text, "On every page")
  top <- withr::local_tempfile(fileext = ".png")
  pz_screenshot(page, top)
  image <- png::readPNG(top)
  expect_true(any(
    image[1:round(dim(image)[1] * 0.15), round(dim(image)[2] / 2), 1] < 0.4
  ))
  expect_error(pz_annotate_caption(page, ""), "nonempty")
  expect_error(pz_annotate_caption(page, "x", font_size = 0), "positive")
  pz_annotate_clear(page)
  expect_null(page_caption(page))
})

test_that("GIF caption overlay can follow a camera move", {
  skip_if_no_av()
  skip_if_not_installed("gifski")
  page <- local_page(
    record_fixture_file(),
    width = 320,
    height = 240,
    scale = 2
  )
  out <- withr::local_tempfile(fileext = ".gif")
  pz_annotate_caption(page, "Moving")
  pz_record_start(page, out, fps = 8, hold = c(0.1, 0.1))
  defer_record_stop(page)
  pz_camera(page, "#box", zoom = 1.5, duration = 0.12)
  pz_wait(page, 0.25)
  pz_record_stop(page)
  expect_gt(recorded_video_info(out)$duration, 0.2)
})

test_that("both burns caption and writes matching sidecar", {
  skip_if_no_av()
  page <- local_record_page()
  out <- withr::local_tempfile(fileext = ".mp4")
  vtt <- sub("\\.mp4$", ".vtt", out)
  withr::defer(unlink(vtt))
  pz_annotate_caption(page, "Both")
  pz_record_start(page, out, captions = "both", fps = 8, hold = c(0.1, 0.1))
  defer_record_stop(page)
  pz_wait(page, 0.2)
  pz_record_stop(page)
  expect_true(file.exists(out))
  expect_equal(page_caption(page)$text, "Both")
  expect_match(paste(readLines(vtt), collapse = "\n"), "Both")
})

test_that("still alpha blend changes only caption rows and channels", {
  skip_if_not_installed("png")
  base <- withr::local_tempfile(fileext = ".png")
  overlay <- withr::local_tempfile(fileext = ".png")
  png::writePNG(array(0.8, dim = c(4, 5, 3)), base)
  top <- array(0, dim = c(4, 5, 4))
  top[2, 3, 1:3] <- c(1, 0, 0)
  top[2, 3, 4] <- 0.5
  png::writePNG(top, overlay)
  caption_blend_still(base, overlay)
  result <- png::readPNG(base)
  expect_equal(result[2, 3, 1:3], c(0.9, 0.4, 0.4), tolerance = 1 / 255)
  expect_equal(result[1, 3, 1:3], rep(0.8, 3), tolerance = 1 / 255)
  expect_equal(result[2, 2, 1:3], rep(0.8, 3), tolerance = 1 / 255)
})

test_that("recording caption pixels follow CSS size at DPR 2", {
  skip_if_no_av()
  skip_if_not_installed("png")
  pill_height <- function(scale) {
    page <- local_page(
      record_fixture_file(),
      width = 320,
      height = 240,
      scale = scale
    )
    expect_equal(page_dpr(page), scale)
    out <- withr::local_tempfile(fileext = ".mp4")
    pz_annotate_caption(page, "DPR")
    pz_record_start(page, out, fps = 8, hold = c(0.3, 0.1))
    defer_record_stop(page)
    pz_wait(page, 0.15)
    pz_record_stop(page)
    frames <- tempfile("caption-dpr-")
    withr::defer(unlink(frames, recursive = TRUE))
    image <- av::av_video_images(out, destdir = frames, format = "png")
    pixels <- png::readPNG(image[[1]])
    center <- pixels[, round(dim(pixels)[2] / 2), 1]
    sum(center < 0.4 & seq_along(center) > length(center) * 0.65)
  }
  height_1 <- pill_height(1)
  height_2 <- pill_height(2)
  expect_gt(height_1, 20)
  expect_equal(height_2 / height_1, 2, tolerance = 0.3)
})

test_that("VTT keeps text after empty lines within one cue", {
  rec <- list(path = withr::local_tempfile(fileext = ".mp4"))
  path <- caption_vtt(
    rec,
    list(list(
      start = 0,
      end = 1,
      caption = list(text = "\na\r\n\r\nb\n\n")
    ))
  )
  lines <- readLines(path)
  expect_equal(lines[4:5], c("a", "b"))
  expect_equal(
    lines,
    c("WEBVTT", "", "00:00:00.000 --> 00:00:01.000", "a", "b", "")
  )
})

test_that("still blend preserves straight alpha on transparent pixels", {
  skip_if_not_installed("png")
  base <- withr::local_tempfile(fileext = ".png")
  overlay <- withr::local_tempfile(fileext = ".png")
  bottom <- array(0, dim = c(2, 2, 4))
  bottom[1, 1, ] <- c(0, 0, 1, 0.25)
  top <- array(0, dim = c(2, 2, 4))
  top[1, 1, ] <- c(1, 0, 0, 0.5)
  png::writePNG(bottom, base)
  png::writePNG(top, overlay)
  caption_blend_still(base, overlay)
  result <- png::readPNG(base)
  expect_equal(result[1, 1, 4], 0.625, tolerance = 1 / 255)
  expect_equal(result[1, 1, 1:3], c(0.8, 0, 0.2), tolerance = 1 / 255)
  expect_equal(result[2, 2, 4], 0)
})

test_that("still blend works for single-pixel dimensions", {
  skip_if_not_installed("png")
  for (dims in list(c(1, 3), c(3, 1), c(1, 1))) {
    base <- withr::local_tempfile(fileext = ".png")
    overlay <- withr::local_tempfile(fileext = ".png")
    png::writePNG(array(0, dim = c(dims, 4)), base)
    top <- array(0, dim = c(dims, 4))
    top[1, 1, ] <- c(1, 0, 0, 1)
    png::writePNG(top, overlay)
    caption_blend_still(base, overlay)
    result <- png::readPNG(base)
    expect_equal(result[1, 1, ], c(1, 0, 0, 1), tolerance = 1 / 255)
  }
})

test_that("clearing all logs the caption clear before mark fades pump", {
  page <- local_record_page()
  out <- withr::local_tempfile(fileext = ".mp4")
  pz_record_start(page, out, hold = c(0, 0))
  defer_record_stop(page)
  page |>
    pz_annotate("#box", reveal = "fade") |>
    pz_annotate_caption("Hello")
  rec <- page_recorder(page)
  before <- rec_vt(rec)
  pz_annotate_clear(page)
  events <- rec$captions
  last <- events[[length(events)]]
  expect_null(last$caption)
  expect_lt(last$vt - before, 0.2)
  pz_record_stop(page)
})

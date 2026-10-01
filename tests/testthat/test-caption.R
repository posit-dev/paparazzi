test_that("frame extraction silences FFmpeg progress and keeps failures visible", {
  skip_if_no_av()
  skip_if_not_installed("png")
  image <- withr::local_tempfile(fileext = ".png")
  video <- withr::local_tempfile(fileext = ".mp4")
  png::writePNG(array(0.5, c(32, 32, 3)), image)
  av::av_encode_video(image, video, framerate = 1, verbose = FALSE)

  old_level <- av::av_log_level()
  withr::defer(av::av_log_level(old_level))
  av::av_log_level(24)

  decoded <- tempfile("av-decoded-")
  withr::defer(unlink(decoded, recursive = TRUE))
  diagnostics <- utils::capture.output(
    frames <- av_video_images_quiet(video, destdir = decoded, format = "png"),
    type = "message"
  )
  expect_gt(length(frames), 0L)
  expect_length(diagnostics, 0L)
  expect_equal(av::av_log_level(), 24)

  expect_error(
    av_video_images_quiet(
      video,
      destdir = withr::local_tempfile(),
      format = "invalid-codec"
    ),
    "avcodec_find_encoder_by_name"
  )
  expect_equal(av::av_log_level(), 24)
})

test_that("burned overlays convert to yuv420p only after compositing", {
  skip_if_not_installed("png")
  file <- withr::local_tempfile(fileext = ".png")
  png::writePNG(array(0.5, c(48, 64, 3)), file)
  size <- png_read_size(file)
  sampled <- list(files = file, index = 1L, vts = 0, n_ticks = 1L)
  overlay <- list(file = "caption-1.png", start = 0, end = 0.1)
  key <- list(file = "keys-1.png", start = 0, end = 0.1)
  for (format in c("mp4", "webm")) {
    rec <- new_recorder("unused", format, 10, NULL, c(0, 0), FALSE, NULL)
    rec$camera_viewport_width <- 64
    rec$files <- file
    rec$scroll <- list(c(0, 0))
    out <- record_output_spec(rec, size)
    expect_equal(out$vfilter, "format=yuv420p")
    for (camera in c(FALSE, TRUE)) {
      base <- out
      if (camera) {
        rec$camera <- list(list(
          start = 0,
          end = 0,
          box = c(12, 9, 36, 27),
          zoom = 1,
          reset = FALSE,
          scroll = c(0, 0)
        ))
        base$vfilter <- camera_filter(rec, sampled, out, size)
        expect_match(base$vfilter, ",format=yuv420p$", fixed = FALSE)
      }
      graph <- screen_filter(rec, sampled, base, list(overlay, key))
      positions <- gregexpr("format=yuv420p", graph, fixed = TRUE)[[1]]
      overlays <- gregexpr("overlay=0:0", graph, fixed = TRUE)[[1]]
      expect_length(overlays, 2L)
      expect_length(positions, 1L)
      expect_gt(positions[[1]], tail(overlays, 1)[[1]])
      expect_match(graph, ",format=yuv420p$", fixed = FALSE)
    }
  }
  rec <- new_recorder("unused", "gif", 10, NULL, c(0, 0), FALSE, NULL)
  out <- record_output_spec(rec, size)
  expect_equal(out$vfilter, "null")
  expect_match(
    screen_filter(rec, sampled, out, list(overlay)),
    ",format=rgb24$"
  )
})

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
  pz_camera(page, pz_frame("#box", zoom = 1.5), duration = 0.12)
  pz_annotate_caption(page, "SECOND")
  pz_wait(page, 0.35)
  pz_annotate_clear(page, "caption")
  pz_wait(page, 0.3)
  pz_record_stop(page)
  expect_true(file.exists(out))
  decoded <- tempfile("caption-decoded-")
  withr::defer(unlink(decoded, recursive = TRUE))
  frames <- av_video_images_quiet(out, destdir = decoded, format = "png")
  expect_gt(length(frames), 5)
  first <- png::readPNG(frames[[3]])
  last <- png::readPNG(tail(frames, 1))
  expect_true(any(first[round(dim(first)[1] * 0.8):dim(first)[1], , 1] < 0.4))
  last_rows <- round(dim(last)[1] * 0.8):dim(last)[1]
  expect_true(all(last[last_rows, round(dim(last)[2] * 0.85), 1] > 0.8))
})

test_that("a caption left active stays visible on the last MP4 frame", {
  skip_if_no_av()
  skip_if_not_installed("png")
  page <- local_record_page()
  out <- withr::local_tempfile(fileext = ".mp4")
  pz_annotate_caption(page, "PERSIST")
  pz_record_start(page, out, fps = 10, hold = c(0, 0.2))
  defer_record_stop(page)
  pz_wait(page, 0.5)
  pz_record_stop(page)
  decoded <- tempfile("caption-persist-decoded-")
  withr::defer(unlink(decoded, recursive = TRUE))
  frames <- av_video_images_quiet(out, destdir = decoded, format = "png")
  expect_gt(length(frames), 5)
  dark_pill <- function(frame) {
    image <- png::readPNG(frame)
    x <- round(dim(image)[2] / 2)
    y <- round(dim(image)[1] * 0.8):dim(image)[1]
    any(image[y, x, 1] < 0.4)
  }
  expect_true(dark_pill(frames[[1]]))
  expect_true(dark_pill(tail(frames, 1)[[1]]))
})

test_that("a caption left active stays visible on the last GIF frame", {
  skip_if_no_av()
  skip_if_not_installed("gifski")
  skip_if_not_installed("png")
  page <- local_page(record_fixture_file(), width = 320, height = 240)
  out <- withr::local_tempfile(fileext = ".gif")
  pz_annotate_caption(page, "PERSIST")
  pz_record_start(page, out, fps = 10, hold = c(0, 0.2))
  defer_record_stop(page)
  pz_wait(page, 0.5)
  pz_record_stop(page)
  decoded <- tempfile("caption-persist-gif-decoded-")
  withr::defer(unlink(decoded, recursive = TRUE))
  frames <- av_video_images_quiet(out, destdir = decoded, format = "png")
  expect_gt(length(frames), 5)
  first <- png::readPNG(frames[[1]])
  last <- png::readPNG(tail(frames, 1)[[1]])
  x <- round(dim(last)[2] / 2)
  y <- round(dim(last)[1] * 0.8):dim(last)[1]
  expect_true(any(first[y, x, 1] < 0.4))
  expect_true(any(last[y, x, 1] < 0.4))
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
  frames <- av_video_images_quiet(out, destdir = decoded, format = "png")
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

test_that("caption windows distinguish open stop from clear at the stop boundary", {
  rec <- list(fps = 10, path = withr::local_tempfile(fileext = ".mp4"))
  withr::defer(unlink(sub("\\.mp4$", ".vtt", rec$path)))
  caption <- list(
    text = "Stay",
    side = "bottom",
    color = "white",
    font_family = "sans-serif",
    font_size = 20
  )
  sampled <- list(vts = seq(0, 0.9, by = 0.1), n_ticks = 10)
  rec$captions <- list(list(vt = 0, caption = caption))
  open <- caption_windows(rec, sampled)
  expect_true(open[[1]]$open)
  expect_equal(open[[1]]$end, 1)
  expect_match(
    paste(readLines(caption_vtt(rec, open)), collapse = "\n"),
    "00:00:00.000 --> 00:00:01.000",
    fixed = TRUE
  )

  rec$captions <- c(rec$captions, list(list(vt = 1, caption = NULL)))
  cleared <- caption_windows(rec, sampled)
  expect_equal(cleared[[1]]$end, open[[1]]$end)
  expect_false(cleared[[1]]$open)

  rec$captions[[2]] <- list(
    vt = 1,
    caption = modifyList(caption, list(text = "Next"))
  )
  expect_false(caption_windows(rec, sampled)[[1]]$open)

  rec$captions[[2]] <- list(vt = 0.4, caption = caption)
  expect_length(caption_windows(rec, sampled), 1)
  expect_true(caption_windows(rec, sampled)[[1]]$open)

  rec$captions[[2]] <- list(vt = 1, caption = caption)
  expect_true(caption_windows(rec, sampled)[[1]]$open)
})

test_that("caption overlays fade only when a later caption event closes the window", {
  page <- local_page(record_fixture_file(), width = 320, height = 240)
  rec <- list(
    fps = 10,
    format = "mp4",
    crop = NULL,
    camera_viewport_width = 320
  )
  out <- list(width = 320, height = 240, vfilter = "null,")
  caption <- list(
    text = "Stay",
    side = "bottom",
    color = "white",
    font_family = "sans-serif",
    font_size = 20
  )
  sampled <- list(vts = seq(0, 0.9, by = 0.1), n_ticks = 10)
  rec$captions <- list(list(vt = 0, caption = caption))
  dir <- withr::local_tempdir()
  open <- caption_overlays(rec, page, out, caption_windows(rec, sampled), dir)
  expect_null(open[[1]]$fade_start)
  expect_null(open[[1]]$fade_in)
  expect_false(grepl(
    "fade=t=out",
    screen_filter(rec, sampled, out, open),
    fixed = TRUE
  ))

  rec$captions <- c(rec$captions, list(list(vt = 1, caption = NULL)))
  closed <- caption_overlays(rec, page, out, caption_windows(rec, sampled), dir)
  expect_equal(closed[[1]]$fade_start, 0.75)
  expect_match(
    screen_filter(rec, sampled, out, closed),
    "fade=t=out",
    fixed = TRUE
  )
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
  frame <- av_video_images_quiet(out, destdir = decoded, format = "png")[[1]]
  image <- png::readPNG(frame)
  height <- dim(image)[1]
  middle <- round(dim(image)[2] / 2)
  expect_true(all(
    image[(height - 80):(height - 20), (middle - 70):(middle + 70), 1] > 0.8
  ))
})

test_that("caption style is independent of badge style and survives navigation", {
  page <- local_record_page()
  pz_stage_annotate(
    page,
    color = "red",
    font_family = "monospace",
    font_size = 7
  )
  pz_annotate_caption(page, "On every page", side = "top")
  expect_equal(page_caption(page)$color, "white")
  expect_equal(page_caption(page)$font_family, "monospace")
  expect_equal(page_caption(page)$font_size, 20)
  pz_stage_annotate(page, font_family = "serif")
  expect_equal(page_caption(page)$font_family, "monospace")
  pz_nav_reload(page)
  expect_equal(page_caption(page)$text, "On every page")
  top <- withr::local_tempfile(fileext = ".png")
  pz_screenshot(page, top)
  image <- png::readPNG(top)
  expect_true(any(
    image[1:round(dim(image)[1] * 0.15), round(dim(image)[2] / 2), 1] < 0.4
  ))
  expect_error(pz_annotate_caption(page, ""), "text.*empty string")
  expect_error(
    pz_annotate_caption(page, "x", color = ""),
    "color.*empty string"
  )
  expect_error(
    pz_annotate_caption(page, "x", font_family = ""),
    "font_family.*empty string"
  )
  expect_error(
    pz_annotate_caption(page, "x", font_size = 0),
    "font_size.*greater than 0"
  )
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
  pz_camera(page, pz_frame("#box", zoom = 1.5), duration = 0.12)
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
    image <- av_video_images_quiet(out, destdir = frames, format = "png")
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
  skip_if_no_av()
  page <- local_record_page()
  out <- withr::local_tempfile(fileext = ".mp4")
  pz_record_start(page, out, hold = c(0, 0))
  defer_record_stop(page)
  page |>
    pz_annotate("#box", reveal = "fade") |>
    pz_annotate_caption("Hello")
  rec <- page_recorder(page)
  before <- length(rec$captions)
  captions_at_pump <- NULL
  clear_duration <- NULL
  real_pump <- annotate_pump
  local_mocked_bindings(
    annotate_pump = function(ctx, duration) {
      captions_at_pump <<- page_recorder(ctx$page)$captions
      clear_duration <<- duration
      real_pump(ctx, duration)
    }
  )

  pz_annotate_clear(page)
  expect_gt(clear_duration, 0)
  expect_length(captions_at_pump, before + 1L)
  expect_null(captions_at_pump[[length(captions_at_pump)]]$caption)
  expect_identical(rec$captions, captions_at_pump)
  pz_record_stop(page)
})

test_that("a caption lasting a tick or two is visible in the encoded frames", {
  skip_if_no_av()
  skip_if_not_installed("png")
  page <- local_record_page()
  out <- withr::local_tempfile(fileext = ".mp4")
  pz_record_start(page, out, fps = 10, hold = c(0, 0))
  defer_record_stop(page)
  pz_wait(page, 0.3)
  pz_annotate_caption(page, "BLINK")
  pz_wait(page, 0.12)
  pz_annotate_clear(page, "caption")
  pz_wait(page, 0.3)
  pz_record_stop(page)
  decoded <- withr::local_tempfile()
  frames <- av_video_images_quiet(out, destdir = decoded, format = "png")
  dark <- vapply(
    frames,
    function(f) {
      img <- png::readPNG(f)
      rows <- round(dim(img)[1] * 0.8):dim(img)[1]
      any(img[rows, , 1] < 0.4)
    },
    logical(1)
  )
  expect_true(any(dark))
  expect_false(dark[[1]])
})

test_that("key callout windows replace and expire on output ticks", {
  rec <- new_recorder(
    tempfile(fileext = ".mp4"),
    "mp4",
    10,
    NULL,
    c(0, 0),
    FALSE,
    NULL
  )
  rec$keypresses <- list(
    list(vt = 0.1, last = 0.1, style = "words", keys = list("first")),
    list(vt = 0.6, last = 0.6, style = "mac", keys = list("second"))
  )
  sampled <- list(vts = seq(0, 2, by = 0.1), n_ticks = 21L)
  windows <- key_callout_windows(rec, sampled)
  expect_equal(vapply(windows, `[[`, numeric(1), "start"), c(0.1, 0.6))
  expect_equal(vapply(windows, `[[`, numeric(1), "end"), c(0.6, 1.9))
  expect_equal(windows[[2]]$fade_start, 1.6)
  expect_identical(windows[[2]]$keys, list("second"))

  rec$keypresses <- list(list(
    vt = 0,
    last = 0,
    style = "words",
    keys = list("held")
  ))
  sampled <- list(
    vts = c(0, 0, 0, 0.1, 0.2, seq(0.3, 2, by = 0.1)),
    n_ticks = 23L
  )
  windows <- key_callout_windows(rec, sampled)
  expect_equal(windows[[1]]$start, 0)
  expect_equal(windows[[1]]$fade_start, 1)
  expect_equal(windows[[1]]$end, 1.3)
})

test_that("a vector key callout expires from its last key", {
  rec <- new_recorder(
    tempfile(fileext = ".mp4"),
    "mp4",
    10,
    NULL,
    c(0, 0),
    FALSE,
    NULL
  )
  rec$keypresses <- list(
    list(vt = 0.2, last = 0.7, style = "words", keys = list("a", "b"))
  )
  sampled <- list(vts = seq(0, 3, by = 0.1), n_ticks = 31L)
  windows <- key_callout_windows(rec, sampled)
  expect_equal(windows[[1]]$start, 0.2)
  expect_equal(windows[[1]]$fade_start, 1.7)
  expect_equal(windows[[1]]$end, 2.0)
})

test_that("decoded keycaps stack above a burned bottom caption", {
  skip_if_no_av()
  skip_if_not_installed("png")
  page <- local_page(
    record_fixture_file(),
    width = 320,
    height = 240,
    scale = 2
  )
  path <- withr::local_tempfile(fileext = ".mp4")
  pz_annotate_caption(page, "CAPTION")
  pz_record_start(page, path, fps = 10, scale = 0.5, hold = c(0.1, 1.8))
  defer_record_stop(page)
  pz_act_press(page, "Mod+k", show_keys = "both")
  pz_record_stop(page)
  decoded <- tempfile("keys-stacked-")
  withr::defer(unlink(decoded, recursive = TRUE))
  files <- av_video_images_quiet(path, destdir = decoded, format = "png")
  expect_gt(length(files), 12)
  active <- png::readPNG(files[[5]])
  expired <- png::readPNG(files[[length(files) - 2L]])
  center <- round(dim(active)[2] / 2)
  caption_rows <- which(
    expired[, center, 1] < 0.5 &
      seq_len(dim(expired)[1]) > dim(expired)[1] * 0.65
  )
  expect_gt(length(caption_rows), 5)
  key_rows <- which(active[, center, 1] < expired[, center, 1] - 0.15)
  expect_gt(length(key_rows), 5)
  expect_lt(max(key_rows), min(caption_rows))
  expect_equal(
    active[1:round(dim(active)[1] / 2), , ],
    expired[1:round(dim(expired)[1] / 2), , ],
    tolerance = 0.2
  )
})

test_that("keycap ticks clip fades without resurrecting replaced callouts", {
  rec <- new_recorder(
    tempfile(fileext = ".mp4"),
    "mp4",
    10,
    NULL,
    c(0, 0),
    FALSE,
    NULL
  )
  rec$keypresses <- list(
    list(vt = 0.01, last = 0.04, style = "words", keys = list("old")),
    list(vt = 0.08, last = 0.08, style = "both", keys = list("new")),
    list(vt = 0.08, last = 0.08, style = "mac", keys = list("newest"))
  )
  sampled <- list(vts = seq(0, 0.4, by = 0.1), n_ticks = 5L)
  windows <- key_callout_windows(rec, sampled)
  expect_length(windows, 1L)
  expect_identical(windows[[1]]$keys, list("newest"))
  expect_equal(windows[[1]]$start, 0.1)
  expect_equal(windows[[1]]$end, 0.5)
  expect_gt(windows[[1]]$fade_start, windows[[1]]$end)
  rec$keypresses <- list(list(
    vt = 0.5,
    last = 0.5,
    style = "words",
    keys = list("late")
  ))
  expect_length(key_callout_windows(rec, sampled), 0L)

  graph <- screen_filter(
    rec,
    sampled,
    list(vfilter = "scale=320:240"),
    list(
      list(
        file = "caption-1.png",
        start = 0,
        end = 0.5,
        fade_in = NULL,
        fade_start = NULL
      ),
      list(
        file = "key-1.png",
        start = 0.1,
        end = 0.5,
        fade_in = NULL,
        fade_start = NULL
      )
    )
  )
  expect_match(graph, "[in]scale=320:240[b0]", fixed = TRUE)
  expect_match(graph, "movie=caption-1.png:loop=1", fixed = TRUE)
  expect_match(graph, "movie=key-1.png:loop=1", fixed = TRUE)
  expect_lt(
    regexpr("movie=caption", graph)[[1]],
    regexpr("movie=key", graph)[[1]]
  )
  expect_false(grepl("movie=/", graph, fixed = TRUE))
})

test_that("keys burn into WebM VTT-only and uncaptioned GIF", {
  skip_if_no_av()
  skip_if_not_installed("png")
  skip_if_not_installed("gifski")
  page <- local_page(
    record_fixture_file(),
    width = 320,
    height = 240,
    scale = 2
  )
  video <- withr::local_tempfile(fileext = ".webm")
  pz_annotate_caption(page, "SUBTITLE")
  pz_record_start(page, video, captions = "vtt", fps = 8, hold = c(0.1, 1.5))
  defer_record_stop(page)
  pz_act_press(page, "Enter", show_keys = "words")
  pz_record_stop(page)
  withr::defer(unlink(sub("\\.webm$", ".vtt", video)))
  expect_true(file.exists(sub("\\.webm$", ".vtt", video)))
  dest <- tempfile("key-webm-")
  withr::defer(unlink(dest, recursive = TRUE))
  frames <- av_video_images_quiet(video, destdir = dest, format = "png")
  active <- png::readPNG(frames[[4]])
  expect_true(any(
    active[round(dim(active)[1] * 0.78):dim(active)[1], , 1] < 0.4
  ))
  expired <- png::readPNG(tail(frames, 1))
  expect_true(all(
    expired[round(dim(expired)[1] * 0.78):dim(expired)[1], , 1] > 0.8
  ))
  pz_annotate_clear(page, "caption")

  gif <- withr::local_tempfile(fileext = ".gif")
  pz_record_start(page, gif, fps = 8, scale = 0.5, hold = c(0.1, 1.5))
  defer_record_stop(page)
  pz_act_press(page, "Tab", show_keys = "mac")
  pz_record_stop(page)
  expect_gt(recorded_video_info(gif)$duration, 1.2)
  dest <- tempfile("key-gif-")
  withr::defer(unlink(dest, recursive = TRUE))
  frames <- av_video_images_quiet(gif, destdir = dest, format = "png")
  expect_gt(length(frames), 1L)
  dark <- vapply(
    frames,
    function(file) {
      image <- png::readPNG(file)
      any(image[round(dim(image)[1] * 0.75):dim(image)[1], , 1] < 0.4)
    },
    logical(1)
  )
  expect_true(any(dark))
})

test_that("a caption narrower than 80% of the output stays on one line", {
  page <- local_record_page()
  path <- withr::local_tempfile(fileext = ".png")
  caption <- list(
    text = "Open help without showing the note",
    side = "bottom",
    color = "white",
    font_family = "sans-serif",
    font_size = 20
  )
  height <- caption_render(page, caption, 720, 480, 1.2, path)
  line <- 20 * 1.2 * 1.35 + 2 * 9 * 1.2
  expect_lt(height, line * 1.5)
})

test_that("a keycap row narrower than 80% of the output stays on one line", {
  page <- local_record_page()
  path <- withr::local_tempfile(fileext = ".png")
  groups <- list(
    c("Ctrl", "Shift", "K"),
    c("Ctrl", "Shift", "P"),
    c("Enter")
  )
  wide <- key_callout_render(page, groups, 720, 480, 1, 24, "sans-serif", path)
  single <- key_callout_render(
    page,
    list("K"),
    720,
    480,
    1,
    24,
    "sans-serif",
    path
  )
  expect_lt(wide, single * 1.5)
})

test_that("caption literal styles ignore staged accent and size and reject NULL", {
  page <- local_page()
  pz_stage_annotate(page, color = "red", font_size = 32)
  pz_annotate_caption(page, "Note")
  omitted <- page_caption(page)
  pz_annotate_caption(page, "Note", color = "white", font_size = 20)
  expect_identical(page_caption(page), omitted)
  expect_identical(omitted$color, "white")
  expect_equal(omitted$font_size, 20)
  expect_error(pz_annotate_caption(page, "Note", color = NULL), "color")
  expect_error(pz_annotate_caption(page, "Note", font_size = NULL), "font_size")
})

test_that("key callouts render in the family captured at press time", {
  page <- local_page()
  # Silkscreen 400 (latin subset), OFL 1.1 -- see fixtures/fonts/
  silkscreen <- pz_font_file(
    "Silkscreen",
    test_path("fixtures", "fonts", "silkscreen-400.woff2")
  )
  pz_stage_fonts(page, silkscreen)
  groups <- list(list("Ctrl", "S"))
  staged_png <- withr::local_tempfile(fileext = ".png")
  fallback_png <- withr::local_tempfile(fileext = ".png")

  key_callout_render(
    page,
    groups,
    400,
    300,
    1,
    24,
    '"Silkscreen", sans-serif',
    staged_png
  )
  key_callout_render(page, groups, 400, 300, 1, 24, "sans-serif", fallback_png)

  expect_false(identical(
    readBin(staged_png, "raw", file.size(staged_png)),
    readBin(fallback_png, "raw", file.size(fallback_png))
  ))
})

test_that("a throwing render script fails with a paparazzi error", {
  page <- local_record_page()
  path <- withr::local_tempfile(fileext = ".png")
  expect_error(
    screen_render(
      page,
      400,
      300,
      path,
      "(() => { throw new Error('boom'); })()"
    ),
    "boom",
    class = "paparazzi_error_js"
  )
  expect_false(file.exists(path))
})

test_that("a shared render session serves multiple overlays", {
  page <- local_record_page()
  screen <- screen_open(page, 400, 300)
  withr::defer(screen$close())
  caption <- list(
    text = "Note",
    side = "bottom",
    color = "white",
    font_family = "sans-serif",
    font_size = 20
  )
  first <- withr::local_tempfile(fileext = ".png")
  second <- withr::local_tempfile(fileext = ".png")
  height <- caption_render(page, caption, 400, 300, 1, first, session = screen)
  expect_gt(height, 0)
  expect_true(file.exists(first))
  height <- caption_render(page, caption, 400, 300, 1, second, session = screen)
  expect_gt(height, 0)
  expect_true(file.exists(second))
})

test_that("key callout windows carry the font_family recorded at press time", {
  rec <- list(fps = 10)
  rec$keypresses <- list(list(
    vt = 0,
    last = 0,
    style = "words",
    font_family = '"Silkscreen", sans-serif',
    keys = list("a")
  ))
  sampled <- list(vts = seq(0, 1, by = 0.1), n_ticks = 11L)
  windows <- key_callout_windows(rec, sampled)
  expect_length(windows, 1)
  expect_equal(windows[[1]]$font_family, '"Silkscreen", sans-serif')
})

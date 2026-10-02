record_fixture_file <- function() {
  test_path("fixtures", "record.html")
}

local_record_page <- function(.env = parent.frame()) {
  local_page(record_fixture_file(), .env = .env)
}

# Classic scrollbars reduce the visual viewport; zoom changes its pixel density.
record_viewport_png_size <- function(page) {
  size <- unlist(pz_js(
    page,
    "[window.visualViewport.width, window.visualViewport.height]"
  ))
  as.integer(round(size * page_dpr(page)))
}

expect_frame_files_size <- function(files, size) {
  dims <- matrix(
    unlist(lapply(files, png_dimensions), use.names = FALSE),
    ncol = 2,
    byrow = TRUE
  )
  testthat::expect_equal(
    dims,
    matrix(size, nrow = length(files), ncol = 2, byrow = TRUE)
  )
}

# Register after a keep_frames unlink defer: defers run LIFO, so the
# recorder stops before its frames dir goes, even when the test fails
# mid-recording. A late capture would otherwise write into the deleted dir.
# Best-effort: a stop that fails in teardown must not mask the test's error.
defer_record_stop <- function(page, .env = parent.frame()) {
  withr::defer(
    {
      rec <- page_recorder(page)
      if (!is.null(rec) && rec$active) try(pz_record_stop(page), silent = TRUE)
    },
    envir = .env
  )
}

skip_if_no_av <- function() {
  testthat::skip_if_not_installed("av")
}

# av_video_images() forces verbose logging in its encoder. Capture that native
# stderr noise, but replay it on failure so FFmpeg diagnostics remain visible.
av_video_images_quiet <- function(...) {
  result <- NULL
  diagnostics <- utils::capture.output(
    result <- tryCatch(av::av_video_images(...), error = identity),
    type = "message"
  )

  if (inherits(result, "error")) {
    if (length(diagnostics)) {
      cat(diagnostics, sep = "\n", file = stderr())
    }
    stop(result)
  }

  result
}

# Media info for assertions: duration (seconds), dimensions, codec,
# and frame count from the first video stream.
recorded_video_info <- function(path) {
  info <- av::av_media_info(path)
  list(
    duration = info$duration,
    width = info$video$width,
    height = info$video$height,
    codec = info$video$codec,
    frames = info$video$frames,
    framerate = info$video$framerate
  )
}

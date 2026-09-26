record_fixture_file <- function() {
  test_path("fixtures", "record.html")
}

local_record_page <- function(.env = parent.frame()) {
  local_page(record_fixture_file(), .env = .env)
}

skip_if_no_av <- function() {
  testthat::skip_if_not_installed("av")
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

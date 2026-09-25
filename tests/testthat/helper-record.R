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

# GIF dimensions from the logical screen descriptor (6-byte header,
# then little-endian uint16 width and height), for assertions when av
# is unavailable.
gif_dimensions <- function(path) {
  gif <- readBin(path, "raw", n = 10)
  stopifnot(identical(gif[1:3], charToRaw("GIF")))
  width <- readBin(gif[7:8], "integer", size = 2, signed = FALSE, endian = "little")
  height <- readBin(gif[9:10], "integer", size = 2, signed = FALSE, endian = "little")
  c(as.integer(width), as.integer(height))
}

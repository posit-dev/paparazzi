#' Record a page interaction
#'
#' @description
#' `pz_record_start()` begins recording the page to a video or GIF;
#' `pz_record_stop()` ends the recording, encodes it, and writes the
#' file. `pz_record_pause()`/`pz_record_resume()` cut stretches out of
#' the recording, and [pz_record_hold()] lingers on the current frame.
#' [pz_record()] is the block form: it records for the duration of an
#' expression and stops on exit, including on error.
#'
#' The output format comes from the `path` extension: `.mp4` (h264),
#' `.webm`, or `.gif`. Frames are captured at the page's current device
#' pixel ratio and resampled to a constant `fps` at encode time, so a
#' skipped capture shows up as a repeated frame rather than a timing
#' shift.
#'
#' @section How recording works:
#' A timer on chromote's private event loop captures a full-viewport
#' PNG roughly every `1/fps` seconds using asynchronous browser calls.
#' The timer fires while that loop is pumped -- during every synchronous
#' paparazzi/chromote call and during [pz_wait()] -- so recording
#' proceeds while a chain of steps runs. **Long-running plain R code
#' between steps freezes the recording**: the timer can't fire while R
#' is busy, and the missed stretch collapses to a held frame.
#'
#' Stopping always captures one final frame of the page state at
#' `pz_record_stop()`, so a change made just before the stop still
#' appears; the last-frame hold repeats that final frame.
#'
#' Cropping never happens at capture time. A [pz_frame()] spec (or the
#' page default from [pz_stage_frame()]) is measured once -- at the
#' start for `pz_frame(when = "start")`, at the end for the default
#' `when = "stop"`, i.e. against the final layout -- and the crop is
#' applied to every frame during encoding. `.mp4` dimensions are
#' rounded down to multiples of 4 and `.webm` to even pixels; `.gif`
#' keeps whole pixels.
#'
#' `.mp4` and `.webm` recordings require \pkg{av}. All `.gif` recordings
#' require \pkg{gifski}; framed GIFs also require \pkg{png} to crop the
#' captured frames before encoding. Packages are checked at
#' `pz_record_start()`.
#'
#' @inheritParams pz_click
#' @param path Output file path; the extension (`.mp4`, `.webm`, or
#'   `.gif`) selects the format. An existing file is overwritten.
#' @param method Capture method. Only `"poll"` is implemented;
#'   `"screencast"` (`Page.startScreencast`) is reserved.
#' @param frame Framing applied at encode time: `NULL` (the default)
#'   uses the page's default framing set with [pz_stage_frame()] if
#'   there is one, else records the full viewport; a [pz_frame()] spec
#'   replaces any default entirely; `FALSE` disables framing.
#' @param fps Output frame rate. Captures are resampled to this
#'   constant rate at encode time.
#' @param scale Output size: `NULL` (the default) keeps the captured
#'   size; a number up to 4 is a scale factor; a larger number is the
#'   output width in pixels (height scales proportionally).
#' @param hold Seconds to hold the first and last frame,
#'   `c(first, last)`.
#' @param keep_frames Keep the captured PNG frames in a
#'   `<name>_frames/` directory next to `path`. Otherwise frames are
#'   written to a temporary directory and deleted after encoding.
#'
#' @return `ctx`, invisibly.
#'
#' @seealso [pz_record()], [pz_record_hold()], [pz_frame()],
#'   [pz_stage_frame()]
#'
#' @examplesIf rlang::is_interactive() && !is.null(suppressMessages(chromote::find_chrome())) && rlang::is_installed("av")
#' page <- pz_open(pz_example("tasks"), width = 800, height = 600)
#' path <- file.path(tempdir(), "help.mp4")
#'
#' # Record the help panel opening, cropped to the page's card
#' page |>
#'   pz_record_start(path, frame = pz_frame("main")) |>
#'   pz_click("#toggle-help") |>
#'   pz_expect_visible(target = "#help") |>
#'   pz_record_stop()
#' file.exists(path)
#' pz_close(page)
#'
#' @export
pz_record_start <- function(
  ctx,
  path,
  ...,
  method = c("poll", "screencast"),
  frame = NULL,
  fps = 15,
  scale = NULL,
  hold = c(0.5, 1),
  keep_frames = FALSE
) {
  check_context(ctx)
  check_dots_empty()
  check_string(path)
  method <- arg_match(method)
  if (identical(method, "screencast")) {
    cli::cli_abort(
      '{.code method = "screencast"} is not supported yet; use {.code method = "poll"}.',
      class = "paparazzi_error_unsupported"
    )
  }
  check_number_decimal(fps, min = 1, max = 120)
  check_number_decimal(scale, min = 0, allow_null = TRUE)
  check_bool(keep_frames)
  hold <- check_record_hold(hold)
  format <- record_format(path)
  frame <- frame_effective(ctx, frame)
  record_check_packages(format, needs_crop = inherits(frame, "paparazzi_frame"))

  page <- ctx$page
  if (!is.null(page_recorder(page))) {
    cli::cli_abort(
      "This page is already recording; call {.fn pz_record_stop} first.",
      class = "paparazzi_error_record"
    )
  }

  rec <- new_recorder(
    path = path,
    format = format,
    fps = fps,
    scale = scale,
    hold = hold,
    keep_frames = keep_frames,
    frame = frame
  )
  # Retain the framing context the recording started in: a when =
  # "stop" frame is measured against the final layout, but resolved
  # from this ctx -- its scope -- not from wherever pz_record_stop()
  # is called. An unscoped start context behaves exactly as before.
  if (inherits(frame, "paparazzi_frame")) {
    rec$frame_ctx <- ctx
  }
  # Measured before the first frame for when = "start"; for "stop" the
  # crop is measured against the final layout in pz_record_stop().
  if (inherits(frame, "paparazzi_frame") && identical(frame$when, "start")) {
    rec$crop <- record_crop_box(rec$frame_ctx, frame)
  }
  rec$frames_dir <- record_frames_dir(path, keep_frames)

  page_set_recorder(page, rec)
  # Fire the first tick as soon as the loop pumps so short recordings
  # still get an early frame; ticks re-arm at 1/fps from then on. The
  # tick closure carries its recorder so it can't adopt a later one.
  later::later(
    function() record_tick(page, rec),
    delay = 0,
    loop = page$child_loop
  )
  invisible(ctx)
}

#' Stop a recording and write the video
#'
#' Ends the recording started with [pz_record_start()], encodes the
#' captured frames, and writes the file given to `pz_record_start()`.
#'
#' @inheritParams pz_click
#'
#' @return `ctx`, invisibly.
#'
#' @examplesIf rlang::is_interactive() && !is.null(suppressMessages(chromote::find_chrome())) && rlang::is_installed("av")
#' page <- pz_open(pz_example("tasks"))
#' path <- file.path(tempdir(), "done.gif")
#' page |>
#'   pz_record_start(path, frame = pz_frame(".task-list", pad = 8)) |>
#'   pz_click(pz_loc(".task-done", which = "first")) |>
#'   pz_record_stop()
#' file.exists(path)
#' pz_close(page)
#'
#' @export
pz_record_stop <- function(ctx) {
  check_context(ctx)
  page <- ctx$page
  rec <- check_recording(ctx)
  withr::defer({
    page_set_recorder(page, NULL)
    if (!rec$keep_frames) {
      unlink(rec$frames_dir, recursive = TRUE)
    }
  })

  # Deactivate first so ticks scheduled by the recording stop re-arming
  # and can't issue captures while the stop settles its own.
  rec$active <- FALSE
  rec$vt_end <- rec_vt(rec)

  # A capture issued before the stop may still be in flight; it belongs
  # to the recording, so let it settle before the final capture.
  tryCatch(
    record_wait_pending(rec, page, "the in-flight frame capture"),
    paparazzi_error_timeout = function(e) {
      rec$pending <- NULL
      record_error(rec, e)
    }
  )

  # Capture and await the page state at stop: the final state must be in
  # the video (the last-frame hold repeats it, not an older frame), and
  # an immediate stop gets its one frame here. vt is pinned to vt_end so
  # the frame is kept (post-vt_end captures are dropped).
  record_capture(rec, page, rec$vt_end)
  tryCatch(
    pz_poll(
      function() is.null(rec$pending),
      timeout = min(page$default_timeout, 5),
      loop = page$child_loop,
      what = "the final frame capture"
    ),
    paparazzi_error_timeout = function(e) {
      rec$pending <- NULL
      record_error(rec, e)
    }
  )

  if (length(rec$files) == 0L) {
    msg <- "No frames were captured."
    if (!is.null(rec$first_error)) {
      msg <- c(msg, i = "First capture error: {rec$first_error}")
    }
    cli::cli_abort(msg, class = "paparazzi_error_record")
  }

  if (
    inherits(rec$frame, "paparazzi_frame") && identical(rec$frame$when, "stop")
  ) {
    # The final-layout measurement resolves from the retained start
    # context, so the crop covers the scope the recording began in
    # even when stop is called from a different one.
    rec$crop <- record_crop_box(rec$frame_ctx, rec$frame)
  }
  record_encode(rec)
  # The staging hook: an auto cursor under cursor = NULL belonged to the
  # recording, so it leaves the page now that stills would catch it.
  stage_record_stopped(ctx)
  invisible(ctx)
}

#' Pause and resume a recording
#'
#' `pz_record_pause()` cuts the stretch up to the next
#' `pz_record_resume()` out of the recording: no frames are captured
#' and the video clock stops, so the pause leaves no trace in the
#' output.
#'
#' @inheritParams pz_click
#'
#' @return `ctx`, invisibly.
#'
#' @examplesIf rlang::is_interactive() && !is.null(suppressMessages(chromote::find_chrome())) && rlang::is_installed("av")
#' page <- pz_open(pz_example("tasks"))
#' path <- file.path(tempdir(), "add-task.mp4")
#' page |>
#'   pz_record_start(path) |>
#'   pz_click("#task-title") |>
#'   pz_record_pause() |>
#'   # Filling in the form is cut from the video
#'   pz_set_value("Buy milk", target = "#task-title") |>
#'   pz_set_value("high", target = "#task-priority") |>
#'   pz_record_resume() |>
#'   pz_click("#add-task") |>
#'   pz_expect_count(8, target = ".task") |>
#'   pz_record_stop()
#' pz_close(page)
#'
#' @export
pz_record_pause <- function(ctx) {
  check_context(ctx)
  rec <- check_recording(ctx)
  if (rec$paused) {
    return(invisible(ctx))
  }
  rec$vt_base <- rec_vt(rec)
  rec$paused <- TRUE
  invisible(ctx)
}

#' @rdname pz_record_pause
#' @export
pz_record_resume <- function(ctx) {
  check_context(ctx)
  rec <- check_recording(ctx)
  if (!rec$paused) {
    return(invisible(ctx))
  }
  rec$active_since <- rec_now()
  rec$paused <- FALSE
  invisible(ctx)
}

#' Hold the current frame while recording
#'
#' Lingers on the current frame for `seconds` in the output video.
#' Unlike [pz_wait()], no real time passes: the hold is inserted into
#' the video timeline at encode time. When the page is not recording
#' this is a no-op, so debugging a chain with the recording commented
#' out doesn't pay for video-only pauses.
#'
#' @inheritParams pz_click
#' @param seconds Seconds to hold the frame in the output.
#'
#' @return `ctx`, invisibly.
#'
#' @examplesIf rlang::is_interactive() && !is.null(suppressMessages(chromote::find_chrome())) && rlang::is_installed("av")
#' page <- pz_open(pz_example("tasks"))
#'
#' # Without a recording, pz_record_hold() returns straight away
#' system.time(pz_record_hold(page, 2))
#'
#' path <- file.path(tempdir(), "help.mp4")
#' page |>
#'   pz_record_start(path) |>
#'   pz_click("#toggle-help") |>
#'   # Give viewers a second to read the help text
#'   pz_record_hold(1) |>
#'   pz_record_stop()
#' pz_close(page)
#'
#' @export
pz_record_hold <- function(ctx, seconds) {
  check_context(ctx)
  check_number_decimal(seconds, min = 0)
  rec <- page_recorder(ctx$page)
  if (is.null(rec) || !rec$active) {
    return(invisible(ctx))
  }
  rec$holds <- c(rec$holds, list(list(vt = rec_vt(rec), seconds = seconds)))
  invisible(ctx)
}

#' Record a block of code
#'
#' The block form of [pz_record_start()]: starts recording, evaluates
#' the embraced expression `code`, and stops and encodes on exit --
#' including on error, so a failed run still produces the video up to
#' the failure. Returns `ctx` invisibly (not the block's value), so the
#' chain continues after the recording.
#'
#' @inheritParams pz_record_start
#' @param code An expression to evaluate while recording.
#' @param ... Passed to [pz_record_start()].
#'
#' @return `ctx`, invisibly.
#'
#' @examplesIf rlang::is_interactive() && !is.null(suppressMessages(chromote::find_chrome())) && rlang::is_installed("av")
#' page <- pz_open(pz_example("tasks"))
#' path <- file.path(tempdir(), "add-task.mp4")
#'
#' # The recording stops and is written when the block exits, even on error
#' page |>
#'   pz_record(path, {
#'     page |>
#'       pz_type("Buy milk", target = "#task-title") |>
#'       pz_click("#add-task") |>
#'       pz_expect_count(8, target = ".task")
#'   }) |>
#'   pz_screenshot(file.path(tempdir(), "after.png"))
#' file.exists(path)
#' pz_close(page)
#'
#' @export
pz_record <- function(ctx, path, code, ...) {
  check_context(ctx)
  expr <- substitute(code)
  env <- parent.frame()
  pz_record_start(ctx, path, ...)
  # Stop on any exit; an error from the block wins over a stop error
  # (e.g. a run that failed before the first frame was captured).
  code_error <- NULL
  withr::defer({
    stop_error <- tryCatch(pz_record_stop(ctx), error = function(e) e)
    if (!is.null(code_error)) {
      stop(code_error)
    } else if (inherits(stop_error, "error")) {
      stop(stop_error)
    }
  })
  tryCatch(eval(expr, env), error = function(e) code_error <<- e)
  invisible(ctx)
}

# The recorder state lives in the page's reserved private$recorder_
# slot (R/context.R). R6 privates are reachable only through the
# object's enclos environment; these helpers are the single access
# point, matching page_frame()/page_set_frame() in R/frame.R.
page_recorder <- function(page) {
  page$.__enclos_env__$private$recorder_
}

page_set_recorder <- function(page, rec) {
  page$.__enclos_env__$private$recorder_ <- rec
  invisible(page)
}

# A timed-out wait fails the change rather than proceeding: the capture
# may still be running in Chrome and would undo the change when it ends.
record_hold <- function(page, code, call = caller_env()) {
  rec <- page_recorder(page)
  if (is.null(rec) || !rec$active) {
    return(code)
  }
  held <- rec$held
  rec$held <- TRUE
  on.exit(rec$held <- held)
  record_wait_pending(
    rec,
    page,
    "the in-flight frame capture before changing the device metrics",
    call = call
  )
  code
}

record_wait_pending <- function(rec, page, what, call = caller_env()) {
  if (is.null(rec$pending)) {
    return(invisible(NULL))
  }
  pz_poll(
    function() is.null(rec$pending),
    timeout = page$default_timeout,
    loop = page$child_loop,
    what = what,
    call = call
  )
}

new_recorder <- function(
  path,
  format,
  fps,
  scale,
  hold,
  keep_frames,
  frame
) {
  rec <- new.env(parent = emptyenv())
  rec$path <- path
  rec$format <- format
  rec$fps <- fps
  rec$scale <- scale
  rec$hold_first <- hold[1]
  rec$hold_last <- hold[2]
  rec$keep_frames <- keep_frames
  rec$frame <- if (inherits(frame, "paparazzi_frame")) frame else NULL
  rec$crop <- NULL
  rec$frame_ctx <- NULL
  rec$frames_dir <- NULL
  rec$times <- numeric(0)
  rec$files <- character(0)
  rec$holds <- list()
  # Video clock: vt = vt_base + (now - active_since) while running.
  # Pausing folds the elapsed stretch into vt_base, so paused time
  # never reaches the video timeline.
  rec$vt_base <- 0
  rec$active_since <- rec_now()
  rec$active <- TRUE
  rec$paused <- FALSE
  rec$held <- FALSE
  rec$pending <- NULL
  rec$vt_end <- NULL
  rec$ticks <- 0L
  rec$n_errors <- 0L
  rec$first_error <- NULL
  rec
}

rec_now <- function() {
  unname(proc.time()[["elapsed"]])
}

rec_vt <- function(rec) {
  if (rec$paused) {
    return(rec$vt_base)
  }
  rec$vt_base + (rec_now() - rec$active_since)
}

check_recording <- function(ctx, call = caller_env()) {
  rec <- page_recorder(ctx$page)
  if (is.null(rec) || !rec$active) {
    cli::cli_abort(
      "This page is not recording; call {.fn pz_record_start} first.",
      class = "paparazzi_error_record",
      call = call
    )
  }
  rec
}

check_record_hold <- function(
  hold,
  arg = caller_arg(hold),
  call = caller_env()
) {
  if (
    !is.numeric(hold) ||
      length(hold) != 2L ||
      anyNA(hold) ||
      !all(is.finite(hold)) ||
      any(hold < 0)
  ) {
    cli::cli_abort(
      "{.arg {arg}} must be two non-negative numbers, {.code c(first, last)} seconds.",
      class = "paparazzi_error_input",
      call = call
    )
  }
  as.double(hold)
}

record_format <- function(path, call = caller_env()) {
  ext <- tolower(tools::file_ext(path))
  if (!ext %in% c("mp4", "webm", "gif")) {
    cli::cli_abort(
      "{.arg path} must end in {.val .mp4}, {.val .webm}, or {.val .gif}, not {.val {paste0('.', ext)}}.",
      class = "paparazzi_error_input",
      call = call
    )
  }
  ext
}

record_check_packages <- function(format, needs_crop, call = caller_env()) {
  if (format %in% c("mp4", "webm")) {
    rlang::check_installed(
      "av",
      reason = paste0("to record .", format, " video.")
    )
    return(invisible())
  }
  rlang::check_installed("gifski", reason = "to record .gif files.")
  if (needs_crop) {
    rlang::check_installed("png", reason = "to crop framed .gif recordings.")
  }
  invisible()
}

record_frames_dir <- function(path, keep_frames) {
  dir <- if (keep_frames) {
    paste0(tools::file_path_sans_ext(path), "_frames")
  } else {
    tempfile("paparazzi-frames-")
  }
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  dir
}

# One timer tick on the child loop: re-arm, then issue an async capture
# unless paused, held for a device change, or one is still in flight
# (a skipped tick repeats a frame after resampling). The tick
# runs inside run_now() during whatever pumped the loop, so its errors
# are caught and counted on the recorder instead of escaping into an
# unrelated call. Each scheduled tick is bound to the recorder that
# scheduled it: one identity check against the page's current recorder
# kills ticks left behind by a stopped recording, which would otherwise
# adopt a newer one and double the capture chain after a quick restart.
record_tick <- function(page, rec = page_recorder(page)) {
  if (is.null(rec) || !rec$active) {
    return(invisible(FALSE))
  }
  if (!identical(rec, page_recorder(page))) {
    return(invisible(FALSE))
  }
  later::later(
    function() record_tick(page, rec),
    delay = 1 / rec$fps,
    loop = page$child_loop
  )
  rec$ticks <- rec$ticks + 1L
  if (rec$paused || rec$held || !is.null(rec$pending)) {
    return(invisible(TRUE))
  }
  record_capture(rec, page, rec_vt(rec))
  invisible(TRUE)
}

# Synchronous teardown for the page-lifecycle close path (context.R):
# the closed session's child loop may never pump again, so a later
# tick can't be relied on to clean up. Deactivates the recorder,
# clears the recorder slot, and drops the temp frames dir; kept frames
# survive on purpose. An in-flight capture is left to resolve
# harmlessly on the discarded recorder.
record_page_closed <- function(page) {
  rec <- page_recorder(page)
  if (is.null(rec)) {
    return(invisible(FALSE))
  }
  rec$active <- FALSE
  page_set_recorder(page, NULL)
  if (!rec$keep_frames && !is.null(rec$frames_dir)) {
    unlink(rec$frames_dir, recursive = TRUE)
  }
  invisible(TRUE)
}

# Issue one async capture on the page: the tick's periodic capture and
# the stop-time final frame both come through here. The pending slot
# prevents overlapping captures; callbacks clear it when chromote
# invokes them on the child loop. A synchronous failure (e.g. a closed
# session) clears it and lands in the recorder's error tally instead.
# Unclipped surface captures at DPR 2 can remap concurrent mouse input
# to half its coordinates; a viewport clip avoids that Chrome path while
# retaining full-resolution PNGs for the encode-time crop.
record_capture <- function(rec, page, vt) {
  index <- length(rec$files) + 1L
  pending <- new.env(parent = emptyenv())
  pending$vt <- vt
  pending$file <- file.path(rec$frames_dir, sprintf("frame-%06d.png", index))
  rec$pending <- pending
  # Both stages share one timeout budget, the same budget
  # pz_record_stop() allows an in-flight capture to settle.
  deadline <- Sys.time() + page$default_timeout
  remaining <- function() {
    max(0.1, as.numeric(difftime(deadline, Sys.time(), units = "secs")))
  }
  tryCatch(
    page$session$Page$getLayoutMetrics(
      wait_ = FALSE,
      timeout_ = remaining(),
      callback_ = function(metrics) {
        tryCatch(
          {
            v <- metrics$cssVisualViewport
            clip <- list(
              x = max(v$pageX, 0),
              y = max(v$pageY, 0),
              width = v$clientWidth,
              height = v$clientHeight,
              scale = 1
            )
            page$session$Page$captureScreenshot(
              format = "png",
              clip = clip,
              fromSurface = TRUE,
              wait_ = FALSE,
              timeout_ = remaining(),
              callback_ = function(res) {
                record_frame_done(rec, pending, res = res)
              },
              error_ = function(err) record_frame_done(rec, pending, err = err)
            )
          },
          error = function(e) record_frame_done(rec, pending, err = e)
        )
      },
      error_ = function(err) record_frame_done(rec, pending, err = err)
    ),
    error = function(e) record_frame_done(rec, pending, err = e)
  )
  invisible(rec)
}

# The capture callback: writes the PNG to the frame store at resolve
# time. A callback for a retired capture cannot consume a newer slot.
# At most one active capture is pending, so frame timestamps stay ordered.
record_frame_done <- function(rec, pending, res = NULL, err = NULL) {
  if (!identical(rec$pending, pending)) {
    return(invisible(NULL))
  }
  rec$pending <- NULL
  tryCatch(
    {
      if (!is.null(err)) {
        if (is_condition(err)) stop(err) else cli::cli_abort("{err}")
      }
      writeBin(jsonlite::base64_dec(res$data), pending$file)
      # A capture issued just before pz_record_stop() resolves after
      # vt_end is fixed; keep only frames taken inside the window.
      if (is.null(rec$vt_end) || pending$vt <= rec$vt_end) {
        rec$times <- c(rec$times, pending$vt)
        rec$files <- c(rec$files, pending$file)
      } else {
        unlink(pending$file)
      }
    },
    error = function(e) record_error(rec, e)
  )
  invisible(NULL)
}

record_error <- function(rec, e) {
  rec$n_errors <- rec$n_errors + 1L
  if (is.null(rec$first_error)) {
    rec$first_error <- conditionMessage(e)
  }
  invisible(NULL)
}

# A navigation replaces the document, so a recording's framing -- whose
# target and bounds are pinned elements of the outgoing document --
# dies with it. The recording itself survives (the timer, clock, and
# captures are session-level), but the framing falls back to the
# viewport: a when = "stop" crop not yet measured resolves as the
# full viewport instead of raising the detach error at stop. A when =
# "start" crop was already measured as a fixed box in viewport
# coordinates and stays.
record_nav_rebased <- function(page) {
  rec <- page_recorder(page)
  if (is.null(rec) || is.null(rec$frame)) {
    return(invisible(FALSE))
  }
  rec$frame <- NULL
  rec$frame_ctx <- NULL
  invisible(TRUE)
}

# The crop box is viewport-relative CSS pixels (the PNG's coordinate
# space). viewport_width is kept for CSS-to-pixel conversion at encode time.
record_crop_box <- function(ctx, spec, call = caller_env()) {
  m <- frame_measure(ctx, NULL, spec, extent = "viewport", call = call)
  box <- frame_round(m$box, pinned = m$pinned, even = TRUE)
  c(frame_region(box, call = call), viewport_width = m$geometry$viewport_width)
}

# PNG pixel dimensions parsed straight from the IHDR chunk, so the
# encode path doesn't need an image package (mirrors the test helper).
png_read_size <- function(path, call = caller_env()) {
  png <- readBin(path, "raw", n = 24)
  signature <- as.raw(c(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a))
  if (
    length(png) < 24 ||
      !identical(png[1:8], signature) ||
      !identical(png[13:16], charToRaw("IHDR"))
  ) {
    cli::cli_abort(
      "Internal error: {.path {path}} is not a PNG frame.",
      class = "paparazzi_error_internal",
      call = call
    )
  }
  list(
    width = readBin(png[17:20], "integer", size = 4, endian = "big"),
    height = readBin(png[21:24], "integer", size = 4, endian = "big")
  )
}

# The ffmpeg filter chain and final output dimensions. The crop is the
# measured frame box (or the whole PNG) floored to the format's
# alignment: multiples of 4 for mp4 and even pixels for webm, both
# required by yuv420p-family encoders; gifski takes any size, so an
# unframed GIF never needs a crop. scale <= 4 is a factor; larger is
# the output width in pixels.
record_output_spec <- function(rec, png_size, call = caller_env()) {
  align <- switch(rec$format, mp4 = 4, webm = 2, gif = 1)
  if (!is.null(rec$crop)) {
    dpr <- png_size$width / rec$crop$viewport_width
    x <- floor(rec$crop$x * dpr)
    y <- floor(rec$crop$y * dpr)
    width <- round(rec$crop$width * dpr)
    height <- round(rec$crop$height * dpr)
    width <- min(width, png_size$width - x)
    height <- min(height, png_size$height - y)
  } else {
    x <- 0
    y <- 0
    width <- png_size$width
    height <- png_size$height
  }
  if (width < align || height < align) {
    cli::cli_abort(
      "The capture region is too small to encode ({width}x{height} pixels).",
      class = "paparazzi_error_record",
      call = call
    )
  }
  aligned_width <- floor(width / align) * align
  aligned_height <- floor(height / align) * align
  x <- x + floor((width - aligned_width) / 2)
  y <- y + floor((height - aligned_height) / 2)
  width <- aligned_width
  height <- aligned_height

  crop <- NULL
  if (
    !is.null(rec$crop) ||
      width != png_size$width ||
      height != png_size$height
  ) {
    crop <- list(x = x, y = y, width = width, height = height)
  }
  filters <- character(0)
  if (!is.null(crop)) {
    filters <- c(
      filters,
      sprintf(
        "crop=%d:%d:%d:%d",
        crop$width,
        crop$height,
        crop$x,
        crop$y
      )
    )
  }
  if (!is.null(rec$scale)) {
    if (rec$scale <= 4) {
      width <- width * rec$scale
      height <- height * rec$scale
    } else {
      height <- height * rec$scale / width
      width <- rec$scale
    }
    width <- max(align, floor(round(width) / align) * align)
    height <- max(align, floor(round(height) / align) * align)
    filters <- c(filters, sprintf("scale=%d:%d", width, height))
  }
  if (rec$format %in% c("mp4", "webm")) {
    filters <- c(filters, "format=yuv420p")
  }
  list(
    vfilter = if (length(filters)) paste(filters, collapse = ",") else "null",
    crop = crop,
    width = as.integer(width),
    height = as.integer(height)
  )
}

# Map output tick times to video times across the hold intervals
# (sorted by vt): inside a hold the video time pins to the hold's vt;
# past a hold the hold's duration shifts the mapping.
ticks_to_vt <- function(ticks, holds) {
  res <- numeric(length(ticks))
  offset <- 0
  hi <- 1L
  for (i in seq_along(ticks)) {
    while (
      hi <= length(holds) &&
        ticks[[i]] >= holds[[hi]]$vt + offset + holds[[hi]]$seconds
    ) {
      offset <- offset + holds[[hi]]$seconds
      hi <- hi + 1L
    }
    if (hi <= length(holds) && ticks[[i]] >= holds[[hi]]$vt + offset) {
      res[[i]] <- holds[[hi]]$vt
    } else {
      res[[i]] <- ticks[[i]] - offset
    }
  }
  res
}

# Resample the captured frames to constant fps in R: normalize video
# time so the first frame is vt 0, lay output ticks over
# vt_end + all holds, and take the latest frame at each tick. Repeats
# in the index vector are how holds and skipped ticks manifest; av and
# gifski both accept repeated input paths.
record_resample <- function(rec) {
  t0 <- rec$times[[1]]
  times <- rec$times - t0
  vt_end <- max(rec$vt_end - t0, 0)
  holds <- c(
    list(list(vt = 0, seconds = rec$hold_first)),
    lapply(rec$holds, function(h) {
      list(vt = max(h$vt - t0, 0), seconds = h$seconds)
    }),
    list(list(vt = vt_end, seconds = rec$hold_last))
  )
  holds <- holds[order(vapply(holds, `[[`, numeric(1), "vt"))]
  total <- vt_end + sum(vapply(holds, `[[`, numeric(1), "seconds"))
  n_ticks <- max(1L, round(total * rec$fps))
  ticks <- (seq_len(n_ticks) - 1) / rec$fps
  vts <- ticks_to_vt(ticks, holds)
  index <- pmax(findInterval(vts, times), 1L)
  list(files = rec$files[index], total = total, n_ticks = n_ticks)
}

record_encode <- function(rec, call = caller_env()) {
  resampled <- record_resample(rec)
  png_size <- png_read_size(rec$files[[1]], call = call)
  out <- record_output_spec(rec, png_size, call = call)
  if (identical(rec$format, "gif")) {
    files <- resampled$files
    if (!is.null(out$crop)) {
      crop_dir <- tempfile("paparazzi-crop-")
      dir.create(crop_dir)
      on.exit(unlink(crop_dir, recursive = TRUE), add = TRUE)
      sources <- unique(rec$files)
      cropped <- file.path(crop_dir, basename(sources))
      box <- out$crop
      for (i in seq_along(sources)) {
        image <- png::readPNG(sources[[i]])
        png::writePNG(
          image[
            seq.int(box$y + 1L, length.out = box$height),
            seq.int(box$x + 1L, length.out = box$width),
            ,
            drop = FALSE
          ],
          cropped[[i]]
        )
      }
      files <- cropped[match(files, sources)]
    }
    gifski::gifski(
      files,
      gif_file = rec$path,
      width = out$width,
      height = out$height,
      delay = 1 / rec$fps,
      loop = TRUE,
      progress = FALSE
    )
  } else {
    codec <- switch(
      rec$format,
      mp4 = "libx264",
      webm = "libvpx-vp9"
    )
    av::av_encode_video(
      resampled$files,
      output = rec$path,
      framerate = rec$fps,
      vfilter = out$vfilter,
      codec = codec,
      verbose = FALSE
    )
  }
  invisible(rec$path)
}

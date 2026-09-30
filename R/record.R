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
#' `.webm`, or `.gif`. Both methods produce a video at the requested
#' `fps`; when a new frame is not available, the previous frame is
#' repeated.
#'
#' @section Choosing a capture method:
#' `"poll"` (the default) takes screenshots at roughly the requested
#' `fps`. Choose it when resolution matters: it captures at the page's
#' full pixel density. `"screencast"` records when the page changes,
#' which can capture more intermediate states of an animation. It does
#' not guarantee a capture rate and may have lower resolution. For
#' example, with a 640-by-480 viewport on a 2x display, poll frames
#' are 1280-by-960 pixels while screencast frames may be 640-by-480
#' pixels. The `scale` argument sets output size, but enlarging a
#' lower-resolution frame does not add detail.
#'
#' Both methods record while paparazzi runs browser actions or
#' [pz_wait()]. Long-running R code between browser actions, including
#' `Sys.sleep()`, can cause intermediate changes to be missed;
#' use `pz_wait()` when you want a visible wait in the video.
#'
#' @section Output and framing:
#' Stopping always captures one final frame of the page state at
#' `pz_record_stop()`, so a change made just before the stop still
#' appears; the last-frame hold repeats that final frame.
#'
#' Use [pz_frame()] (or the page default set with
#' [pz_stage_frame()]) to crop the finished recording. By default the
#' frame follows the layout at stop; `pz_frame(when = "start")` fixes it
#' to the layout at start. If the page navigates, a frame tied to the
#' previous page falls back to the full viewport unless it was fixed at
#' the start. MP4 dimensions are rounded down to multiples of 4 and
#' WebM to even pixels; GIF keeps whole pixels.
#'
#' WebVTT captions (when requested) are written as a `.vtt` file next to
#' the MP4 or WebM. Cue times include the first/last holds and explicit
#' [pz_record_hold()] intervals but exclude pauses. Caption burn and VTT
#' use the current caption set by [pz_annotate_caption()].
#'
#' MP4 and WebM recordings require \pkg{av}; GIF recordings require
#' \pkg{gifski}. Simple GIFs need only gifski, but two features call in
#' extra packages: framed GIFs require \pkg{png}, and GIFs with camera
#' movement or burned-in captions require \pkg{av}.
#' Packages are checked at `pz_record_start()` or when a caption is
#' added to an active GIF recording.
#'
#' @inheritParams pz_click
#' @param path Output file path; the extension (`.mp4`, `.webm`, or
#'   `.gif`) selects the format. An existing file is overwritten. If
#'   omitted while knitting, a numbered file in the chunk's figure
#'   directory is used and the recording appears in the document. If
#'   omitted in an interactive session, a temporary file is used and the
#'   recording is shown in the viewer when it stops. Otherwise a path is
#'   required.
#' @param format The format when `path` is omitted: `"auto"` (the
#'   default) records MP4, or GIF when knitting to a non-HTML format,
#'   where video can only be linked. With a `path`, the extension decides
#'   and `format` must be `"auto"`.
#' @param method Capture method: `"poll"` (the default) for regular,
#'   higher-resolution captures, or `"screencast"` for captures driven
#'   by visual changes. See *Choosing a capture method* for tradeoffs.
#' @param frame Area to show in the finished recording: `NULL` uses
#'   the page default set with [pz_stage_frame()], if any, or shows the
#'   full viewport; a [pz_frame()] spec replaces that default;
#'   `FALSE` ignores it. An explicit frame with
#'   `target_box = "annotated"` is invalid for the home frame. A staged
#'   annotated frame silently measures element boxes only for recording.
#' @param fps Frames per second in the finished recording. Poll aims
#'   to capture at this rate; screencast capture depends on visual
#'   changes.
#' @param scale Output size: `NULL` (the default) keeps the captured
#'   size; a number up to 4 is a scale factor; a larger number is the
#'   output width in pixels (height scales proportionally).
#' @param hold Seconds to hold the first and last frame,
#'   `c(first, last)`.
#' @param captions `"burn"` (the default) draws captions on the recording;
#'   `"vtt"` writes a WebVTT sidecar without drawing captions; `"both"`
#'   does both. WebVTT needs an MP4 or WebM recording, not a GIF.
#' @param keep_frames Keep the captured PNG frames in a
#'   `<name>_frames/` directory next to `path`. Otherwise frames are
#'   written to a temporary directory and deleted after encoding.
#'
#' @section Recording chains:
#' `pz_record_start()` returns a context that belongs to the new
#' recording. Chainable functions return it (and contexts derived from
#' it with [pz_find()]) visibly while the recording runs, and printing it
#' stops the recording. So a chain that starts with `pz_record_start()`
#' needs no [pz_record_stop()] when it is printed: at the end of a
#' knitted chunk expression the recording appears in the document, and
#' in the console it is shown in the viewer. Assign the chain or call
#' `pz_record_stop()` to record across several statements. Chains that
#' don't come from `pz_record_start()`, such as `page |> pz_click()`,
#' keep returning invisibly and never stop a recording.
#'
#' @return A context in the recording chain, invisibly.
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
  keep_frames = FALSE,
  captions = c("burn", "vtt", "both"),
  format = c("auto", "mp4", "webm", "gif")
) {
  check_context(ctx)
  check_dots_empty()
  format <- arg_match(format)
  implicit <- missing(path)
  if (implicit) {
    path <- record_implicit_path(format)
  } else if (format != "auto") {
    cli::cli_abort(
      "Supply {.arg format} only when {.arg path} is omitted; the extension of {.arg path} sets the format.",
      class = "paparazzi_error_input"
    )
  }
  check_string(path)
  method <- arg_match(method)
  check_number_decimal(fps, min = 1, max = 120)
  check_number_decimal(scale, min = 0, allow_null = TRUE)
  check_bool(keep_frames)
  hold <- check_record_hold(hold)
  format <- record_format(path)
  captions <- arg_match(captions)
  if (identical(format, "gif") && captions != "burn") {
    cli::cli_abort("WebVTT sidecars need an MP4 or WebM recording.")
  }
  staged_frame <- is.null(frame)
  frame <- frame_effective(ctx, frame)
  if (inherits(frame, "paparazzi_frame") && frame$target_box == "annotated") {
    if (staged_frame) {
      frame$target_box <- "element"
    } else {
      cli::cli_abort(
        "The recording's home {.arg frame} cannot use {.code target_box = 'annotated'}; use {.code target_box = 'element'} for the home frame."
      )
    }
  }
  record_check_packages(
    format,
    needs_crop = inherits(frame, "paparazzi_frame"),
    needs_caption = !is.null(page_caption(ctx$page)) && captions == "burn"
  )

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
    frame = frame,
    method = method
  )
  rec$implicit <- implicit
  rec$caption_mode <- captions
  rec$captions <- if (is.null(page_caption(page))) {
    list()
  } else {
    list(list(vt = 0, caption = page_caption(page)))
  }
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
  if (identical(method, "screencast")) {
    tryCatch(
      record_start_screencast(page, rec),
      error = function(e) {
        rec$active <- FALSE
        record_stop_screencast(page, rec)
        page_set_recorder(page, NULL)
        if (!rec$keep_frames) {
          unlink(rec$frames_dir, recursive = TRUE)
        }
        stop(e)
      }
    )
  } else {
    # The tick closure carries its recorder so it can't adopt a later one.
    later::later(
      function() record_tick(page, rec),
      delay = 0,
      loop = page$child_loop
    )
  }
  invisible(PaparazziContext$new(page, scope = ctx$scope, recording = rec))
}

#' Stop a recording and write the video
#'
#' Ends the recording started with [pz_record_start()], encodes the
#' captured frames, and writes the file given to `pz_record_start()`.
#'
#' @inheritParams pz_click
#'
#' @return `ctx`, invisibly, when the path was supplied outside knitting.
#'   While knitting, returns a printable image for GIF, HTML video for
#'   MP4/WebM, or a video link in non-HTML output, even when the path was
#'   supplied explicitly. Without a path in an interactive session,
#'   returns a preview that shows the recording in the viewer when
#'   printed.
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

  camera_settle(page, rec)

  # Deactivate first so ticks scheduled by the recording stop re-arming
  # and can't issue captures while the stop settles its own.
  rec$active <- FALSE
  rec$vt_end <- rec_vt(rec)
  record_stop_screencast(page, rec)

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
  # A screencast frame may have CSS-viewport resolution even at a higher
  # device pixel ratio. Match it for the final screenshot so encode-time
  # framing uses the same coordinates for every frame.
  capture_scale <- if (identical(rec$method, "screencast")) {
    1 / pz_js(page, "window.devicePixelRatio")
  } else {
    1
  }
  record_capture(rec, page, rec$vt_end, scale = capture_scale)
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
  record_encode(rec, page)
  # The staging hook: an auto cursor under cursor = NULL belonged to the
  # recording, so it leaves the page now that stills would catch it.
  stage_record_stopped(ctx)
  if (isTRUE(getOption("knitr.in.progress"))) {
    return(record_knit_media(rec$path))
  }
  if (rec$implicit && rlang::is_interactive()) {
    return(structure(rec$path, class = "paparazzi_preview"))
  }
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
    return(ctx_return(ctx))
  }
  camera_settle(ctx$page, rec)
  rec$vt_base <- rec_vt(rec)
  rec$paused <- TRUE
  ctx_return(ctx)
}

#' @rdname pz_record_pause
#' @export
pz_record_resume <- function(ctx) {
  check_context(ctx)
  rec <- check_recording(ctx)
  if (!rec$paused) {
    return(ctx_return(ctx))
  }
  if (identical(rec$method, "screencast")) {
    record_wait_pending(rec, ctx$page, "the frame capture before resuming")
  }
  rec$active_since <- rec_now()
  rec$paused <- FALSE
  if (identical(rec$method, "screencast")) {
    record_screencast_snapshot(ctx$page, rec)
  }
  ctx_return(ctx)
}

#' Hold the current frame while recording
#'
#' Lingers on the current frame for `seconds` in the output video.
#' Unlike [pz_wait()], no real time passes: the hold is inserted into
#' the video timeline at encode time. When the page is not recording
#' this is a no-op, so debugging a chain with the recording commented
#' out doesn't pay for video-only pauses. A camera move still in
#' progress (see [pz_camera()]) finishes before the hold begins.
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
    return(ctx_return(ctx))
  }
  camera_settle(ctx$page, rec)
  rec$holds <- c(rec$holds, list(list(vt = rec_vt(rec), seconds = seconds)))
  ctx_return(ctx)
}

#' Record a block of code
#'
#' The block form of [pz_record_start()]: starts recording, evaluates
#' the embraced expression `code`, and stops and encodes on exit --
#' including on error, so a failed run still produces the video up to
#' the failure. Returns what [pz_record_stop()] returns, never the block's
#' value: `ctx` invisibly when a path was given outside knitting, media
#' while knitting, or a viewer preview when the path is omitted in an
#' interactive session. Write `pz_record(code = { ... })` to omit the
#' path.
#'
#' @inheritParams pz_record_start
#' @param code An expression to evaluate while recording.
#' @param ... Passed to [pz_record_start()].
#'
#' @return `ctx`, invisibly, or printable media; see [pz_record_stop()].
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
  # Non-local exits (including interrupts) still stop the recording.
  on.exit(pz_record_stop(ctx), add = TRUE)
  code_error <- tryCatch(
    {
      eval(expr, env)
      NULL
    },
    error = identity
  )
  # The normal path stops once, and the block's error takes priority.
  on.exit(NULL)
  stop_result <- tryCatch(pz_record_stop(ctx), error = identity)
  if (inherits(code_error, "error")) {
    stop(code_error)
  }
  if (inherits(stop_result, "error")) {
    stop(stop_result)
  }
  if (!inherits(stop_result, "PaparazziContext")) {
    return(stop_result)
  }
  invisible(ctx)
}

record_implicit_path <- function(format, call = caller_env()) {
  knitting <- isTRUE(getOption("knitr.in.progress"))
  if (format == "auto") {
    html <- knitting &&
      knitr::is_html_output(excludes = c("markdown", "gfm", "epub", "epub2"))
    format <- if (knitting && !html) "gif" else "mp4"
  }
  if (knitting) {
    return(knit_capture_path(format))
  }
  if (rlang::is_interactive()) {
    return(tempfile("paparazzi-", fileext = paste0(".", format)))
  }
  cli::cli_abort(
    "{.arg path} is required outside knitting and interactive sessions.",
    class = "paparazzi_error_input",
    call = call
  )
}

# Printing a running recording chain ends it: the recording is the
# chain's printed result, shown in the viewer when interactive.
record_print_stop <- function(ctx) {
  result <- pz_record_stop(ctx)
  if (rlang::is_interactive()) {
    rec_path <- if (inherits(result, "paparazzi_preview")) {
      result
    } else {
      structure(ctx$recording$path, class = "paparazzi_preview")
    }
    print(rec_path)
  }
  invisible(ctx)
}

record_knit_media <- function(path) {
  if (record_format(path) == "gif") {
    return(knitr::include_graphics(path))
  }
  # The figure directory is carried along when R Markdown or Quarto moves
  # the rendered document; an external named path is not.
  figure_dir <- dirname(knitr::fig_path(record_format(path)))
  dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)
  in_figures <- identical(
    normalizePath(dirname(path)),
    normalizePath(figure_dir)
  )
  media_path <- if (in_figures) {
    path
  } else {
    file.path(
      figure_dir,
      paste0(unname(tools::md5sum(path)), "-", basename(path))
    )
  }
  if (
    !identical(normalizePath(path), normalizePath(media_path, mustWork = FALSE))
  ) {
    if (!file.copy(path, media_path, overwrite = TRUE)) {
      cli::cli_abort("Could not copy recording to {.path {media_path}}.")
    }
  }
  if (xfun::is_abs_path(media_path)) {
    output_dir <- knitr::opts_knit$get("rmarkdown.output_dir")
    output_dir <- output_dir %||% knitr::opts_knit$get("output.dir")
    media_path <- xfun::relative_path(
      media_path,
      output_dir %||% getwd()
    )
  }
  # Percent-encode filename characters without encoding path separators.
  url <- gsub(
    "%2F",
    "/",
    utils::URLencode(media_path, reserved = TRUE),
    fixed = TRUE
  )
  if (knitr::is_html_output(excludes = c("markdown", "gfm", "epub", "epub2"))) {
    return(knitr::asis_output(paste0(
      '<video controls preload="metadata" src="',
      url,
      '">',
      '<a href="',
      url,
      '">Download recording</a></video>'
    )))
  }
  knitr::asis_output(paste0("[Download recording](<", url, ">)"))
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
  result <- code
  rec$held <- held
  if (
    !held && rec$active && !rec$paused && identical(rec$method, "screencast")
  ) {
    record_screencast_snapshot(page, rec)
  }
  result
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
  frame,
  method = "poll"
) {
  rec <- new.env(parent = emptyenv())
  rec$path <- path
  rec$format <- format
  rec$method <- method
  rec$deregister_screencast <- NULL
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
  rec$scroll <- list()
  rec$camera <- list()
  rec$caption_mode <- "burn"
  rec$captions <- list()
  rec$keypresses <- list()
  rec$camera_viewport_width <- NULL
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

record_check_packages <- function(
  format,
  needs_crop,
  needs_caption = FALSE,
  call = caller_env()
) {
  if (format %in% c("mp4", "webm")) {
    rlang::check_installed(
      "av",
      reason = paste0("to record .", format, " video.")
    )
    return(invisible())
  }
  rlang::check_installed("gifski", reason = "to record .gif files.")
  if (needs_caption) {
    rlang::check_installed(
      "av",
      reason = "to burn captions onto .gif recordings."
    )
  }
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
  record_stop_screencast(page, rec)
  page_set_recorder(page, NULL)
  if (!rec$keep_frames && !is.null(rec$frames_dir)) {
    unlink(rec$frames_dir, recursive = TRUE)
  }
  invisible(TRUE)
}

record_start_screencast <- function(page, rec) {
  session <- page$session
  rec$deregister_screencast <- session$Page$screencastFrame(
    callback_ = function(frame) record_screencast_frame(page, rec, frame)
  )
  session$Page$startScreencast(
    format = "png",
    timeout_ = page$default_timeout
  )
  invisible(rec)
}

record_stop_screencast <- function(page, rec) {
  deregister <- rec$deregister_screencast
  if (is.null(deregister)) {
    return(invisible(NULL))
  }
  rec$deregister_screencast <- NULL
  session <- page$session
  tryCatch(
    session$Page$stopScreencast(
      wait_ = FALSE,
      callback_ = function(...) NULL,
      error_ = function(e) record_error(rec, e)
    ),
    error = function(e) record_error(rec, e)
  )
  tryCatch(deregister(), error = function(e) record_error(rec, e))
  invisible(NULL)
}

record_screencast_frame <- function(page, rec, frame) {
  session <- page$session
  tryCatch(
    session$Page$screencastFrameAck(
      sessionId = frame$sessionId,
      wait_ = FALSE,
      callback_ = function(...) NULL,
      error_ = function(e) record_error(rec, e)
    ),
    error = function(e) record_error(rec, e)
  )
  if (
    !rec$active ||
      rec$paused ||
      rec$held ||
      !is.null(rec$pending) ||
      !identical(rec, page_recorder(page))
  ) {
    return(invisible(NULL))
  }
  tryCatch(
    {
      pending <- new.env(parent = emptyenv())
      pending$vt <- rec_vt(rec)
      pending$scroll <- c(
        frame$metadata$scrollOffsetX,
        frame$metadata$scrollOffsetY
      )
      pending$viewport_width <- frame$metadata$deviceWidth
      pending$file <- file.path(
        rec$frames_dir,
        sprintf("frame-%06d.png", length(rec$files) + 1L)
      )
      rec$pending <- pending
      record_frame_done(rec, pending, res = frame)
    },
    error = function(e) record_error(rec, e)
  )
  invisible(NULL)
}

record_screencast_snapshot <- function(page, rec) {
  if (!is.null(rec$pending)) {
    return(invisible(NULL))
  }
  tryCatch(
    record_capture(
      rec,
      page,
      rec_vt(rec),
      scale = 1 / pz_js(page, "window.devicePixelRatio")
    ),
    error = function(e) record_error(rec, e)
  )
  invisible(NULL)
}

# Shared async screenshot for poll ticks, screencast boundary snapshots,
# and the stop-time final frame. The pending slot prevents overlapping captures; callbacks clear it when chromote
# invokes them on the child loop. A synchronous failure (e.g. a closed
# session) clears it and lands in the recorder's error tally instead.
# Unclipped surface captures at DPR 2 can remap concurrent mouse input
# to half its coordinates; a viewport clip avoids that Chrome path.
# The screencast stop capture uses a smaller clip scale so its PNG
# matches the event frames' CSS-pixel resolution.
record_capture <- function(rec, page, vt, scale = 1) {
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
            pending$scroll <- c(max(v$pageX, 0), max(v$pageY, 0))
            pending$viewport_width <- v$clientWidth
            clip <- list(
              x = max(v$pageX, 0),
              y = max(v$pageY, 0),
              width = v$clientWidth,
              height = v$clientHeight,
              scale = scale
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
        rec$scroll[[length(rec$files)]] <- pending$scroll
        if (is.null(rec$camera_viewport_width)) {
          rec$camera_viewport_width <- pending$viewport_width
        }
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
  holds <- holds[order(map_dbl(holds, `[[`, "vt"))]
  total <- vt_end + sum(map_dbl(holds, `[[`, "seconds"))
  n_ticks <- max(1L, round(total * rec$fps))
  ticks <- (seq_len(n_ticks) - 1) / rec$fps
  vts <- ticks_to_vt(ticks, holds)
  index <- pmax(findInterval(vts, times), 1L)
  list(
    files = rec$files[index],
    vts = vts + t0,
    index = index,
    total = total,
    n_ticks = n_ticks
  )
}

record_encode <- function(rec, page = NULL, call = caller_env()) {
  resampled <- record_resample(rec)
  png_size <- png_read_size(rec$files[[1]], call = call)
  out <- record_output_spec(rec, png_size, call = call)
  if (length(rec$camera)) {
    out$vfilter <- camera_filter(rec, resampled, out, png_size, call = call)
  }
  windows <- caption_windows(rec, resampled)
  key_windows <- key_callout_windows(rec, resampled)
  mode <- rec$caption_mode %||% "burn"
  if (mode %in% c("vtt", "both")) {
    caption_vtt(rec, windows)
  }
  burning <- (length(windows) > 0L && mode != "vtt") ||
    length(key_windows) > 0L
  if (burning) {
    caption_dir <- tempfile("paparazzi-caption-")
    dir.create(caption_dir)
    on.exit(unlink(caption_dir, recursive = TRUE), add = TRUE)
    captions <- if (mode == "vtt") {
      list()
    } else {
      caption_overlays(rec, page, out, windows, caption_dir)
    }
    keys <- key_callout_overlays(
      rec,
      page,
      out,
      key_windows,
      captions,
      caption_dir
    )
    out$vfilter <- screen_filter(rec, resampled, out, c(captions, keys))
  }
  if (identical(rec$format, "gif")) {
    files <- resampled$files
    if (length(rec$camera) || burning) {
      crop_dir <- tempfile("paparazzi-camera-")
      dir.create(crop_dir)
      on.exit(unlink(crop_dir, recursive = TRUE), add = TRUE)
      sequence <- file.path(crop_dir, "camera-%04d.png")
      input_files <- if (burning) normalizePath(files) else files
      output_file <- if (burning) {
        normalizePath(sequence, mustWork = FALSE)
      } else {
        sequence
      }
      encode <- function() {
        av::av_encode_video(
          input_files,
          output = output_file,
          framerate = rec$fps,
          vfilter = out$vfilter,
          codec = "png",
          verbose = FALSE
        )
      }
      if (burning) {
        withr::with_dir(caption_dir, encode())
      } else {
        encode()
      }
      # av can emit one extra terminal frame; keep exactly the ticks.
      files <- sprintf(sequence, seq_len(resampled$n_ticks))
      if (!all(file.exists(files))) {
        cli::cli_abort("The camera rendered fewer GIF frames than requested.")
      }
    } else if (!is.null(out$crop)) {
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
    input_files <- if (burning) {
      normalizePath(resampled$files)
    } else {
      resampled$files
    }
    output_file <- if (burning) {
      normalizePath(rec$path, mustWork = FALSE)
    } else {
      rec$path
    }
    encode <- function() {
      av::av_encode_video(
        input_files,
        output = output_file,
        framerate = rec$fps,
        vfilter = out$vfilter,
        codec = codec,
        verbose = FALSE
      )
    }
    if (burning) withr::with_dir(caption_dir, encode()) else encode()
  }
  invisible(rec$path)
}

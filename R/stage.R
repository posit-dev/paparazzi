# Staging: the per-page settings that make recorded runs watchable --
# cursor visibility and glide speed, entrance side, natural typing, and
# a hold after each action. Settings live on the page and persist across
# recordings. Staging only animates WHILE RECORDING (stage_recording());
# without a recording the same chain runs straight to its final state,
# except that a visible cursor (cursor = TRUE, or an explicit
# pz_cursor_show()) is drawn statically for stills. Animation is
# page-side CSS transitions driven by an R-side pump of the child loop
# (pump_loop(), the pz_wait() mechanism) -- no timers of our own, so the
# recorder's capture ticks are the only clock the animation answers to.
#' Stage the page for recording
#'
#' Sets the staging options that animate pointer actions, typing, and
#' scrolling while the page is recording. Only supplied arguments
#' change; settings live on the page and persist across recordings, so
#' [pz_record_start()] never repeats them. Without a recording, staging
#' is skipped and the chain runs straight to its final state -- except
#' `cursor = TRUE`, which shows a static cursor in screenshots too.
#'
#' @inheritParams pz_click
#' @param ... Checked empty; reserved for future use.
#' @param cursor Cursor visibility: `NULL` (the default) shows the
#'   cursor only while recording, `TRUE` shows it always (stills too),
#'   `FALSE` never shows it.
#' @param cursor_speed Glide speed in pixels per second. Glide duration
#'   scales with distance: roughly `clamp(0.25 + distance /
#'   cursor_speed, 0.3, 1.2)` seconds.
#' @param enter Where a cursor that has never been shown first appears:
#'   `NULL` (the default) fades in on the target; a side (`"top"`,
#'   `"bottom"`, `"left"`, `"right"`) starts off-frame on that side and
#'   glides in.
#' @param typing Typing style while recording: `"natural"` (the
#'   default) inserts one character at a time with randomized delays;
#'   `"instant"` inserts the whole string at once.
#' @param typing_speed Natural typing speed in characters per second.
#' @param pause Seconds to hold after each action while recording.
#'
#' @return `ctx`, invisibly.
#'
#' @seealso [pz_cursor_show()], [pz_record_start()]
#'
#' @export
pz_stage <- function(
  ctx,
  ...,
  cursor = NULL,
  cursor_speed = NULL,
  enter = NULL,
  typing = NULL,
  typing_speed = NULL,
  pause = NULL
) {
  check_context(ctx)
  check_dots_empty()
  page <- ctx$page
  overrides <- page$.__enclos_env__$private$staging_$stage %||% list()

  if (!is.null(cursor)) {
    check_bool(cursor)
    overrides$cursor <- cursor
  }
  if (!is.null(cursor_speed)) {
    check_number_decimal(cursor_speed, min = 1)
    overrides$cursor_speed <- cursor_speed
  }
  if (!is.null(enter)) {
    overrides$enter <- parse_direction(enter, valid = STAGE_SIDES, arg = "enter")
  }
  if (!is.null(typing)) {
    overrides$typing <- arg_match(typing, c("natural", "instant"))
  }
  if (!is.null(typing_speed)) {
    check_number_decimal(typing_speed, min = 0.1)
    overrides$typing_speed <- typing_speed
  }
  if (!is.null(pause)) {
    check_number_decimal(pause, min = 0)
    overrides$pause <- pause
  }
  page_set_stage(page, overrides)

  # The cursor setting applies immediately: FALSE hides a drawn cursor;
  # TRUE draws a static one (visible in stills) when there is none.
  stage <- page_stage(page)
  cur <- page_cursor_peek(page)
  if (identical(stage$cursor, FALSE)) {
    if (!is.null(cur) && !is.null(cur$x)) {
      cursor_draw(ctx, visible = FALSE)
    }
  } else if (isTRUE(stage$cursor) && cursor_visible(page)) {
    point <- cursor_current_point(ctx)
    if (is.null(cur) || is.null(cur$x)) {
      cursor_apply(ctx, point)
    } else {
      cursor_draw(ctx, visible = TRUE)
    }
  }
  invisible(ctx)
}
# The settings list with defaults filled. The page stores only the
# overrides pz_stage() was given, so later default changes reach pages
# that never set the field.
STAGE_DEFAULTS <- list(
  cursor = NULL,
  cursor_speed = 1500,
  enter = NULL,
  typing = "natural",
  typing_speed = 16,
  pause = 0
)
page_stage <- function(page) {
  overrides <- page$.__enclos_env__$private$staging_$stage
  utils::modifyList(STAGE_DEFAULTS, overrides %||% list())
}
page_set_stage <- function(page, overrides) {
  page$.__enclos_env__$private$staging_$stage <- overrides
  invisible(page)
}
# "While recording": a recorder exists and is active. Paused still
# counts -- the capture cadence is the recorder's concern.
stage_recording <- function(page) {
  rec <- page_recorder(page)
  !is.null(rec) && isTRUE(rec$active)
}
# Glide duration: clamp(0.25 + distance / cursor_speed, 0.3, 1.2).
stage_glide_duration <- function(from, to, speed) {
  dist <- sqrt((to[["x"]] - from[["x"]])^2 + (to[["y"]] - from[["y"]])^2)
  min(max(0.25 + dist / speed, 0.3), 1.2)
}
# The pointer-action seam, called from el_pointer_point() once the
# target's click point is known: while recording, the cursor gets to the
# point the way its state says -- fade in on it (never shown), glide in
# from the enter/off-frame side, or glide from its last position. Not
# recording, a visible cursor (cursor = TRUE, or explicitly shown)
# jumps to the point so stills track the real pointer.
stage_move_cursor <- function(ctx, point) {
  page <- ctx$page
  if (!cursor_visible(page)) {
    return(invisible(ctx))
  }
  if (!stage_recording(page)) {
    cursor_apply(ctx, point)
    return(invisible(ctx))
  }
  cursor_show_at(ctx, point)
  invisible(ctx)
}
# The scroll half of the el_pointer_point() seam. Recording: animated
# wheel scrolling over the container; not recording: the established
# instant scroll.
stage_scroll_into_view <- function(ctx, els, call = caller_env()) {
  if (!stage_recording(ctx$page)) {
    return(el_scroll_into_view(els, call = call))
  }
  stage_wheel_into_view(ctx, els, call = call)
}
# Instant placeholder until the wheel driver lands in this file; keeps
# the seam wired so the action pipeline is staging-aware from the start.
stage_wheel_into_view <- function(ctx, els, call = caller_env()) {
  el_scroll_into_view(els, call = call)
}
# pz_stage(pause =): a hold after each action while recording, skipped
# otherwise (the SPEC matrix). Real time passes -- the recorded frames
# capture the settled page.
stage_action_pause <- function(ctx) {
  page <- ctx$page
  if (!stage_recording(page)) {
    return(invisible(ctx))
  }
  pause <- page_stage(page)$pause
  if (pause > 0) {
    pump_loop(page$child_loop, pause)
  }
  invisible(ctx)
}
# The record-stop hook (called from pz_record_stop()): an auto cursor
# under cursor = NULL belongs to the recording, so it goes away when the
# recording ends; an explicitly shown cursor or cursor = TRUE stays.
stage_record_stopped <- function(ctx) {
  page <- ctx$page
  if (page$is_closed()) {
    return(invisible(ctx))
  }
  cur <- page_cursor_peek(page)
  if (
    !is.null(cur) &&
      identical(cur$visibility, "auto") &&
      is.null(page_stage(page)$cursor) &&
      !is.null(cur$x)
  ) {
    cursor_draw(ctx, visible = FALSE)
  }
  invisible(ctx)
}

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
# The animated auto-scroll: real mouseWheel events with the cursor
# over the container, instead of the instant scrollIntoView. Each round
# probes the deltas that scrollIntoView(block: 'nearest') would apply
# across EVERY scrollable ancestor of the element plus the viewport
# (a target visible inside a container that is itself below the fold
# still needs the outer containers scrolled), wheels the delta of the
# OUTERMOST container that still has one, and re-probes; the outer clips
# contain the inner ones, so the wheeled container is always on screen
# when its wheel fires. A round that leaves every container's scroll
# position unchanged (a page canceling wheel events) or exceeds the
# round bound (a page fighting the scroll) falls back to the instant
# scroll: the final state is always correct, animated or not.
stage_wheel_into_view <- function(ctx, els, call = caller_env()) {
  if (els$count == 0L || is.null(els$object_id)) {
    return(invisible(els))
  }
  prev <- NULL
  rounds <- 0L
  repeat {
    probe <- els_values(els, wheel_probe_js, call = call)
    if (is.null(probe)) {
      return(invisible(els))
    }
    delta <- c(probe$dx, probe$dy)
    if (all(delta == 0)) {
      return(invisible(els))
    }
    pos <- unlist(probe$pos)
    rounds <- rounds + 1L
    if (
      (!is.null(prev) && identical(pos, prev)) ||
        rounds > 2L * probe$n + 3L
    ) {
      # Stalled (no scroll position moved) or oscillating: the instant
      # scroll guarantees the final state.
      return(el_scroll_into_view(els, call = call))
    }
    prev <- pos
    point <- c(x = probe$x, y = probe$y)
    stage_move_cursor(ctx, point)
    stage <- page_stage(ctx$page)
    duration <- min(max(0.25 + max(abs(delta)) / stage$cursor_speed, 0.3), 1.2)
    stage_wheel(ctx, point, delta[[1]], delta[[2]], duration, call = call)
  }
}
# Wheel a scroll delta over `duration` seconds: ~100px steps, weights
# from a cubic ease-in-out over the step index so the scroll eases like
# a glide, a short pump between steps (the wheels land asynchronously,
# and the recorder's ticks capture the intermediate positions).
stage_wheel <- function(ctx, point, dx, dy, duration, call = caller_env()) {
  page <- ctx$page
  steps <- max(1L, ceiling(max(abs(dx), abs(dy)) / 100))
  ease <- function(t) {
    if (t < 0.5) 4 * t^3 else 1 - (-2 * t + 2)^3 / 2
  }
  t0 <- 0
  for (i in seq_len(steps)) {
    t1 <- ease(i / steps)
    frac <- t1 - t0
    t0 <- t1
    action_cdp(
      ctx,
      "scrolling",
      call = call,
      cmd = page$session$Input$dispatchMouseEvent(
        type = "mouseWheel",
        x = point[["x"]],
        y = point[["y"]],
        deltaX = dx * frac,
        deltaY = dy * frac,
        pointerType = "mouse",
        timeout_ = page$default_timeout
      )
    )
    interval <- duration / steps
    pump_loop(page$child_loop, interval, interval = min(interval, 0.05))
  }
  invisible(TRUE)
}
# The staged pz_scroll(by =)/pz_scroll(to =): wheel the scope's
# container (or the document) to the target scroll position with the
# cursor over it, then verify; a miss (wheel-cancelling page, latching
# onto a nested scroller under the container center) falls back to the
# instant application so the final scroll position is always exact.
scroll_staged <- function(ctx, scoped, by, to, call = caller_env()) {
  # A wheel only lands on a container the cursor point is actually
  # over; a scoped container outside the viewport is first brought into
  # view (a no-op when it already is).
  if (!is.null(scoped)) {
    el_scroll_into_view(scoped, call = call)
  }
  probe <- if (!is.null(scoped)) {
    els_values(scoped, wheel_container_js, call = call)
  } else {
    pz_js(ctx, paste0("(", wheel_container_js, ").call([])"))
  }
  target <- scroll_wheel_target(probe, by, to)
  delta <- c(target$left - probe$left, target$top - probe$top)
  if (all(delta == 0)) {
    return(invisible(ctx))
  }
  point <- c(x = probe$x, y = probe$y)
  stage_move_cursor(ctx, point)
  stage <- page_stage(ctx$page)
  duration <- min(max(0.25 + max(abs(delta)) / stage$cursor_speed, 0.3), 1.2)
  stage_wheel(ctx, point, delta[[1]], delta[[2]], duration, call = call)
  # Verify and repair: wheels are best-effort (clamping, canceling),
  # the recorded end state must match the instant path.
  actual <- if (!is.null(scoped)) {
    els_values(scoped, wheel_container_js, call = call)
  } else {
    pz_js(ctx, paste0("(", wheel_container_js, ").call([])"))
  }
  if (
    abs(actual$top - target$top) > 2 || abs(actual$left - target$left) > 2
  ) {
    arg <- scroll_arg_json(
      by = if (!is.null(by)) c(target$left - actual$left, target$top - actual$top),
      to = to
    )
    if (!is.null(scoped)) {
      arg_list <- if (!is.null(by)) {
        list(by = as.list(c(target$left - actual$left, target$top - actual$top)))
      } else {
        list(to = as.list(to))
      }
      els_arg_values(scoped, scroll_apply_js, list(list(value = arg_list)))
    } else {
      action_cdp(
        ctx,
        "scrolling",
        call = call,
        cmd = ctx$page$session$Runtime$evaluate(
          paste0("(", scroll_apply_js, ").call([], ", arg, ")"),
          returnByValue = TRUE,
          timeout_ = ctx$page$default_timeout
        )
      )
    }
  }
  invisible(ctx)
}
# The target scroll position for a by/to scroll, from the container
# probe: by adds an offset, to aims at an edge/corner/center per the
# direction tokens (an axis the tokens don't name keeps its position).
scroll_wheel_target <- function(probe, by, to) {
  left <- probe$left
  top <- probe$top
  if (!is.null(by)) {
    left <- left + by[[1]]
    top <- top + by[[2]]
  } else {
    center <- identical(to, "center")
    if ("left" %in% to) left <- 0
    if ("right" %in% to) left <- probe$maxLeft
    if (center) left <- probe$maxLeft / 2
    if ("top" %in% to) top <- 0
    if ("bottom" %in% to) top <- probe$maxTop
    if (center) top <- probe$maxTop / 2
  }
  list(
    left = min(max(left, 0), probe$maxLeft),
    top = min(max(top, 0), probe$maxTop)
  )
}
# The container probe for by/to scrolls: the current scope's scroll
# container (the scope element or its nearest scrollable ancestor, the
# document at the root -- the same walk scroll_apply_js does), its
# viewport center for cursor placement, and its scroll position and
# range. One function serves both rootings: callFunctionOn on the
# pinned set as `this`, or Runtime$evaluate with `this` an empty array.
wheel_container_js <- "function() {
  const isScrollable = (e) => {
    if (e === document.scrollingElement) {
      return true;
    }
    const s = getComputedStyle(e);
    if (!/(auto|scroll)/.test(s.overflow + ' ' + s.overflowX + ' ' + s.overflowY)) {
      return false;
    }
    return e.scrollHeight > e.clientHeight || e.scrollWidth > e.clientWidth;
  };
  let container = null;
  for (let e = this.length ? this[0] : null; e; e = e.parentElement) {
    if (isScrollable(e)) {
      container = e;
      break;
    }
  }
  if (!container) {
    container = document.scrollingElement;
  }
  const doc = container === document.scrollingElement;
  const cr = doc
    ? { left: 0, top: 0, width: window.innerWidth, height: window.innerHeight }
    : container.getBoundingClientRect();
  return {
    x: Math.min(Math.max(cr.left + cr.width / 2, 1), window.innerWidth - 1),
    y: Math.min(Math.max(cr.top + cr.height / 2, 1), window.innerHeight - 1),
    top: container.scrollTop,
    left: container.scrollLeft,
    maxTop: container.scrollHeight - container.clientHeight,
    maxLeft: container.scrollWidth - container.clientWidth
  };
}"
# The scroll probe: for EVERY scrollable ancestor of the first element,
# the delta that scrollIntoView(block/inline: 'nearest') would apply
# to bring the next-inner box (the element itself, or the inner
# container's clip) inside the container's clip -- the viewport
# (scrollingElement) is always the outermost, so a target visible inside
# a container that is below the fold still probes a nonzero outer
# delta. Inner deltas are invariant under outer scrolls, so wheeling
# outermost-first settles each level once. Returns the outermost
# container's nonzero delta (0/0 when the element is in view in every
# clip), that container's viewport center for cursor placement, the
# scroll positions of the whole chain (the R driver's stall check),
# and the chain length (its round bound). Computed without scrolling;
# the R driver re-probes after wheeling.
wheel_probe_js <- "function() {
  if (!this.length) return null;
  const el = this[0];
  const isScrollable = (e) => {
    if (e === document.scrollingElement) return true;
    const s = getComputedStyle(e);
    if (!/(auto|scroll)/.test(s.overflow + ' ' + s.overflowX + ' ' + s.overflowY)) {
      return false;
    }
    return e.scrollHeight > e.clientHeight || e.scrollWidth > e.clientWidth;
  };
  const clip = (c) => c === document.scrollingElement
    ? { top: 0, left: 0, bottom: window.innerHeight, right: window.innerWidth,
        width: window.innerWidth, height: window.innerHeight }
    : c.getBoundingClientRect();
  const chain = [];
  for (let e = el.parentElement; e; e = e.parentElement) {
    if (e !== document.scrollingElement && isScrollable(e)) chain.push(e);
  }
  chain.push(document.scrollingElement);
  let box = el.getBoundingClientRect();
  const pos = [];
  const deltas = [];
  for (let i = 0; i < chain.length; i++) {
    const c = chain[i];
    const cr = clip(c);
    let dy = 0;
    if (box.top < cr.top) dy = box.top - cr.top;
    else if (box.bottom > cr.bottom) dy = Math.min(box.top - cr.top, box.bottom - cr.bottom);
    let dx = 0;
    if (box.left < cr.left) dx = box.left - cr.left;
    else if (box.right > cr.right) dx = Math.min(box.left - cr.left, box.right - cr.right);
    const maxTop = c.scrollHeight - c.clientHeight;
    const maxLeft = c.scrollWidth - c.clientWidth;
    deltas.push({
      dx: Math.min(Math.max(c.scrollLeft + dx, 0), maxLeft) - c.scrollLeft,
      dy: Math.min(Math.max(c.scrollTop + dy, 0), maxTop) - c.scrollTop
    });
    pos.push(c.scrollTop, c.scrollLeft);
    box = cr;
  }
  let k = -1;
  for (let i = chain.length - 1; i >= 0; i--) {
    if (deltas[i].dx !== 0 || deltas[i].dy !== 0) { k = i; break; }
  }
  if (k === -1) {
    return { dx: 0, dy: 0, x: 0, y: 0, pos: pos, n: chain.length };
  }
  const cr = clip(chain[k]);
  return {
    x: Math.min(Math.max(cr.left + cr.width / 2, 1), window.innerWidth - 1),
    y: Math.min(Math.max(cr.top + cr.height / 2, 1), window.innerHeight - 1),
    dx: deltas[k].dx,
    dy: deltas[k].dy,
    pos: pos,
    n: chain.length
  };
}"
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

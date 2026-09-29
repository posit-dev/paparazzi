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
#' scrolling while the page is recording, as well as defaults for new
#' annotations. Only supplied arguments
#' change -- an omitted argument leaves its setting alone, while an
#' explicit `NULL` restores the default for that setting (so
#' `pz_stage(cursor = FALSE)` can be undone with `pz_stage(cursor =
#' NULL)`). Settings live on the page and persist across recordings, so
#' [pz_record_start()] never repeats them. Without a recording, staging
#' is skipped and the chain runs straight to its final state -- except
#' `cursor = TRUE`, which shows a static cursor in screenshots too.
#'
#' @inheritParams pz_click
#' @param ... Checked empty; reserved for future use.
#' @param cursor Cursor visibility: `NULL` (the default) shows the
#'   cursor only while recording, `TRUE` shows it always (stills too),
#'   `FALSE` never shows it. Supply `NULL` to restore the default.
#' @param cursor_speed Staging speed in pixels per second for cursor glides
#'   and recorded scrolls. The default, 500 px/s, gives viewers time to
#'   follow the movement; 400-600 px/s is a useful range for deliberate
#'   actions. Each glide uses its straight-line distance; each scroll
#'   uses the largest axis delta. Duration is
#'   `clamp(0.25 + distance / cursor_speed, 0.5, 2)` seconds: the 0.25s
#'   base makes short moves less sensitive to speed, and the 0.5-2s
#'   limits mean extreme speeds have little effect. Supply `NULL` to
#'   restore the default.
#' @param cursor_scale Cursor size relative to the original 20px overlay
#'   artwork, from greater than 0 to 5. The default is 1.75 (about 35px);
#'   use 1 for the original size. Applies to recordings and stills.
#'   Supply `NULL` to restore the default.
#' @param enter Where a cursor that has never been shown first appears:
#'   `NULL` (the default) fades in on the target; a side (`"top"`,
#'   `"bottom"`, `"left"`, `"right"`) or corner (`"top left"`,
#'   `"bottom right"`, ...) starts off-frame past that edge and glides
#'   in. Supply `NULL` to restore the default.
#' @param typing Typing style while recording: `"natural"` (the
#'   default) inserts one character at a time with randomized delays;
#'   `"instant"` inserts the whole string at once. Supply `NULL` to
#'   restore the default.
#' @param typing_speed Natural typing speed in characters per second.
#'   Supply `NULL` to restore the default.
#' @param pause Seconds to hold after each action while recording.
#'   Supply `NULL` to restore the default.
#' @param camera_follow Whether pointer and typing actions automatically pan
#'   a zoomed recording camera to keep their target in view. Defaults to
#'   `TRUE`; `FALSE` disables it and `NULL` restores the default.
#' @param show_keys Keystroke callouts for [pz_press()]: `"none"` (default),
#'   `"words"`, `"mac"`, or `"both"`. Supply `NULL` to restore the default.
#'   Callouts appear only in recordings.
#' @param annotate_color CSS color for new annotations. Supply `NULL` to
#'   restore the default.
#' @param annotate_font_family CSS font family for new annotation badges.
#'   Supply `NULL` to restore the default.
#' @param annotate_font_size Badge font size in CSS pixels. Supply `NULL`
#'   to restore the default.
#'
#' @return `ctx`, invisibly.
#'
#' @seealso [pz_cursor_show()], [pz_record_start()]
#'
#' @examplesIf rlang::is_interactive() && !is.null(suppressMessages(chromote::find_chrome())) && rlang::is_installed("av")
#' page <- pz_open(pz_example("tasks"))
#'
#' # Staging settings stay on the page until you change them
#' page |> pz_stage(enter = "left", cursor_speed = 500, typing_speed = 20, pause = 0.3)
#'
#' path <- file.path(tempdir(), "add-task.mp4")
#' page |>
#'   pz_record(path, {
#'     page |>
#'       pz_type("Buy milk", target = "#task-title") |>
#'       pz_click("#add-task")
#'   })
#'
#' # NULL restores a setting's default
#' page |> pz_stage(pause = NULL)
#'
#' # cursor = TRUE shows the cursor in screenshots too
#' page |>
#'   pz_stage(cursor = TRUE) |>
#'   pz_hover("#add-task") |>
#'   pz_screenshot(file.path(tempdir(), "cursor.png"), target = "#new-task")
#' pz_close(page)
#'
#' @export
pz_stage <- function(
  ctx,
  ...,
  cursor,
  cursor_speed,
  cursor_scale,
  enter,
  typing,
  typing_speed,
  pause,
  camera_follow,
  show_keys,
  annotate_color,
  annotate_font_family,
  annotate_font_size
) {
  check_context(ctx)
  check_dots_empty()
  page <- ctx$page
  overrides <- page$.__enclos_env__$private$staging_$stage %||% list()

  # missing() is the only way to leave a setting alone; an explicit
  # NULL removes the override (back to the default), a value sets it.
  if (!missing(cursor)) {
    if (is.null(cursor)) {
      overrides[["cursor"]] <- NULL
    } else {
      check_bool(cursor)
      overrides$cursor <- cursor
    }
  }
  if (!missing(cursor_speed)) {
    if (is.null(cursor_speed)) {
      overrides[["cursor_speed"]] <- NULL
    } else {
      check_number_decimal(cursor_speed, min = 1)
      overrides$cursor_speed <- cursor_speed
    }
  }
  if (!missing(cursor_scale)) {
    if (is.null(cursor_scale)) {
      overrides[["cursor_scale"]] <- NULL
    } else {
      check_number_decimal(
        cursor_scale,
        min = 0,
        max = 5,
        allow_infinite = FALSE
      )
      if (cursor_scale == 0) {
        cli::cli_abort("{.arg cursor_scale} must be greater than 0.")
      }
      overrides$cursor_scale <- cursor_scale
    }
  }
  if (!missing(enter)) {
    if (is.null(enter)) {
      overrides[["enter"]] <- NULL
    } else {
      overrides$enter <- parse_direction(
        enter,
        valid = STAGE_DIRECTIONS,
        arg = "enter"
      )
    }
  }
  if (!missing(typing)) {
    if (is.null(typing)) {
      overrides[["typing"]] <- NULL
    } else {
      overrides$typing <- arg_match(typing, c("natural", "instant"))
    }
  }
  if (!missing(typing_speed)) {
    if (is.null(typing_speed)) {
      overrides[["typing_speed"]] <- NULL
    } else {
      check_number_decimal(typing_speed, min = 0.1)
      overrides$typing_speed <- typing_speed
    }
  }
  if (!missing(pause)) {
    if (is.null(pause)) {
      overrides[["pause"]] <- NULL
    } else {
      check_number_decimal(pause, min = 0)
      overrides$pause <- pause
    }
  }
  if (!missing(camera_follow)) {
    if (is.null(camera_follow)) {
      overrides[["camera_follow"]] <- NULL
    } else {
      check_bool(camera_follow)
      overrides$camera_follow <- camera_follow
    }
  }
  if (!missing(show_keys)) {
    overrides$show_keys <- if (is.null(show_keys)) {
      NULL
    } else {
      arg_match(show_keys, c("none", "words", "mac", "both"))
    }
  }
  if (!missing(annotate_color)) {
    if (is.null(annotate_color)) {
      overrides[["annotate_color"]] <- NULL
    } else {
      check_string(annotate_color)
      overrides$annotate_color <- annotate_color
    }
  }
  if (!missing(annotate_font_family)) {
    if (is.null(annotate_font_family)) {
      overrides[["annotate_font_family"]] <- NULL
    } else {
      check_string(annotate_font_family)
      overrides$annotate_font_family <- annotate_font_family
    }
  }
  if (!missing(annotate_font_size)) {
    if (is.null(annotate_font_size)) {
      overrides[["annotate_font_size"]] <- NULL
    } else {
      check_number_decimal(annotate_font_size, min = 0, allow_infinite = FALSE)
      if (annotate_font_size == 0) {
        cli::cli_abort("{.arg annotate_font_size} must be greater than 0.")
      }
      overrides$annotate_font_size <- annotate_font_size
    }
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
  } else if (
    !missing(cursor_scale) &&
      !is.null(cur) &&
      !is.null(cur$x) &&
      cursor_visible(page)
  ) {
    cursor_draw(ctx, visible = TRUE)
  }
  ctx_return(ctx)
}

# The settings list with defaults filled. The page stores only the
# overrides pz_stage() was given, so later default changes reach pages
# that never set the field.
STAGE_DEFAULTS <- list(
  cursor = NULL,
  cursor_speed = 500,
  cursor_scale = 1.75,
  enter = NULL,
  typing = "natural",
  typing_speed = 16,
  pause = 0,
  camera_follow = TRUE,
  show_keys = "none",
  annotate_color = "#e11d48",
  annotate_font_family = "sans-serif",
  annotate_font_size = 14
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

stage_glide_duration <- function(from, to, speed) {
  dist <- sqrt((to[["x"]] - from[["x"]])^2 + (to[["y"]] - from[["y"]])^2)
  min(max(0.25 + dist / speed, 0.5), 2)
}

# The pointer-action seam, called from el_pointer_point() once the
# target's click point is known: while recording, the cursor gets to the
# point the way its state says -- fade in on it (never shown), glide in
# from the enter/off-frame side, or glide from its last position. Not
# recording, a visible cursor (cursor = TRUE, or explicitly shown)
# jumps to the point so stills track the real pointer.
stage_move_cursor <- function(ctx, point) {
  page <- ctx$page
  follow <- isTRUE(attr(point, "camera_follow"))
  if (!cursor_visible(page)) {
    if (follow) {
      stage_follow_without_glide(ctx, attr(point, "rect"))
    }
    return(ctx_return(ctx))
  }
  if (!stage_recording(page)) {
    cursor_apply(ctx, point)
    return(ctx_return(ctx))
  }
  if (is.null(attr(point, "rect"))) {
    # The action seam supplies an actionable viewport point, not its
    # resolved element; hit-testing that point recovers its visible rect.
    rect <- pz_js(
      ctx,
      paste0(
        "(() => { const el = document.elementFromPoint(",
        point[["x"]],
        ",",
        point[["y"]],
        "); if (!el) return null; const r = el.getBoundingClientRect();",
        " return [r.x, r.y, r.width, r.height]; })()"
      )
    )
    if (!is.null(rect)) {
      attr(point, "rect") <- set_names(
        unlist(rect),
        c("x", "y", "width", "height")
      )
    }
  }
  cursor_show_at(ctx, point, follow = follow)
  ctx_return(ctx)
}

stage_follow_without_glide <- function(ctx, rect) {
  if (is.null(rect) || !camera_follow_move(ctx, rect, 0.5)) {
    return(ctx_return(ctx))
  }
  if (!page_recorder(ctx$page)$paused) {
    pump_loop(ctx$page$child_loop, 0.5)
  }
  ctx_return(ctx)
}

# The scroll half of the el_pointer_point() seam. Recording: animated
# wheel scrolling over the container; not recording: the established
# instant scroll.
stage_scroll_into_view <- function(
  ctx,
  els,
  duration = NULL,
  call = caller_env()
) {
  if (!stage_recording(ctx$page) || isTRUE(duration == 0)) {
    return(el_scroll_into_view(els, call = call))
  }
  stage_wheel_into_view(ctx, els, duration = duration, call = call)
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
stage_wheel_into_view <- function(
  ctx,
  els,
  duration = NULL,
  call = caller_env()
) {
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
    if (!isTRUE(probe$hit > 0)) {
      # No point where a wheel would reach the container (a nested
      # scroller covers the dispatch point and would consume it): the
      # instant scroll runs BEFORE any wheel can change another
      # container.
      return(el_scroll_into_view(els, call = call))
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
    wheel_duration <- duration %||%
      min(max(0.25 + max(abs(delta)) / stage$cursor_speed, 0.5), 2)
    stage_wheel(ctx, point, delta[[1]], delta[[2]], wheel_duration, call = call)
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
# cursor over it, then verify and repair. The wheel point is hit-tested
# for the container first -- a nested scroller covering it would
# consume the wheels and leave a state the instant path never produces
# -- and when no suitable point exists the instant application runs
# BEFORE any wheel fires. After the wheels, a miss (clamping,
# canceling) still repairs instantly so the final position is exact.
scroll_staged <- function(
  ctx,
  scoped,
  by,
  to,
  duration = NULL,
  call = caller_env()
) {
  # A wheel only lands on a container the cursor point is actually
  # over; a scoped container outside the viewport is first brought
  # into view -- the staged way while recording, like every other
  # pre-action scroll (a no-op when it already is).
  if (!is.null(scoped)) {
    stage_scroll_into_view(ctx, scoped, duration = duration, call = call)
  }
  # The container probe, with or without an aim (the target scroll
  # position, which turns on the hit test); one function serves the
  # pinned scoped set and the root's empty-array rooting.
  wheel_container <- function(aim = NULL) {
    if (!is.null(scoped)) {
      if (is.null(aim)) {
        els_values(scoped, wheel_container_js, call = call)
      } else {
        els_values(
          scoped,
          wheel_container_js,
          args = list(list(value = c(aim[[1]], aim[[2]]))),
          doing = "working with",
          call = call
        )
      }
    } else {
      pz_js(
        ctx,
        paste0(
          "(",
          wheel_container_js,
          ").call([]",
          if (is.null(aim)) "" else paste0(", ", jsonlite::toJSON(unname(aim))),
          ")"
        )
      )
    }
  }
  apply_instant <- function(actual) {
    arg <- scroll_arg_json(
      by = if (!is.null(by)) {
        c(target$left - actual$left, target$top - actual$top)
      },
      to = to
    )
    if (!is.null(scoped)) {
      arg_list <- if (!is.null(by)) {
        list(
          by = as.list(c(target$left - actual$left, target$top - actual$top))
        )
      } else {
        list(to = as.list(to))
      }
      els_values(
        scoped,
        scroll_apply_js,
        args = list(list(value = arg_list)),
        doing = "working with",
        call = call
      )
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
    ctx_return(ctx)
  }
  probe <- wheel_container()
  target <- scroll_wheel_target(probe, by, to)
  delta <- c(target$left - probe$left, target$top - probe$top)
  if (all(delta == 0)) {
    return(ctx_return(ctx))
  }
  # A wheel at the container's center only reaches the container when
  # the point is over it; no such point means the instant application
  # runs before any wheel fires.
  if (!isTRUE(wheel_container(c(target$left, target$top))$hit > 0)) {
    apply_instant(probe)
    return(ctx_return(ctx))
  }
  point <- c(x = probe$x, y = probe$y)
  stage_move_cursor(ctx, point)
  stage <- page_stage(ctx$page)
  wheel_duration <- duration %||%
    min(max(0.25 + max(abs(delta)) / stage$cursor_speed, 0.5), 2)
  stage_wheel(ctx, point, delta[[1]], delta[[2]], wheel_duration, call = call)
  # Verify and repair: wheels are best-effort (clamping, canceling),
  # the recorded end state must match the instant path.
  actual <- wheel_container()
  if (abs(actual$top - target$top) > 2 || abs(actual$left - target$left) > 2) {
    apply_instant(actual)
  }
  ctx_return(ctx)
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
    if ("left" %in% to) {
      left <- 0
    }
    if ("right" %in% to) {
      left <- probe$maxLeft
    }
    if (center) {
      left <- probe$maxLeft / 2
    }
    if ("top" %in% to) {
      top <- 0
    }
    if ("bottom" %in% to) {
      top <- probe$maxTop
    }
    if (center) top <- probe$maxTop / 2
  }
  list(
    left = min(max(left, 0), probe$maxLeft),
    top = min(max(top, 0), probe$maxTop)
  )
}

# The wheel-latching hit test, interpolated into the two probe functions
# (it closes over their isScrollable): a wheel dispatched at (x, y)
# scrolls the nearest scrollable ancestor of the element under the
# point that can consume the delta, so it reaches `container` only
# when no nearer scroller intervenes. elementFromPoint() passes
# through the overlay's pointer-events: none. Returns 1/0.
wheel_hit_js <- "const wheelHit = (container, x, y, dx, dy) => {
  const canConsume = (c) =>
    (dy < 0 && c.scrollTop > 0) ||
    (dy > 0 && c.scrollTop < c.scrollHeight - c.clientHeight) ||
    (dx < 0 && c.scrollLeft > 0) ||
    (dx > 0 && c.scrollLeft < c.scrollWidth - c.clientWidth);
  const under = document.elementFromPoint(x, y);
  if (!under) return 0;
  for (let e = under; e; e = e.parentElement) {
    if (e === container) return 1;
    if (isScrollable(e) && canConsume(e)) return 0;
  }
  return 0;
};"

# The container probe for by/to scrolls: the current scope's scroll
# container (the scope element or its nearest scrollable ancestor, the
# document at the root -- the same walk scroll_apply_js does), its
# viewport center for cursor placement, and its scroll position and
# range. With an `aim` (the target scroll position, [left, top]) it
# also hit-tests the center point for that delta, so a wheel is only
# dispatched when it would reach the container. One function serves
# both rootings: callFunctionOn on the pinned set as `this`, or
# Runtime$evaluate with `this` an empty array.
wheel_container_js <- paste0(
  "function(aim) {
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
  ",
  wheel_hit_js,
  "
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
  const x = Math.min(Math.max(cr.left + cr.width / 2, 1), window.innerWidth - 1);
  const y = Math.min(Math.max(cr.top + cr.height / 2, 1), window.innerHeight - 1);
  let hit = 1;
  if (aim) {
    const dx = aim[0] - container.scrollLeft;
    const dy = aim[1] - container.scrollTop;
    if (dx !== 0 || dy !== 0) {
      hit = wheelHit(container, x, y, dx, dy);
    }
  }
  return {
    x: x,
    y: y,
    top: container.scrollTop,
    left: container.scrollLeft,
    maxTop: container.scrollHeight - container.clientHeight,
    maxLeft: container.scrollWidth - container.clientWidth,
    hit: hit
  };
}"
)

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
wheel_probe_js <- paste0(
  "function() {
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
  ",
  wheel_hit_js,
  "
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
    return { dx: 0, dy: 0, hit: 1, x: 0, y: 0, pos: pos, n: chain.length };
  }
  const cr = clip(chain[k]);
  const x = Math.min(Math.max(cr.left + cr.width / 2, 1), window.innerWidth - 1);
  const y = Math.min(Math.max(cr.top + cr.height / 2, 1), window.innerHeight - 1);
  return {
    x: x,
    y: y,
    dx: deltas[k].dx,
    dy: deltas[k].dy,
    hit: wheelHit(chain[k], x, y, deltas[k].dx, deltas[k].dy),
    pos: pos,
    n: chain.length
  };
}"
)

# pz_stage(pause =): a hold after each action while recording, skipped
# otherwise (the SPEC matrix). Real time passes -- the recorded frames
# capture the settled page.
stage_action_pause <- function(ctx) {
  page <- ctx$page
  if (!stage_recording(page)) {
    return(ctx_return(ctx))
  }
  pause <- page_stage(page)$pause
  if (pause > 0) {
    pump_loop(page$child_loop, pause)
  }
  ctx_return(ctx)
}

# The record-stop hook (called from pz_record_stop()): an auto cursor
# under cursor = NULL belongs to the recording, so it goes away when the
# recording ends; an explicitly shown cursor or cursor = TRUE stays.
stage_record_stopped <- function(ctx) {
  page <- ctx$page
  if (page$is_closed()) {
    return(ctx_return(ctx))
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
  ctx_return(ctx)
}

# Staging: the per-page settings that make recorded runs watchable --
# cursor visibility and glide speed, entrance side, natural typing, and
# a hold after each action. Settings live on the page and persist across
# recordings. Staging only animates WHILE RECORDING (recorder_active());
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
#' change -- an omitted argument leaves its setting alone, an explicit
#' `NULL` restores the default, and a value sets it (so
#' `pz_stage(cursor = FALSE)` can be undone with `pz_stage(cursor =
#' NULL)`). Settings live on the page and persist across recordings, so
#' [pz_record_start()] never repeats them. Without a recording, staging
#' is skipped and the chain runs straight to its final state -- except
#' `cursor = TRUE`, which shows a static cursor in screenshots too.
#'
#' @inheritParams pz_act_click
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
#'   The default is 16. Supply `NULL` to restore the default.
#' @param pause Seconds to hold after each action while recording.
#'   The default is 0. Supply `NULL` to restore the default.
#' @param camera_follow Whether pointer and typing actions automatically pan
#'   a zoomed recording camera to keep their target in view. Defaults to
#'   `TRUE`; `FALSE` disables it and `NULL` restores the default.
#' @param show_keys Keystroke callouts for [pz_act_press()]: `"none"` (default),
#'   `"words"`, `"mac"`, or `"both"`. Supply `NULL` to restore the default.
#'   Callouts appear only in recordings.
#' @param click_effect Click feedback shown by [pz_act_click()] while
#'   recording: `"press"` (the default) scales the cursor down while
#'   pressed, `"ring"` draws an expanding ring that fades out at the
#'   click point instead of scaling, and `"none"` shows nothing.
#'   Supply `NULL` to restore the default.
#' @param click_effect_color CSS color of the `"ring"` click effect.
#'   The default is `"#e11d48"`. Supply `NULL` to restore the default.
#'
#' @return `ctx`, invisibly.
#'
#' @seealso [pz_stage_frame()], [pz_stage_annotate()], [pz_cursor_show()],
#'   [pz_record_start()]
#'
#' @examplesIf paparazzi:::examples_run("av")
#' page <- pz_open(pz_example("tasks"))
#'
#' # Staging settings stay on the page until you change them
#' page |> pz_stage(enter = "left", cursor_speed = 500, typing_speed = 20, pause = 0.3)
#'
#' # Recorded clicks show a custom-colored ring
#' page |> pz_stage(click_effect = "ring", click_effect_color = "#2563eb")
#'
#' path <- file.path(tempdir(), "add-task.mp4")
#' page |>
#'   pz_record(path, {
#'     page |>
#'       pz_act_type("Buy milk", target = "#task-title") |>
#'       pz_act_click("#add-task")
#'   })
#'
#' # NULL restores a setting's default
#' page |> pz_stage(pause = NULL)
#'
#' # cursor = TRUE shows the cursor in screenshots too
#' page |>
#'   pz_stage(cursor = TRUE) |>
#'   pz_act_hover("#task-title") |>
#'   pz_screenshot(file.path(tempdir(), "cursor.png"), frame = "#new-task")
#' pz_close(page)
#'
#' @export
pz_stage <- function(
  ctx,
  ...,
  cursor = NULL,
  cursor_speed = NULL,
  cursor_scale = NULL,
  enter = NULL,
  typing = NULL,
  typing_speed = NULL,
  pause = NULL,
  camera_follow = NULL,
  show_keys = NULL,
  click_effect = NULL,
  click_effect_color = NULL
) {
  check_context(ctx)
  check_dots_empty()
  page <- ctx$page
  overrides <- page$staging$stage %||% list()

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
  if (!missing(click_effect)) {
    overrides$click_effect <- if (is.null(click_effect)) {
      NULL
    } else {
      arg_match(click_effect, c("press", "ring", "none"))
    }
  }
  if (!missing(click_effect_color)) {
    if (is.null(click_effect_color)) {
      overrides[["click_effect_color"]] <- NULL
    } else {
      check_string(click_effect_color, allow_empty = FALSE)
      overrides$click_effect_color <- click_effect_color
    }
  }
  page_set_stage(page, overrides)

  stage <- page_stage(page)
  cur <- page_cursor_peek(page)
  if (identical(stage$cursor, FALSE)) {
    if (!is.null(cur) && !is.null(cur$x)) {
      cursor_draw(ctx, visible = FALSE)
    }
  } else if (isTRUE(stage$cursor) && cursor_drawn(page)) {
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
      cursor_drawn(page)
  ) {
    cursor_draw(ctx, visible = TRUE)
  }
  ctx_return(ctx)
}

#' Set the page's annotation style defaults
#'
#' Sets persistent page defaults for new annotations in screenshots and
#' recordings. An omitted argument leaves its setting alone, an explicit
#' `NULL` restores its default, and a value sets it. Per-call annotation
#' style arguments override these defaults; note the per-call names on
#' [pz_annotate()] differ (`label_fill`/`label_text_color`) from the staged
#' names (`fill`/`text_color`), and the staged fill and text color style
#' callout chrome only, not mark badges.
#'
#' @inheritParams pz_act_click
#' @param ... Checked empty; reserved for future use.
#' @param color CSS accent color for new annotations: mark outlines, callout
#'   bubble borders, leader lines and decorations. The default is `"#e11d48"`.
#'   Supply `NULL` to restore the default.
#' @param fill CSS background color for new callout bubbles and their
#'   badges. The default is `"#171717"`. Supply `NULL` to restore the
#'   default. Callout chrome only: [pz_annotate()] mark badges follow their
#'   mark's `color` unless overridden per call with `label_fill`.
#' @param text_color CSS text color for new callout bubbles and their
#'   badges. The default is `"white"`. Supply `NULL` to restore the
#'   default. Callout chrome only, like `fill`.
#' @param stroke_width Stroke width in CSS pixels for new annotation marks
#'   and callout leader lines; decoration sizes scale with it. The default
#'   is 3. Supply `NULL` to restore the default.
#' @param distance Bubble-to-target gap in CSS pixels for new callouts,
#'   with or without a leader. By default the gap is 24 with a leader and
#'   8 without one. Supply `NULL` to restore the default.
#' @param font_family CSS font family for new annotation badges and key
#'   callouts. The default is `"sans-serif"`. Supply `NULL` to restore the
#'   default. A font object staged with [pz_stage_fonts()] is also accepted
#'   and resolves to its family with a sans-serif fallback.
#' @param font_size Badge font size in CSS pixels. The default is 14.
#'   Supply `NULL` to restore the default.
#'
#' @return `ctx`, invisibly.
#' @seealso [pz_stage()], [pz_stage_frame()], [pz_annotate()]
#'
#' @examplesIf paparazzi:::examples_run(site = TRUE)
#' page <- pz_open(pz_example("tasks"))
#' path <- file.path(tempdir(), "tasks.png")
#'
#' page |>
#'   # New annotations on this page use these styles
#'   pz_stage_annotate(color = "#2563eb", font_size = 16) |>
#'   pz_annotate("#add-task", label = TRUE) |>
#'   pz_screenshot(path) |>
#'   # NULL restores a default
#'   pz_stage_annotate(color = NULL)
#' pz_screenshot(page, frame = pz_frame("#new-task", pad = 16, target_box = "annotated"))
#' pz_close(page)
#'
#' @export
pz_stage_annotate <- function(
  ctx,
  ...,
  color = NULL,
  fill = NULL,
  text_color = NULL,
  stroke_width = NULL,
  distance = NULL,
  font_family = NULL,
  font_size = NULL
) {
  check_context(ctx)
  check_dots_empty()
  page <- ctx$page
  overrides <- page$staging$stage %||% list()
  if (!missing(color)) {
    if (is.null(color)) {
      overrides[["annotate_color"]] <- NULL
    } else {
      check_string(color, allow_empty = FALSE)
      overrides$annotate_color <- color
    }
  }
  if (!missing(font_family)) {
    if (is.null(font_family)) {
      overrides[["annotate_font_family"]] <- NULL
    } else {
      overrides$annotate_font_family <- check_font_family(font_family, page)
    }
  }
  if (!missing(fill)) {
    if (is.null(fill)) {
      overrides[["annotate_fill"]] <- NULL
    } else {
      check_string(fill, allow_empty = FALSE)
      overrides$annotate_fill <- fill
    }
  }
  if (!missing(text_color)) {
    if (is.null(text_color)) {
      overrides[["annotate_text_color"]] <- NULL
    } else {
      check_string(text_color, allow_empty = FALSE)
      overrides$annotate_text_color <- text_color
    }
  }
  if (!missing(stroke_width)) {
    if (is.null(stroke_width)) {
      overrides[["annotate_stroke_width"]] <- NULL
    } else {
      check_positive_css_px(stroke_width, arg = "stroke_width")
      overrides$annotate_stroke_width <- stroke_width
    }
  }
  if (!missing(distance)) {
    if (is.null(distance)) {
      overrides[["annotate_distance"]] <- NULL
    } else {
      check_number_decimal(distance, min = 0, allow_infinite = FALSE)
      overrides$annotate_distance <- distance
    }
  }
  if (!missing(font_size)) {
    if (is.null(font_size)) {
      overrides[["annotate_font_size"]] <- NULL
    } else {
      check_positive_css_px(font_size)
      overrides$annotate_font_size <- font_size
    }
  }
  page_set_stage(page, overrides)
  ctx_return(ctx)
}

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
  click_effect = "press",
  click_effect_color = "#e11d48",
  annotate_color = "#e11d48",
  annotate_fill = "#171717",
  annotate_text_color = "white",
  annotate_stroke_width = 3,
  annotate_distance = NULL,
  annotate_font_family = "sans-serif",
  annotate_font_size = 14
)

page_stage <- function(page) {
  overrides <- page$staging$stage
  utils::modifyList(STAGE_DEFAULTS, overrides %||% list())
}

page_set_stage <- function(page, overrides) {
  page$staging$stage <- overrides
  invisible(page)
}

recorder_active <- function(page) {
  rec <- page_recorder(page)
  !is.null(rec) && isTRUE(rec$active)
}

stage_glide_duration <- function(from, to, speed) {
  dist <- sqrt((to[["x"]] - from[["x"]])^2 + (to[["y"]] - from[["y"]])^2)
  min(max(0.25 + dist / speed, 0.5), 2)
}

stage_move_cursor <- function(ctx, point) {
  page <- ctx$page
  follow <- isTRUE(attr(point, "camera_follow"))
  if (!cursor_visible(page)) {
    if (follow) {
      stage_follow_without_glide(ctx, attr(point, "rect"))
    }
    return(ctx_return(ctx))
  }
  if (!recorder_active(page)) {
    cursor_apply(ctx, point)
    return(ctx_return(ctx))
  }
  if (is.null(attr(point, "rect"))) {
    attr(point, "rect") <- point_hit_rect(ctx, point)
  }
  cursor_show_at(ctx, point, follow = follow)
  ctx_return(ctx)
}

point_hit_rect <- function(ctx, point) {
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
  if (is.null(rect)) {
    return(NULL)
  }
  set_names(unlist(rect), c("x", "y", "width", "height"))
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

stage_scroll_into_view <- function(
  ctx,
  els,
  duration = NULL,
  call = caller_env()
) {
  if (!recorder_active(ctx$page) || isTRUE(duration == 0)) {
    return(el_scroll_into_view(els, call = call))
  }
  stage_wheel_into_view(ctx, els, duration = duration, call = call)
}

stage_wheel_into_view <- function(
  ctx,
  els,
  duration = NULL,
  call = caller_env()
) {
  if (els$count == 0L) {
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
      return(el_scroll_into_view(els, call = call))
    }
    pos <- unlist(probe$positions)
    rounds <- rounds + 1L
    stalled <- !is.null(prev) && identical(pos, prev)
    max_rounds <- 2L * probe$chainLength + 3L
    if (stalled || rounds > max_rounds) {
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

stage_drag_carry <- function(ctx, from, to, step) {
  page <- ctx$page
  duration <- stage_glide_duration(from, to, page_stage(page)$cursor_speed)
  cursor_apply(ctx, to, duration = duration, pressed = TRUE, pump = FALSE)
  start <- Sys.time()
  interval <- 1 / 30
  lead <- interval / 2
  repeat {
    elapsed <- as.numeric(difftime(Sys.time(), start, units = "secs"))
    at <- (elapsed + lead) / duration
    if (at >= 1) {
      break
    }
    ease <- glide_ease_invert(at, glide_ease_x, glide_ease_y)
    point <- c(
      x = unname(from[["x"]] + (to[["x"]] - from[["x"]]) * ease),
      y = unname(from[["y"]] + (to[["y"]] - from[["y"]]) * ease)
    )
    dispatched <- proc.time()[["elapsed"]]
    step(point)
    rest <- interval - (proc.time()[["elapsed"]] - dispatched)
    if (rest > 0.005) {
      pump_loop(page$child_loop, rest, interval = min(rest, 0.02))
    }
  }
  rest <- as.numeric(difftime(
    start + duration + 0.05,
    Sys.time(),
    units = "secs"
  ))
  if (rest > 0) {
    pump_loop(page$child_loop, rest, interval = min(rest, 0.02))
  }
  invisible(TRUE)
}

scroll_staged <- function(
  ctx,
  scoped,
  by,
  to,
  duration = NULL,
  call = caller_env()
) {
  if (!is.null(scoped)) {
    stage_scroll_into_view(ctx, scoped, duration = duration, call = call)
  }
  wheel_container <- function() {
    if (!is.null(scoped)) {
      els_values(scoped, wheel_container_js, call = call)
    } else {
      pz_js(ctx, paste0("(", wheel_container_js, ").call([])"))
    }
  }
  wheel_container_hit <- function(aim) {
    if (!is.null(scoped)) {
      els_values(
        scoped,
        wheel_container_hit_js,
        args = list(list(value = c(aim[[1]], aim[[2]]))),
        doing = "working with",
        call = call
      )
    } else {
      pz_js(
        ctx,
        paste0(
          "(",
          wheel_container_hit_js,
          ").call([], ",
          js_literal(unname(aim), auto_unbox = FALSE),
          ")"
        )
      )
    }
  }
  apply_instant <- function(actual) {
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
      arg <- scroll_arg_json(
        by = if (!is.null(by)) {
          c(target$left - actual$left, target$top - actual$top)
        },
        to = to
      )
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
  if (!isTRUE(wheel_container_hit(c(target$left, target$top)) > 0)) {
    apply_instant(probe)
    return(ctx_return(ctx))
  }
  point <- c(x = probe$x, y = probe$y)
  stage_move_cursor(ctx, point)
  stage <- page_stage(ctx$page)
  wheel_duration <- duration %||%
    min(max(0.25 + max(abs(delta)) / stage$cursor_speed, 0.5), 2)
  stage_wheel(ctx, point, delta[[1]], delta[[2]], wheel_duration, call = call)
  actual <- wheel_container()
  if (abs(actual$top - target$top) > 2 || abs(actual$left - target$left) > 2) {
    apply_instant(actual)
  }
  ctx_return(ctx)
}

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

# A wheel dispatched at (x, y) scrolls the nearest scrollable ancestor
# of the element under the point that can consume the delta, so it
# reaches `container` only when no nearer scroller intervenes.
wheel_hit_js <- "const isScrollable = (e) => {
  if (e === document.scrollingElement) return true;
  const s = getComputedStyle(e);
  if (!/(auto|scroll)/.test(s.overflow + ' ' + s.overflowX + ' ' + s.overflowY)) {
    return false;
  }
  return e.scrollHeight > e.clientHeight || e.scrollWidth > e.clientWidth;
};
const wheelHit = (container, x, y, dx, dy) => {
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

wheel_container_setup_js <- paste0(
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
"
)

wheel_container_js <- paste0(
  "function() {
",
  wheel_container_setup_js,
  "
  return {
    x: x,
    y: y,
    top: container.scrollTop,
    left: container.scrollLeft,
    maxTop: container.scrollHeight - container.clientHeight,
    maxLeft: container.scrollWidth - container.clientWidth
  };
}"
)

wheel_container_hit_js <- paste0(
  "function(aim) {
",
  wheel_container_setup_js,
  "
  const dx = aim[0] - container.scrollLeft;
  const dy = aim[1] - container.scrollTop;
  return dx === 0 && dy === 0 ? 1 : wheelHit(container, x, y, dx, dy);
}"
)

wheel_probe_js <- paste0(
  "function() {
  if (!this.length) return null;
  const el = this[0];
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
    return { dx: 0, dy: 0, hit: 1, x: 0, y: 0, positions: pos, chainLength: chain.length };
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
    positions: pos,
    chainLength: chain.length
  };
}"
)

stage_action_pause <- function(ctx) {
  page <- ctx$page
  if (!recorder_active(page)) {
    return(ctx_return(ctx))
  }
  pause <- page_stage(page)$pause
  if (pause > 0) {
    pump_loop(page$child_loop, pause)
  }
  ctx_return(ctx)
}

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
  } else if (isTRUE(cur$resting)) {
    cur$resting <- FALSE
    cursor_draw(ctx, visible = cursor_visible(page))
  }
  if (!is.null(cur)) {
    cur$resting <- FALSE
  }
  ctx_return(ctx)
}

# The overlay cursor: a fake pointer drawn under the existing
# #paparazzi-overlay-root host (its shadow root), as a sibling layer of
# the inspect outlines. Living under that host is what excludes the
# cursor from pz_find() and every bounding-box computation (the resolver
# filters closest('#paparazzi-overlay-root'), which matches the host
# itself); pointer-events: none keeps hit-testing and elementFromPoint()
# aimed at the page. All animation is page-side CSS transitions; the R
# side sets end states and pumps the child loop (see R/stage.R), so the
# recorder's ticks capture the intermediate frames.
#' Show the overlay cursor
#'
#' @description
#' Shows paparazzi's overlay cursor, optionally over a `target` element.
#' While recording, the cursor appears with staging: it glides from its
#' last position, fades in on the target when it has never been shown,
#' or glides in from `from` (or the `enter` side set with [pz_stage()])
#' when entering the frame. Without a recording the cursor appears
#' statically, which is how a cursor lands in a screenshot. Its default
#' size is 1.75 times the original artwork; set `cursor_scale` with
#' [pz_stage()] to change the size in videos and stills.
#'
#' @inheritParams pz_click
#' @param target A CSS selector string, a [pz_loc()] spec, or a list of
#'   specs. The cursor centers on the match. `NULL` uses the current
#'   scope's element or, at the root context, shows the cursor at its
#'   last position (or the viewport center the first time).
#' @param from A side (`"top"`, `"bottom"`, `"left"`, `"right"`) or
#'   corner (`"top left"`, `"bottom right"`, ...) of the frame to enter
#'   from. `NULL` (the default) re-enters from the direction the cursor
#'   last left through (see [pz_cursor_leave()]); a cursor that has never
#'   been shown uses the `enter` setting of [pz_stage()]. Otherwise the
#'   cursor glides from its current position.
#'
#' @return `ctx`, invisibly.
#'
#' @seealso [pz_stage()] for cursor settings, [pz_cursor_hide()],
#'   [pz_cursor_move()], [pz_cursor_leave()]
#'
#' @examplesIf rlang::is_interactive() && !is.null(suppressMessages(chromote::find_chrome()))
#' page <- pz_open(pz_example("tasks"))
#' path <- file.path(tempdir(), "add-button.png")
#'
#' # Outside a recording the cursor appears at once, ready for a still
#' page |>
#'   pz_cursor_show("#add-task") |>
#'   pz_screenshot(path, target = "#new-task", frame = pz_frame(pad = 24))
#' pz_close(page)
#'
#' @export
pz_cursor_show <- function(ctx, target = NULL, ..., from = NULL, icon = NULL) {
  icon <- cursor_check_icon(icon)
  check_context(ctx)
  check_dots_empty()
  from <- if (!is.null(from)) {
    parse_direction(from, valid = STAGE_DIRECTIONS, arg = "from")
  }
  check_cursor_enabled(ctx)
  cur <- page_cursor(ctx$page)
  cur$visibility <- "shown"

  point <- if (!is.null(target)) {
    cursor_target_point(ctx, target)
  } else {
    scoped <- scope_root(ctx)
    if (!is.null(scoped)) {
      check_scope_single(scoped)
      stage_scroll_into_view(ctx, scoped)
      rects <- el_rects(scoped)
      c(
        x = rects$x[[1]] + rects$width[[1]] / 2,
        y = rects$y[[1]] + rects$height[[1]] / 2
      )
    } else {
      cursor_current_point(ctx)
    }
  }
  cursor_show_at(ctx, point, from = from, icon = icon)
  invisible(ctx)
}

#' Hide the overlay cursor
#'
#' Hides the cursor set up by [pz_cursor_show()] or shown implicitly
#' while recording. The cursor keeps its last position; showing it
#' again returns it there. The hide is explicit and sticky: the cursor
#' stays hidden until [pz_cursor_show()] or [pz_cursor_move()] shows it
#' again -- neither a recorded pointer action nor the `cursor` staging
#' setting brings it back. That is what distinguishes
#' `pz_cursor_hide()` from [pz_cursor_leave()], which keeps the cursor
#' visible and glides back in on the next action.
#'
#' @inheritParams pz_click
#'
#' @return `ctx`, invisibly.
#'
#' @seealso [pz_cursor_show()], [pz_cursor_leave()]
#'
#' @examplesIf rlang::is_interactive() && !is.null(suppressMessages(chromote::find_chrome()))
#' page <- pz_open(pz_example("tasks"))
#' page |>
#'   pz_cursor_show("#add-task") |>
#'   pz_cursor_hide() |>
#'   pz_screenshot(file.path(tempdir(), "no-cursor.png"))
#' pz_close(page)
#'
#' @export
pz_cursor_hide <- function(ctx, ...) {
  check_context(ctx)
  check_dots_empty()
  cur <- page_cursor(ctx$page)
  cur$visibility <- "hidden"
  if (!is.null(cur$x)) {
    cursor_draw(ctx, visible = FALSE)
    if (stage_recording(ctx$page) && is.null(cur$off_frame)) {
      pump_loop(ctx$page$child_loop, 0.25)
    }
  }
  invisible(ctx)
}

#' Move the overlay cursor to an element
#'
#' Moves the cursor over `target`, showing it first if hidden. While
#' recording the move is a glide whose duration scales with distance
#' (see [pz_stage()]); pass `duration` to override it. Without a
#' recording the cursor jumps.
#'
#' @inheritParams pz_click
#' @param target A CSS selector string, a [pz_loc()] spec, or a list of
#'   specs. The cursor centers on the match.
#' @param duration Glide duration in seconds; `NULL` computes one from
#'   the distance and the `cursor_speed` staging setting.
#'
#' @return `ctx`, invisibly.
#'
#' @seealso [pz_cursor_show()], [pz_cursor_leave()]
#'
#' @examplesIf rlang::is_interactive() && !is.null(suppressMessages(chromote::find_chrome())) && rlang::is_installed("av")
#' page <- pz_open(pz_example("tasks"))
#' path <- file.path(tempdir(), "tour.mp4")
#'
#' # While recording, the cursor glides between elements
#' page |>
#'   pz_record(path, {
#'     page |>
#'       pz_cursor_show(".filters", from = "left") |>
#'       pz_cursor_move("#toggle-help", duration = 1) |>
#'       pz_cursor_move("#add-task")
#'   })
#' pz_close(page)
#'
#' @export
pz_cursor_move <- function(ctx, target, ..., duration = NULL, icon = NULL) {
  icon <- cursor_check_icon(icon)
  check_context(ctx)
  check_dots_empty()
  check_number_decimal(
    duration,
    min = 0,
    allow_null = TRUE,
    allow_infinite = FALSE
  )
  check_cursor_enabled(ctx)
  cur <- page_cursor(ctx$page)
  cur$visibility <- "shown"

  point <- cursor_target_point(ctx, target)
  cursor_show_at(ctx, point, duration = duration, icon = icon)
  invisible(ctx)
}

#' Move the overlay cursor out of the frame
#'
#' Sends the cursor out of the frame through `side`: while recording it
#' glides out, otherwise it leaves immediately. The cursor is still
#' visible (just off-frame); the next pointer action or cursor call
#' glides it back in from that side.
#'
#' @inheritParams pz_click
#' @param side A side (`"top"`, `"bottom"`, `"left"`, `"right"`) or
#'   corner (`"top left"`, `"bottom right"`, ...) of the frame to leave
#'   through. Defaults to `"right"`.
#'
#' @return `ctx`, invisibly.
#'
#' @seealso [pz_cursor_show()]
#'
#' @examplesIf rlang::is_interactive() && !is.null(suppressMessages(chromote::find_chrome())) && rlang::is_installed("av")
#' page <- pz_open(pz_example("tasks"))
#' path <- file.path(tempdir(), "help.mp4")
#' page |>
#'   pz_record(path, {
#'     page |>
#'       pz_click("#toggle-help") |>
#'       # Move the cursor out of the way so the help text is unobstructed
#'       pz_cursor_leave("right") |>
#'       pz_record_hold(1)
#'   })
#' pz_close(page)
#'
#' @export
pz_cursor_leave <- function(ctx, side = "right", icon = NULL) {
  icon <- cursor_check_icon(icon)
  check_context(ctx)
  side <- parse_direction(side, valid = STAGE_DIRECTIONS, arg = "side")
  check_cursor_enabled(ctx)
  page <- ctx$page
  cur <- page_cursor(page)

  point <- cursor_off_frame_point(ctx, side, cursor_current_point(ctx))
  duration <- if (!is.null(cur$x)) {
    stage_glide_duration(
      c(x = cur$x, y = cur$y),
      point,
      page_stage(page)$cursor_speed
    )
  }
  cursor_apply(
    ctx,
    point,
    duration = duration %||% 0,
    icon = icon %||% cur$icon
  )
  # Set after cursor_apply(), which clears it: the cursor stays visible
  # but off-frame, and the next action glides back in from this side.
  cur$off_frame <- side
  invisible(ctx)
}

# The sides-and-corners subset of the direction vocabulary, for
# pz_stage(enter =), pz_cursor_show(from =), and pz_cursor_leave(side =).
# Corners enter/leave past both edges at once.
STAGE_DIRECTIONS <- list(
  c("top"),
  c("bottom"),
  c("left"),
  c("right"),
  c("left", "top"),
  c("right", "top"),
  c("bottom", "left"),
  c("bottom", "right")
)

# The cursor runtime state: a mutable environment in the page's reserved
# private$staging_$cursor slot, created on first cursor use and reached
# only through these accessors (the page_frame() pattern). Fields:
# visibility ("auto"/"shown"/"hidden"), x/y (viewport CSS px, NULL until
# placed), off_frame (NULL or the side tokens the cursor left through),
# init_id (the new-document script identifier), page_enabled (Page
# domain enabled for the init script).
page_cursor <- function(page) {
  cur <- page$.__enclos_env__$private$staging_$cursor
  if (is.null(cur)) {
    cur <- new.env(parent = emptyenv())
    cur$visibility <- "auto"
    cur$icon <- "default"
    cur$x <- NULL
    cur$y <- NULL
    cur$off_frame <- NULL
    cur$init_id <- NULL
    cur$page_enabled <- FALSE
    page$.__enclos_env__$private$staging_$cursor <- cur
  }
  cur
}

page_cursor_peek <- function(page) {
  page$.__enclos_env__$private$staging_$cursor
}

# Effective visibility: the setting FALSE hides always; an explicit
# shown/hidden state wins; "auto" follows the recording (or cursor =
# TRUE for stills).
cursor_visible <- function(page) {
  stage <- page_stage(page)
  if (identical(stage$cursor, FALSE)) {
    return(FALSE)
  }
  cur <- page_cursor_peek(page)
  visibility <- if (is.null(cur)) "auto" else cur$visibility
  switch(
    visibility,
    shown = TRUE,
    hidden = FALSE,
    auto = stage_recording(page) || isTRUE(stage$cursor)
  )
}

check_cursor_enabled <- function(ctx, call = caller_env()) {
  if (identical(page_stage(ctx$page)$cursor, FALSE)) {
    cli::cli_abort(
      "The cursor is disabled by {.code pz_stage(cursor = FALSE)}.",
      class = "paparazzi_error_cursor",
      call = call
    )
  }
  invisible(ctx)
}

# Where the cursor should appear with no target: its last position, or
# the viewport center when it has never been placed.
cursor_current_point <- function(ctx) {
  cur <- page_cursor_peek(ctx$page)
  if (!is.null(cur) && !is.null(cur$x)) {
    return(c(x = cur$x, y = cur$y))
  }
  v <- unlist(pz_js(ctx, "[window.innerWidth, window.innerHeight]"))
  c(x = v[1] / 2, y = v[2] / 2)
}

# The center of a resolved target, scrolled into view (staged while
# recording, instantly otherwise).
cursor_target_point <- function(ctx, target, call = caller_env()) {
  els <- loc_resolve(ctx, target, multiple = "error", call = call)
  withr::defer(release_elements(els))
  stage_scroll_into_view(ctx, els, call = call)
  rects <- el_rects(els, call = call)
  c(
    x = rects$x[[1]] + rects$width[[1]] / 2,
    y = rects$y[[1]] + rects$height[[1]] / 2
  )
}

# A point 40px past the named frame edge, at the target's coordinate on
# the other axis: where an entering cursor starts and a leaving cursor
# ends up. Corner directions offset both axes and ignore the target's
# coordinates entirely.
cursor_off_frame_point <- function(ctx, side, point) {
  v <- unlist(pz_js(ctx, "[window.innerWidth, window.innerHeight]"))
  margin <- 40
  x <- if ("left" %in% side) {
    -margin
  } else if ("right" %in% side) {
    v[1] + margin
  } else {
    point[["x"]]
  }
  y <- if ("top" %in% side) {
    -margin
  } else if ("bottom" %in% side) {
    v[2] + margin
  } else {
    point[["y"]]
  }
  c(x = unname(x), y = unname(y))
}

# Show the cursor at a point, choosing the entrance from the current
# state: an explicit `from` side (or the enter setting on first show)
# starts off-frame and glides in; first show without a side fades in;
# otherwise glide from the last position. An explicit duration wins over
# the computed glide. Everything collapses to a static jump when not
# recording (handled in cursor_apply()).
cursor_show_at <- function(
  ctx,
  point,
  duration = NULL,
  from = NULL,
  icon = NULL
) {
  page <- ctx$page
  cur <- page_cursor(page)
  stage <- page_stage(page)
  has_pos <- !is.null(cur$x)
  entry <- from %||%
    if (!has_pos || !is.null(cur$off_frame)) {
      cur$off_frame %||% stage$enter
    }
  if (!is.null(entry)) {
    start <- cursor_off_frame_point(ctx, entry, point)
    cursor_apply(
      ctx,
      point,
      duration = duration %||%
        stage_glide_duration(start, point, stage$cursor_speed),
      from = start,
      icon = icon
    )
  } else if (!has_pos) {
    cursor_apply(ctx, point, fade = TRUE, icon = icon)
  } else {
    start <- c(x = cur$x, y = cur$y)
    cursor_apply(
      ctx,
      point,
      duration = duration %||%
        stage_glide_duration(start, point, stage$cursor_speed),
      icon = icon
    )
  }
  invisible(ctx)
}


# Each keyword owns a layer, even where path geometry is shared: later
# glide choreography can switch any pair by animating visibility.
CURSOR_ART <- list(
  default = list(
    path = "M4 1 L4 19 L8.5 14.8 L11.5 21 L14 20 L11 13.5 L17.5 13.5 Z",
    x = 0,
    y = 0
  ),
  pointer = list(
    path = "M5 1.7 C4.1 1.3 3.1 1.8 2.7 2.8 L1.1 6.1 C0.6 7.2 1 8.3 2 9 L8.7 13.7 L7 15.4 C6.3 16.1 6.3 17.2 7 17.9 L10.5 21.2 C11.1 21.8 12 22 12.8 22 L16.6 22 C19.1 22 21 20 21 17.5 L21 12 C21 10.8 20.1 9.9 18.9 9.9 C18.1 9.9 17.4 10.4 17 11.1 L17 10.2 C17 9 16.1 8.1 14.9 8.1 C14.1 8.1 13.4 8.6 13 9.3 L13 9 C13 7.8 12.1 6.9 10.9 6.9 C10.2 6.9 9.5 7.3 9.1 7.9 L7.2 3 C6.9 2.2 6 1.7 5 1.7 Z",
    x = 0,
    y = 0,
    stroke = 1
  ),
  text = list(
    path = "M5 3 H19 M12 3 V21 M5 21 H19 M9 6 H15 M9 18 H15",
    x = -6,
    y = -8
  ),
  `not-allowed` = list(
    path = "M21 12 A9 9 0 1 1 3 12 A9 9 0 1 1 21 12 Z M5.7 5.7 L18.3 18.3",
    x = -6,
    y = -8
  ),
  crosshair = list(
    path = "M12 2 V8 M12 16 V22 M2 12 H8 M16 12 H22 M16 12 A4 4 0 1 1 8 12 A4 4 0 1 1 16 12 Z",
    x = -6,
    y = -8
  ),
  grab = list(
    path = "M4 11 L4 7 Q4 5 6 5 Q8 5 8 7 L8 4 Q8 2 10 2 Q12 2 12 4 L12 3 Q12 1 14 1 Q16 1 16 3 L16 5 Q16 3 18 3 Q20 3 20 5 L20 14 Q20 21 14 22 L10 22 Q6 22 4 18 L2 14 Q1 12 2 11 Q3 10 4 11 Z",
    x = -6,
    y = -8
  ),
  grabbing = list(
    path = "M3 11 Q2 9 4 8 L7 7 L7 5 Q7 3 9 3 Q11 3 11 5 L12 4 Q12 2 14 2 Q16 2 16 4 Q18 3 19 5 L21 12 Q22 15 19 19 Q17 22 13 22 L9 22 Q5 22 3 18 Z",
    x = -6,
    y = -8
  ),
  `ew-resize` = list(
    path = "M2 12 L9 5 V9 H15 V5 L22 12 L15 19 V15 H9 V19 Z",
    x = -6,
    y = -8
  ),
  `ns-resize` = list(
    path = "M2 12 L9 5 V9 H15 V5 L22 12 L15 19 V15 H9 V19 Z",
    x = -6,
    y = -8,
    transform = "rotate(90 12 12)"
  ),
  `nesw-resize` = list(
    path = "M2 12 L9 5 V9 H15 V5 L22 12 L15 19 V15 H9 V19 Z",
    x = -6,
    y = -8,
    transform = "rotate(-45 12 12)"
  ),
  `nwse-resize` = list(
    path = "M2 12 L9 5 V9 H15 V5 L22 12 L15 19 V15 H9 V19 Z",
    x = -6,
    y = -8,
    transform = "rotate(45 12 12)"
  ),
  `row-resize` = list(
    path = "M2 12 L9 5 V9 H15 V5 L22 12 L15 19 V15 H9 V19 Z",
    x = -6,
    y = -8,
    transform = "rotate(90 12 12)"
  ),
  `col-resize` = list(
    path = "M2 12 L9 5 V9 H15 V5 L22 12 L15 19 V15 H9 V19 Z",
    x = -6,
    y = -8
  )
)

cursor_check_icon <- function(icon) {
  if (is.null(icon)) {
    return(NULL)
  }
  arg_match(icon, values = names(CURSOR_ART))
}

# The one mover: draw the cursor at `point` (visible, unpressed, shape
# auto-detected from the element under the point), animating only while
# recording -- a glide of `duration` seconds, an instant pre-position at
# `from` first for frame entries, or a fade-in at the point. Without a
# recording every variant is a static jump. Updates the cursor state and
# the new-document script, and pumps the child loop for the animation,
# so the recorder's ticks capture it.
cursor_apply <- function(
  ctx,
  point,
  duration = 0,
  from = NULL,
  fade = FALSE,
  icon = NULL
) {
  page <- ctx$page
  cur <- page_cursor(page)
  recording <- stage_recording(page)
  state <- list(
    x = unname(point[["x"]]),
    y = unname(point[["y"]]),
    visible = TRUE,
    icon = icon,
    previous = cur$icon,
    pressed = FALSE,
    duration = if (recording) duration else 0,
    from = if (recording && !is.null(from)) unname(from),
    fade = recording && fade,
    anim = recording
  )
  cur$icon <- cursor_command(ctx, state)
  cur$x <- state$x
  cur$y <- state$y
  cur$off_frame <- NULL
  if (state$duration > 0) {
    pump_loop(page$child_loop, state$duration)
  }
  if (isTRUE(state$fade)) {
    pump_loop(page$child_loop, 0.3)
  }
  cursor_register_init(ctx)
  invisible(ctx)
}

# Redraw the cursor at its recorded position with a new visibility or
# press state. No movement; the opacity/scale transitions in the layer
# animate the change while the caller pumps.
cursor_draw <- function(ctx, visible, pressed = FALSE) {
  cur <- page_cursor(ctx$page)
  cursor_command(
    ctx,
    list(
      x = cur$x %||% 0,
      y = cur$y %||% 0,
      visible = visible,
      icon = cur$icon,
      pressed = pressed,
      duration = 0,
      anim = stage_recording(ctx$page)
    )
  )
  cursor_register_init(ctx)
  invisible(ctx)
}

cursor_press <- function(ctx, pressed) {
  if (!cursor_visible(ctx$page)) {
    return(invisible(ctx))
  }
  cursor_draw(ctx, visible = TRUE, pressed = pressed)
  invisible(ctx)
}

# One state application in the page. The JS is create-if-missing (boot
# + apply in every call), so a page whose init script never ran -- or a
# fresh document after navigation -- can always be driven forward.
cursor_command <- function(ctx, state) {
  state$scale <- page_stage(ctx$page)$cursor_scale
  state$icons <- CURSOR_ART
  json <- jsonlite::toJSON(state, auto_unbox = TRUE, null = "null")
  pz_js(ctx, paste0("(", cursor_command_js, ")(", json, ")"), await = FALSE)
}

# Boot: the cursor layer under the existing overlay host's shadow root.
# Two nested divs keep the transforms independent: .pz-glide carries the
# translate (its transition is the glide), .pz-inner carries the size,
# press scale, and fade opacity. The layer is position: fixed (pointer
# coordinates are viewport-relative, unlike the inspect layer's document
# coordinates) and counter-zoomed by 1 / zoom(documentElement), because
# a CSS zoom on <html> would otherwise scale the layer away from the
# pointer coordinate space; getBoundingClientRect and CDP pointer
# coordinates both live in the zoomed (visual) space.
cursor_command_js <- r"(function(state) {
  let host = document.getElementById('paparazzi-overlay-root');
  if (!host) {
    host = document.createElement('div');
    host.id = 'paparazzi-overlay-root';
    host.style.cssText = 'position:absolute;top:0;left:0;width:0;height:0;z-index:2147483647;pointer-events:none;';
    document.documentElement.appendChild(host);
  }
  if (!host.shadowRoot) host.attachShadow({ mode: 'open' });
  const root = host.shadowRoot;
  let layer = root.querySelector('.pz-cursor');
  if (!layer) {
    layer = document.createElement('div');
    layer.className = 'pz-cursor';
    layer.style.cssText = 'position:fixed;left:0;top:0;pointer-events:none;';
    layer.innerHTML = '<div class="pz-glide" style="pointer-events:none;"><div class="pz-inner" style="pointer-events:none;opacity:0;transform-origin:4px 2px;position:relative;width:20px;height:20px;"></div></div>';
    const inner = layer.querySelector('.pz-inner');
    for (const [keyword, art] of Object.entries(state.icons)) {
      const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
      svg.setAttribute('class', 'pz-icon pz-icon-' + keyword);
      svg.setAttribute('width', '20');
      svg.setAttribute('height', '20');
      svg.setAttribute('viewBox', '0 0 24 24');
      svg.style.cssText = 'position:absolute;pointer-events:none;visibility:hidden;left:' + art.x + 'px;top:' + art.y + 'px;';
      const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
      path.setAttribute('d', art.path);
      path.setAttribute('fill', '#111');
      path.setAttribute('stroke', '#fff');
      path.setAttribute('stroke-width', art.stroke || '1.4');
      path.setAttribute('stroke-linejoin', 'round');
      if (art.transform) path.setAttribute('transform', art.transform);
      svg.appendChild(path);
      inner.appendChild(svg);
    }
    const style = document.createElement('style');
    style.textContent = '@keyframes pz-icon-in { 0%, 99.9% { visibility:hidden; } 100% { visibility:visible; } } @keyframes pz-icon-out { 0%, 99.9% { visibility:visible; } 100% { visibility:hidden; } }';
    layer.appendChild(style);
    root.appendChild(layer);
  }
  const z = parseFloat(getComputedStyle(document.documentElement).zoom) || 1;
  layer.style.zoom = String(1 / z);
  const glide = layer.querySelector('.pz-glide');
  const inner = layer.querySelector('.pz-inner');
  const icons = layer.querySelectorAll('.pz-icon');
  let icon = state.icon;
  if (!icon) {
    icon = 'default';
    let el = document.elementFromPoint(state.x, state.y);
    for (; el; el = el.parentElement) {
      const cursor = getComputedStyle(el).cursor;
      if (cursor === 'auto') continue;
      // Chrome serializes cursor URLs with a trailing keyword when a
      // CSS fallback is present. A bare URL has no supported fallback.
      const keyword = cursor.startsWith('url(')
        ? (cursor.match(/\)\s*([a-z-]+)\s*$/) || [])[1]
        : cursor;
      if (Object.prototype.hasOwnProperty.call(state.icons, keyword)) icon = keyword;
      break;
    }
  }
  const deferSwitch = state.anim && state.duration > 0 && !state.icon &&
    state.previous && state.previous !== icon;
  for (const svg of icons) {
    const keyword = svg.classList[1].slice('pz-icon-'.length);
    svg.style.animation = 'none';
    svg.style.visibility = keyword === icon ? 'visible' : 'hidden';
  }
  if (deferSwitch) {
    // Keep the previous artwork through the glide. A later phase
    // moves the discrete visibility boundary to destination entry.
    void inner.offsetWidth;
    for (const svg of icons) {
      const keyword = svg.classList[1].slice('pz-icon-'.length);
      if (keyword === state.previous) {
        svg.style.animation = 'pz-icon-out ' + state.duration + 's forwards';
      } else if (keyword === icon) {
        svg.style.animation = 'pz-icon-in ' + state.duration + 's forwards';
      }
    }
  }
  if (state.from) {
    glide.style.transition = 'none';
    glide.style.transform = 'translate(' + state.from[0] + 'px,' + state.from[1] + 'px)';
  }
  if (state.fade) {
    inner.style.transition = 'none';
    inner.style.opacity = '0';
  }
  if (state.from || state.fade) void glide.offsetWidth;
  glide.style.transition = state.duration > 0
    ? 'transform ' + state.duration + 's cubic-bezier(0.42,0,0.58,1)'
    : 'none';
  glide.style.transform = 'translate(' + state.x + 'px,' + state.y + 'px)';
  inner.style.transition = state.anim
    ? 'opacity 0.25s ease, transform 0.12s ease'
    : 'none';
  inner.style.opacity = state.visible ? '1' : '0';
  inner.style.transform = 'scale(' + state.scale * (state.pressed ? 0.8 : 1) + ')';
  return icon;
})"
# The new-document script: the same boot+apply with the last state baked
# in, registered so a navigation re-injects the overlay at its last
# position. Page.enable() is required for the script to run (probed on
# http and file:// documents alike); re-registering (remove + add)
# swaps the source, so every cursor state change keeps the script fresh.
cursor_register_init <- function(ctx) {
  page <- ctx$page
  cur <- page_cursor(page)
  session <- page$session
  timeout <- page$default_timeout
  if (!is.null(cur$init_id)) {
    try(
      session$Page$removeScriptToEvaluateOnNewDocument(
        identifier = cur$init_id,
        timeout_ = timeout
      ),
      silent = TRUE
    )
    cur$init_id <- NULL
  }
  if (!cur$page_enabled) {
    session$Page$enable(timeout_ = timeout)
    cur$page_enabled <- TRUE
  }
  state <- list(
    x = cur$x %||% 0,
    y = cur$y %||% 0,
    visible = cursor_visible(page) && !is.null(cur$x),
    icon = cur$icon,
    pressed = FALSE,
    duration = 0,
    anim = FALSE,
    scale = page_stage(page)$cursor_scale,
    icons = CURSOR_ART
  )
  json <- jsonlite::toJSON(state, auto_unbox = TRUE, null = "null")
  # New-document scripts run before the document element exists, so the
  # boot waits for it; the overlay then reappears at its last position.
  source <- paste0(
    "(function() { const boot = function() { (",
    cursor_command_js,
    ")(",
    json,
    "); };",
    "if (document.documentElement) { boot(); }",
    "else { document.addEventListener('DOMContentLoaded', boot, { once: true }); } })();"
  )
  res <- session$Page$addScriptToEvaluateOnNewDocument(
    source = source,
    timeout_ = timeout
  )
  cur$init_id <- res$identifier
  invisible(ctx)
}

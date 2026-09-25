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
#' statically, which is how a cursor lands in a screenshot.
#'
#' @inheritParams pz_click
#' @param target A CSS selector string, a [pz_loc()] spec, or a list of
#'   specs. The cursor centers on the match. `NULL` uses the current
#'   scope's element or, at the root context, shows the cursor at its
#'   last position (or the viewport center the first time).
#' @param from A side of the frame to enter from: `"top"`, `"bottom"`,
#'   `"left"`, or `"right"`.
#'
#' @return `ctx`, invisibly.
#'
#' @seealso [pz_stage()] for cursor settings, [pz_cursor_hide()],
#'   [pz_cursor_move()], [pz_cursor_leave()]
#'
#' @export
pz_cursor_show <- function(ctx, target = NULL, ..., from = NULL) {
  check_context(ctx)
  check_dots_empty()
  from <- if (!is.null(from)) {
    parse_direction(from, valid = STAGE_SIDES, arg = "from")
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
  cursor_show_at(ctx, point, from = from)
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
#' @export
pz_cursor_move <- function(ctx, target, ..., duration = NULL) {
  check_context(ctx)
  check_dots_empty()
  check_number_decimal(duration, min = 0, allow_null = TRUE)
  check_cursor_enabled(ctx)
  cur <- page_cursor(ctx$page)
  cur$visibility <- "shown"

  point <- cursor_target_point(ctx, target)
  cursor_show_at(ctx, point, duration = duration)
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
#' @param side A side of the frame to leave through: `"top"`,
#'   `"bottom"`, `"left"`, or `"right"`.
#'
#' @return `ctx`, invisibly.
#'
#' @seealso [pz_cursor_show()]
#'
#' @export
pz_cursor_leave <- function(ctx, side = "right") {
  check_context(ctx)
  side <- parse_direction(side, valid = STAGE_SIDES, arg = "side")
  check_cursor_enabled(ctx)
  page <- ctx$page
  cur <- page_cursor(page)

  point <- cursor_off_frame_point(ctx, side, cursor_current_point(ctx))
  duration <- if (!is.null(cur$x)) {
    stage_glide_duration(c(x = cur$x, y = cur$y), point, page_stage(page)$cursor_speed)
  }
  cursor_apply(ctx, point, duration = duration %||% 0)
  # Set after cursor_apply(), which clears it: the cursor stays visible
  # but off-frame, and the next action glides back in from this side.
  cur$off_frame <- side
  invisible(ctx)
}
# The sides-only subset of the direction vocabulary, for pz_stage(enter
# =), pz_cursor_show(from =), and pz_cursor_leave(side =).
STAGE_SIDES <- list(c("top"), c("bottom"), c("left"), c("right"))
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
# ends up.
cursor_off_frame_point <- function(ctx, side, point) {
  v <- unlist(pz_js(ctx, "[window.innerWidth, window.innerHeight]"))
  margin <- 40
  switch(
    side,
    top = c(x = unname(point[["x"]]), y = -margin),
    bottom = c(x = unname(point[["x"]]), y = v[2] + margin),
    left = c(x = -margin, y = unname(point[["y"]])),
    right = c(x = v[1] + margin, y = unname(point[["y"]]))
  )
}
# Show the cursor at a point, choosing the entrance from the current
# state: an explicit `from` side (or the enter setting on first show)
# starts off-frame and glides in; first show without a side fades in;
# otherwise glide from the last position. An explicit duration wins over
# the computed glide. Everything collapses to a static jump when not
# recording (handled in cursor_apply()).
cursor_show_at <- function(ctx, point, duration = NULL, from = NULL) {
  page <- ctx$page
  cur <- page_cursor(page)
  stage <- page_stage(page)
  has_pos <- !is.null(cur$x)
  entry <- from %||% if (!has_pos || !is.null(cur$off_frame)) {
    cur$off_frame %||% stage$enter
  }
  if (!is.null(entry)) {
    start <- cursor_off_frame_point(ctx, entry, point)
    cursor_apply(
      ctx,
      point,
      duration = duration %||%
        stage_glide_duration(start, point, stage$cursor_speed),
      from = start
    )
  } else if (!has_pos) {
    cursor_apply(ctx, point, fade = TRUE)
  } else {
    start <- c(x = cur$x, y = cur$y)
    cursor_apply(
      ctx,
      point,
      duration = duration %||%
        stage_glide_duration(start, point, stage$cursor_speed)
    )
  }
  invisible(ctx)
}
# The one mover: draw the cursor at `point` (visible, unpressed, shape
# auto-detected from the element under the point), animating only while
# recording -- a glide of `duration` seconds, an instant pre-position at
# `from` first for frame entries, or a fade-in at the point. Without a
# recording every variant is a static jump. Updates the cursor state and
# the new-document script, and pumps the child loop for the animation,
# so the recorder's ticks capture it.
cursor_apply <- function(ctx, point, duration = 0, from = NULL, fade = FALSE) {
  page <- ctx$page
  cur <- page_cursor(page)
  recording <- stage_recording(page)
  state <- list(
    x = unname(point[["x"]]),
    y = unname(point[["y"]]),
    visible = TRUE,
    shape = "auto",
    pressed = FALSE,
    duration = if (recording) duration else 0,
    from = if (recording && !is.null(from)) unname(from),
    fade = recording && fade,
    anim = recording
  )
  cursor_command(ctx, state)
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
  cursor_command(ctx, list(
    x = cur$x %||% 0,
    y = cur$y %||% 0,
    visible = visible,
    shape = "auto",
    pressed = pressed,
    duration = 0,
    anim = stage_recording(ctx$page)
  ))
  cursor_register_init(ctx)
  invisible(ctx)
}
# The press scale-down around a click's pressed/released pair.
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
  json <- jsonlite::toJSON(state, auto_unbox = TRUE, null = "null")
  pz_js(ctx, paste0("(", cursor_command_js, ")(", json, ")"), await = FALSE)
  invisible(ctx)
}
# Boot: the cursor layer under the existing overlay host's shadow root.
# Two nested divs keep the transforms independent: .pz-glide carries the
# translate (its transition is the glide), .pz-inner carries the press
# scale and the fade opacity. The layer is position: fixed (pointer
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
    layer.innerHTML =
      '<div class="pz-glide" style="pointer-events:none;">' +
      '<div class="pz-inner" style="pointer-events:none;opacity:0;transform-origin:4px 2px;">' +
      '<svg class="pz-arrow" width="20" height="20" viewBox="0 0 24 24" style="display:block;pointer-events:none;">' +
      '<path d="M4 1 L4 19 L8.5 14.8 L11.5 21 L14 20 L11 13.5 L17.5 13.5 Z" fill="#111" stroke="#fff" stroke-width="1.4" stroke-linejoin="round"/>' +
      '</svg>' +
      '<svg class="pz-hand" width="20" height="20" viewBox="0 0 24 24" style="display:none;pointer-events:none;">' +
      '<path d="M8 3.5 C8 2.7 8.7 2 9.5 2 C10.3 2 11 2.7 11 3.5 L11 10 L12 10 L12 4.5 C12 3.7 12.7 3 13.5 3 C14.3 3 15 3.7 15 4.5 L15 10.5 L16 10.5 L16 6 C16 5.2 16.7 4.5 17.5 4.5 C18.3 4.5 19 5.2 19 6 L19 14 C19 18 16.5 21 12.5 21 C9.5 21 7.5 19.6 6.2 17.2 L3.6 12.6 C3.2 11.9 3.5 11 4.2 10.6 C4.9 10.2 5.7 10.4 6.1 11 L8 13.5 Z" fill="#111" stroke="#fff" stroke-width="1" stroke-linejoin="round"/>' +
      '</svg>' +
      '</div></div>';
    root.appendChild(layer);
  }
  const z = parseFloat(getComputedStyle(document.documentElement).zoom) || 1;
  layer.style.zoom = String(1 / z);
  const glide = layer.firstChild;
  const inner = glide.firstChild;
  let shape = state.shape;
  if (shape === 'auto') {
    shape = 'arrow';
    let el = document.elementFromPoint(state.x, state.y);
    while (el && el !== document.documentElement) {
      const c = getComputedStyle(el).cursor;
      if (c !== 'auto') {
        shape = c === 'pointer' ? 'hand' : 'arrow';
        break;
      }
      el = el.parentElement;
    }
  }
  layer.querySelector('.pz-arrow').style.display = shape === 'hand' ? 'none' : 'block';
  layer.querySelector('.pz-hand').style.display = shape === 'hand' ? 'block' : 'none';
  if (state.from) {
    glide.style.transition = 'none';
    glide.style.transform = 'translate(' + state.from[0] + 'px,' + state.from[1] + 'px)';
  }
  if (state.fade) {
    inner.style.transition = 'none';
    inner.style.opacity = '0';
  }
  if (state.from || state.fade) {
    void glide.offsetWidth;
  }
  glide.style.transition = state.duration > 0
    ? 'transform ' + state.duration + 's cubic-bezier(0.42,0,0.58,1)'
    : 'none';
  glide.style.transform = 'translate(' + state.x + 'px,' + state.y + 'px)';
  // Opacity/press transitions only run for animated (recording) states;
  // a static draw must land at full opacity in the very next capture.
  inner.style.transition = state.anim
    ? 'opacity 0.25s ease, transform 0.12s ease'
    : 'none';
  inner.style.opacity = state.visible ? '1' : '0';
  inner.style.transform = state.pressed ? 'scale(0.8)' : 'scale(1)';
  return true;
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
    shape = "auto",
    pressed = FALSE,
    duration = 0,
    anim = FALSE
  )
  json <- jsonlite::toJSON(state, auto_unbox = TRUE, null = "null")
  # New-document scripts run before the document element exists, so the
  # boot waits for it; the overlay then reappears at its last position.
  source <- paste0(
    "(function() { const boot = function() { (", cursor_command_js, ")(", json, "); };",
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

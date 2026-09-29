#' @include utils-purrr.R
NULL

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
#' @param icon CSS cursor keyword to show for this call. `NULL` (the
#'   default) infers the icon at the actual landing point: the first
#'   computed `cursor` other than `auto` on the element under the point
#'   or an ancestor. Every CSS cursor keyword is supported: for example,
#'   `default`, `pointer`, `text`, `crosshair`, `wait`, `zoom-in`, and the
#'   resize keywords. `none` hides the artwork without changing the
#'   overlay's position; an explicit `auto` shows the default arrow.
#'   A bare `url()` uses `default`; a `url()` with a supported keyword
#'   fallback uses that keyword. Custom URL images are not drawn. An
#'   explicit icon lasts through this call's landing but
#'   does not override the next call's automatic inference. The selected
#'   icon stays on the cursor until the next destination; the
#'   first off-frame entrance starts with `default` unless overridden.
#'   While recording, an automatic move keeps the icon already visible
#'   until it enters the destination and switches there; an explicit
#'   `icon` applies from the start of the glide and stays through its landing
#'   and any press. The artwork tracks CSS zoom and the device pixel
#'   ratio internally, and a navigation re-injects the overlay with its
#'   last icon.
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
#'   pz_cursor_show("#add-task", icon = "pointer") |>
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
      structure(
        c(
          x = rects$x[[1]] + rects$width[[1]] / 2,
          y = rects$y[[1]] + rects$height[[1]] / 2
        ),
        rect = c(
          x = rects$x[[1]],
          y = rects$y[[1]],
          width = rects$width[[1]],
          height = rects$height[[1]]
        )
      )
    } else {
      cursor_current_point(ctx)
    }
  }
  cursor_show_at(ctx, point, from = from, icon = icon)
  ctx_return(ctx)
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
  ctx_return(ctx)
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
#' @inheritParams pz_cursor_show
#' @param duration Glide duration in seconds; `NULL` computes one from
#'   the distance and the `cursor_speed` staging setting.
#' @param offset Landing offset in viewport CSS pixels, `c(x, y)` with
#'   positive x to the right and positive y downward. A single number is
#'   recycled to both axes; `NULL` (the default) means no offset. It applies
#'   only to this call and only to the drawn overlay, not to page pointer
#'   events. The cursor may land outside the viewport without clamping.
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
#'       pz_cursor_move("#add-task", icon = "crosshair")
#'   })
#' pz_close(page)
#'
#' @export
pz_cursor_move <- function(
  ctx,
  target,
  ...,
  duration = NULL,
  icon = NULL,
  offset = NULL
) {
  icon <- cursor_check_icon(icon)
  offset <- if (is.null(offset)) c(0, 0) else check_offset(offset)
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

  destination <- cursor_target_point(ctx, target)
  point <- structure(destination + offset, rect = attr(destination, "rect"))
  cursor_show_at(
    ctx,
    point,
    duration = duration,
    icon = icon,
    destination = destination
  )
  ctx_return(ctx)
}

#' Move the overlay cursor out of the frame
#'
#' Sends the cursor out of the frame through `side`: while recording it
#' glides out, otherwise it leaves immediately. The cursor is still
#' visible (just off-frame); the next pointer action or cursor call
#' glides it back in from that side.
#'
#' @inheritParams pz_click
#' @inheritParams pz_cursor_show
#' @param side A side (`"top"`, `"bottom"`, `"left"`, `"right"`) or
#'   corner (`"top left"`, `"bottom right"`, ...) of the frame to leave
#'   through. Defaults to `"right"`.
#' @param icon CSS cursor keyword to show during the exit. `NULL` (the
#'   default) keeps the icon already on the cursor: there is nothing to
#'   infer at the off-frame exit point. The exit icon becomes the last
#'   visible icon, so the next entrance starts with it.
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
#'       pz_cursor_leave("right", icon = "default") |>
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
  ctx_return(ctx)
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
  ctx_return(ctx)
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
  structure(
    c(
      x = rects$x[[1]] + rects$width[[1]] / 2,
      y = rects$y[[1]] + rects$height[[1]] / 2
    ),
    rect = c(
      x = rects$x[[1]],
      y = rects$y[[1]],
      width = rects$width[[1]],
      height = rects$height[[1]]
    )
  )
}

# First eased time when the cursor anchor enters a viewport rect.
# Clip in line-progress space, then invert the monotone CSS ease curve.
cursor_entry_time <- function(start, end, rect) {
  lower <- 0
  upper <- 1
  for (axis in c("x", "y")) {
    delta <- end[[axis]] - start[[axis]]
    edge <- rect[[axis]] +
      if (axis == "x") rect[["width"]] else rect[["height"]]
    if (delta == 0) {
      if (start[[axis]] < rect[[axis]] || start[[axis]] > edge) {
        return(NULL)
      }
      next
    }
    limits <- sort((c(rect[[axis]], edge) - start[[axis]]) / delta)
    lower <- max(lower, limits[[1]])
    upper <- min(upper, limits[[2]])
  }
  if (lower > upper || upper < 0 || lower > 1) {
    return(NULL)
  }
  progress <- max(0, lower)
  if (progress == 0 || progress == 1) {
    return(progress)
  }
  lo <- 0
  hi <- 1
  for (i in seq_len(55)) {
    v <- (lo + hi) / 2
    y <- 3 * (1 - v) * v^2 + v^3
    if (y < progress) lo <- v else hi <- v
  }
  v <- (lo + hi) / 2
  3 * (1 - v)^2 * v * 0.42 + 3 * (1 - v) * v^2 * 0.58 + v^3
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
  icon = NULL,
  destination = NULL,
  follow = FALSE
) {
  page <- ctx$page
  cur <- page_cursor(page)
  stage <- page_stage(page)
  rect <- attr(point, "rect")
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
      icon = icon,
      rect = rect,
      destination = destination,
      follow = follow
    )
  } else if (!has_pos) {
    cursor_apply(
      ctx,
      point,
      fade = TRUE,
      icon = icon,
      rect = rect,
      destination = destination,
      follow = follow
    )
  } else {
    start <- c(x = cur$x, y = cur$y)
    cursor_apply(
      ctx,
      point,
      duration = duration %||%
        stage_glide_duration(start, point, stage$cursor_speed),
      icon = icon,
      rect = rect,
      destination = destination,
      follow = follow
    )
  }
  ctx_return(ctx)
}


# Each keyword needs its own layer so glide keyframes can animate visibility.
CURSOR_ART <- local({
  directory <- system.file("cursors", package = "paparazzi")
  manifest <- jsonlite::fromJSON(
    file.path(directory, "cursors.json"),
    simplifyVector = FALSE
  )
  entries <- Filter(function(entry) !is.null(entry$cursor), manifest$cursors)
  art <- lapply(entries, function(entry) {
    svg <- paste(
      readLines(file.path(directory, entry$file), warn = FALSE),
      collapse = "\n"
    )
    list(
      svg = svg,
      x = 4 - entry$hotspot[[1]] * 20 / 32,
      y = 2 - entry$hotspot[[2]] * 20 / 32
    )
  })
  names(art) <- map_chr(entries, `[[`, "cursor")
  art$auto <- art$default
  art$none <- list(
    svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32"></svg>',
    x = 0,
    y = 0
  )
  art
})

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
  icon = NULL,
  rect = NULL,
  destination = NULL,
  follow = FALSE
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
  start <- if (!is.null(state$from)) {
    set_names(state$from, c("x", "y"))
  } else if (!is.null(cur$x)) {
    c(x = cur$x, y = cur$y)
  }
  if (recording && duration > 0 && is.null(icon) && !is.null(start)) {
    # No destination rect (an untargeted entrance): the intended
    # destination IS the landing point, so the flip waits for it.
    at <- if (is.null(rect)) 1 else cursor_entry_time(start, point, rect)
    landing <- cursor_command(
      ctx,
      list(x = state$x, y = state$y, resolveOnly = TRUE)
    )
    entered <- if (is.null(destination)) {
      landing
    } else {
      cursor_command(
        ctx,
        list(
          x = unname(destination[["x"]]),
          y = unname(destination[["y"]]),
          resolveOnly = TRUE
        )
      )
    }
    if (!is.null(at) && !identical(cur$icon, entered)) {
      state$switch <- list(at = at, from = cur$icon, to = entered)
    }
    prior <- if (is.null(at)) cur$icon else entered
    if (!identical(prior, landing)) {
      state$land <- list(from = prior, to = landing)
    }
  }
  if (follow && !is.null(rect)) {
    camera_follow_move(ctx, rect, if (state$fade) 0.3 else state$duration)
  }
  cur$icon <- cursor_command(ctx, state)
  cur$x <- state$x
  cur$y <- state$y
  cur$off_frame <- NULL
  if (state$duration > 0) {
    pump_loop(page$child_loop, state$duration + 0.05)
  }
  if (isTRUE(state$fade)) {
    pump_loop(page$child_loop, 0.3)
  }
  cursor_register_init(ctx)
  ctx_return(ctx)
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
  ctx_return(ctx)
}

cursor_press <- function(ctx, pressed) {
  if (!cursor_visible(ctx$page)) {
    return(ctx_return(ctx))
  }
  cursor_draw(ctx, visible = TRUE, pressed = pressed)
  ctx_return(ctx)
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
    layer.setAttribute('aria-hidden', 'true');
    layer.style.cssText = 'position:fixed;left:0;top:0;pointer-events:none;z-index:1;';
    layer.innerHTML = '<div class="pz-glide" style="pointer-events:none;"><div class="pz-inner" style="pointer-events:none;opacity:0;transform-origin:4px 2px;position:relative;width:20px;height:20px;"></div></div>';
    const inner = layer.querySelector('.pz-inner');
    for (const [keyword, art] of Object.entries(state.icons)) {
      inner.insertAdjacentHTML('beforeend', art.svg);
      const svg = inner.lastElementChild;
      svg.setAttribute('class', 'pz-icon pz-icon-' + keyword);
      svg.setAttribute('width', '20');
      svg.setAttribute('height', '20');
      svg.style.cssText = 'position:absolute;pointer-events:none;visibility:hidden;left:' + art.x + 'px;top:' + art.y + 'px;';
    }
    const style = document.createElement('style');
    style.className = 'pz-icon-keyframes';
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
    while (el) {
      const cursor = getComputedStyle(el).cursor;
      if (cursor !== 'auto') {
        // Chrome serializes cursor URLs with a trailing keyword when a
        // CSS fallback is present. A bare URL has no supported fallback.
        const keyword = cursor.startsWith('url(')
          ? (cursor.match(/\)\s*,\s*([a-z-]+)\s*$/) || [])[1]
          : cursor;
        if (Object.prototype.hasOwnProperty.call(state.icons, keyword)) icon = keyword;
        break;
      }
      // An open shadow host reports its own cursor, not its shadow
      // content's; hit-test inside the shadow tree and keep walking the
      // composed parent chain when a tree is exhausted.
      if (el.shadowRoot) {
        const inner = el.shadowRoot.elementFromPoint(state.x, state.y);
        if (inner) {
          el = inner;
          continue;
        }
      }
      el = el.parentElement || el.getRootNode().host || null;
    }
  }
  if (state.resolveOnly) return icon;
  const boundaries = [];
  if (state.anim && state.duration > 0) {
    if (state.switch && state.switch.from !== state.switch.to) {
      boundaries.push({at: state.switch.at * 100, to: state.switch.to});
    }
    if (state.land && state.land.from !== state.land.to) {
      boundaries.push({at: 100, to: state.land.to});
    }
  }
  const switching = boundaries.length > 0 &&
    boundaries[boundaries.length - 1].to === icon;
  const style = layer.querySelector('.pz-icon-keyframes');
  style.textContent = '';
  const startIcon = state.switch ? state.switch.from : state.land?.from;
  const participating = switching
    ? [...new Set([startIcon, ...boundaries.map(b => b.to)])]
    : [];
  if (switching) {
    style.textContent = participating.map((keyword) => {
      let visible = keyword === startIcon;
      let previous = 0;
      const frames = [];
      for (const boundary of boundaries) {
        const at = Math.min(100, Math.max(0, boundary.at));
        if (at > 0) {
          const before = Math.max(previous, at - 0.1);
          frames.push((previous === 0 ? '0%, ' : '') + before + '% { visibility:' + (visible ? 'visible' : 'hidden') + '; }');
        }
        visible = keyword === boundary.to;
        frames.push(at + '% { visibility:' + (visible ? 'visible' : 'hidden') + '; }');
        previous = at;
      }
      frames.push('100% { visibility:' + (visible ? 'visible' : 'hidden') + '; }');
      const name = keyword === startIcon ? 'pz-icon-out' :
        keyword === boundaries[0].to ? 'pz-icon-in' : 'pz-icon-land';
      return '@keyframes ' + name + ' { ' + frames.join(' ') + ' }';
    }).join(' ');
  }
  for (const svg of icons) {
    const keyword = svg.classList[1].slice('pz-icon-'.length);
    svg.style.animation = 'none';
    svg.style.visibility = keyword === icon ? 'visible' : 'hidden';
  }
  if (switching) {
    void inner.offsetWidth;
    for (const svg of icons) {
      const keyword = svg.classList[1].slice('pz-icon-'.length);
      const index = participating.indexOf(keyword);
      if (index < 0) continue;
      const name = index === 0 ? 'pz-icon-out' :
        keyword === boundaries[0].to ? 'pz-icon-in' : 'pz-icon-land';
      svg.style.animation = name + ' ' + state.duration + 's forwards';
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
  ctx_return(ctx)
}

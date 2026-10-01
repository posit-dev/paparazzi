#' @include overlay.R
NULL

#' Frame a capture region
#'
#' @description
#' [pz_frame()] builds a lazy framing spec for a capture: the region is
#' computed at capture time, then padded, nudged, grown to an aspect
#' ratio, and clamped. Every capture takes one: screenshots through
#' `pz_screenshot(frame =)`, recordings through
#' `pz_record_start(frame =)`, and camera shots through
#' `pz_camera(frame =)`. Wherever a frame is accepted, a bare locator
#' (a CSS selector string, a [pz_loc()] spec, or a list of either) is
#' promoted to `pz_frame(<locator>)`.
#'
#' Every field defaults to `NULL`, meaning "inherit": at capture time
#' an unset field takes the [pz_stage_frame()] value if one is staged,
#' else the built-in default. The built-in defaults are `pad = 0`,
#' `offset = c(0, 0)`, `anchor = "center"`, `when = "stop"`, and
#' `target_box = "element"`, with `ratio`, `bounds`, `zoom`, and
#' `target` unset. Camera shots never inherit the staged frame; their
#' built-in defaults are `pad = 24` and `target_box = "element"`.
#'
#' The framed region is computed in this order:
#' 1. Union the bounding boxes of the target's matched elements. With
#'    `target_box = "annotated"`, include their attached annotations.
#' 2. Expand by `pad`.
#' 3. With `zoom = NULL`, shift by `offset`, then grow the shorter side
#'    to reach `ratio` (never shrink), placing the content by `anchor`.
#'    With a numeric `zoom`, the region is the view divided by `zoom`
#'    (the viewport for stills and recordings, the recording's home
#'    frame for camera shots), with `ratio` setting its aspect if
#'    given; the padded target is placed inside it by `anchor`, then
#'    shifted by `offset`.
#' 4. Clamp to `bounds` and to the page's rendered area.
#' 5. Round to whole pixels.
#'
#' @param target The element(s) the frame is computed from: a CSS
#'   selector string, a [pz_loc()] spec, or a list of either (the frame
#'   is the union of the matched elements' bounding boxes). `NULL`
#'   frames the current scope's box, or the viewport at the root.
#' @param ... Checked empty; reserved for future use.
#' @param ratio Width/height ratio for the region, e.g. `16/9`. `NULL`
#'   disables aspect-ratio expansion, keeping the region tight to its
#'   content. Ignored (with a warning) by camera shots.
#' @param pad Padding in CSS pixels: one number for all sides, or
#'   `c(top, right, bottom, left)`. Negative values crop inside the
#'   content box.
#' @param offset Nudge the region by `c(x, y)` pixels, applied after
#'   `pad`.
#' @param anchor Where the content sits while the region grows around
#'   it: `"center"`, a side (`"top"`, `"bottom"`, `"left"`,
#'   `"right"`), or a corner (`"top left"`, `"top right"`,
#'   `"bottom left"`, `"bottom right"`). Case-insensitive;
#'   `"top right"`, `"right top"`, and `"top-right"` are equivalent.
#' @param bounds A target (a CSS selector string, a [pz_loc()] spec, or
#'   a list of either) whose union box the region is clamped within.
#'   `NULL` adds no bounds target; the page's rendered area still limits the
#'   region.
#' @param when When a recording measures the frame: `"stop"` (the
#'   default) measures against the final layout; `"start"` clips at
#'   capture start. Screenshots ignore this; camera shots warn.
#' @param target_box `"element"` (the default) measures only matched
#'   elements. `"annotated"` also includes painted marks, callouts, and
#'   spotlight cutouts attached to those elements or their descendants;
#'   redactions and annotations on unrelated elements are excluded.
#'   Applies to stills and camera shots, not the recording's home frame.
#' @param zoom Magnification relative to the full view (the viewport
#'   for stills and recordings, the recording's home frame for camera
#'   shots). `NULL` fits the region to the target plus `pad`, grown to
#'   `ratio`. A number fixes the region size at the view divided by
#'   `zoom`; `anchor` places the padded target inside it. Stills crop
#'   only, never upscale: a zoomed still is a smaller PNG at the page's
#'   pixel ratio. The camera caps a fitted shot at the capture's pixel
#'   density; an explicit `zoom` past it warns at encode time.
#'
#' @return An S3 object of class `paparazzi_frame`.
#'
#' @examples
#' # Frames are specs: nothing is measured until a capture uses them
#' pz_frame(pad = 32)
#' pz_frame(ratio = 16/9, pad = 24, anchor = "top")
#' pz_frame(".task-list", ratio = 4/3, bounds = "main")
#'
#' @examplesIf paparazzi:::examples_run(site = TRUE)
#' page <- pz_open(pz_example("tasks"))
#' path <- file.path(tempdir(), "tasks.png")
#'
#' # A locator target frames the union of its boxes
#' page |> pz_screenshot(path, frame = pz_frame(list("h1", ".filters"), pad = 16))
#'
#' # Unset fields inherit the staged framing
#' page |>
#'   pz_stage_frame(pad = 16) |>
#'   pz_screenshot(path, frame = pz_frame("#new-task", ratio = 16/9))
#' pz_screenshot(page, frame = pz_frame("#new-task", ratio = 16/9))
#' pz_close(page)
#'
#' @export
pz_frame <- function(
  target = NULL,
  ...,
  ratio = NULL,
  pad = NULL,
  offset = NULL,
  anchor = NULL,
  bounds = NULL,
  when = NULL,
  target_box = NULL,
  zoom = NULL
) {
  check_dots_empty()
  new_frame_spec(
    target = target,
    ratio = ratio,
    pad = pad,
    offset = offset,
    anchor = anchor,
    bounds = bounds,
    when = when,
    target_box = target_box,
    zoom = zoom
  )
}

#' @export
print.paparazzi_frame <- function(x, ...) {
  describe <- function(t) {
    if (is.null(t)) "<scope>" else format_loc(t)
  }
  fields <- paste0("target: ", describe(x[["target"]]))
  for (field in c(
    "ratio",
    "pad",
    "offset",
    "anchor",
    "bounds",
    "when",
    "target_box",
    "zoom"
  )) {
    value <- x[[field]]
    if (is.null(value)) {
      next
    }
    text <- switch(
      field,
      bounds = describe(value),
      paste(value, collapse = " ")
    )
    fields <- c(fields, paste0(field, ": ", text))
  }
  cli::cat_line("<paparazzi_frame> ", paste(fields, collapse = ", "))
  invisible(x)
}

#' Set or clear the page's default framing
#'
#' @description
#' [pz_stage_frame()] stores a default [pz_frame()] on the page. Every
#' screenshot and recording resolves its own `frame =` field by field:
#' an unset field takes the staged value if one is set, else the
#' built-in default. `frame = FALSE` disables framing for a single
#' call. Camera shots ignore the staged frame; see [pz_camera()].
#'
#' Unlike [pz_stage()]'s animation settings, framing (like
#' [pz_stage_annotate()]'s styles) applies to screenshots as well as
#' recordings. An annotated
#' staged frame measures attached annotations in stills; recordings use
#' only its element boxes for the home frame.
#'
#' @inheritParams pz_act_click
#' @param ... The default frame's target: a CSS selector string, a
#'   [pz_loc()] spec, or a list of either. Several unnamed arguments are
#'   unioned. With no target, framed captures use the current scope's
#'   box (the viewport at the root). A single `NULL` clears the
#'   default.
#' @param ratio,pad,offset,anchor,bounds,target_box,zoom Framing
#'   settings, as in [pz_frame()]; `NULL` leaves the field unset, so
#'   captures fall back to the built-in default for it.
#'
#' @return `ctx`, invisibly.
#'
#' @seealso [pz_stage()], [pz_stage_annotate()], [pz_frame()], [pz_screenshot()]
#'
#' @examplesIf paparazzi:::examples_run(site = TRUE)
#' page <- pz_open(pz_example("tasks"))
#' path <- file.path(tempdir(), "tasks.png")
#'
#' page |>
#'   pz_stage_frame(pad = 24) |>
#'   # Framed by the default: the form plus 24px of padding
#'   pz_screenshot(path, frame = "#new-task") |>
#'   # Fields not set here still come from the staged default
#'   pz_screenshot(path, frame = pz_frame("#new-task", ratio = 16/9)) |>
#'   # FALSE turns framing off for one call
#'   pz_screenshot(path, frame = FALSE) |>
#'   # NULL clears the default
#'   pz_stage_frame(NULL)
#' pz_screenshot(page, frame = pz_frame("#new-task", pad = 24, ratio = 16/9))
#' pz_close(page)
#'
#' @export
pz_stage_frame <- function(
  ctx,
  ...,
  ratio = NULL,
  pad = NULL,
  offset = NULL,
  anchor = NULL,
  bounds = NULL,
  target_box = NULL,
  zoom = NULL
) {
  check_context(ctx)
  dots <- list(...)
  nms <- names(dots)
  if (!is.null(nms) && any(nzchar(nms))) {
    cli::cli_abort(
      "{.arg ...} in {.fn pz_stage_frame} takes only the frame's target, unnamed.",
      class = "paparazzi_error_input"
    )
  }
  if (length(dots) == 1L && is.null(dots[[1]])) {
    if (
      !is.null(ratio) ||
        !is.null(pad) ||
        !is.null(offset) ||
        !is.null(anchor) ||
        !is.null(bounds) ||
        !is.null(target_box) ||
        !is.null(zoom)
    ) {
      cli::cli_abort(
        "{.code NULL} clears the default framing and can't be combined with framing settings.",
        class = "paparazzi_error_input"
      )
    }
    page_set_frame(ctx$page, NULL)
    return(ctx_return(ctx))
  }
  target <- if (length(dots) == 0L) {
    NULL
  } else if (length(dots) == 1L) {
    dots[[1]]
  } else {
    dots
  }
  spec <- new_frame_spec(
    target = target,
    ratio = ratio,
    pad = pad,
    offset = offset,
    anchor = anchor,
    bounds = bounds,
    target_box = target_box,
    zoom = zoom
  )
  page_set_frame(ctx$page, spec)
  ctx_return(ctx)
}

DIRECTION_TOKENS <- c("bottom", "center", "left", "right", "top")

DIRECTIONS <- list(
  c("top"),
  c("bottom"),
  c("left"),
  c("right"),
  c("left", "top"),
  c("right", "top"),
  c("bottom", "left"),
  c("bottom", "right"),
  c("center")
)

direction_labels <- function(valid = DIRECTIONS) {
  map_chr(valid, paste, collapse = " ")
}

parse_direction <- function(
  x,
  valid = DIRECTIONS,
  arg = caller_arg(x),
  call = caller_env()
) {
  if (!is_string(x)) {
    stop_input_type(x, "a direction string", arg = arg, call = call)
  }
  tokens <- sort(unique(strsplit(tolower(trimws(x)), "[[:space:]]+|-+")[[1]]))
  ok <- length(tokens) > 0 &&
    !anyNA(match(tokens, DIRECTION_TOKENS)) &&
    some(valid, function(t) identical(t, tokens))
  if (!ok) {
    cli::cli_abort(
      c(
        "{.arg {arg}} must be one of {.str {direction_labels(valid)}}, not {.str {x}}.",
        i = "Combine one vertical side with one horizontal side, or use {.str center}."
      ),
      class = "paparazzi_error_input",
      call = call
    )
  }
  tokens
}

new_frame_spec <- function(
  target = NULL,
  ratio = NULL,
  pad = NULL,
  offset = NULL,
  anchor = NULL,
  bounds = NULL,
  when = NULL,
  target_box = NULL,
  zoom = NULL,
  call = caller_env()
) {
  if (!is.null(target)) {
    target <- as_loc_list(target, call = call)
  }
  if (!is.null(bounds)) {
    bounds <- as_loc_list(bounds, arg = "bounds", call = call)
  }
  if (!is.null(ratio)) {
    check_number_decimal(ratio, arg = "ratio", call = call)
    if (ratio <= 0) {
      cli::cli_abort(
        "{.arg ratio} must be greater than 0, not {ratio}.",
        class = "paparazzi_error_input",
        call = call
      )
    }
  }
  if (!is.null(pad)) {
    pad <- check_pad(pad, call = call)
  }
  if (!is.null(offset)) {
    offset <- check_offset(offset, call = call)
  }
  if (!is.null(anchor)) {
    anchor <- parse_direction(anchor, arg = "anchor", call = call)
  }
  if (!is.null(when)) {
    when <- arg_match(when, values = c("stop", "start"), error_call = call)
  }
  if (!is.null(target_box)) {
    target_box <- arg_match(
      target_box,
      values = c("element", "annotated"),
      error_call = call
    )
  }
  if (!is.null(zoom)) {
    check_number_decimal(
      zoom,
      min = 0,
      allow_infinite = FALSE,
      arg = "zoom",
      call = call
    )
    if (zoom == 0) {
      cli::cli_abort(
        "{.arg zoom} must be greater than zero.",
        class = "paparazzi_error_input",
        call = call
      )
    }
  }
  structure(
    list(
      target = target,
      ratio = ratio,
      pad = pad,
      offset = offset,
      anchor = anchor,
      bounds = bounds,
      when = when,
      target_box = target_box,
      zoom = zoom
    ),
    class = "paparazzi_frame"
  )
}

frame_defaults <- list(
  ratio = NULL,
  pad = c(0, 0, 0, 0),
  offset = c(0, 0),
  anchor = "center",
  bounds = NULL,
  when = "stop",
  target_box = "element",
  zoom = NULL
)

frame_camera_defaults <- list(
  ratio = NULL,
  pad = c(24, 24, 24, 24),
  offset = c(0, 0),
  anchor = "center",
  bounds = NULL,
  when = NULL,
  target_box = "element",
  zoom = NULL
)

frame_fill <- function(spec, staged = NULL, defaults = frame_defaults) {
  out <- unclass(spec)
  for (field in names(defaults)) {
    if (is.null(out[[field]])) {
      value <- if (!is.null(staged) && !is.null(staged[[field]])) {
        staged[[field]]
      } else {
        defaults[[field]]
      }
      if (!is.null(value)) {
        out[[field]] <- value
      }
    }
  }
  class(out) <- class(spec)
  out
}

as_frame_spec <- function(frame, arg = caller_arg(frame), call = caller_env()) {
  if (
    is.null(frame) ||
      identical(frame, FALSE) ||
      inherits(frame, "paparazzi_frame")
  ) {
    return(frame)
  }
  if (is_string(frame) || inherits(frame, "paparazzi_loc") || is_list(frame)) {
    return(new_frame_spec(target = frame, call = call))
  }
  cli::cli_abort(
    c(
      "{.arg {arg}} must be a {.fn pz_frame} spec, a target (a CSS selector string, a {.fn pz_loc} spec, or a list of either), {.code FALSE}, or {.code NULL}, not {.obj_type_friendly {frame}}.",
      i = "{.code frame = FALSE} captures without framing."
    ),
    class = "paparazzi_error_unsupported",
    call = call
  )
}

check_pad <- function(pad, arg = caller_arg(pad), call = caller_env()) {
  if (
    !is.numeric(pad) || length(pad) == 0 || anyNA(pad) || !all(is.finite(pad))
  ) {
    cli::cli_abort(
      "{.arg {arg}} must be a finite number or {.code c(top, right, bottom, left)}, not {.obj_type_friendly {pad}}.",
      class = "paparazzi_error_input",
      call = call
    )
  }
  if (length(pad) == 1L) {
    return(rep(pad, 4))
  }
  if (length(pad) == 4L) {
    return(as.double(pad))
  }
  cli::cli_abort(
    "{.arg {arg}} must be one number or {.code c(top, right, bottom, left)}, not {length(pad)} numbers.",
    class = "paparazzi_error_input",
    call = call
  )
}

check_offset <- function(
  offset,
  arg = caller_arg(offset),
  call = caller_env()
) {
  if (
    !is.numeric(offset) ||
      length(offset) == 0 ||
      anyNA(offset) ||
      !all(is.finite(offset))
  ) {
    cli::cli_abort(
      "{.arg {arg}} must be a finite number or {.code c(x, y)}, not {.obj_type_friendly {offset}}.",
      class = "paparazzi_error_input",
      call = call
    )
  }
  if (length(offset) == 1L) {
    return(rep(offset, 2))
  }
  if (length(offset) == 2L) {
    return(as.double(offset))
  }
  cli::cli_abort(
    "{.arg {arg}} must be one number or {.code c(x, y)}, not {length(offset)} numbers.",
    class = "paparazzi_error_input",
    call = call
  )
}

page_frame <- function(page) {
  page$staging$frame
}

page_set_frame <- function(page, frame) {
  page$staging$frame <- frame
  invisible(page)
}

frame_effective <- function(ctx, frame, call = caller_env()) {
  frame <- as_frame_spec(frame, call = call)
  if (identical(frame, FALSE)) {
    return(FALSE)
  }
  staged <- page_frame(ctx$page)
  if (is.null(frame) && is.null(staged)) {
    return(NULL)
  }
  out <- frame_fill(frame %||% pz_frame(), staged, frame_defaults)
  out["target"] <- frame_target(
    target = if (!is.null(frame[["target"]])) frame["target"],
    scope = if (length(ctx$scope) > 0L) list(target = NULL),
    staged = if (!is.null(staged[["target"]])) staged["target"],
    viewport = list(target = NULL)
  )
  out
}

frame_measure <- function(
  ctx,
  spec,
  extent = c("page", "viewport"),
  call = caller_env()
) {
  extent <- arg_match(extent)
  box <- frame_content_box(ctx, spec, call = call)
  clamps <- list()
  if (!is.null(spec$bounds)) {
    els <- loc_resolve(ctx, spec$bounds, multiple = "all", call = call)
    withr::defer(release_elements(els))
    clamps[["frame bounds"]] <- box_union(
      el_rects(els, call = call),
      call = call
    )
  }
  geometry <- page_geometry(ctx, call = call)
  if (is.null(box)) {
    box <- c(0, 0, geometry$viewport_width, geometry$viewport_height)
  }
  if (identical(extent, "page")) {
    clamps[["the page"]] <- c(
      geometry$document_left - geometry$scroll_x,
      -geometry$scroll_y,
      geometry$document_left - geometry$scroll_x + geometry$document_width,
      -geometry$scroll_y + geometry$document_height
    )
  } else {
    clamps[["the viewport"]] <- c(
      0,
      0,
      geometry$viewport_width,
      geometry$viewport_height
    )
  }
  box <- frame_apply(
    spec,
    box,
    clamps,
    view = c(geometry$viewport_width, geometry$viewport_height),
    call = call
  )
  pinned <- c(
    some(clamps, function(clamp) clamp[1] >= box[1]),
    some(clamps, function(clamp) clamp[2] >= box[2]),
    some(clamps, function(clamp) clamp[3] <= box[3]),
    some(clamps, function(clamp) clamp[4] <= box[4])
  )
  list(box = box, pinned = pinned, geometry = geometry)
}

frame_region <- function(box, call = caller_env()) {
  width <- box[3] - box[1]
  height <- box[4] - box[2]
  if (width <= 0 || height <= 0) {
    cli::cli_abort(
      "The framed region is empty.",
      class = "paparazzi_error_frame",
      call = call
    )
  }
  list(x = box[1], y = box[2], width = width, height = height)
}

frame_clip <- function(ctx, spec, call = caller_env()) {
  m <- frame_measure(ctx, spec, extent = "page", call = call)
  # The pipeline ran viewport-relative; CDP clip coordinates are
  # document-relative.
  box <- m$box + rep(c(m$geometry$scroll_x, m$geometry$scroll_y), 2)
  box <- frame_round(box, pinned = m$pinned, even = FALSE)
  # An RTL frame can resolve into the document's negative-x region, and CDP
  # clip origins must be non-negative.
  if (box[1] < 0) {
    box[3] <- box[3] - box[1]
    box[1] <- 0
  }
  frame_region(box, call = call)
}

frame_target <- function(target, scope = NULL, staged = NULL, viewport = NULL) {
  target %||% scope %||% staged %||% viewport
}

frame_content_box <- function(ctx, spec, call = caller_env()) {
  els <- frame_target(
    target = if (!is.null(spec[["target"]])) {
      loc_resolve(ctx, spec[["target"]], multiple = "all", call = call)
    },
    scope = scope_connected(ctx, call = call)
  )
  if (is.null(els)) {
    return(NULL)
  }
  if (!is.null(spec[["target"]])) {
    withr::defer(release_elements(els))
  }
  frame_target_box(ctx, els, spec, call = call)
}

frame_target_box <- function(ctx, els, spec, call = caller_env()) {
  box <- box_union(el_rects(els, call = call), call = call)
  if (!identical(spec$target_box, "annotated")) {
    return(box)
  }
  painted <- els_values_flat(
    els,
    paste0(
      "function() { return ",
      ANNOTATION_LAYER_JS,
      "?.paintedRects(this) ?? null; }"
    ),
    call = call
  )
  if (is.null(painted)) {
    return(box)
  }
  c(
    min(box[1], painted[1]),
    min(box[2], painted[2]),
    max(box[3], painted[3]),
    max(box[4], painted[4])
  )
}

box_union <- function(rects, call = caller_env()) {
  if (nrow(rects) == 0L) {
    cli::cli_abort(
      "Internal error: computing a frame for an empty element set.",
      class = "paparazzi_error_internal",
      call = call
    )
  }
  c(
    min(rects$x),
    min(rects$y),
    max(rects$x + rects$width),
    max(rects$y + rects$height)
  )
}

page_geometry <- function(ctx, call = caller_env()) {
  g <- pz_js(
    ctx,
    "[window.scrollX, window.scrollY, window.innerWidth, window.innerHeight,
      Math.max(document.documentElement.scrollWidth, document.body.scrollWidth),
      Math.max(document.documentElement.scrollHeight, document.body.scrollHeight),
      (function() {
        // An RTL document wider than the viewport overflows to the
        // left: the scrollable canvas reaches negative document x,
        // spanning [-(scrollWidth - innerWidth), innerWidth].
        const vw = window.innerWidth;
        const docW = Math.max(
          document.documentElement.scrollWidth,
          document.body.scrollWidth
        );
        return getComputedStyle(document.documentElement).direction === 'rtl' &&
          docW > vw ? -(docW - vw) : 0;
      })()]"
  )
  g <- unlist(g)
  if (!is.numeric(g) || length(g) != 7) {
    cli::cli_abort(
      "Internal error: the page geometry read returned {.obj_type_friendly {g}}, not seven numbers.",
      class = "paparazzi_error_internal",
      call = call
    )
  }
  list(
    scroll_x = g[1],
    scroll_y = g[2],
    viewport_width = g[3],
    viewport_height = g[4],
    document_width = g[5],
    document_height = g[6],
    document_left = g[7]
  )
}

frame_apply <- function(
  spec,
  box,
  clamps = list(),
  view = NULL,
  call = caller_env()
) {
  pad <- spec$pad
  box <- box + c(-pad[4], -pad[1], pad[2], pad[3])
  if (is.null(spec$zoom)) {
    box <- box + rep(spec$offset, 2)
    box <- frame_grow_ratio(spec$ratio, box, spec$anchor)
  } else {
    box <- frame_zoom_region(spec, box, view)
  }
  if (box[3] <= box[1] || box[4] <= box[2]) {
    cli::cli_abort(
      "The framed region is empty.",
      class = "paparazzi_error_frame",
      call = call
    )
  }
  for (label in names(clamps)) {
    clamp <- clamps[[label]]
    box <- c(
      max(box[1], clamp[1]),
      max(box[2], clamp[2]),
      min(box[3], clamp[3]),
      min(box[4], clamp[4])
    )
    if (box[3] <= box[1] || box[4] <= box[2]) {
      cli::cli_abort(
        "The framed region is entirely outside {label}.",
        class = "paparazzi_error_frame",
        call = call
      )
    }
  }
  box
}

frame_zoom_region <- function(spec, box, view) {
  size <- view / spec$zoom
  if (!is.null(spec$ratio)) {
    size <- if (size[1] / size[2] > spec$ratio) {
      c(size[2] * spec$ratio, size[2])
    } else {
      c(size[1], size[1] / spec$ratio)
    }
  }
  frame_place(size, box, spec$anchor) + rep(spec$offset, 2)
}

frame_place <- function(size, box, anchor) {
  x <- if ("left" %in% anchor) {
    box[1]
  } else if ("right" %in% anchor) {
    box[3] - size[1]
  } else {
    (box[1] + box[3] - size[1]) / 2
  }
  y <- if ("top" %in% anchor) {
    box[2]
  } else if ("bottom" %in% anchor) {
    box[4] - size[2]
  } else {
    (box[2] + box[4] - size[2]) / 2
  }
  c(x, y, x + size[1], y + size[2])
}

frame_grow_ratio <- function(ratio, box, anchor) {
  if (is.null(ratio)) {
    return(box)
  }
  w <- box[3] - box[1]
  h <- box[4] - box[2]
  if (w <= 0 || h <= 0) {
    return(box)
  }
  if (w / h < ratio) {
    extra <- h * ratio - w
    if ("left" %in% anchor) {
      box[3] <- box[3] + extra
    } else if ("right" %in% anchor) {
      box[1] <- box[1] - extra
    } else {
      box[1] <- box[1] - extra / 2
      box[3] <- box[3] + extra / 2
    }
  } else if (w / h > ratio) {
    extra <- w / ratio - h
    if ("top" %in% anchor) {
      box[4] <- box[4] + extra
    } else if ("bottom" %in% anchor) {
      box[2] <- box[2] - extra
    } else {
      box[2] <- box[2] - extra / 2
      box[4] <- box[4] + extra / 2
    }
  }
  box
}

frame_round <- function(
  box,
  pinned = c(FALSE, FALSE, FALSE, FALSE),
  even = FALSE
) {
  round_edge <- function(value, pin, up) {
    unit <- if (even) 2 else 1
    if (pin) {
      unit * (if (up) ceiling(value / unit) else floor(value / unit))
    } else {
      unit * round(value / unit)
    }
  }
  c(
    round_edge(box[1], pinned[1], up = TRUE),
    round_edge(box[2], pinned[2], up = TRUE),
    round_edge(box[3], pinned[3], up = FALSE),
    round_edge(box[4], pinned[4], up = FALSE)
  )
}

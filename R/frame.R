#' @include overlay.R
NULL

#' Frame a capture region
#'
#' @description
#' [pz_frame()] builds a lazy framing spec for a capture: the region is
#' computed at capture time, then padded, nudged, grown to an aspect
#' ratio, and clamped. Screenshots take it through
#' `pz_screenshot(frame =)`, recordings through
#' `pz_record_start(frame =)`.
#'
#' The framed region is computed in this order:
#' 1. Union the bounding boxes of the target's matched elements. With
#'    `target_box = "annotated"`, include their attached annotations.
#' 2. Expand by `pad`, then shift by `offset`.
#' 3. If `ratio` is set, grow the shorter side to reach it (never
#'    shrink), placing the content by `anchor`.
#' 4. Clamp to `bounds` and to the page's rendered area.
#' 5. Round to whole pixels.
#'
#' @param target The element(s) the frame is computed from. `NULL` (the
#'   default) uses the target of the function the frame is passed to.
#'   Otherwise a CSS selector string, a [pz_loc()] spec, or a list of
#'   either: the frame is the union of the matched elements' bounding
#'   boxes.
#' @param ... Checked empty; reserved for future use.
#' @param ratio Width/height ratio to grow the region to, e.g. `16/9`.
#'   `NULL` keeps the region tight to its content.
#' @param pad Padding in CSS pixels: one number for all sides, or
#'   `c(top, right, bottom, left)`. Negative values crop inside the
#'   content box.
#' @param offset Nudge the region by `c(x, y)` pixels, applied after
#'   `pad`.
#' @param anchor Where the content sits while `ratio` grows the region:
#'   `"center"`, a side (`"top"`, `"bottom"`, `"left"`, `"right"`), or
#'   a corner (`"top left"`, `"top right"`, `"bottom left"`,
#'   `"bottom right"`). Case-insensitive; `"top right"`, `"right top"`,
#'   and `"top-right"` are equivalent.
#' @param bounds A target (a CSS selector string, a [pz_loc()] spec, or
#'   a list of either) whose union box the region is clamped within.
#' @param when When a recording measures the frame: `"stop"` (the
#'   default) measures against the final layout; `"start"` clips at
#'   capture start. Screenshots ignore this.
#' @param target_box `"element"` (the default) measures only matched
#'   elements. `"annotated"` also includes painted marks, callouts, and
#'   spotlight cutouts attached to those elements or their descendants;
#'   redactions and annotations on unrelated elements are excluded.
#'   Applies to stills, not the recording's home frame.
#'
#' @return An S3 object of class `paparazzi_frame`.
#'
#' @examples
#' # Frames are specs: nothing is measured until a capture uses them
#' pz_frame(pad = 32)
#' pz_frame(ratio = 16/9, pad = 24, anchor = "top")
#' pz_frame(".task-list", ratio = 4/3, bounds = "main")
#'
#' @examplesIf paparazzi:::examples_run()
#' page <- pz_open(pz_example("tasks"))
#' path <- file.path(tempdir(), "tasks.png")
#'
#' # With no target of its own, the frame uses the screenshot's target
#' page |> pz_screenshot(path, target = "#new-task", frame = pz_frame(pad = 16))
#'
#' # A frame target overrides it; a list frames the union of the boxes
#' page |> pz_screenshot(path, frame = pz_frame(list("h1", ".filters"), pad = 16))
#' pz_close(page)
#'
#' @export
pz_frame <- function(
  target = NULL,
  ...,
  ratio = NULL,
  pad = 0,
  offset = c(0, 0),
  anchor = "center",
  bounds = NULL,
  when = c("stop", "start"),
  target_box = c("element", "annotated")
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
    target_box = target_box
  )
}

#' @export
print.paparazzi_frame <- function(x, ...) {
  describe <- function(t) {
    if (is.null(t)) "<call's target>" else format_loc(t)
  }
  fields <- c(
    paste0("target: ", describe(x$target)),
    paste0("ratio: ", format(x$ratio)),
    paste0("pad: ", paste(x$pad, collapse = "/")),
    paste0("offset: ", paste(x$offset, collapse = "/")),
    paste0("anchor: ", paste(x$anchor, collapse = " ")),
    paste0("bounds: ", describe(x$bounds)),
    paste0("when: ", x$when),
    paste0("target_box: ", x$target_box)
  )
  cli::cat_line("<paparazzi_frame> ", paste(fields, collapse = ", "))
  invisible(x)
}

#' Set or clear the page's default framing
#'
#' @description
#' [pz_stage_frame()] stores a default [pz_frame()] on the page, applied
#' to every screenshot and recording that doesn't pass its own
#' `frame =`. An explicit [pz_frame()] replaces the default entirely --
#' settings are never merged -- and `frame = FALSE` disables framing for
#' a single call.
#'
#' Unlike [pz_stage()]'s animation settings, framing (like
#' [pz_stage_annotate()]'s styles) applies to screenshots as well as
#' recordings. An annotated
#' staged frame measures attached annotations in stills; recordings use
#' only its element boxes for the home frame, and camera shots use their
#' own `target_box` setting.
#'
#' @inheritParams pz_click
#' @param ... The default frame's target: a CSS selector string, a
#'   [pz_loc()] spec, or a list of either. Several unnamed arguments are
#'   unioned. With no target, the default frames each call's own target.
#'   A single `NULL` clears the default.
#' @param ratio,pad,offset,anchor,bounds,target_box Framing settings, as in
#'   [pz_frame()]; `NULL` means the [pz_frame()] default for that
#'   setting.
#'
#' @return `ctx`, invisibly.
#'
#' @seealso [pz_stage()], [pz_stage_annotate()], [pz_frame()], [pz_screenshot()]
#'
#' @examplesIf paparazzi:::examples_run()
#' page <- pz_open(pz_example("tasks"))
#' path <- file.path(tempdir(), "tasks.png")
#'
#' page |>
#'   pz_stage_frame(pad = 24) |>
#'   # Framed by the default: the form plus 24px of padding
#'   pz_screenshot(path, target = "#new-task") |>
#'   # An explicit frame replaces the default, settings and all
#'   pz_screenshot(path, target = "#new-task", frame = pz_frame(ratio = 16/9)) |>
#'   # FALSE turns framing off for one call
#'   pz_screenshot(path, frame = FALSE) |>
#'   # NULL clears the default
#'   pz_stage_frame(NULL)
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
  target_box = NULL
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
        !is.null(target_box)
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
    pad = pad %||% 0,
    offset = offset %||% c(0, 0),
    anchor = anchor %||% "center",
    bounds = bounds,
    when = "stop",
    target_box = target_box %||% "element"
  )
  page_set_frame(ctx$page, spec)
  ctx_return(ctx)
}

# The direction vocabulary (SPEC "Directions") as sorted token sets:
# the sides, the four corners, and "center". Consumers that take a
# subset of the vocabulary pass their own `valid` to parse_direction().
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

# Normalize a direction string to its sorted token set: lowercase,
# split on spaces or hyphens, sort, dedupe. Tokens outside the
# vocabulary and combinations outside `valid` abort with the valid
# values listed. Shared by framing, cursor, staging, and action directions.
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

# The frame spec constructor: validates and normalizes every field.
# target and bounds are promoted to loc lists eagerly, so type errors
# surface at spec-build time; resolution stays lazy. pad is normalized
# to c(top, right, bottom, left), offset to c(x, y), anchor to its
# sorted token set.
new_frame_spec <- function(
  target = NULL,
  ratio = NULL,
  pad = 0,
  offset = c(0, 0),
  anchor = "center",
  bounds = NULL,
  when = "stop",
  target_box = "element",
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
  pad <- check_pad(pad, call = call)
  offset <- check_offset(offset, call = call)
  anchor <- parse_direction(anchor, arg = "anchor", call = call)
  when <- arg_match(when, values = c("stop", "start"), error_call = call)
  target_box <- arg_match(
    target_box,
    values = c("element", "annotated"),
    error_call = call
  )
  structure(
    list(
      target = target,
      ratio = ratio,
      pad = pad,
      offset = offset,
      anchor = anchor,
      bounds = bounds,
      when = when,
      target_box = target_box
    ),
    class = "paparazzi_frame"
  )
}

# CSS-style padding: one number for all sides, or c(top, right,
# bottom, left).
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

# The page-level default framing: one field in the page's reserved
# staging state (private in R/context.R), read by screenshots and
# recordings. R6 private fields are reachable only through the
# object's enclos environment; these helpers are the single access
# point, so promoting the field to an active binding later touches
# one place.
page_frame <- function(page) {
  page$.__enclos_env__$private$staging_$frame
}

page_set_frame <- function(page, frame) {
  page$.__enclos_env__$private$staging_$frame <- frame
  invisible(page)
}

# The framing a capture uses: NULL means the page default if one is
# set, else no framing; FALSE opts out for one call; a pz_frame()
# spec (explicit or default) is used as-is. Anything else -- including
# TRUE -- remains an unsupported value.
frame_effective <- function(ctx, frame, call = caller_env()) {
  if (is.null(frame)) {
    frame <- page_frame(ctx$page)
  }
  if (
    is.null(frame) ||
      identical(frame, FALSE) ||
      inherits(frame, "paparazzi_frame")
  ) {
    return(frame)
  }
  cli::cli_abort(
    c(
      "{.arg frame} must be a {.fn pz_frame} spec, {.code FALSE}, or {.code NULL}, not {.obj_type_friendly {frame}}.",
      i = "{.code frame = FALSE} captures without framing."
    ),
    class = "paparazzi_error_unsupported",
    call = call
  )
}

# Measure a frame before translating or rounding it. Screenshot capture
# clamps to the document box (including its RTL left edge) because it can
# render below the fold; recording captures only the visible viewport.
frame_measure <- function(
  ctx,
  target,
  spec,
  extent = c("page", "viewport"),
  call = caller_env()
) {
  extent <- arg_match(extent)
  box <- frame_content_box(ctx, target, spec, call = call)
  clamps <- list()
  if (!is.null(spec$bounds)) {
    els <- loc_resolve(ctx, spec$bounds, multiple = "all", call = call)
    withr::defer(release_elements(els))
    clamps[["frame bounds"]] <- box_union(
      el_rects(els, call = call),
      call = call
    )
  }
  # Resolution auto-waits; a target appearing mid-wait can expand the
  # document. Read geometry only after resolving content and bounds.
  geometry <- page_geometry(ctx, call = call)
  if (is.null(box)) {
    box <- c(0, 0, geometry$viewport_width, geometry$viewport_height)
  }
  if (identical(extent, "page")) {
    # The page's rendered area in viewport coordinates; the document
    # box can extend left of the viewport for a wide RTL document.
    clamps[["the page"]] <- c(
      geometry$document_left - geometry$scroll_x,
      -geometry$scroll_y,
      geometry$document_left - geometry$scroll_x + geometry$document_width,
      -geometry$scroll_y + geometry$document_height
    )
  } else {
    # The recording PNG holds only the viewport, not the full page.
    clamps[["the viewport"]] <- c(
      0,
      0,
      geometry$viewport_width,
      geometry$viewport_height
    )
  }
  box <- frame_apply(spec, box, clamps, call = call)
  # A binding clamp assigned its edge exactly; coinciding edges count as
  # pinned too. Round these inward so the pixel clip stays within bounds.
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

# The CDP clip for a framed still: measure against the page, translate
# to document coordinates, and round to whole pixels.
frame_clip <- function(ctx, target, spec, call = caller_env()) {
  m <- frame_measure(ctx, target, spec, extent = "page", call = call)
  # The pipeline ran viewport-relative; CDP clip coordinates are
  # document-relative.
  box <- m$box + rep(c(m$geometry$scroll_x, m$geometry$scroll_y), 2)
  box <- frame_round(box, pinned = m$pinned, even = FALSE)
  # Horizontal only: an RTL frame can resolve into the document's
  # negative-x region, and CDP clip origins must be non-negative.
  # Shift the origin to 0 preserving the size -- the captured region
  # shifts with it, mirroring the unframed path (clip_viewport()).
  if (box[1] < 0) {
    box[3] <- box[3] - box[1]
    box[1] <- 0
  }
  frame_region(box, call = call)
}

# The content box a frame is computed from, viewport-relative: the
# frame's own target if it has one, else the call's target, else the
# pinned scope (scoped context), else NULL for the viewport fallback
# (the caller fills it from the geometry it reads after resolution).
frame_content_box <- function(ctx, target, spec, call = caller_env()) {
  want <- if (is.null(spec$target)) target else spec$target
  if (!is.null(want)) {
    els <- loc_resolve(ctx, want, multiple = "all", call = call)
    withr::defer(release_elements(els))
    return(frame_target_box(ctx, els, spec, call = call))
  }
  scoped <- scope_root(ctx, call = call)
  if (!is.null(scoped)) {
    return(frame_target_box(ctx, scoped, spec, call = call))
  }
  NULL
}

frame_target_box <- function(ctx, els, spec, call = caller_env()) {
  box <- box_union(el_rects(els, call = call), call = call)
  if (spec$target_box != "annotated") {
    return(box)
  }
  painted <- els_call(
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

# The union of element rects, as a viewport-relative box
# c(left, top, right, bottom).
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

# One JS read of the geometry framing needs: scroll offsets, viewport
# size, document size, and the document's left edge in document
# coordinates.
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

# Pure framing geometry on a viewport-relative box
# c(left, top, right, bottom): pad, offset, ratio growth by anchor,
# then the clamps (named boxes in the same space, intersected in
# order). A box that ends up degenerate aborts with
# paparazzi_error_frame.
frame_apply <- function(spec, box, clamps = list(), call = caller_env()) {
  pad <- spec$pad
  box <- box + c(-pad[4], -pad[1], pad[2], pad[3])
  box <- box + rep(spec$offset, 2)
  box <- frame_grow_ratio(spec$ratio, box, spec$anchor)
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

# Grow the shorter side to reach `ratio` (width / height), never
# shrinking, placing the content by the anchor tokens: left/right and
# top/bottom pin the content to that edge (all growth on the opposite
# side); otherwise the extra space splits evenly. A box with an empty
# side has no aspect to grow and is returned unchanged.
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

# Round box edges: whole pixels for stills, even pixels for video
# (the recorder's path), so width and height never split a pixel.
# Edges a clamp fixed in place ("pinned") round INWARD -- left/top
# up, right/bottom down -- so the final pixel clip stays within the
# CSS bounds; free edges round to the nearest pixel.
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

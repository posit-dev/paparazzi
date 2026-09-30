#' Add text callouts to page elements
#'
#' Draws one callout per matching element, repeating `text` for every match.
#' Callouts follow their targets during scrolling and layout changes, and
#' appear in screenshots and recordings until cleared with
#' [pz_annotate_clear()]. They belong to the current document and disappear
#' on navigation. A bubble is kept within the viewport even if this moves it
#' away from the requested side; text that cannot fit a tiny viewport is
#' clipped. A viewport resize does not rewrap an existing callout.
#'
#' @inheritParams pz_annotate
#' @param text One nonempty string of literal text (not HTML).
#' @param side A side (`"top"`, `"right"`, `"bottom"`, `"left"`) or a
#'   diagonal corner such as `"top right"`. `NULL` chooses the cardinal
#'   side with the most room when drawn. The chosen side stays fixed.
#' @param leader The line between the bubble and the target. `TRUE` (the
#'   default) draws a line with an arrow at the target, equal to
#'   `c(start = "none", end = "arrow")`; `FALSE` draws no line, leaving a
#'   tooltip-style bubble. A named character vector sets a decoration for
#'   each end: `start` is the bubble side, `end` is the target side, and an
#'   omitted name defaults to `"none"`. Decoration values are `"none"`,
#'   `"arrow"` (a filled triangle), `"dot"`, or `"bar"` (a perpendicular
#'   tick). The shaft stops at each decoration's base, and short leaders
#'   shrink the decorations.
#' @param label Optional badge; `TRUE` numbers the matches, while one string
#'   or number repeats for each match. `NULL` omits the badge.
#' @param reveal `"pop"` (the default), `"fade"`, `"draw"`, `"slide"`,
#'   `"wipe"`, or `"none"`. Animates only during an active,
#'   unpaused recording; clearing plays the reverse. `"draw"` draws the
#'   leader's shaft, then shows its decorations.
#' @param color Accent color for the bubble border, leader line and
#'   decorations; `NULL` uses the staged annotation color.
#' @param fill,text_color CSS colors for the bubble background and text
#'   (and the callout's badge); `NULL` uses the staged `fill`/`text_color`
#'   from [pz_stage_annotate()], falling back to `"#171717"` on `"white"`.
#'   [pz_annotate()] mark badges do not use these; they follow their mark's
#'   `color` unless overridden per call with `label_fill`/`label_text_color`.
#' @param stroke_width Leader line width in CSS pixels, or `NULL` for the
#'   staged `stroke_width` from [pz_stage_annotate()]. Decoration sizes
#'   scale with it. Shared with [pz_annotate()] marks.
#' @param distance Bubble-to-target gap in CSS pixels, or `NULL` for the
#'   staged `distance` from [pz_stage_annotate()]. Applies with or without
#'   a leader.
#' @param font_family CSS font family; `NULL` uses the staged default.
#' @param font_size Font size in CSS pixels; `NULL` uses the staged default.
#' @return `ctx`, invisibly.
#' @seealso [pz_annotate()], [pz_annotate_clear()]
#' @export
pz_annotate_callout <- function(
  ctx,
  text,
  ...,
  target = NULL,
  side = NULL,
  leader = TRUE,
  label = NULL,
  reveal = c("pop", "fade", "draw", "slide", "wipe", "none"),
  id = NULL,
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
  check_string(text, allow_empty = FALSE)
  if (!is.null(side)) {
    side <- parse_direction(side, valid = STAGE_DIRECTIONS, arg = "side")
  }
  leader <- check_callout_leader(leader)
  label <- check_annotation_label(label)
  reveal <- rlang::arg_match(reveal)
  check_annotation_id(id)
  style <- annotate_style(ctx, color, font_family, font_size)
  surface <- annotate_fill_style(ctx, fill, text_color)
  stroke_width <- annotate_stroke_width(ctx, stroke_width)
  distance <- annotate_distance(ctx, distance)
  els <- annotate_elements(ctx, target)
  annotate_register_init(ctx)
  recording <- annotate_recording(ctx$page)
  options <- list(
    id = id,
    text = text,
    side = side,
    leader = leader,
    label = label,
    reveal = reveal,
    color = style$color,
    fill = surface$fill,
    textColor = surface$text_color,
    strokeWidth = stroke_width,
    distance = distance,
    fontFamily = style$font_family,
    fontSize = style$font_size,
    animate = recording
  )
  annotate_call(ctx, els, "callout", options, "drawing the callout")
  ctx_return(ctx)
}

CALLOUT_DECORATIONS <- c("none", "arrow", "dot", "bar")

# leader is TRUE/FALSE or a named character vector of decorations for the
# shaft's ends; normalized to FALSE or c(start = , end = ) with omitted
# ends filled with "none".
check_callout_leader <- function(leader, call = caller_env()) {
  if (isTRUE(leader)) {
    return(c(start = "none", end = "arrow"))
  }
  if (isFALSE(leader)) {
    return(FALSE)
  }
  if (!is.character(leader)) {
    cli::cli_abort(
      paste0(
        "{.arg leader} must be {.val TRUE}, {.val FALSE}, or a named ",
        "character vector of decorations."
      ),
      call = call
    )
  }
  check_character(leader, arg = "leader", call = call)
  ends <- names(leader)
  if (
    is.null(ends) ||
      any(!nzchar(ends)) ||
      anyDuplicated(ends) ||
      !all(ends %in% c("start", "end"))
  ) {
    cli::cli_abort(
      paste0(
        "{.arg leader} must be a character vector named from ",
        "{.val start} and {.val end}."
      ),
      call = call
    )
  }
  bad <- !leader %in% CALLOUT_DECORATIONS
  if (any(bad)) {
    cli::cli_abort(
      paste0(
        "{.arg leader} decorations must be one of ",
        "{.val {CALLOUT_DECORATIONS}}, not {.val {leader[bad]}}."
      ),
      call = call
    )
  }
  out <- c(start = "none", end = "none")
  out[ends] <- leader
  out
}

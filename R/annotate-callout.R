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
#' @param arrow Whether to draw an arrow ending at the target box. `FALSE`
#'   leaves a tooltip-style bubble.
#' @param label Optional badge; `TRUE` numbers the matches, while one string
#'   or number repeats for each match. `NULL` omits the badge.
#' @param reveal `"pop"` (the default), `"fade"`, `"draw"`, `"slide"`,
#'   `"wipe"`, or `"none"`. Animates only during an active,
#'   unpaused recording; clearing plays the reverse.
#' @param color Accent border and arrow color; `NULL` uses the staged
#'   annotation color. The bubble remains dark with white text.
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
  arrow = TRUE,
  label = NULL,
  reveal = c("pop", "fade", "draw", "slide", "wipe", "none"),
  id = NULL,
  color = NULL,
  font_family = NULL,
  font_size = NULL
) {
  check_context(ctx)
  check_dots_empty()
  check_string(text, allow_empty = FALSE)
  if (!is.null(side)) {
    side <- parse_direction(side, valid = STAGE_DIRECTIONS, arg = "side")
  }
  check_bool(arrow)
  label <- check_annotation_label(label)
  reveal <- rlang::arg_match(reveal)
  check_annotation_id(id)
  style <- annotate_style(ctx, color, font_family, font_size)
  els <- annotate_elements(ctx, target)
  annotate_register_init(ctx)
  recording <- annotate_recording(ctx$page)
  options <- list(
    id = id,
    text = text,
    side = side,
    arrow = arrow,
    label = label,
    reveal = reveal,
    color = style$color,
    fontFamily = style$font_family,
    fontSize = style$font_size,
    animate = recording
  )
  annotate_call(ctx, els, "callout", options, "drawing the callout")
  ctx_return(ctx)
}

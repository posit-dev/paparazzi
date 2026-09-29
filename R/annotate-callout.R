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
#'   or number repeats for each match.
#' @param reveal `"fade"`, `"draw"`, `"pop"`, `"slide"`, `"wipe"`, or
#'   `"none"`. `NULL` uses `"pop"`. Animates only during an active,
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
  reveal = NULL,
  id = NULL,
  color = NULL,
  font_family = NULL,
  font_size = NULL
) {
  check_context(ctx)
  check_dots_empty()
  check_string(text)
  if (!nzchar(text)) {
    cli::cli_abort("{.arg text} must be nonempty.")
  }
  if (!is.null(side)) {
    side <- parse_direction(side, valid = STAGE_DIRECTIONS, arg = "side")
  }
  check_bool(arrow)
  if (!is.null(label)) {
    if (!isTRUE(label)) {
      if (
        !(is.character(label) || is.numeric(label)) ||
          length(label) != 1L ||
          is.na(label)
      ) {
        cli::cli_abort("{.arg label} must be `TRUE`, one string or one number.")
      }
      label <- as.character(label)
    }
  }
  reveal <- reveal %||% "pop"
  if (
    !is.character(reveal) ||
      length(reveal) != 1L ||
      is.na(reveal) ||
      !reveal %in% c("fade", "draw", "pop", "slide", "wipe", "none")
  ) {
    cli::cli_abort(
      "{.arg reveal} must be {.val fade}, {.val draw}, {.val pop}, {.val slide}, {.val wipe}, or {.val none}."
    )
  }
  check_annotation_id(id)
  stage <- page_stage(ctx$page)
  color <- color %||% stage$annotate_color
  font_family <- font_family %||% stage$annotate_font_family
  font_size <- font_size %||% stage$annotate_font_size
  check_string(color)
  check_string(font_family)
  check_number_decimal(font_size, min = 0, allow_infinite = FALSE)
  if (font_size == 0) {
    cli::cli_abort("{.arg font_size} must be greater than 0.")
  }
  els <- loc_resolve(ctx, target, multiple = "all")
  withr::defer(release_elements(els))
  annotate_register_init(ctx)
  recording <- annotate_recording(ctx$page)
  options <- list(
    id = id,
    text = text,
    side = side,
    arrow = arrow,
    label = label,
    reveal = reveal,
    color = color,
    fontFamily = font_family,
    fontSize = font_size,
    animate = recording
  )
  duration <- annotate_call(ctx, els, "callout", options, "drawing the callout")
  if (recording && duration > 0) {
    pump_loop(ctx$page$child_loop, duration / 1000 + 0.05)
  }
  invisible(ctx)
}

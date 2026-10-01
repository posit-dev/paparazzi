#' Spotlight page elements
#'
#' Dims the page except for a rounded cutout around each matched element.
#' The scrim covers the document, including below-fold areas captured in
#' screenshots. The spotlight follows its elements through scrolling and
#' layout changes; hidden, disconnected, or zero-size elements lose their
#' cutouts. Cutouts clip to the target's axis-aligned overflow ancestors
#' (custom `overflow-clip-margin` excepted), so a target scrolled out of an
#' overflow container opens no cutout over the content below it. It appears in screenshots and recordings until cleared, and is
#' lost on navigation.
#' Only one spotlight exists per page: a new call replaces the previous one,
#' and [pz_annotate_clear()] removes it by the reserved id `"spotlight"` or
#' with a clear-all call. The cutout covers each target's padded border box;
#' overflowing descendants and top-layer dialogs/popovers are not covered.
#'
#' @inheritParams pz_annotate
#' @param dim Opacity of the black overlay outside the cutouts, from 0
#'   (transparent) to 1 (black). Defaults to 0.6.
#' @param reveal `"fade"` (default) or `"none"`. A fade plays only during an
#'   active, unpaused recording, and reverses on clear. Otherwise drawing and
#'   clearing are instant.
#' @return `ctx`, invisibly.
#' @seealso [pz_annotate()], [pz_annotate_clear()]
#' @export
pz_annotate_spotlight <- function(
  ctx,
  target = NULL,
  ...,
  pad = 0,
  dim = 0.6,
  reveal = c("fade", "none")
) {
  check_context(ctx)
  check_dots_empty()
  pad <- check_pad(pad, arg = "pad")
  check_number_decimal(dim, min = 0, max = 1, allow_infinite = FALSE)
  reveal <- rlang::arg_match(reveal)
  els <- annotate_elements(ctx, target)
  annotate_register_init(ctx)
  recording <- annotate_recording(ctx$page)
  options <- list(
    pad = unname(pad),
    dim = dim,
    reveal = reveal,
    animate = recording
  )
  annotate_call(ctx, els, "spotlight", options, "drawing the spotlight")
  ctx_return(ctx)
}

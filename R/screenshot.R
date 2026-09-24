#' Take a screenshot
#'
#' @description
#' Captures a PNG of the page and writes it to `path`, returning the
#' context invisibly so screenshots slot into `|>` chains.
#'
#' The captured region depends on `target`:
#' * `NULL` from the root context (from [pz_open()]): the current
#'   viewport.
#' * `NULL` from a scoped context (from `pz_find*()`): the scope's
#'   bounding box.
#' * A CSS selector string, a [pz_loc()] spec, or a list of either: the
#'   union of the bounding boxes of all matched elements. A selector
#'   matching several elements is a union, not an error.
#'
#' Screenshots are captured at the page's current device pixel ratio: the
#' PNG's pixel dimensions are the captured CSS size multiplied by the
#' dpr. A [pz_frame()] can frame the capture; the page's default framing
#' is set with `pz_stage_frame()`.
#'
#' @inheritParams pz_click
#' @param path File path the PNG is written to; an existing file is
#'   overwritten.
#' @param target What to capture: `NULL` for the viewport (root context)
#'   or the scope's box (scoped context), or a CSS selector string,
#'   `pz_loc()` spec, or list of either for the union of matched
#'   elements' bounding boxes.
#' @param frame Framing to apply to the capture: `NULL` (the default)
#'   uses the page's default framing set with `pz_stage_frame()` if there
#'   is one, else captures unframed; a [pz_frame()] spec frames the
#'   capture, replacing any default entirely; `FALSE` disables framing
#'   for this capture.
#'
#' @seealso [pz_frame()], [pz_stage_frame()]
#'
#' @return `ctx`, invisibly.
#'
#' @export
pz_screenshot <- function(ctx, path, ..., target = NULL, frame = NULL) {
  check_context(ctx)
  check_dots_empty()
  check_string(path)

  # NULL means the page default (pz_stage_frame()) if one is set; FALSE
  # opts out for one call; a pz_frame() spec replaces the default.
  frame <- frame_effective(ctx, frame)

  clip <- if (inherits(frame, "paparazzi_frame")) {
    frame_clip(ctx, target, frame)
  } else if (is.null(target) && length(ctx$scope) == 0) {
    clip_viewport(ctx)
  } else if (is.null(target)) {
    # The clip is the union of the boxes of the current scope's pinned
    # set, detach-checked once per call (one use, one check): a scope
    # that left the page raises the classed error instead of clipping
    # to stale zero boxes. Revisit if scoping settles on
    # intersect-instead-of-union.
    scoped <- scope_root(ctx)
    clip_rects_union(ctx, el_rects(scoped))
  } else {
    els <- loc_resolve(ctx, target, multiple = "all")
    withr::defer(release_elements(els))
    clip_rects_union(ctx, el_rects(els))
  }

  res <- screenshot_capture(ctx, clip)
  writeBin(jsonlite::base64_dec(res$data), path)
  invisible(ctx)
}
# The clip for a root-context capture: the viewport, in document
# coordinates, read in one JS evaluation.
clip_viewport <- function(ctx, call = caller_env()) {
  v <- pz_js(
    ctx,
    "[window.scrollX, window.scrollY, window.innerWidth, window.innerHeight]"
  )
  # pz_js() converts a JS array to an R list, so flatten it before the
  # shape check.
  v <- unlist(v)
  if (!is.numeric(v) || length(v) != 4) {
    cli::cli_abort(
      "Internal error: the viewport read returned {.obj_type_friendly {v}}, not four numbers.",
      class = "paparazzi_error_internal",
      call = call
    )
  }
  clip <- list(x = v[[1]], y = v[[2]], width = v[[3]], height = v[[4]])
  # scrollX goes negative on horizontally-scrolled RTL pages, and CDP
  # rejects a negative clip origin; clamp it (the region shifts by the
  # clamped amount). Bounds-aware capture is the framing task's job.
  clip$x <- max(clip$x, 0)
  clip$y <- max(clip$y, 0)
  clip
}
# The clip for an element capture: the union of viewport-relative rects,
# shifted into document coordinates. The four edges are pure reductions
# over the tibble columns -- the prior-art bug (the blog's union_png())
# updated x before computing width, so no rect is ever mutated
# mid-computation.
clip_rects_union <- function(ctx, rects, call = caller_env()) {
  if (nrow(rects) == 0L) {
    cli::cli_abort(
      "Internal error: computing a clip for an empty element set.",
      class = "paparazzi_error_internal",
      call = call
    )
  }
  x0 <- min(rects$x)
  y0 <- min(rects$y)
  x1 <- max(rects$x + rects$width)
  y1 <- max(rects$y + rects$height)
  clip <- list(x = x0, y = y0, width = x1 - x0, height = y1 - y0)
  # el_rects() is viewport-relative; CDP clip coordinates (with
  # captureBeyondViewport) are document-relative, so add the scroll
  # offsets. Off-viewport targets need no scrollIntoView.
  scroll <- pz_js(ctx, "[window.scrollX, window.scrollY]")
  clip$x <- clip$x + scroll[[1]]
  clip$y <- clip$y + scroll[[2]]
  # CDP rejects negative clip offsets; clamping to the document bounds is
  # the framing task's job, so only the origin is fixed.
  clip$x <- max(clip$x, 0)
  clip$y <- max(clip$y, 0)
  clip
}
# One synchronous CDP call, like loc_resolve_once(): no promise chaining.
# captureBeyondViewport = TRUE makes Chrome interpret the clip in page
# (document) coordinates, and fromSurface = TRUE renders the surface at
# the page's device pixel ratio, so clip$scale = 1 yields a PNG at
# exactly the current dpr (chromote passes scale/pixel_ratio for the
# same reason).
screenshot_capture <- function(ctx, clip, call = caller_env()) {
  timeout <- ctx$page$default_timeout
  tryCatch(
    ctx$page$session$Page$captureScreenshot(
      format = "png",
      clip = list(
        x = clip$x,
        y = clip$y,
        width = clip$width,
        height = clip$height,
        scale = 1
      ),
      fromSurface = TRUE,
      captureBeyondViewport = TRUE,
      timeout_ = timeout
    ),
    error = function(e) {
      # A chromote command timeout is a timeout of the capture, not a raw
      # chromote error.
      if (grepl("timed out", conditionMessage(e), ignore.case = TRUE)) {
        cli::cli_abort(
          "Timed out after {timeout}s capturing the screenshot.",
          class = "paparazzi_error_timeout",
          call = call,
          parent = e
        )
      }
      stop(e)
    }
  )
}

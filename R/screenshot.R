#' Take a screenshot
#'
#' @description
#' Captures a PNG of the page. With an explicit `path`, returns the context
#' invisibly so screenshots slot into `|>` chains. Without a path, the
#' capture is a terminal step: a figure in a knitted document or a
#' printable preview in an interactive session.
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
#' A screen-space caption set with [pz_annotate_caption()] is composited
#' onto the captured PNG after framing; captioned stills require \pkg{png}.
#'
#' @inheritParams pz_click
#' @param path File path the PNG is written to; an existing file is
#'   overwritten. If omitted while knitting, a numbered file in the
#'   chunk's figure directory is used and the screenshot is included in
#'   the document. If omitted in an interactive session, a temporary PNG
#'   is shown when the result is printed. A path is required otherwise.
#'   In a document, end the pipe with `pz_screenshot()` to include it; give
#'   intermediate screenshots a path to keep chaining.
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
#' @return With an explicit path, `ctx`, invisibly. Without a path while
#'   knitting, a knitr image; without a path in an interactive session,
#'   an image preview. These image results are terminal, not contexts.
#'
#' @examplesIf rlang::is_interactive() && !is.null(suppressMessages(chromote::find_chrome()))
#' page <- pz_open(pz_example("tasks"))
#' path <- file.path(tempdir(), "tasks.png")
#'
#' # At the root, target = NULL captures the viewport
#' page |> pz_screenshot(path)
#'
#' # A target captures its box; a list captures the union of the boxes
#' page |> pz_screenshot(path, target = ".task-list")
#' page |> pz_screenshot(path, target = list("#new-task", ".filters"))
#'
#' # Padding, aspect ratio and anchoring come from pz_frame()
#' page |> pz_screenshot(path, target = "#new-task", frame = pz_frame(pad = 16))
#' file.exists(path)
#' pz_close(page)
#'
#' @export
pz_screenshot <- function(ctx, path, ..., target = NULL, frame = NULL) {
  check_context(ctx)
  check_dots_empty()
  implicit <- missing(path)
  knitting <- isTRUE(getOption("knitr.in.progress"))
  if (implicit && knitting) {
    path <- knit_capture_path("png")
  } else if (implicit && rlang::is_interactive()) {
    path <- tempfile("paparazzi-", fileext = ".png")
  }
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

  # Hide only inspect outlines for the capture; annotations and the
  # visible cursor belong in stills.
  overlay_display <- overlay_hide(ctx)
  on.exit(overlay_restore(ctx, overlay_display), add = TRUE)
  res <- screenshot_capture(ctx, clip)
  writeBin(jsonlite::base64_dec(res$data), path)
  caption <- page_caption(ctx$page)
  if (!is.null(caption)) {
    if (!rlang::is_installed("png")) {
      cli::cli_abort(
        "The {.pkg png} package is needed for captioned screenshots."
      )
    }
    size <- png_read_size(path)
    overlay <- tempfile("paparazzi-caption-", fileext = ".png")
    on.exit(unlink(overlay), add = TRUE)
    caption_render(
      ctx$page,
      caption,
      size$width,
      size$height,
      size$width / clip$width,
      overlay
    )
    caption_blend_still(path, overlay)
  }
  if (implicit && knitting) {
    return(knitr::include_graphics(
      path,
      dpi = 96 * pz_js(ctx, "window.devicePixelRatio")
    ))
  }
  if (implicit) {
    return(structure(path, class = "paparazzi_preview"))
  }
  ctx_return(ctx)
}

#' @export
#' @noRd
print.paparazzi_preview <- function(x, ...) {
  path <- preview_stage(unclass(x))
  viewer <- getOption("viewer")
  if (is.function(viewer)) {
    viewer(path)
  } else {
    utils::browseURL(path)
  }
  invisible(x)
}

# The RStudio viewer only serves files under the session temp directory,
# and viewers show images directly but need a page for video.
preview_stage <- function(path) {
  video <- tolower(tools::file_ext(path)) %in% c("mp4", "webm")
  temp <- paste0(normalizePath(tempdir(), winslash = "/"), "/")
  if (!video && startsWith(normalizePath(path, winslash = "/"), temp)) {
    return(path)
  }
  dir <- tempfile("paparazzi-preview-")
  dir.create(dir)
  file.copy(path, file.path(dir, basename(path)))
  if (!video) {
    return(file.path(dir, basename(path)))
  }
  page <- file.path(dir, "index.html")
  writeLines(
    c(
      "<!doctype html>",
      '<meta charset="utf-8">',
      '<body style="margin:0;min-height:100vh;display:grid;place-items:center;background:#222">',
      paste0(
        '<video controls autoplay muted loop playsinline ',
        'style="max-width:100%;max-height:100vh" src="',
        utils::URLencode(basename(path), reserved = TRUE),
        '"></video>'
      ),
      "</body>"
    ),
    page
  )
  page
}

knit_capture_path <- function(ext) {
  # fig_path() does not advance for external images; magick uses knitr's
  # plot counter to avoid overwriting earlier captures in the chunk.
  number <- utils::getFromNamespace("plot_counter", "knitr")()
  path <- knitr::fig_path(ext, number = number)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  path
}

# The clip for a root-context capture: the viewport in document coordinates.
clip_viewport <- function(ctx, call = caller_env()) {
  g <- page_geometry(ctx, call = call)
  # RTL scrollX can be negative; CDP rejects negative clip origins.
  list(
    x = max(g$scroll_x, 0),
    y = max(g$scroll_y, 0),
    width = g$viewport_width,
    height = g$viewport_height
  )
}

# The clip for an element capture: the union of viewport-relative rects,
# shifted into document coordinates.
clip_rects_union <- function(ctx, rects, call = caller_env()) {
  edges <- box_union(rects, call = call)
  clip <- list(
    x = edges[1],
    y = edges[2],
    width = edges[3] - edges[1],
    height = edges[4] - edges[2]
  )
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
  pz_js(
    ctx,
    "document.getElementById('paparazzi-overlay-root')?.shadowRoot?.querySelector('.pz-annotations')?.pz?.sync()"
  )
  timeout <- ctx$page$default_timeout
  cdp_call(
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
    timeout,
    "capturing the screenshot",
    call = call
  )
}

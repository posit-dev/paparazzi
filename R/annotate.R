#' @include overlay.R
NULL

#' Mark page elements
#'
#' Draws an annotation for each element matched by `target`. Annotations
#' follow their elements as the page scrolls or changes layout, and appear
#' in screenshots and recordings until cleared with [pz_annotate_clear()].
#' Annotations belong to the current document; navigating away removes them.
#' Marks and their badges clip to the target's axis-aligned overflow
#' ancestors (custom `overflow-clip-margin` excepted), and a mark hides
#' while its target disconnects, stops rendering, is `visibility: hidden`
#' with no visible descendants, or is entirely clipped.
#'
#' @inheritParams pz_act_click
#' @param target A selector, [pz_loc()] spec, or list of targets.
#'   `NULL` uses the current scope, or `document.body` at the root.
#' @param ... Checked empty; reserved for future use.
#' @param type `"box"` (outline), `"circle"` (ellipse), `"underline"` (bottom
#'   stroke), or `"highlight"` (translucent fill blended over the page).
#' @param label Optional badge. `TRUE` numbers the matches 1, 2, ...;
#'   one string or number repeats on each match. `NULL` omits the badge.
#' @param pad Extra CSS pixels around each element: one number or
#'   `c(top, right, bottom, left)`. Defaults to zero.
#' @param reveal `"auto"` (the default) uses `"fade"` for boxes and `"draw"`
#'   for other types. Other choices are `"fade"`, `"draw"`, `"pop"`, `"slide"`,
#'   `"wipe"`, or `"none"`.
#'   Reveals animate only during an active, unpaused recording; clearing
#'   reverses the reveal. Wipe sweeps clockwise from 12 o'clock.
#' @param id Optional nonempty id. Reusing it replaces its annotations;
#'   `NULL` generates a unique id, so calls accumulate annotations.
#'   `"spotlight"` and `"caption"` are reserved for other types.
#' @param color CSS accent color for the mark outline, or `NULL` for the
#'   page default from [pz_stage_annotate()].
#' @param label_fill,label_text_color CSS colors for the badge background
#'   and text. `NULL` (the default) fills the badge with the mark's `color`
#'   and uses white text. The `fill` and `text_color` set by
#'   [pz_stage_annotate()] style callouts, not mark badges.
#' @param stroke_width Mark stroke width in CSS pixels, or `NULL` for the
#'   staged `stroke_width` from [pz_stage_annotate()].
#' @param font_family CSS font family for the badge, or `NULL` for the
#'   page default.
#' @param font_size Badge font size in CSS pixels, or `NULL` for the page
#'   default.
#'
#' @return `ctx`, invisibly.
#' @seealso [pz_annotate_clear()], [pz_stage_annotate()]
#' @export
pz_annotate <- function(
  ctx,
  target = NULL,
  ...,
  type = "box",
  label = NULL,
  pad = 0,
  reveal = c("auto", "fade", "draw", "pop", "slide", "wipe", "none"),
  id = NULL,
  color = NULL,
  label_fill = NULL,
  label_text_color = NULL,
  stroke_width = NULL,
  font_family = NULL,
  font_size = NULL
) {
  check_context(ctx)
  check_dots_empty()
  check_string(type)
  type <- rlang::arg_match0(type, c("box", "circle", "underline", "highlight"))
  reveal <- rlang::arg_match(reveal)
  if (reveal == "auto") {
    reveal <- if (type == "box") "fade" else "draw"
  }
  check_annotation_id(id)
  label <- check_annotation_label(label)
  pad <- check_pad(pad, arg = "pad")
  style <- annotate_style(ctx, color, font_family, font_size)
  if (!is.null(label_fill)) {
    check_string(label_fill, allow_empty = FALSE)
  }
  if (!is.null(label_text_color)) {
    check_string(label_text_color, allow_empty = FALSE)
  }
  stroke_width <- annotate_stroke_width(ctx, stroke_width)
  els <- annotate_elements(ctx, target)
  annotate_register_init(ctx)
  recording <- annotate_recording(ctx$page)
  options <- list(
    id = id,
    type = type,
    pad = unname(pad),
    label = label,
    color = style$color,
    labelFill = label_fill %||% style$color,
    labelTextColor = label_text_color %||% "white",
    strokeWidth = stroke_width,
    fontFamily = style$font_family,
    fontSize = style$font_size,
    reveal = reveal,
    animate = recording
  )
  annotate_call(ctx, els, "draw", options, "drawing the annotation")
  ctx_return(ctx)
}

#' Redact page elements
#'
#' Covers every element matched by `target` with an instant opaque fill or
#' backdrop blur in screenshots and recordings. Fill is the safe choice for
#' secrets: blur can leave text partly legible. Redactions follow elements
#' as they move and respect axis-aligned overflow clipping, except custom
#' `overflow-clip-margin`. If a target disconnects, stops rendering, or is
#' entirely clipped, its redaction hides until it becomes visible again. They
#' belong to the current document and are lost on navigation. Redaction covers
#' each element's border box plus `pad`, not overflowing descendants; target
#' the overflowing element or add padding.
#' Later top-layer UI (modal dialogs and popovers) paints above redactions, so
#' targets inside an open modal or popover are rejected.
#'
#' @inheritParams pz_annotate
#' @param method `"fill"` (default) or `"blur"` (32 CSS px backdrop blur).
#' @param pad Extra CSS pixels around each element; defaults to zero.
#' @param id Optional nonempty id; reusing it replaces the old annotation.
#'   `NULL` generates a unique id, so calls accumulate annotations.
#'   `"spotlight"` and `"caption"` are reserved.
#' @param color CSS color for fill; `NULL` uses near-black (`#171717`), not
#'   the staged mark color. A near-black opaque base stays underneath even
#'   when a custom color is translucent or invalid. For blur, only `NULL` is allowed.
#' @return `ctx`, invisibly.
#' @seealso [pz_annotate()], [pz_annotate_clear()]
#' @export
pz_annotate_redact <- function(
  ctx,
  target = NULL,
  ...,
  method = c("fill", "blur"),
  pad = 0,
  id = NULL,
  color = NULL
) {
  check_context(ctx)
  check_dots_empty()
  method <- rlang::arg_match(method)
  check_annotation_id(id)
  if (!is.null(color)) {
    check_string(color)
    if (method == "blur") {
      cli::cli_abort(
        "{.arg color} is only supported with {.code method = 'fill'}."
      )
    }
  }
  pad <- check_pad(pad, arg = "pad")
  els <- annotate_elements(ctx, target)
  annotate_register_init(ctx)
  options <- list(id = id, method = method, pad = unname(pad), color = color)
  annotate_call(ctx, els, "redact", options, "redacting the elements")
  ctx_return(ctx)
}

#' Clear page annotations
#'
#' Remove an annotation by id, or remove every annotation when `id` is
#' `NULL`. During an active recording, marks play their reveal in reverse
#' before removal; paused recordings and stills clear instantly.
#'
#' @inheritParams pz_annotate
#' @param id Id to clear; `NULL` clears all. Reserved ids are allowed.
#' @return `ctx`, invisibly.
#' @export
pz_annotate_clear <- function(ctx, id = NULL, ...) {
  check_context(ctx)
  check_dots_empty()
  check_annotation_id(id, allow_reserved = TRUE)
  recording <- annotate_recording(ctx$page)
  data <- jsonlite::toJSON(
    list(id = id, animate = recording),
    auto_unbox = TRUE,
    null = "null"
  )
  duration <- pz_js(
    ctx,
    paste0(
      "(() => { return ",
      ANNOTATION_LAYER_JS,
      "?.clear(",
      data,
      ") || false; })()"
    )
  )
  # Log the caption clear at the call's video time, not after mark fades.
  if (is.null(id) || identical(id, "caption")) {
    caption_clear(ctx$page)
  }
  annotate_pump(ctx, duration)
  ctx_return(ctx)
}

annotate_elements <- function(ctx, target, frame = caller_env()) {
  scoped <- if (is.null(target)) scope_root(ctx, call = frame)
  if (!is.null(scoped)) {
    return(scoped)
  }
  els <- loc_resolve(ctx, target, multiple = "all", call = frame)
  withr::defer(release_elements(els), envir = frame)
  els
}

annotate_style <- function(
  ctx,
  color,
  font_family,
  font_size,
  call = caller_env()
) {
  stage <- page_stage(ctx$page)
  color <- color %||% stage$annotate_color
  font_family <- font_family %||% stage$annotate_font_family
  font_size <- font_size %||% stage$annotate_font_size
  check_string(color, allow_empty = FALSE, call = call)
  check_string(font_family, allow_empty = FALSE, call = call)
  check_annotation_font_size(font_size, call = call)
  list(color = color, font_family = font_family, font_size = font_size)
}

# Bubble and badge surfaces: per-call fill/text_color win, then the staged
# defaults, then the built-ins in STAGE_DEFAULTS.
annotate_fill_style <- function(
  ctx,
  fill,
  text_color,
  fill_arg = "fill",
  text_color_arg = "text_color",
  call = caller_env()
) {
  stage <- page_stage(ctx$page)
  fill <- fill %||% stage$annotate_fill
  text_color <- text_color %||% stage$annotate_text_color
  check_string(fill, allow_empty = FALSE, arg = fill_arg, call = call)
  check_string(
    text_color,
    allow_empty = FALSE,
    arg = text_color_arg,
    call = call
  )
  list(fill = fill, text_color = text_color)
}

annotate_stroke_width <- function(ctx, stroke_width, call = caller_env()) {
  stroke_width <- stroke_width %||% page_stage(ctx$page)$annotate_stroke_width
  check_positive_css_px(stroke_width, arg = "stroke_width", call = call)
  stroke_width
}

# Unset, a callout with a leader stands off far enough for the line to
# read as an arrow; a leaderless tooltip hugs its target.
annotate_distance <- function(ctx, distance, leader, call = caller_env()) {
  distance <- distance %||%
    page_stage(ctx$page)$annotate_distance %||%
    if (isFALSE(leader)) 8 else 24
  check_number_decimal(
    distance,
    min = 0,
    allow_infinite = FALSE,
    arg = "distance",
    call = call
  )
  distance
}

# Calls a layer entry point with the resolved elements as `this`, booting
# the layer first if this document doesn't have one yet.
annotate_call <- function(ctx, els, fn, options, what) {
  json <- jsonlite::toJSON(options, auto_unbox = TRUE, null = "null")
  timeout <- ctx$page$default_timeout
  res <- cdp_call(
    ctx$page$session$Runtime$callFunctionOn(
      paste0(
        "function() { return (",
        annotate_boot_js(),
        ")().pz.",
        fn,
        "(this, ",
        json,
        "); }"
      ),
      objectId = els$object_id,
      returnByValue = TRUE,
      timeout_ = timeout
    ),
    timeout,
    what
  )
  cdp_check_exception(res, what)
  annotate_pump(ctx, res$result$value)
}

annotate_pump <- function(ctx, duration) {
  if (annotate_recording(ctx$page) && is.numeric(duration) && duration > 0) {
    pump_loop(ctx$page$child_loop, duration / 1000 + 0.05)
  }
  invisible(duration)
}

annotate_recording <- function(page) {
  stage_recording(page) && !isTRUE(page_recorder(page)$paused)
}

annotate_register_init <- function(ctx) {
  page <- ctx$page
  if (!is.null(page$.__enclos_env__$private$staging_$annotate_init_id)) {
    return(invisible(NULL))
  }
  session <- page$session
  timeout <- page$default_timeout
  session$Page$enable(timeout_ = timeout)
  source <- paste0(
    "(() => { const boot = () => (",
    annotate_boot_js(),
    ")(); ",
    "if (document.documentElement) boot(); ",
    "else document.addEventListener('DOMContentLoaded', boot, {once:true}); })();"
  )
  res <- session$Page$addScriptToEvaluateOnNewDocument(
    source = source,
    timeout_ = timeout
  )
  page$.__enclos_env__$private$staging_$annotate_init_id <- res$identifier
  invisible(NULL)
}

# A document-bound runtime: the layer owns the only Map of annotations.
annotate_boot_js <- local({
  boot <- NULL
  function() {
    if (is.null(boot)) {
      path <- system.file(
        "js",
        "annotate.js",
        package = "paparazzi",
        mustWork = TRUE
      )
      source <- paste(readLines(path, warn = FALSE), collapse = "\n")
      boot <<- paste0(
        "function() {",
        OVERLAY_HOST_JS,
        "return (",
        source,
        ")(root); }"
      )
    }
    boot
  }
})

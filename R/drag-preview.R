drag_preview_create <- function(ctx, preview = TRUE) {
  page <- ctx$page
  if (
    !preview ||
      !recorder_active(page) ||
      isTRUE(page_recorder(page)$paused) ||
      !cursor_visible(page)
  ) {
    return(NULL)
  }
  state <- new.env(parent = emptyenv())
  state$owner <- ctx
  state$warned <- FALSE
  state
}

drag_preview_prepare <- function(state, els, from) {
  drag_preview_optional(state, function(ctx) {
    timeout <- ctx$page$default_timeout
    res <- cdp_call(
      ctx$page$session$Runtime$callFunctionOn(
        paste0(
          "function(point, annotationsAbsent) { return (",
          drag_preview_boot_js(),
          ") (this[0], point, annotationsAbsent).run('prepare'); }"
        ),
        objectId = els$object_id,
        arguments = list(
          list(value = as.list(from)),
          list(value = is.null(ctx$page$staging$annotate_init_id))
        ),
        awaitPromise = TRUE,
        returnByValue = TRUE,
        timeout_ = timeout
      ),
      timeout,
      "preparing the drag preview"
    )
    err <- res$exceptionDetails
    if (!is.null(err)) {
      message <- drag_preview_error_message(
        err$exception$description %||% err$text %||% "unknown error"
      )
      cli::cli_abort(
        "JavaScript error preparing the drag preview: {message}",
        class = "paparazzi_error_js"
      )
    }
    drag_preview_result(js_value(res$result))
    invisible(NULL)
  })
}

drag_preview_show <- function(state, point) {
  drag_preview_command(state, "show", as.list(point))
}

drag_preview_move <- function(state, point) {
  drag_preview_command(state, "move", as.list(point))
}

drag_preview_settle <- function(state) {
  drag_preview_command(state, "settle") %||% 0
}

drag_preview_dispose <- function(state) {
  if (is.null(state) || is.null(state$owner)) {
    return(invisible(NULL))
  }
  ctx <- state$owner
  state$owner <- NULL
  # Unwind must preserve the real input error, including when CDP has gone away.
  try(
    pz_js(ctx, paste0(DRAG_PREVIEW_CONTROLLER_JS, "?.dispose()")),
    silent = TRUE
  )
  invisible(NULL)
}

drag_preview_optional <- function(state, fn) {
  if (is.null(state) || is.null(state$owner)) {
    return(invisible(NULL))
  }
  tryCatch(
    fn(state$owner),
    error = function(e) {
      if (inherits(e, "paparazzi_error_input")) {
        stop(e)
      }
      drag_preview_dispose(state)
      if (!state$warned) {
        state$warned <- TRUE
        message <- drag_preview_error_message(conditionMessage(e))
        cli::cli_warn(
          c(
            "The optional drag preview was disabled; the drag will continue.",
            i = drag_preview_warning_reason(e),
            i = "Use {.code preview = FALSE} to turn off the preview.",
            i = "See the Drag preview section in {.help paparazzi::pz_act_drag}."
          ),
          class = "paparazzi_warning_drag_preview"
        )
      }
      invisible(NULL)
    }
  )
}

drag_preview_command <- function(state, method, arg = NULL) {
  drag_preview_optional(state, function(ctx) {
    result <- pz_js(
      ctx,
      paste0(
        "(() => { const controller = ",
        DRAG_PREVIEW_CONTROLLER_JS,
        "; if (!controller) return {failure:{message:'Drag preview controller is unavailable'}};",
        "return controller.run('",
        method,
        "',",
        if (is.null(arg)) "null" else js_literal(arg),
        "); })()"
      )
    )
    drag_preview_result(result)
  })
}

drag_preview_result <- function(result) {
  if (!is.null(result$failure)) {
    cli::cli_abort(
      "{result$failure$message}",
      class = "paparazzi_error_drag_preview",
      reason = result$failure$reason
    )
  }
  result$value
}

drag_preview_error_message <- function(message) {
  sub("(?s)\\n[[:space:]]*at .*", "", message, perl = TRUE)
}

drag_preview_warning_reason <- function(e) {
  switch(
    e$reason %||% "",
    stylesheets = paste(
      "The browser cannot read the page's stylesheets, often on {.code file://} pages.",
      "Open the page over HTTP: {.fn pz_open} serves local {.file .html} paths",
      "when {.pkg httpuv} is installed and loads; or use {.fn pz_serve_static}.",
      "Cross-origin stylesheets must also allow the browser to read their rules."
    ),
    references = paste(
      "The source contains an iframe or SVG <use> reference.",
      "Use a source without these references."
    ),
    fonts = paste(
      "The page uses unsupported CSS rule groups, imported stylesheets,",
      "or fonts without readable embedded CSS sources.",
      "Move rules out of unsupported groups or imports and embed font sources",
      "as data URLs in @font-face rules."
    ),
    redaction = paste(
      "A paparazzi redaction overlaps or is related to the source,",
      "or paparazzi cannot verify the redaction state.",
      "Keep redactions separate from the source or turn off the preview;",
      "do not remove redactions from sensitive content for a preview."
    ),
    geometry = paste(
      "The source geometry or content cannot be captured safely.",
      "Use a source without transforms, filters, clipping, overflowing content,",
      "shadow DOM, or generated content."
    ),
    "{message}"
  )
}

DRAG_PREVIEW_CONTROLLER_JS <- paste0(
  "document.getElementById('",
  OVERLAY_HOST_ID,
  "')?.shadowRoot?.querySelector('.pz-drag-preview')?.pz"
)

drag_preview_boot_js <- function() {
  asset <- function(path) {
    paste(
      readLines(
        system.file(path, package = "paparazzi", mustWork = TRUE),
        warn = FALSE
      ),
      collapse = "\n"
    )
  }
  vendor <- system.file(
    "js/vendor/html-to-image",
    package = "paparazzi",
    mustWork = TRUE
  )
  bundle <- list.files(
    vendor,
    pattern = "^html-to-image-.+\\.umd\\.js$",
    full.names = TRUE
  )
  if (length(bundle) != 1L) {
    cli::cli_abort("Expected exactly one vendored html-to-image UMD asset.")
  }
  paste0(
    "function(element, point, annotationsAbsent) {",
    OVERLAY_HOST_JS,
    "const exports = {}; const module = {exports};",
    paste(readLines(bundle, warn = FALSE), collapse = "\n"),
    "\nreturn (",
    asset("js/drag-preview.js"),
    ")(root, exports, element, point, annotationsAbsent); }"
  )
}

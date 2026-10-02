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
          ") (this[0], point, annotationsAbsent).prepare(); }"
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
    cdp_check_exception(res, "preparing the drag preview")
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
        cli::cli_warn(
          c(
            "The optional drag preview was disabled; the drag will continue.",
            i = "{conditionMessage(e)}"
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
    pz_js(
      ctx,
      paste0(
        "(() => { const controller = ",
        DRAG_PREVIEW_CONTROLLER_JS,
        "; if (!controller) throw new Error('Drag preview controller is unavailable');",
        "return controller.",
        method,
        "(",
        if (is.null(arg)) "" else js_literal(arg),
        "); })()"
      )
    )
  })
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

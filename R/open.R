#' Open a page
#'
#' Opens a URL, local file, or existing [chromote::ChromoteSession] as a
#' paparazzi page: the root context that starts every `|>` chain.
#'
#' @param x What to open:
#'   * a URL string (any scheme, including `file://`, `about:`, `data:`);
#'   * a path to an existing local file (opened as `file://`);
#'   * an existing `ChromoteSession` (wrapped as-is; nothing is navigated).
#'
#'   Shiny app directories and `pz_app()` handles are not yet supported;
#'   Shiny app **objects** are never supported -- run the app in another
#'   process and pass its URL.
#' @param ... Checked empty for now. Will be forwarded to `pz_device()` for
#'   device emulation (e.g. `width = 390, mobile = TRUE`).
#' @param wait What to wait for before returning. `"auto"` currently resolves
#'   to `"load"`; `"shiny"` arrives with the Shiny-integration task.
#' @param timeout Session default timeout in seconds; `NULL` uses the package
#'   default (10 s). Per-call `timeout = NULL` means "session default".
#' @param shiny_options,envvars Reserved for Shiny app support.
#' @return A `PaparazziPage` (the root context).
#' @export
pz_open <- function(
  x,
  ...,
  wait = c("auto", "load", "shiny", "none"),
  timeout = NULL,
  shiny_options = list(),
  envvars = NULL
) {
  rlang::check_dots_empty()
  if (!is.null(timeout)) {
    rlang::check_number_decimal(timeout, min = 0)
  }
  wait <- rlang::arg_match(wait)
  if (identical(wait, "shiny")) {
    rlang::abort(
      '`wait = "shiny"` is not supported yet; use `wait = "load"` for now.',
      class = "paparazzi_error_unsupported"
    )
  }
  if (identical(wait, "auto")) {
    wait <- "load"
  }
  if (!is.list(shiny_options)) {
    rlang::abort(
      "`shiny_options` must be a list.",
      class = "paparazzi_error_input"
    )
  }
  if (!is.null(envvars) && !is.character(envvars)) {
    rlang::abort(
      "`envvars` must be a character vector or `NULL`.",
      class = "paparazzi_error_input"
    )
  }

  if (inherits(x, "ChromoteSession")) {
    return(PaparazziPage$new(session = x, timeout = timeout %||% 10))
  }

  url <- open_target_url(x)
  session <- chromote::ChromoteSession$new()
  page <- PaparazziPage$new(session = session, timeout = timeout %||% 10)

  # If navigation or the load wait fails, don't leak the browser.
  ok <- FALSE
  on.exit(if (!ok) try(page$close(), silent = TRUE), add = TRUE)

  session$Page$navigate(url)
  if (identical(wait, "load")) {
    wait_for_load(page, timeout = page$default_timeout)
  }

  ok <- TRUE
  page
}

#' Resolve `x` to a URL, or error for unsupported/unknown inputs
#' @noRd
open_target_url <- function(x, call = rlang::caller_env()) {
  if (inherits(x, "shiny.appobj")) {
    rlang::abort(
      c(
        "Shiny app objects can't be opened directly.",
        i = "Run the app in another process (e.g. `shiny::runApp()`) and pass its URL to `pz_open()`."
      ),
      class = "paparazzi_error_unsupported",
      call = call
    )
  }
  if (!rlang::is_string(x)) {
    rlang::abort(
      sprintf(
        "`x` must be a URL, a path to a local file, or a ChromoteSession; not %s.",
        obj_type_friendly(x)
      ),
      class = "paparazzi_error_input",
      call = call
    )
  }
  if (grepl("^[a-zA-Z][a-zA-Z0-9+.-]*:", x)) {
    return(x)
  }
  if (file.exists(x)) {
    if (dir.exists(x) || grepl("[/\\\\]?app\\.[rR]$", x)) {
      rlang::abort(
        c(
          "Opening Shiny app directories is not supported yet.",
          i = "Start the app yourself in another process and pass its URL to `pz_open()`."
        ),
        class = "paparazzi_error_unsupported",
        call = call
      )
    }
    return(paste0("file://", normalizePath(x)))
  }
  rlang::abort(
    c(
      sprintf("`x` is neither a URL nor an existing file: %s", x),
      i = "URLs need a scheme, e.g. \"https://example.com\"."
    ),
    class = "paparazzi_error_input",
    call = call
  )
}

#' Poll until the page finishes loading
#' @noRd
wait_for_load <- function(page, timeout) {
  pz_poll(
    fn = function() {
      isTRUE(tryCatch(
        pz_js(page, "document.readyState === 'complete'"),
        error = function(e) FALSE
      ))
    },
    timeout = timeout,
    loop = page$child_loop,
    what = "page load"
  )
  invisible(page)
}

#' Close a page
#'
#' Closes the page's browser session. Idempotent; closing an already-closed
#' page is a no-op.
#'
#' @param page A `PaparazziPage` from [pz_open()].
#' @return `page`, invisibly.
#' @export
pz_close <- function(page) {
  if (!inherits(page, "PaparazziPage")) {
    rlang::abort(
      "`page` must be a page from `pz_open()`.",
      class = "paparazzi_error_input"
    )
  }
  page$close()
  invisible(page)
}

#' Open a page that closes when a block or calling frame exits
#'
#' `pz_with_page()` evaluates `code` with the page open and closes it on exit,
#' including on error. `pz_local_page()` opens a page and closes it when the
#' calling frame (e.g. a test) exits, via [withr::defer()]. Both accept an
#' already-open page or anything [pz_open()] accepts, and always close on
#' exit: the block owns the resource.
#'
#' @param x An open page, or anything [pz_open()] accepts.
#' @param code Code to run while the page is open. An expression (evaluated
#'   as-is; useful when `x` is an already-open page the code can reference)
#'   or a function, called with the page as its only argument.
#' @param ... Passed to [pz_open()] when `x` is not already a page.
#' @param .env The frame whose exit closes the page.
#' @return `pz_with_page()` returns the page invisibly; `pz_local_page()`
#'   returns it visibly.
#' @export
pz_with_page <- function(x, code, ...) {
  page <- if (inherits(x, "PaparazziPage")) x else pz_open(x, ...)
  on.exit(pz_close(page), add = TRUE)
  if (rlang::is_function(code)) {
    code(page)
  } else {
    force(code)
  }
  invisible(page)
}

#' @rdname pz_with_page
#' @export
pz_local_page <- function(x, ..., .env = rlang::caller_env()) {
  page <- if (inherits(x, "PaparazziPage")) x else pz_open(x, ...)
  withr::defer(pz_close(page), envir = .env)
  page
}

`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}

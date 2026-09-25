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
#'   Shiny app directories and app files (`app.R`, `ui.R`, `server.R`,
#'   `app-*.R`, ...) and `pz_app()` handles are not yet supported; Shiny app
#'   **objects** are never supported -- run the app in another process and
#'   pass its URL.
#' @param ... Forwarded to [pz_device()] as device settings (e.g.
#'   `width = 390, mobile = TRUE`); they must be named.
#' @param wait What to wait for before returning. `"auto"` currently resolves
#'   to `"load"`; `"shiny"` arrives with the Shiny-integration task.
#' @param timeout Session default timeout in seconds; `NULL` uses the package
#'   default (10 s). Per-call `timeout = NULL` means "session default".
#' @param shiny_options,envvars Reserved for Shiny app support.
#'
#' @return A `PaparazziPage` (the root context).
#'
#' @export
pz_open <- function(
  x,
  ...,
  wait = c("auto", "load", "shiny", "none"),
  timeout = NULL,
  shiny_options = list(),
  envvars = NULL
) {
  device_dots <- device_check_dots(list2(...))
  check_number_decimal(timeout, min = 0, allow_null = TRUE)
  wait <- arg_match(wait)
  if (identical(wait, "shiny")) {
    cli::cli_abort(
      '{.code wait = "shiny"} is not supported yet; use {.code wait = "load"} for now.',
      class = "paparazzi_error_unsupported"
    )
  }
  if (identical(wait, "auto")) {
    wait <- "load"
  }
  if (!is.list(shiny_options)) {
    stop_input_type(shiny_options, "a list")
  }
  if (!is.null(envvars) && !is.character(envvars)) {
    stop_input_type(envvars, "a character vector")
  }

  if (inherits(x, "ChromoteSession")) {
    page <- PaparazziPage$new(session = x, timeout = timeout %||% 10)
    # Device settings apply before anything else touches the page.
    device_open(page, device_dots)
    return(page)
  }

  url <- open_target_url(x)
  session <- chromote::ChromoteSession$new()
  page <- PaparazziPage$new(session = session, timeout = timeout %||% 10)
  # Applied before navigating, so media queries and layout are right at
  # first render.
  device_open(page, device_dots)

  # If navigation or the load wait fails, don't leak the browser.
  ok <- FALSE
  withr::defer(if (!ok) try(page$close(), silent = TRUE))

  # CDP reports navigation failures as `errorText`, not as errors.
  nav <- session$Page$navigate(url)
  if (!is.null(nav$errorText) && nzchar(nav$errorText)) {
    cli::cli_abort(
      "Navigation to {.url {url}} failed: {nav$errorText}",
      class = "paparazzi_error_navigation"
    )
  }
  if (identical(wait, "load")) {
    wait_for_load(page, timeout = page$default_timeout)
  }

  ok <- TRUE
  page
}
#' Close a page
#'
#' Closes the page's browser session. Idempotent; closing an already-closed
#' page is a no-op.
#'
#' @param page A `PaparazziPage` from [pz_open()].
#'
#' @return `page`, invisibly.
#'
#' @export
pz_close <- function(page) {
  check_page(page)
  page$close()
  invisible(page)
}
#' Open a page that closes when a block or calling frame exits
#'
#' [pz_with_page()] evaluates `code` with the page open and closes it on exit,
#' including on error. [pz_local_page()] opens a page and closes it when the
#' calling frame (e.g. a test) exits, via [withr::defer()]. Both accept an
#' already-open page or anything [pz_open()] accepts, and always close on
#' exit: the block owns the resource.
#'
#' @param x An open page, or anything [pz_open()] accepts.
#' @param code Code to run while the page is open. An expression (evaluated
#'   as-is; useful when `x` is an already-open page the code can reference)
#'   or a function, called with the page as its only argument. A braced
#'   `{ }` block is always treated as an expression, even if it returns a
#'   function.
#' @param ... Passed to [pz_open()] when `x` is not already a page.
#' @param .env The frame whose exit closes the page.
#'
#' @return [pz_with_page()] returns the page invisibly; [pz_local_page()]
#'   returns it visibly.
#'
#' @export
pz_with_page <- function(x, code, ...) {
  page <- if (is_pz_page(x)) x else pz_open(x, ...)
  withr::defer(pz_close(page))
  # Decide expression-vs-function from the quoted form: a braced block is
  # always an expression, even when its value happens to be a function.
  expr <- substitute(code)
  value <- eval(expr, envir = parent.frame())
  is_block <- is.call(expr) && identical(expr[[1]], quote(`{`))
  if (!is_block && is_function(value)) {
    value <- value(page)
  }
  invisible(page)
}
#' @rdname pz_with_page
#' @export
pz_local_page <- function(x, ..., .env = caller_env()) {
  page <- if (is_pz_page(x)) x else pz_open(x, ...)
  withr::defer(pz_close(page), envir = .env)
  page
}
open_target_url <- function(x, call = caller_env()) {
  if (inherits(x, "shiny.appobj")) {
    cli::cli_abort(
      c(
        "Shiny app objects can't be opened directly.",
        i = "Run the app in another process (e.g. {.fn shiny::runApp}) and pass its URL to {.fn pz_open}."
      ),
      class = "paparazzi_error_unsupported",
      call = call
    )
  }
  if (!is_string(x)) {
    cli::cli_abort(
      "{.arg x} must be a URL, a path to a local file, or a ChromoteSession; not {.obj_type_friendly {x}}.",
      class = "paparazzi_error_input",
      call = call
    )
  }
  # file.exists() comes before the scheme regex: Windows drive paths like
  # "C:/..." look like a URL scheme to it.
  if (file.exists(x)) {
    if (dir.exists(x) || is_shiny_app_file(basename(x))) {
      cli::cli_abort(
        c(
          "Opening Shiny apps is not supported yet.",
          i = "Start the app yourself in another process and pass its URL to {.fn pz_open}."
        ),
        class = "paparazzi_error_unsupported",
        call = call
      )
    }
    return(file_url(x))
  }
  # Real schemes have 2+ characters; single-letter "schemes" are drive letters.
  if (grepl("^[a-zA-Z][a-zA-Z0-9+.-]+:", x)) {
    return(x)
  }
  cli::cli_abort(
    c(
      "{.arg x} is neither a URL nor an existing file: {.val {x}}",
      i = "URLs need a scheme, e.g. \"https://example.com\"."
    ),
    class = "paparazzi_error_input",
    call = call
  )
}
# Conventional Shiny app file names: app.R/ui.R/server.R, and the variants
# Shiny's editor tooling recognizes: app-*.R/app_*.R and *-app.R/*_app.R.
is_shiny_app_file <- function(name) {
  if (name %in% c("app.R", "app.r", "ui.R", "server.R")) {
    return(TRUE)
  }

  grepl("^(app[_-].+|.+[_-]app)[.]R$", name)
}
file_url <- function(path) {
  path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  segs <- strsplit(path, "/", fixed = TRUE)[[1]]
  enc <- vapply(
    segs,
    function(seg) {
      # Leave Windows drive letters ("C:") alone; encode everything else.
      if (grepl("^[A-Za-z]:$", seg)) {
        seg
      } else {
        utils::URLencode(seg, reserved = TRUE, repeated = TRUE)
      }
    },
    character(1)
  )
  path <- paste(enc, collapse = "/")
  if (!startsWith(path, "/")) {
    path <- paste0("/", path)
  }
  paste0("file://", path)
}
wait_for_load <- function(page, timeout, call = caller_env()) {
  deadline <- Sys.time() + timeout
  pz_poll(
    fn = function() {
      # Give each readyState check only the remaining budget, so a stalled
      # renderer can't stretch the load wait beyond its own timeout.
      remaining <- as.numeric(difftime(deadline, Sys.time(), units = "secs"))
      isTRUE(tryCatch(
        pz_js(
          page,
          "document.readyState === 'complete'",
          timeout = max(remaining, 0.1)
        ),
        error = function(e) FALSE
      ))
    },
    timeout = timeout,
    loop = page$child_loop,
    what = "page load",
    call = call
  )
  invisible(page)
}

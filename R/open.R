#' Open a page
#'
#' Opens a URL, local file, Shiny app, or existing
#' [chromote::ChromoteSession] as a paparazzi page: the root context that
#' starts every `|>` chain.
#'
#' @param x What to open:
#'   * a URL string (any scheme, including `file://`, `about:`, `data:`);
#'   * a path to an existing local file (opened as `file://`);
#'   * a Shiny app directory (including split `ui.R`/`server.R` apps) or
#'     runnable app file (`app.R`, `app-*.R`, `*_app.R`, etc.), started by
#'     this page and stopped when it closes;
#'   * a [pz_app()] handle, shared across pages (closing the page leaves
#'     the app running); `ui.R` and `server.R` passed alone open as files;
#'   * an existing `ChromoteSession` (wrapped as-is; nothing is navigated).
#'
#'   Shiny app **objects** are not supported -- run the app in another
#'   process and pass its URL.
#' @param ... Forwarded to [pz_device()] as device settings (e.g.
#'   `width = 390, mobile = TRUE`); they must be named.
#' @param wait What to wait for before returning. `"auto"` waits for Shiny
#'   idle on app paths and handles, and for load on other pages. `"shiny"`
#'   explicitly waits for Shiny to connect and become idle; non-Shiny pages
#'   error.
#' @param timeout Session default timeout in seconds; `NULL` uses the package
#'   default (10 s). Per-call `timeout = NULL` means "session default".
#' @param shiny_options,envvars Passed to [pz_app()] when opening an app path.
#'
#' @return A `PaparazziPage` (the root context).
#'
#' @examplesIf rlang::is_interactive() && !is.null(suppressMessages(chromote::find_chrome()))
#' # A local HTML file opens as a file:// URL
#' page <- pz_open(pz_example("tasks"))
#' pz_get_url(page)
#' pz_close(page)
#'
#' # Named arguments in `...` set up the device before the page loads
#' phone <- pz_open(pz_example("tasks"), width = 390, height = 844, mobile = TRUE)
#' pz_js(phone, "window.innerWidth")
#' pz_close(phone)
#'
#' @examplesIf rlang::is_interactive() && !is.null(suppressMessages(chromote::find_chrome())) && rlang::is_installed("shiny")
#' # An app directory runs in a background R process that the page owns.
#' # pz_open() returns once Shiny has connected and gone idle.
#' page <- pz_open(pz_example("tasks-app"))
#' pz_get_text(page, target = "#summary")
#' pz_close(page) # also stops the app
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
    if (identical(wait, "shiny")) {
      pz_wait_for_shiny_idle(page, timeout = page$default_timeout)
    }
    return(page)
  }

  owned_app <- NULL
  shared_app <- if (inherits(x, "PaparazziApp")) x else NULL
  is_app <- inherits(x, "PaparazziApp") ||
    (is_string(x) && file.exists(x) &&
      (dir.exists(x) || is_shiny_app_file(basename(x))))
  if (inherits(x, "PaparazziApp")) {
    url <- x$url
  } else if (is_app) {
    owned_app <- pz_app(x, shiny_options = shiny_options, envvars = envvars, timeout = timeout)
    withr::defer(if (!is.null(owned_app)) owned_app$stop())
    url <- owned_app$url
  } else {
    url <- open_target_url(x)
  }
  wait <- open_wait_mode(wait, is_app)
  session <- chromote::ChromoteSession$new()
  page <- PaparazziPage$new(
    session = session, timeout = timeout %||% 10,
    owned_app = owned_app, shared_app = shared_app
  )
  owned_app <- NULL
  # If device settings, navigation, or the load wait fail, don't leak
  # the browser this call just created. The wrap branch above must not
  # register this: the caller owns that session.
  ok <- FALSE
  withr::defer(if (!ok) try(page$close(), silent = TRUE))

  # Applied before navigating, so media queries and layout are right at
  # first render.
  device_open(page, device_dots)

  navigated <- if (identical(wait, "shiny")) {
    session$Page$frameNavigated(wait_ = FALSE)
  } else if (identical(wait, "load")) {
    resolve_navigated <- NULL
    event <- promises::promise(function(resolve, reject) {
      resolve_navigated <<- resolve
    })
    cancel_navigated <- session$Page$frameNavigated(callback_ = resolve_navigated)
    # A same-document navigation emits no frameNavigated event; unlike the
    # event promise, a callback can be removed before the session closes.
    withr::defer(cancel_navigated())
    event
  }
  # CDP reports navigation failures as `errorText`, not as errors.
  nav <- session$Page$navigate(url)
  if (!is.null(nav$errorText) && nzchar(nav$errorText)) {
    cli::cli_abort(
      "Navigation to {.url {url}} failed: {nav$errorText}",
      class = "paparazzi_error_navigation"
    )
  }
  if (wait %in% c("load", "shiny") && !is.null(nav$loaderId)) {
    nav_await(page, navigated, what = "page navigation")
  }
  if (identical(wait, "load")) {
    wait_for_load(page, timeout = page$default_timeout)
    device_css_reapply(page)
  } else if (identical(wait, "shiny")) {
    pz_wait_for_shiny_idle(page, timeout = page$default_timeout)
    device_css_reapply(page)
  }

  ok <- TRUE
  page
}
open_wait_mode <- function(wait, is_shiny_app) {
  if (!identical(wait, "auto")) {
    return(wait)
  }
  if (is_shiny_app) {
    return("shiny")
  }
  "load"
}
#' Close a page
#'
#' Closes the page's browser session and, if the page started a Shiny app,
#' stops that app. A page opened from a shared [pz_app()] handle leaves the
#' app running. Idempotent; closing an already-closed page is a no-op.
#'
#' @param page A `PaparazziPage` from [pz_open()].
#'
#' @return `page`, invisibly.
#'
#' @examplesIf rlang::is_interactive() && !is.null(suppressMessages(chromote::find_chrome()))
#' page <- pz_open(pz_example("tasks"))
#' pz_close(page)
#'
#' # Closing a closed page does nothing
#' pz_close(page)
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
#' @examplesIf rlang::is_interactive() && !is.null(suppressMessages(chromote::find_chrome()))
#' path <- file.path(tempdir(), "task-list.png")
#'
#' # The page closes when the function returns, even if it errors
#' pz_with_page(pz_example("tasks"), function(page) {
#'   pz_screenshot(page, path, target = ".task-list")
#' })
#' file.exists(path)
#'
#' # pz_local_page() ties the page to the calling function, e.g. a test
#' count_tasks <- function() {
#'   page <- pz_local_page(pz_example("tasks"))
#'   pz_get_count(page, target = ".task")
#' }
#' count_tasks()
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
# Standalone app files: app.R and the runnable app-*.R/app_*.R and
# *-app.R/*_app.R variants. ui.R/server.R require their containing directory.
is_shiny_app_file <- function(name) {
  if (name %in% c("app.R", "app.r")) {
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

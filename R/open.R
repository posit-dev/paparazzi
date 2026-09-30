#' Open a page
#'
#' Opens a URL, local file, local server, or existing
#' [chromote::ChromoteSession] as a paparazzi page: the root context that
#' starts every `|>` chain.
#'
#' @param x What to open:
#'   * a URL string (any scheme, including `file://`, `about:`, `data:`);
#'   * a Shiny app directory or runnable app file (`app.R`, `app-*.R`,
#'     `*_app.R`, etc.);
#'   * a `.qmd` or `.Rmd` file, or a Quarto project directory;
#'   * a static directory or `.html` file;
#'   * another existing local file (opened as `file://`);
#'   * a handle from [pz_serve_shiny()], [pz_serve_quarto()], or
#'     [pz_serve_static()], shared across pages;
#'   * an existing `ChromoteSession` (wrapped as-is; nothing is navigated).
#'
#'   Path detection checks Shiny first (directories containing `app.R` or
#'   `server.R`, or named app files), then Quarto (`.qmd`, `.Rmd`, or a
#'   directory containing `_quarto.yml`), then static directories and HTML
#'   files. `ui.R` and `server.R` passed alone open as files.
#'   A path starts a one-off server using the backend defaults; closing the
#'   page stops it. Closing a page opened from a handle leaves its server
#'   running. Shiny app **objects** are not supported; supply an app path
#'   or a running app's URL instead.
#' @param ... Forwarded to [pz_device()] as device settings (e.g.
#'   `width = 390, mobile = TRUE`); they must be named.
#' @param wait What to wait for before returning. `"auto"` (the default)
#'   waits for Shiny idle on app paths and handles, and for load on other
#'   pages. `"load"` waits for the page to load. `"shiny"` explicitly waits
#'   for Shiny to connect and become idle; non-Shiny pages error. `"none"`
#'   returns without waiting. An existing `ChromoteSession` isn't
#'   navigated, so only `"shiny"` waits there.
#' @param timeout Session default timeout in seconds; defaults to 10.
#'   Per-call `timeout = NULL` in waits and expectations uses this default.
#' @param shiny_options,envvars Passed to [pz_serve_shiny()] when opening an app path.
#'   `envvars = NULL` adds no process environment overrides.
#'
#' @return A `PaparazziPage` (the root context).
#'
#' @section Browser:
#' `pz_open()` opens pages in chromote's default browser
#' ([chromote::default_chromote_object()]) and starts it if none is running.
#' A browser paparazzi starts keeps its profile in [tempdir()], so the
#' profile is removed when R exits, unless a `--user-data-dir` is already set
#' with [chromote::set_chrome_args()]. A default set with
#' [chromote::set_default_chromote_object()] is used as-is.
#'
#' @examplesIf paparazzi:::examples_run()
#' # A local HTML file is served over HTTP
#' page <- pz_open(pz_example("tasks"))
#' pz_get_url(page)
#' pz_close(page)
#'
#' # Named arguments in `...` set up the device before the page loads
#' phone <- pz_open(pz_example("tasks"), width = 390, height = 844, mobile = TRUE)
#' pz_js(phone, "window.innerWidth")
#' pz_close(phone)
#'
#' @examplesIf paparazzi:::examples_run("shiny")
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
  timeout = 10,
  shiny_options = list(),
  envvars = NULL
) {
  device_dots <- device_check_dots(list2(...))
  check_number_decimal(timeout, min = 0)
  wait <- arg_match(wait)
  if (!is.list(shiny_options)) {
    stop_input_type(shiny_options, "a list")
  }
  if (!is.null(envvars) && !is.character(envvars)) {
    stop_input_type(envvars, "a character vector")
  }

  if (inherits(x, "ChromoteSession")) {
    page <- PaparazziPage$new(session = x, timeout = timeout)
    # Device settings apply before anything else touches the page.
    device_open(page, device_dots)
    if (identical(wait, "shiny")) {
      pz_wait_for_shiny_idle(page, timeout = page$default_timeout)
    }
    return(page)
  }

  owned_app <- NULL
  shared_app <- if (inherits(x, "PaparazziServe")) x else NULL
  kind <- if (inherits(x, "PaparazziServe")) x$backend else serve_kind(x)
  is_app <- identical(kind, "shiny")
  if (inherits(x, "PaparazziServe")) {
    url <- x$url
  } else if (!is.null(kind)) {
    owned_app <- serve_open(x, kind, shiny_options, envvars, timeout)
    withr::defer(if (!is.null(owned_app)) owned_app$stop())
    url <- owned_app$url
  } else {
    url <- open_target_url(x)
  }
  wait <- open_wait_mode(wait, is_app)
  open_default_browser()
  session <- chromote::ChromoteSession$new()
  page <- PaparazziPage$new(
    session = session,
    timeout = timeout,
    owned_app = owned_app,
    shared_app = shared_app
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
    cancel_navigated <- session$Page$frameNavigated(
      callback_ = resolve_navigated
    )
    # A same-document navigation emits no frameNavigated event; unlike the
    # event promise, a callback can be removed before the session closes.
    withr::defer(cancel_navigated())
    event
  }
  nav <- session$Page$navigate(url)
  nav_check_response(nav, url)
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

#' Close a page
#'
#' Closes the page's browser session and any server it started. A page
#' opened from a shared serving handle leaves the server running.
#' Closing an already-closed page is a no-op.
#'
#' @param page A `PaparazziPage` from [pz_open()], or any context on it
#'   (such as the end of a chain). A chain from [pz_record_start()] whose
#'   recording is still running stops and writes it first.
#'
#' @return The page, invisibly.
#'
#' @examplesIf paparazzi:::examples_run()
#' page <- pz_open(pz_example("tasks"))
#' pz_close(page)
#'
#' # Closing a closed page does nothing
#' pz_close(page)
#'
#' @export
pz_close <- function(page) {
  if (inherits(page, "PaparazziContext")) {
    recording <- ctx_recording(page)
    ctx <- page
    page <- page$page
    if (recording) {
      on.exit(page$close(), add = TRUE)
      pz_record_stop(ctx)
    }
  }
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
#' @examplesIf paparazzi:::examples_run()
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

# Chrome deletes its default headless profile (a scoped_dir* under the user's
# Chrome-headless directory) only on a graceful Browser.close, so a browser
# that exits any other way leaks it. A profile under tempdir() goes away with
# the R session. Checked on every open because chromote's
# default_chromote_object() would silently replace a dead default without
# the profile. Remove once chromote passes its own --user-data-dir
# (rstudio/chromote#239).
open_default_browser <- function() {
  if (chromote::has_default_chromote_object()) {
    return(invisible())
  }
  # Explicit args, not set_chrome_args(): a global --user-data-dir would be
  # reused by any later Chromote$new(), and Chrome allows one browser per
  # profile.
  args <- chromote::get_chrome_args()
  if (!any(startsWith(args, "--user-data-dir"))) {
    profile <- tempfile("chrome-profile-")
    args <- c(args, paste0("--user-data-dir=", profile))
  }
  browser <- chromote::Chromote$new(browser = chromote::Chrome$new(args = args))
  chromote::set_default_chromote_object(browser)
  invisible()
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

open_target_url <- function(x, call = caller_env()) {
  if (inherits(x, "shiny.appobj")) {
    cli::cli_abort(
      c(
        "Shiny app objects can't be opened directly.",
        i = "Use {.fn pz_serve_shiny} with an app directory or R file, or pass a running app's URL to {.fn pz_open}."
      ),
      class = "paparazzi_error_unsupported",
      call = call
    )
  }
  if (!is_string(x)) {
    cli::cli_abort(
      "{.arg x} must be a URL, a supported local path, a serving handle, or a ChromoteSession; not {.obj_type_friendly {x}}.",
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
  enc <- map_chr(
    segs,
    function(seg) {
      # Leave Windows drive letters ("C:") alone; encode everything else.
      if (grepl("^[A-Za-z]:$", seg)) {
        seg
      } else {
        utils::URLencode(seg, reserved = TRUE, repeated = TRUE)
      }
    }
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

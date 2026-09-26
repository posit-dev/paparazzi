#' Navigate the page
#'
#' @description
#' `pz_nav_goto()` navigates to `url`; `pz_nav_reload()` reloads the page;
#' `pz_nav_back()`/`pz_nav_forward()` step through the history.
#'
#' Every navigation resets the scope to the root: the returned context has
#' an empty scope stack, and the pinned scope objects are released, so a
#' context scoped **before** the navigation raises a detach error if used
#' afterwards -- re-scope with [pz_find()] on the returned root context.
#' Session-level state (timeout, staging, and recording) is
#' untouched.
#'
#' @inheritParams pz_click
#' @param url The URL to navigate to (any scheme, including `file://`).
#' @param wait What to wait for before returning: `"load"` waits for the
#'   document to finish loading; `"shiny"` also waits for Shiny idle.
#'   `"auto"` (the default) uses `"shiny"` when the page was opened on an
#'   app handle or app path and lands on that app's origin, `"load"`
#'   otherwise. `"none"` returns without settling. [pz_nav_back()] and
#'   [pz_nav_forward()] take no `wait`: they wait for load only, and return
#'   at once at a history boundary, where nothing navigates. A Shiny page
#'   restored from the back/forward cache may not reconnect, so they don't
#'   wait for Shiny; call [pz_wait_for_shiny_idle()] if you need it.
#'
#' @return The root context, invisibly.
#'
#' @seealso [pz_find_reset()] for scope-only resets (no navigation).
#'
#' @examplesIf rlang::is_interactive() && !is.null(suppressMessages(chromote::find_chrome()))
#' page <- pz_open(pz_example("tasks"))
#' url <- pz_get_url(page)
#'
#' # The filter links change the URL fragment, so each filter is a history entry
#' page |> pz_nav_goto(paste0(url, "#done"))
#' pz_get_count(page, target = ".task:not(.hidden)")
#'
#' page |> pz_nav_back()
#' pz_get_count(page, target = ".task:not(.hidden)")
#'
#' page |> pz_nav_forward()
#' pz_get_url(page)
#'
#' # Reloading keeps the URL, fragment included
#' page |> pz_nav_reload()
#' pz_get_url(page)
#' pz_close(page)
#'
#' @export
pz_nav_goto <- function(
  ctx,
  url,
  ...,
  wait = c("auto", "load", "shiny", "none")
) {
  check_context(ctx)
  check_dots_empty()
  check_string(url)
  wait <- arg_match(wait)
  root <- wait_nav_reset(ctx)

  page <- ctx$page
  navigated <- if (!identical(wait, "none")) {
    # A cross-document navigation can return from Page.navigate while
    # the outgoing document still reports readyState "complete", so
    # the readyState wait alone would settle on the old page before
    # the destination commits. frameNavigated fires at the commit --
    # the reload path relies on the same event -- so the next
    # occurrence is registered before the trigger and synchronized
    # before the readyState wait.
    page$session$Page$frameNavigated(wait_ = FALSE)
  }
  nav <- page$session$Page$navigate(url, timeout_ = page$default_timeout)
  # CDP reports navigation failures as `errorText`, not as errors.
  if (!is.null(nav$errorText) && nzchar(nav$errorText)) {
    cli::cli_abort(
      "Navigation to {.url {url}} failed: {nav$errorText}",
      class = "paparazzi_error_navigation"
    )
  }
  if (!identical(wait, "none")) {
    # A same-document navigation (a URL fragment) never fires
    # frameNavigated, but its navigate response also carries no
    # loaderId while a cross-document one does -- so the anchor is
    # skipped there: the document never changed and is already
    # complete, and the readyState wait settling instantly is
    # correct. A download aborts the navigation the same way.
    if (!is.null(nav$loaderId)) {
      nav_await(page, navigated, what = "page navigation")
    }
    wait_for_load(page, timeout = page$default_timeout)
    # The settle point for the css zoom: the injected script covers only
    # commits made while the Page domain stayed enabled.
    device_css_reapply(page)
    nav_settle_shiny(page, wait, page$default_timeout)
  }
  invisible(root)
}

#' @rdname pz_nav_goto
#'
#' @export
pz_nav_reload <- function(ctx, ..., wait = c("auto", "load", "shiny", "none")) {
  check_context(ctx)
  check_dots_empty()
  wait <- arg_match(wait)
  root <- wait_nav_reset(ctx)

  page <- ctx$page
  if (!identical(wait, "none")) {
    # A reload leaves the history index where it was, so the index
    # anchor used by back/forward can't settle this one. frameNavigated
    # fires on reloads, full navigations, and bfcache restores alike
    # (loadEventFired skips bfcache restores), so the next occurrence
    # is registered before the trigger and synchronized before the
    # readyState wait: the outgoing document still reports readyState
    # "complete" while the reload is in flight.
    navigated <- page$session$Page$frameNavigated(wait_ = FALSE)
    page$session$Page$reload(timeout_ = page$default_timeout)
    nav_await(page, navigated, what = "page reload")
    wait_for_load(page, timeout = page$default_timeout)
    device_css_reapply(page)
    nav_settle_shiny(page, wait, page$default_timeout)
  } else {
    page$session$Page$reload(timeout_ = page$default_timeout)
  }
  invisible(root)
}

#' @rdname pz_nav_goto
#'
#' @export
pz_nav_back <- function(ctx, ...) {
  check_context(ctx)
  check_dots_empty()
  root <- wait_nav_reset(ctx)

  if (nav_history(ctx$page, -1)) {
    wait_for_load(ctx$page, timeout = ctx$page$default_timeout)
  }
  # Runs at the history boundary too: the cache was cleared in
  # wait_nav_reset(), and re-setting the same zoom is harmless.
  device_css_reapply(ctx$page)
  invisible(root)
}

#' @rdname pz_nav_goto
#'
#' @export
pz_nav_forward <- function(ctx, ...) {
  check_context(ctx)
  check_dots_empty()
  root <- wait_nav_reset(ctx)

  if (nav_history(ctx$page, 1)) {
    wait_for_load(ctx$page, timeout = ctx$page$default_timeout)
  }
  device_css_reapply(ctx$page)
  invisible(root)
}

# Called after the navigation's existing load settle, on the landed document.
nav_settle_shiny <- function(page, wait, timeout) {
  if (identical(wait, "auto")) {
    private <- page$.__enclos_env__$private
    app <- private$owned_app_ %||% private$shared_app_
    if (is.null(app)) {
      return(invisible(page))
    }
    # pz_app() URLs are root URLs ending in a slash.
    app_origin <- sub("/$", "", app$url)
    if (
      !identical(pz_js(page, "location.origin", timeout = timeout), app_origin)
    ) {
      return(invisible(page))
    }
  }
  if (!identical(wait, "load")) {
    pz_wait_for_shiny_idle(page, timeout = timeout)
  }
  invisible(page)
}

# Step `offset` entries in the history (back: -1, forward: +1). CDP's
# currentIndex is 0-based while R's entries list is 1-based, so the
# current entry's R index is currentIndex + 1 and the target's is
# currentIndex + offset + 1. A boundary step reaches no entry and
# returns FALSE (the page stays put; no error). Back also stops at the
# about:blank entry the browser creates with every new session -- it is
# not part of the user's history, and forward can still reach any entry
# a goto landed on.
#
# navigateToHistoryEntry returns while the outgoing document still
# reports readyState "complete", so the caller's load wait would settle
# instantly on the old page. The history index anchors the wait: it
# flips when the browser commits the entry. For a normal load that is
# at commit, before the new document finishes (readyState then cycles,
# and the subsequent wait_for_load() does the real settling); for a
# bfcache restore it flips instantly together with an already-complete
# readyState, which is correct: nothing more loads. A window-marker
# poll would not survive this split: a marker set on the page survives
# a bfcache restore, so it never signals the flip.
nav_history <- function(page, offset, call = caller_env()) {
  session <- page$session
  hist <- session$Page$getNavigationHistory(timeout_ = page$default_timeout)
  idx <- hist$currentIndex + offset + 1
  if (idx < 1 || idx > length(hist$entries)) {
    return(FALSE)
  }
  if (
    offset < 0 &&
      idx == 1 &&
      identical(hist$entries[[idx]]$url, "about:blank")
  ) {
    return(FALSE)
  }
  session$Page$navigateToHistoryEntry(
    entryId = hist$entries[[idx]]$id,
    timeout_ = page$default_timeout
  )
  target <- idx - 1
  pz_poll(
    fn = function() {
      # Mid-switch, the session can transiently report "Not attached
      # to an active page"; that means not-yet, so the poll retries.
      hist <- tryCatch(
        session$Page$getNavigationHistory(timeout_ = page$default_timeout),
        error = function(e) NULL
      )
      isTRUE(hist$currentIndex == target)
    },
    timeout = page$default_timeout,
    loop = page$child_loop,
    what = "history navigation",
    call = call
  )
  TRUE
}

# Synchronize a chromote event promise (registered with wait_ = FALSE
# before its trigger): poll until it settles, pumping the page's child
# loop so the websocket message that resolves it gets processed. Only
# the public then() API is used; chromote event promises resolve with
# the event payload and never reject in practice, but a rejection is
# re-thrown rather than swallowed.
nav_await <- function(page, p, what, call = caller_env()) {
  settled <- FALSE
  failed <- NULL
  # then() on an already-settled promise schedules the callback on the
  # CURRENT loop, not the loop the promise resolved on -- and the event
  # can settle before we get here (frameNavigated is dispatched while
  # the trigger command's own synchronize pumps the child loop, e.g.
  # when its response is delayed under load). pz_poll() below pumps
  # only the child loop, so a callback queued on the default loop would
  # never run and the wait would always time out. with_loop() pins the
  # callback to the loop that gets pumped; for a still-pending promise
  # it changes nothing (resolution queues on the resolving loop, which
  # is the child loop).
  later::with_loop(
    page$child_loop,
    promises::then(
      p,
      onFulfilled = function(value) {
        settled <<- TRUE
      },
      onRejected = function(e) {
        settled <<- TRUE
        failed <<- list(e)
      }
    )
  )
  pz_poll(
    fn = function() settled,
    timeout = page$default_timeout,
    loop = page$child_loop,
    what = what,
    call = call
  )
  if (!is.null(failed)) {
    stop(failed[[1]])
  }
  invisible(p)
}

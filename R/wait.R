#' Wait while pumping the page's event loop
#'
#' Pauses for `seconds`, driving chromote's child event loop so timers
#' scheduled on it (e.g. recording capture) keep firing during the wait.
#' Never sleeps without pumping the loop.
#'
#' @inheritParams pz_click
#' @param seconds Number of seconds to wait.
#'
#' @return `ctx`, invisibly.
#'
#' @export
pz_wait <- function(ctx, seconds) {
  check_context(ctx)
  check_number_decimal(seconds, min = 0)
  pump_loop(ctx$page$child_loop, seconds)
  invisible(ctx)
}
#' Wait until a JavaScript condition holds
#'
#' Polls `expr` until it evaluates truthy, then returns `ctx` invisibly.
#' Each poll awaits a promise `expr` returns, so async conditions work;
#' JavaScript truthiness applies (a non-empty string or a non-zero
#' number counts). An `expr` that throws is a JavaScript error, not a
#' failed poll.
#'
#' There is deliberately no element-state wait (`pz_wait_for(target,
#' state =)`): [pz_expect_visible()], [pz_expect_hidden()], and
#' [pz_expect_exists()] with `not = TRUE` already retry, so they wait.
#'
#' @inheritParams pz_click
#' @param expr A string of JavaScript that evaluates truthy when the
#'   condition holds. A returned promise is awaited first.
#' @param timeout Seconds before giving up; `NULL` uses the session
#'   default.
#'
#' @return `ctx`, invisibly.
#' @seealso [pz_wait_for_stable()], [pz_wait_for_navigation()]
#' @examples
#' \dontrun{
#' page |> pz_wait_for_js("window.app !== undefined")
#' }
#'
#' @export
pz_wait_for_js <- function(ctx, expr, ..., timeout = NULL) {
  check_dots_empty()
  check_context(ctx)
  check_string(expr)
  timeout <- resolve_timeout(timeout, ctx$page)
  # Truthiness is JavaScript's, not R's: a non-empty string or non-zero
  # number must count, so the poll reads an actual boolean. Each
  # evaluation gets the wait's full budget, so a pending promise can't
  # stretch the wait past its own timeout.
  check <- paste0("Promise.resolve(", expr, ").then((v) => !!v)")
  pz_poll(
    fn = function() isTRUE(pz_js(ctx, check, timeout = timeout)),
    timeout = timeout,
    loop = ctx$page$child_loop,
    what = paste0("JS condition ", expr)
  )
  invisible(ctx)
}
#' Wait until an element stops changing
#'
#' Samples the `prop` property of every element matching `target` (or
#' the current context) until the sampled value has held still for
#' `for_ms` milliseconds: text has stopped arriving, or an animation
#' has come to rest. `prop = "rect"` samples the bounding box instead
#' of a property, rounded to whole pixels.
#'
#' The wait first waits (up to `timeout`) for `target` to match, then
#' samples within a second, separate `timeout` budget of its own: a
#' target that appears near the locator deadline still gets its full
#' `for_ms` window.
#'
#' There is deliberately no element-state wait: [pz_expect_visible()],
#' [pz_expect_hidden()], and [pz_expect_exists()] with `not = TRUE` already
#' retry, so they wait.
#'
#' @inheritParams pz_click
#' @param target A CSS selector string, a [pz_loc()] spec, or a list of
#'   specs and strings (a union matching any of them). `NULL` means the
#'   current context: the pinned set at a scoped context, the page body
#'   at the root.
#' @param prop The element property to sample: any single JavaScript
#'   property name (`"textContent"`, `"value"`, `"scrollTop"`, ...),
#'   or `"rect"` for the bounding box.
#' @param for_ms Milliseconds the sampled value must hold still before
#'   the wait passes.
#' @param timeout Seconds before giving up; `NULL` uses the session
#'   default.
#'
#' @return `ctx`, invisibly.
#' @seealso [pz_wait_for_js()], [pz_wait_for_navigation()]
#' @examples
#' \dontrun{
#' # Wait for the chat to stop streaming replies.
#' page |> pz_wait_for_stable(target = ".replies", for_ms = 500)
#' # Wait for an animation to finish moving.
#' page |> pz_wait_for_stable(target = ".card", prop = "rect", for_ms = 300)
#' }
#'
#' @export
pz_wait_for_stable <- function(
  ctx,
  ...,
  target = NULL,
  prop = "textContent",
  for_ms = 500,
  timeout = NULL
) {
  check_dots_empty()
  check_context(ctx)
  prop <- check_stable_prop(prop)
  check_number_decimal(for_ms, min = 0)
  timeout <- resolve_timeout(timeout, ctx$page)

  sample_js <- stable_sample_js(prop)
  scoped <- scope_top(ctx)
  target_expr <- target_resolver_expr(target)
  if (!is.null(target) || is.null(scoped)) {
    # Stability of a set that doesn't exist yet is meaningless, so
    # the wait first waits (up to `timeout`) for a match -- BEFORE the
    # stability poll starts. The sampling loop then owns its own full
    # budget: a target appearing near the locator deadline still
    # gets its whole `for_ms` window.
    release_elements(
      loc_resolve(ctx, target, timeout = timeout, multiple = "all")
    )
  }
  sample <- function() {
    els <- if (is.null(target) && !is.null(scoped)) {
      # The pinned set itself, detach-probed per sample.
      scope_root(ctx)
    } else {
      loc_resolve_once(
        ctx,
        target_expr$fn,
        target_expr$description,
        root = scope_root(ctx)
      )
    }
    if (!inherits(els, "paparazzi_pinned")) {
      withr::defer(release_elements(els))
    }
    if (els$count == 0L) {
      return("0")
    }
    paste0(els$count, "\u0001", paste(els_call(els, sample_js), collapse = "\u0001"))
  }

  last <- NULL
  stable_since <- NULL
  pz_poll(
    fn = function() {
      s <- sample()
      now <- Sys.time()
      if (is.null(last) || !identical(last, s)) {
        last <<- s
        stable_since <<- now
      }
      as.numeric(difftime(now, stable_since, units = "secs")) >= for_ms / 1000
    },
    timeout = timeout,
    interval = min(0.1, max(for_ms / 2000, 0.01)),
    loop = ctx$page$child_loop,
    what = paste0("the page to be stable for ", for_ms, "ms")
  )
  invisible(ctx)
}
#' Wait for a navigation to finish
#'
#' The explicit wait after an action that navigates -- a clicked link, a
#' submitted form, a JS redirect. Paparazzi never detects navigations on
#' its own, so a wait marks exactly where one is expected. Call it
#' immediately after the action: it waits for the document the action
#' navigated to to finish loading and then hold still for a moment, so a
#' navigation that is in flight when the wait starts is waited out, not
#' raced. A navigation that begins while the wait is already running is
#' caught too; one scheduled beyond the timeout can't be -- block on
#' its trigger with [pz_wait_for_js()] first.
#'
#' The settled state alone is not enough: the wait snapshots the
#' document it starts on and passes only when the settled document is
#' a different one, so a page where nothing navigates times out with
#' a classed error rather than passing. On success it resets the scope
#' to the root and releases every pinned scope object: contexts scoped
#' before the navigation error on their next use instead of acting on
#' a stale set.
#'
#' @inheritParams pz_click
#' @param wait What to wait for: `"auto"` resolves to `"load"` (the
#'   document finishes loading, like [pz_open()]); `"none"` skips the
#'   wait and only resets the scope.
#' @param timeout Seconds before giving up; `NULL` uses the session
#'   default.
#'
#' @return `ctx`, invisibly, with the scope reset to the root.
#' @seealso [pz_find_reset()], [pz_wait_for_js()], [pz_wait_for_stable()]
#' @examples
#' \dontrun{
#' page |>
#'   pz_click(target = "a.next-page") |>
#'   pz_wait_for_navigation()
#' }
#'
#' @export
pz_wait_for_navigation <- function(
  ctx,
  ...,
  wait = c("auto", "load", "none"),
  timeout = NULL
) {
  check_dots_empty()
  check_context(ctx)
  wait <- arg_match(wait)
  timeout <- resolve_timeout(timeout, ctx$page)

  if (identical(wait, "none")) {
    return(invisible(wait_nav_reset(ctx)))
  }
  # "auto" waits for what pz_open() does; other resolutions (shiny)
  # arrive with the Shiny-integration task. Both phases share the
  # budget: each gets the full timeout, like wait_for_stable's resolve
  # and stability windows. The snapshot precedes them both: a complete,
  # settled page satisfies the settle check with nothing navigating,
  # so the wait must hold the identity of the document it started on
  # and only pass on a different document (a new timeOrigin) -- or on
  # one it caught incomplete, the in-flight navigation this wait
  # waits out.
  snapshot <- nav_snapshot(ctx, timeout)
  wait_for_load(ctx$page, timeout = timeout)
  nav_settle(
    ctx,
    settle = nav_settle_secs,
    timeout = timeout,
    snapshot = snapshot
  )
  root <- wait_nav_reset(ctx)
  device_css_reapply(ctx$page)
  invisible(root)
}
# The quiescence window for a navigation: how long the page's load state
# must hold still before pz_wait_for_navigation() proceeds. A commit in
# flight when the wait starts shows up as a state change inside this
# window and is waited out; anything later than that is beyond a
# post-action wait.
nav_settle_secs <- 0.5
# The wait-start document identity: readyState completeness plus the
# document's timeOrigin, the token a navigation always replaces. A
# read that fails mid-swap can't pin the identity, so it degrades to
# the in-flight reading (incomplete at wait start).
nav_snapshot <- function(ctx, timeout) {
  s <- tryCatch(
    pz_js(
      ctx,
      "JSON.stringify([document.readyState === 'complete', performance.timeOrigin])",
      timeout = timeout
    ),
    error = function(e) NULL
  )
  if (is.null(s)) {
    list(complete = FALSE, origin = NULL)
  } else {
    state <- jsonlite::fromJSON(s, simplifyVector = FALSE)
    list(complete = isTRUE(state[[1]]), origin = state[[2]])
  }
}
# Phase two of pz_wait_for_navigation(): the page's load state -- the
# readyState and the document's timeOrigin -- must be complete AND
# unchanged for `settle` seconds. Any change restarts the window, so a
# document swap mid-window (the commit the action triggered) is caught
# and its load is waited out before passing. Completing the window is
# not enough on its own: the pass needs positive evidence a navigation
# occurred, a timeOrigin the wait-start snapshot doesn't hold (or a
# snapshot that caught the document incomplete -- the in-flight case),
# so a settled page with nothing navigated times out instead of
# passing.
nav_settle <- function(ctx, settle, timeout, snapshot, call = caller_env()) {
  read <- function() {
    tryCatch(
      pz_js(
        ctx,
        "JSON.stringify([document.readyState === 'complete', performance.timeOrigin])",
        timeout = timeout
      ),
      # Mid-navigation evaluations can fail while the renderer swaps
      # documents; that's a changing state, not an error.
      error = function(e) NULL
    )
  }
  last <- NULL
  stable_since <- NULL
  pz_poll(
    fn = function() {
      s <- read()
      now <- Sys.time()
      if (is.null(s) || !identical(last, s)) {
        last <<- s
        stable_since <<- now
      }
      if (is.null(s)) {
        return(FALSE)
      }
      # simplifyVector = FALSE keeps the boolean a boolean: the mixed
      # [boolean, number] JSON would coerce TRUE to 1 otherwise.
      state <- jsonlite::fromJSON(s, simplifyVector = FALSE)
      nav <- !identical(state[[2]], snapshot$origin) || !isTRUE(snapshot$complete)
      isTRUE(state[[1]]) && nav &&
        as.numeric(difftime(now, stable_since, units = "secs")) >= settle
    },
    timeout = timeout,
    loop = ctx$page$child_loop,
    what = "the navigation to complete",
    call = call
  )
}
pump_loop <- function(loop, seconds, interval = 0.1) {
  deadline <- Sys.time() + seconds
  repeat {
    remaining <- as.numeric(difftime(deadline, Sys.time(), units = "secs"))
    if (remaining <= 0) {
      break
    }
    later::run_now(timeoutSecs = min(remaining, interval), loop = loop)
  }
  invisible(TRUE)
}
#' Poll `fn()` until it returns `TRUE` or `timeout` seconds elapse
#'
#' Between checks, pumps `loop` (the page's child loop) instead of sleeping,
#' so timers scheduled on the loop keep firing during the poll.
#'
#' @param fn Zero-arg function returning `TRUE` when the condition holds.
#' @param timeout Seconds before giving up.
#' @param interval Seconds between checks.
#' @param loop A `later` event loop.
#' @param what Description of the condition, used in the timeout error.
#' @param call Reported as the source of the timeout error.
#' @noRd
pz_poll <- function(
  fn,
  timeout,
  interval = 0.1,
  loop,
  what = "condition",
  call = caller_env()
) {
  deadline <- Sys.time() + timeout
  repeat {
    if (isTRUE(fn())) {
      return(invisible(TRUE))
    }
    remaining <- as.numeric(difftime(deadline, Sys.time(), units = "secs"))
    if (remaining <= 0) {
      cli::cli_abort(
        # Plain interpolation: descriptions may carry their own quotes
        # (has_text: "..."), and {.val} would escape them.
        "Timed out after {timeout}s waiting for {what}.",
        class = "paparazzi_error_timeout",
        call = call
      )
    }
    later::run_now(timeoutSecs = min(remaining, interval), loop = loop)
  }
}
# A sampled property: any single JavaScript property name, or "rect" for
# the bounding box. The identifier check keeps property names from being
# interpreted as JS source.
check_stable_prop <- function(prop, call = caller_env()) {
  check_string(prop, call = call)
  if (identical(prop, "rect")) {
    return(prop)
  }
  if (!grepl("^[A-Za-z_$][A-Za-z0-9_$]*$", prop)) {
    cli::cli_abort(
      c(
        "{.arg prop} must be a single JavaScript property name (e.g. {.str textContent}) or {.str rect}.",
        i = "For custom conditions, use {.fn pz_wait_for_js}."
      ),
      class = "paparazzi_error_input",
      call = call
    )
  }
  prop
}
# One sample of every element in the set, as a per-element string:
# property values stringified (null/undefined as empty), rects rounded
# to whole pixels so sub-pixel noise doesn't read as change. A change
# in the match count changes the joined sample too.
stable_sample_js <- function(prop) {
  if (identical(prop, "rect")) {
    paste0(
      "function() {
        return this.map((el) => {
          const r = el.getBoundingClientRect();
          return [r.x, r.y, r.width, r.height].map((v) => Math.round(v)).join(',');
        });
      }"
    )
  } else {
    paste0(
      "function() {
        return this.map((el) => {
          const v = el[", jsonlite::toJSON(prop, auto_unbox = TRUE), "];
          return v == null ? '' : String(v);
        });
      }"
    )
  }
}
# The reset that follows every navigation: the object group holding
# every pinned scope is released wholesale (contexts derived before the
# navigation raise the classed detach error on their next use), and the
# returned context is back at the root. The caller's context is never
# mutated.
wait_nav_reset <- function(ctx) {
  ctx$page$release_object_group()
  # The inline css zoom dies with the document being left; its
  # "applied" cache dies with it, and the settle point re-applies.
  state <- attr(ctx$page, "paparazzi_device")
  if (!is.null(state)) {
    state$css_zoom <- NULL
  }
  if (length(ctx$scope) == 0) {
    ctx
  } else {
    PaparazziContext$new(ctx$page, scope = list())
  }
}

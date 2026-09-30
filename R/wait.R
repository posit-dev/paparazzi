#' Wait while pumping the page's event loop
#'
#' Pauses for `seconds`, driving chromote's child event loop so timers
#' scheduled on it (e.g. recording capture) keep firing during the wait.
#' Never sleeps without pumping the loop.
#'
#' @inheritParams pz_act_click
#' @param seconds Number of seconds to wait.
#'
#' @return `ctx`, invisibly.
#'
#' @examplesIf paparazzi:::examples_run()
#' page <- pz_open(pz_example("tasks"))
#'
#' # A fixed pause; prefer an expectation or wait_for function when you
#' # know what you're waiting for
#' page |>
#'   pz_act_click("#toggle-help") |>
#'   pz_wait(0.5)
#' pz_close(page)
#'
#' @export
pz_wait <- function(ctx, seconds) {
  check_context(ctx)
  check_number_decimal(seconds, min = 0)
  pump_loop(ctx$page$child_loop, seconds)
  ctx_return(ctx)
}

#' Wait until a Shiny page is idle
#'
#' Waits for the Shiny connection, for `<html>` to lose `shiny-busy`, and
#' for every `.recalculating` output to finish. All three conditions must
#' hold continuously for at least 200ms, including brief busy/recalculating
#' transitions. A page without the Shiny global errors instead of waiting;
#' a page whose Shiny app never connects times out.
#'
#' @inheritParams pz_wait_for_js
#' @return `ctx`, invisibly.
#' @seealso [pz_open()]
#' @examplesIf paparazzi:::examples_run("shiny")
#' page <- pz_open(pz_example("tasks-app"))
#'
#' # Clicking Add makes the server re-render the task list, which takes a moment
#' page |>
#'   pz_set_value("Buy milk", target = "#title") |>
#'   pz_act_click("#add") |>
#'   pz_wait_for_shiny_idle()
#' pz_get_text(page, target = "#summary")
#' pz_close(page)
#'
#' @export
pz_wait_for_shiny_idle <- function(ctx, ..., timeout = NULL) {
  check_dots_empty()
  check_context(ctx)
  timeout <- resolve_timeout(timeout, ctx$page)
  deadline <- Sys.time() + timeout
  remaining <- function() {
    as.numeric(difftime(deadline, Sys.time(), units = "secs"))
  }
  wait_for_load(ctx$page, timeout = timeout)
  if (
    !isTRUE(pz_js(
      ctx,
      "!!window.Shiny",
      timeout = max(0.1, remaining())
    ))
  ) {
    cli::cli_abort(
      "This is not a Shiny page; {.fn pz_wait_for_shiny_idle} requires a Shiny app.",
      class = "paparazzi_error_unsupported"
    )
  }

  budget <- max(0, remaining())
  idle_js <- paste0(
    "new Promise((resolve) => {",
    "  const budget = ",
    ceiling(budget * 1000),
    ";",
    "  let hold = null;",
    "  let deadlineTimer;",
    "  let observer;",
    "  const events = 'shiny:connected shiny:disconnected shiny:busy shiny:idle';",
    "  const idle = () => !!window.Shiny?.shinyapp?.$socket &&",
    "    Shiny.shinyapp.$socket.readyState === WebSocket.OPEN &&",
    "    !document.documentElement.classList.contains('shiny-busy') &&",
    "    !document.querySelector('.recalculating');",
    "  const hasClass = (value, name) => (value || '').split(/\\s+/).includes(name);",
    "  const relevant = (records) => records.some((record) => {",
    "    if (record.type === 'attributes') {",
    "      if (record.target === document.documentElement &&",
    "          (hasClass(record.oldValue, 'shiny-busy') || record.target.classList.contains('shiny-busy'))) return true;",
    "      return hasClass(record.oldValue, 'recalculating') || record.target.classList.contains('recalculating');",
    "    }",
    "    return [...record.addedNodes, ...record.removedNodes].some((node) =>",
    "      node.nodeType === 1 && (node.matches('.recalculating') || node.querySelector('.recalculating')));",
    "  });",
    "  const finish = (value) => {",
    "    clearTimeout(hold); clearTimeout(deadlineTimer);",
    "    observer.disconnect();",
    "    window.jQuery(document).off(events, changed);",
    "    window.removeEventListener('pagehide', pagehide);",
    "    resolve(value);",
    "  };",
    "  const check = () => {",
    "    clearTimeout(hold); hold = null;",
    "    if (idle()) hold = setTimeout(() => {",
    "      if (relevant(observer.takeRecords())) { check(); return; }",
    "      if (idle()) finish(true); else check();",
    "    }, 200);",
    "  };",
    "  const changed = () => check();",
    "  const pagehide = () => finish(false);",
    "  observer = new MutationObserver((records) => { if (relevant(records)) check(); });",
    "  observer.observe(document, {subtree: true, childList: true, attributes: true,",
    "    attributeFilter: ['class'], attributeOldValue: true});",
    "  window.jQuery(document).on(events, changed);",
    "  window.addEventListener('pagehide', pagehide);",
    "  deadlineTimer = setTimeout(() => finish(false), budget);",
    "  check();",
    "})"
  )
  passed <- if (budget > 0) {
    tryCatch(
      isTRUE(pz_js(ctx, idle_js, timeout = max(0.1, remaining() + 0.1))),
      paparazzi_error_timeout = function(e) FALSE
    )
  } else {
    FALSE
  }
  if (!passed) {
    cli::cli_abort(
      "Timed out after {timeout}s waiting for Shiny idle.",
      class = "paparazzi_error_timeout"
    )
  }
  ctx_return(ctx)
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
#' @inheritParams pz_act_click
#' @param expr A string of JavaScript that evaluates truthy when the
#'   condition holds. A returned promise is awaited first.
#' @param timeout Seconds before giving up; `NULL` uses the session
#'   default.
#'
#' @return `ctx`, invisibly.
#' @seealso [pz_wait_for_stable()], [pz_wait_for_navigation()]
#' @examplesIf paparazzi:::examples_run()
#' page <- pz_open(pz_example("tasks"))
#' page |>
#'   pz_act_type("Buy milk", target = "#task-title") |>
#'   pz_act_press("Enter") |>
#'   pz_wait_for_js("document.querySelectorAll('.task').length === 8")
#' pz_get_text(page, target = pz_loc(".task-title", which = "first"))
#' pz_close(page)
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
  ctx_return(ctx)
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
#' @inheritParams pz_act_click
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
#' @examplesIf paparazzi:::examples_run()
#' page <- pz_open(pz_example("tasks"))
#'
#' # The status line reads "Saving..." and then "Saved"; wait for it to settle
#' page |>
#'   pz_act_type("Buy milk", target = "#task-title") |>
#'   pz_act_click("#add-task") |>
#'   pz_wait_for_stable(target = "#status", for_ms = 500)
#' pz_get_text(page, target = "#status")
#' pz_close(page)
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
    paste0(
      els$count,
      "\u0001",
      paste(els_call(els, sample_js), collapse = "\u0001")
    )
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
  ctx_return(ctx)
}

#' Wait for a navigation to finish
#'
#' The explicit wait after an action that navigates -- a clicked link, a
#' submitted form, a JS redirect. Paparazzi never detects navigations on
#' its own, so a wait marks exactly where one is expected. Call it
#' immediately after the action. It waits for the new document to finish
#' loading and then hold still for a moment. Three cases pass:
#'
#' * the navigation finished before the wait started: the current document
#'   differs from the document where the preceding action began (including
#'   a page restored from the back/forward cache);
#' * the navigation is in flight when the wait starts, and is waited out;
#' * the navigation begins while the wait is running. One scheduled beyond
#'   the timeout can't be caught -- block on its trigger with
#'   [pz_wait_for_js()] first.
#'
#' A page where nothing navigates times out with a classed error rather
#' than passing, and so does a second wait after the same action: a
#' successful wait uses up the action's navigation.
#'
#' On success the wait resets the scope to the root and releases every
#' pinned scope object: contexts scoped before the navigation error on
#' their next use instead of acting on a stale set.
#'
#' @inheritParams pz_act_click
#' @param wait What to wait for: `"load"` settles the navigation;
#'   `"shiny"` also waits for Shiny idle after load. `"auto"` uses
#'   `"shiny"` only when the page was opened on an app handle or app path
#'   and lands on that app's origin; otherwise it uses `"load"`.
#'   `"none"` skips settling and only resets the scope.
#' @param timeout Seconds before giving up; `NULL` uses the session
#'   default.
#'
#' @return `ctx`, invisibly, with the scope reset to the root.
#' @seealso [pz_find_reset()], [pz_wait_for_js()], [pz_wait_for_stable()]
#' @examplesIf paparazzi:::examples_run()
#' page <- pz_open(pz_example("tasks"))
#' page |> pz_act_click(pz_loc(".task-done", within = pz_loc(".task", has_text = "bank")))
#' pz_get_count(page, target = ".task.done")
#'
#' # "Start over" is a link to a new copy of the page
#' page |>
#'   pz_act_click("#start-over") |>
#'   pz_wait_for_navigation()
#' pz_get_count(page, target = ".task.done")
#' pz_close(page)
#'
#' @export
pz_wait_for_navigation <- function(
  ctx,
  ...,
  wait = c("auto", "load", "shiny", "none"),
  timeout = NULL
) {
  check_dots_empty()
  check_context(ctx)
  wait <- arg_match(wait)
  timeout <- resolve_timeout(timeout, ctx$page)

  if (identical(wait, "none")) {
    return(ctx_return(wait_nav_reset(ctx)))
  }
  # The load and settle phases each get the full timeout, like
  # wait_for_stable's resolve and stability windows. The snapshot
  # precedes them both: a complete, settled page satisfies the settle
  # check with nothing navigating, so the wait holds the identity of the
  # document it started on and passes only on a different document (a
  # new timeOrigin), a different loaderId from the last action, or
  # one it caught incomplete (the in-flight navigation it waits out).
  snapshot <- nav_snapshot(ctx, timeout)
  wait_for_load(ctx$page, timeout = timeout)
  nav_settle(
    ctx,
    settle = nav_settle_secs,
    timeout = timeout,
    snapshot = snapshot,
    action_loader = ctx$page$.__enclos_env__$private$last_action_loader_
  )
  root <- wait_nav_reset(ctx)
  device_css_reapply(ctx$page)
  nav_settle_shiny(ctx$page, wait, timeout)
  ctx_return(root)
}

# The quiescence window for a navigation: how long the page's load state
# must hold still before pz_wait_for_navigation() proceeds. A commit in
# flight when the wait starts shows up as a state change inside this
# window and is waited out; anything later than that is beyond a
# post-action wait.
nav_settle_secs <- 0.5

# The wait-start document identity: readyState completeness plus the
# document's timeOrigin, the token a navigation always replaces. A read
# that fails during a document swap (including a command timeout) can't
# pin the identity, so it degrades to the in-flight reading. Closed-page
# and JavaScript errors cannot indicate a swap.
nav_snapshot <- function(ctx, timeout) {
  s <- tryCatch(
    pz_js(
      ctx,
      "JSON.stringify([document.readyState === 'complete', performance.timeOrigin])",
      timeout = timeout
    ),
    error = function(e) {
      if (inherits(e, c("paparazzi_error_closed", "paparazzi_error_js"))) {
        stop(e)
      }
      NULL
    }
  )
  if (is.null(s)) {
    list(complete = FALSE, origin = NULL)
  } else {
    state <- jsonlite::fromJSON(s, simplifyVector = FALSE)
    list(complete = isTRUE(state[[1]]), origin = state[[2]])
  }
}

# Phase two of pz_wait_for_navigation(): the page's main-frame loaderId,
# readyState, and timeOrigin must be complete and unchanged for `settle`
# seconds. A loader change restarts the window even when the old document
# was complete. Completing the window is not enough on its own: the pass
# needs positive evidence a navigation occurred -- a changed wait-start
# timeOrigin, an incomplete wait-start snapshot, or a loaderId different
# from the last action's main-frame loaderId.
nav_settle <- function(
  ctx,
  settle,
  timeout,
  snapshot,
  action_loader = NULL,
  call = caller_env()
) {
  read <- function() {
    tryCatch(
      list(
        loader = ctx$page$session$Page$getFrameTree(
          timeout_ = timeout
        )$frameTree$frame$loaderId,
        js = pz_js(
          ctx,
          "JSON.stringify([document.readyState === 'complete', performance.timeOrigin])",
          timeout = timeout
        )
      ),
      # Mid-navigation reads can fail while the renderer swaps documents;
      # that's a changing state, not an error.
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
      state <- jsonlite::fromJSON(s$js, simplifyVector = FALSE)
      nav <- !identical(state[[2]], snapshot$origin) ||
        !isTRUE(snapshot$complete) ||
        (!is.null(action_loader) && !identical(s$loader, action_loader))
      isTRUE(state[[1]]) &&
        nav &&
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
          const v = el[",
      jsonlite::toJSON(prop, auto_unbox = TRUE),
      "];
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
  ctx$page$.__enclos_env__$private$last_action_loader_ <- NULL
  ctx$page$release_object_group()
  record_nav_rebased(ctx$page)
  # The inline css zoom dies with the document being left; its
  # "applied" cache dies with it, and the settle point re-applies.
  state <- attr(ctx$page, "paparazzi_device")
  if (!is.null(state)) {
    state$css_zoom <- NULL
  }
  if (length(ctx$scope) == 0) {
    ctx
  } else {
    ctx_derive(ctx, list())
  }
}

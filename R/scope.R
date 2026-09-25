# The scoping stack. pz_find*() resolves a target eagerly (auto-waiting
# for >= 1 match), pins the matched set as a CDP remote object in the
# page's object group, and pushes it onto an immutable per-context
# stack. Targets passed to later pz_*() calls resolve lazily INSIDE the
# pinned scope; the pinned set itself is checked once per use and never
# silently re-queried.
#' Find elements and push them as the current scope
#'
#' @description
#' [pz_find()] resolves `target` (auto-waiting for at least one match),
#' pins the matched set as the current scope, and returns a new context:
#' later calls on it operate inside that scope. Explicit targets resolve
#' lazily among the scope's descendants at use time -- re-renders within
#' the scope are fine -- and `target = NULL` means the scope itself for
#' the calls that accept one.
#'
#' The pinned set is eager: it is fixed at find time, and a later
#' re-render that detaches any of its elements aborts with a classed
#' error on the next use -- the scope is never silently re-queried (a
#' lazy, reusable target is what [pz_loc()] is for). Multi-match targets
#' pin the whole set.
#'
#' The stack is immutable: `pz_find*()` never mutate the context they
#' are called on, and contexts derived from the same parent share its
#' pinned sets.
#'
#' @inheritParams pz_click
#' @param target A CSS selector string, a [pz_loc()] spec, or a list of
#'   specs and strings (a union matching any of them). Required: there
#'   is nothing to find without a target, so `NULL` is an error. To
#'   narrow an existing scope, use [pz_find_first()], [pz_find_last()],
#'   or [pz_find_nth()] without a target.
#' @param from_root Resolve the target from the page root instead of
#'   the current scope? The new scope is still pushed on top of the
#'   stack, so [pz_find_pop()] returns to the previous scope.
#'
#' @return A new context, invisibly.
#'
#' @seealso [pz_find_first()], [pz_find_pop()], [pz_find_reset()]
#'
#' @export
pz_find <- function(ctx, target, ..., from_root = FALSE) {
  check_context(ctx)
  check_dots_empty()
  check_bool(from_root)
  if (missing(target) || is.null(target)) {
    cli::cli_abort(
      c(
        "{.arg target} is needed: {.fn pz_find} pins the elements it finds.",
        i = "To narrow the current scope, use {.fn pz_find_first}, {.fn pz_find_last}, or {.fn pz_find_nth} without a target."
      ),
      class = "paparazzi_error_target"
    )
  }
  invisible(find_push(ctx, as_loc_list(target), from_root))
}
#' Find the first match and push it as the current scope
#'
#' [pz_find_first()] is [pz_find()] with `which = "first"`. With a
#' `target`, it pins the spec's first match. Without a `target`, it
#' narrows the current scope to its first element: one eager slice of
#' the pinned set, with no re-query and no waiting.
#'
#' @inheritParams pz_click
#' @param target A CSS selector string or a [pz_loc()] spec. `NULL`
#'   narrows the current scope; a union can't pick one match by
#'   position, and a spec that already carries `which` is an error.
#' @param from_root Resolve the target from the page root instead of
#'   the current scope? Requires a `target`.
#'
#' @return A new context, invisibly.
#'
#' @seealso [pz_find()], [pz_find_last()], [pz_find_nth()]
#'
#' @export
pz_find_first <- function(ctx, target = NULL, ..., from_root = FALSE) {
  check_context(ctx)
  check_dots_empty()
  check_bool(from_root)
  invisible(find_which(ctx, target, "first", from_root))
}
#' Find the last match and push it as the current scope
#'
#' [pz_find_last()] is [pz_find()] with `which = "last"`. With a
#' `target`, it pins the spec's last match. Without a `target`, it
#' narrows the current scope to its last element: one eager slice of
#' the pinned set, with no re-query and no waiting.
#'
#' @inheritParams pz_find_first
#'
#' @return A new context, invisibly.
#'
#' @seealso [pz_find()], [pz_find_first()], [pz_find_nth()]
#'
#' @export
pz_find_last <- function(ctx, target = NULL, ..., from_root = FALSE) {
  check_context(ctx)
  check_dots_empty()
  check_bool(from_root)
  invisible(find_which(ctx, target, "last", from_root))
}
#' Find the nth match and push it as the current scope
#'
#' [pz_find_nth()] is [pz_find()] with `which = n`. With a `target`, it
#' pins the spec's `n`th match; an out-of-range `n` means no match, so
#' the call keeps auto-waiting like any [pz_loc()] resolution. Without
#' a `target`, it narrows the current scope to its `n`th element: one
#' eager slice of the pinned set, and an out-of-range `n` errors
#' immediately -- the set was fixed at pin time, so there is nothing to
#' wait for.
#'
#' @inheritParams pz_find_first
#' @param n The match to pick, 1-based (`"first"`/`"last"` are the
#'   [pz_find_first()]/[pz_find_last()] wrappers, not values here).
#'
#' @return A new context, invisibly.
#'
#' @seealso [pz_find()], [pz_find_first()], [pz_find_last()]
#'
#' @export
pz_find_nth <- function(ctx, n, ..., target = NULL, from_root = FALSE) {
  check_context(ctx)
  check_dots_empty()
  n <- check_which(n, strings = FALSE)
  check_bool(from_root)
  invisible(find_which(ctx, target, n, from_root))
}
#' Pop the current scope
#'
#' `pz_find_pop()` returns a context one scope level up the stack. The
#' popped pinned set is NOT released -- a context derived before the
#' pop may still hold it -- and popping never mutates the context it
#' was called on. At the root it is a no-op returning `ctx` unchanged.
#'
#' @inheritParams pz_click
#'
#' @return A new context, invisibly.
#'
#' @seealso [pz_find()], [pz_find_reset()]
#'
#' @export
pz_find_pop <- function(ctx) {
  check_context(ctx)
  if (length(ctx$scope) == 0) {
    return(invisible(ctx))
  }
  invisible(PaparazziContext$new(ctx$page, scope = utils::head(ctx$scope, -1)))
}
#' Clear all scope, back to the root
#'
#' `pz_find_reset()` returns a context with an empty scope stack. No
#' pinned set is released -- contexts derived before the reset may
#' still hold them -- and resetting never mutates the context it was
#' called on. At the root it is a no-op returning `ctx` unchanged.
#'
#' @inheritParams pz_click
#'
#' @return A new context, invisibly.
#'
#' @seealso [pz_find()], [pz_find_pop()]
#'
#' @export
pz_find_reset <- function(ctx) {
  check_context(ctx)
  if (length(ctx$scope) == 0) {
    return(invisible(ctx))
  }
  invisible(PaparazziContext$new(ctx$page, scope = list()))
}
# The pinned set at the top of the scope stack, or NULL at the root:
# the raw stack read, without the detach check scope_root() adds. For
# routing decisions that don't consume the scope.
scope_top <- function(ctx) {
  if (length(ctx$scope) == 0) {
    NULL
  } else {
    ctx$scope[[length(ctx$scope)]]
  }
}
check_scope_single <- function(scoped, call = caller_env()) {
  if (scoped$count > 1) {
    cli::cli_abort(
      c(
        "Found {scoped$count} elements in the current scope.",
        i = "Narrow the scope, or target one element with {.fn pz_loc} and {.arg which}."
      ),
      class = "paparazzi_error_multiple",
      call = call
    )
  }
}

# The pinned set at the top of the scope stack, after the detach check;
# NULL at the root context. The single seam every consumer reads once
# per pz_*() call: "before each use" is per operation that touches the
# scope, not per CDP command (an action's scroll-rect-dispatch sequence
# is one use).
scope_root <- function(ctx, call = caller_env()) {
  scoped <- scope_top(ctx)
  if (is.null(scoped)) {
    NULL
  } else {
    pinned_assert_connected(scoped, call = call)
  }
}
# Pushing never touches an existing context: derived contexts share the
# parent's pinned sets, which is safe because the wrapper is immutable
# and never released by consumers (cleanup is the finalizer plus group
# release).
push_scope <- function(ctx, pinned) {
  PaparazziContext$new(ctx$page, scope = c(ctx$scope, list(pinned)))
}
# The pinned-set wrapper: a paparazzi_elements subclass, so
# els_call()/els_values()/el_rects()/el_scroll_into_view() accept
# pinned sets unchanged and action_elements()'s top-of-stack branch
# treats one as the element set. `locs` keeps the spec the set was
# pinned from, for formatting narrowed scopes.
new_pinned <- function(page, object_id, count, description, locs) {
  els <- structure(
    list(
      page = page,
      object_id = object_id,
      count = as.integer(count),
      description = description,
      locs = locs
    ),
    class = c("paparazzi_pinned", "paparazzi_elements")
  )
  # reg.finalizer() only binds to environments, so the finalizer rides
  # on a fresh one the wrapper alone holds: when the wrapper becomes
  # unreachable, so does the environment, and the release fires. The
  # closure captures the pieces, never the wrapper, so no cycle keeps
  # the wrapper alive. Best-effort only -- group release is
  # authoritative. The release must be fire-and-forget: a finalizer can
  # run at any allocation, and a synchronous wait would pump the event
  # loop mid-expression, settling an in-flight command's promise before
  # its own wait_for() registers -- chromote's synchronize() then
  # schedules its completion handler on the default loop (never pumped
  # here) and spins forever.
  if (!is.null(object_id)) {
    finalizer <- new.env(parent = emptyenv())
    reg.finalizer(finalizer, function(e) {
      if (!page$is_closed()) {
        try(
          page$session$Runtime$releaseObject(
            object_id,
            wait_ = FALSE,
            callback_ = function(res) invisible(NULL),
            error_ = function(err) invisible(NULL)
          ),
          silent = TRUE
        )
      }
    })
    attr(els, "finalizer_") <- finalizer
  }
  els
}
# The detach check: one callFunctionOn, returnByValue. Any detached
# element invalidates the set (pinned sets promise their whole set). A
# CDP failure that means the set's world is gone -- "Could not find
# object with given id" (a context that outlived a group release) or
# "Cannot find context with specified id" / "Execution context was
# destroyed" (a navigation that destroyed the context the set was
# pinned in) -- maps to the same class, so post-navigation /
# post-close contexts raise the classed error rather than a raw
# chromote one.
pinned_assert_connected <- function(pinned, call = caller_env()) {
  res <- tryCatch(
    pinned$page$session$Runtime$callFunctionOn(
      "function() { return this.every((el) => el && el.isConnected); }",
      objectId = pinned$object_id,
      returnByValue = TRUE,
      timeout_ = pinned$page$default_timeout
    ),
    error = function(e) {
      if (pinned_dead_context_error(e)) {
        pinned_abort_detached(pinned, call)
      }
      stop(e)
    }
  )
  err <- res$exceptionDetails
  if (!is.null(err)) {
    cli::cli_abort(
      "JavaScript error checking the scope {pinned$description}: {err$exception$description %||% err$text %||% 'unknown error'}.",
      class = "paparazzi_error_js",
      call = call
    )
  }
  if (!isTRUE(res$result$value)) {
    pinned_abort_detached(pinned, call)
  }
  invisible(pinned)
}
# A chromote failure meaning the pinned set's execution context no
# longer exists: the object group was released (the object is gone),
# or a navigation destroyed the context the set was pinned in (the
# context is gone, and every object with it).
pinned_dead_context_error <- function(e) {
  msg <- conditionMessage(e)
  any(
    grepl("could not find object with", msg, ignore.case = TRUE),
    grepl("cannot find context", msg, ignore.case = TRUE),
    grepl("execution context was destroyed", msg, ignore.case = TRUE)
  )
}
pinned_abort_detached <- function(pinned, call = caller_env()) {
  cli::cli_abort(
    c(
      "Scope element is no longer in the page (it was probably re-rendered).",
      "Scope: {pinned$description}",
      i = "Call {.fn pz_find} again after the update, or target it with {.fn pz_loc}."
    ),
    class = "paparazzi_error_detached",
    call = call
  )
}
# Eager narrowing of the current scope: one callFunctionOn on the
# pinned array, tagged with the object group so the slice is released
# with everything else. No re-query and no auto-wait -- the set was
# fixed at pin time, so waiting is pointless. The null filters are
# defensive: a live set always holds its pick.
scope_slice_js <- function(which) {
  # NOT switch(): a numeric which would select an alternative by
  # position (2 -> "last", > 3 -> no match), not by value.
  if (identical(which, "first")) {
    "function() { return this.slice(0, 1); }"
  } else if (identical(which, "last")) {
    "function() { return [this[this.length - 1]].filter((el) => el != null); }"
  } else {
    paste0("function() { return [this[", which, " - 1]].filter((el) => el != null); }")
  }
}
# A narrowed scope's description: a single loc takes `which` directly
# and re-formats with format_loc(); a union (or no locs at all) can't
# carry a which, so its description is the parent's plus a match
# suffix. A loc that already carries a which keeps it: it selected
# exactly one match, so any narrowing of that set is the same element
# and re-labeling it would name the wrong match. Shared by scope
# narrowing (the parent is the pinned set) and the element list-column
# (the parent is the getter's matched array).
narrow_description <- function(locs, description, which) {
  if (length(locs) == 1) {
    loc <- locs[[1]]
    if (is.null(loc$which)) {
      loc$which <- which
    }
    format_loc(loc)
  } else {
    paste0(description, " (match: ", which, ")")
  }
}
narrow_locs <- function(locs, which) {
  if (length(locs) == 1) {
    loc <- locs[[1]]
    if (is.null(loc$which)) {
      loc$which <- which
    }
    list(loc)
  } else {
    # A union can't take a which; the description carries the match.
    locs
  }
}
# pz_find_first()/pz_find_last()/pz_find_nth() with a target: apply
# `which` to the promoted loc and pin its match. Without a target:
# narrow the current scope eagerly.
find_which <- function(ctx, target, which, from_root, call = caller_env()) {
  if (is.null(target)) {
    return(find_narrow(ctx, which, from_root, call))
  }
  locs <- as_loc_list(target, call = call)
  if (length(locs) > 1) {
    cli::cli_abort(
      c(
        "A union target can't pick one match by position.",
        i = "Put {.arg which} on a single {.fn pz_loc} spec instead, or drop {.arg target} to narrow the current scope."
      ),
      class = "paparazzi_error_input",
      call = call
    )
  }
  loc <- locs[[1]]
  if (!is.null(loc$which)) {
    cli::cli_abort(
      c(
        "{.arg target} already picks its match ({format_loc(loc)}); the find can't override it.",
        i = "Drop {.arg which} from the spec, or find it as-is with {.fn pz_find}."
      ),
      class = "paparazzi_error_input",
      call = call
    )
  }
  loc$which <- which
  find_push(ctx, list(loc), from_root, call)
}
# Narrow the current scope: slice the pinned set at the top, eager and
# without re-query, and push the slice.
find_narrow <- function(ctx, which, from_root, call) {
  if (from_root) {
    cli::cli_abort(
      c(
        "Narrowing needs a current scope, so {.arg from_root} can't combine with a missing {.arg target}.",
        i = "Pass a {.arg target} to find from the root, or drop {.arg from_root} to narrow the current scope."
      ),
      class = "paparazzi_error_scope",
      call = call
    )
  }
  scoped <- scope_root(ctx, call = call)
  if (is.null(scoped)) {
    cli::cli_abort(
      c(
        "There is no current scope to narrow.",
        i = "Call {.fn pz_find} to create one first."
      ),
      class = "paparazzi_error_scope",
      call = call
    )
  }
  if (is.numeric(which) && which > scoped$count) {
    # An out-of-range narrowing errors immediately: the set was fixed
    # at pin time, so there is nothing to wait for. An out-of-range
    # `which` on a target, by contrast, keeps auto-waiting.
    cli::cli_abort(
      "The current scope has {scoped$count} elements; there is no match {which}.",
      class = "paparazzi_error_scope",
      call = call
    )
  }
  description <- narrow_description(scoped$locs, scoped$description, which)
  els <- loc_resolve_once(
    ctx,
    scope_slice_js(which),
    description,
    call = call,
    root = scoped,
    object_group = ctx$page$object_group
  )
  pinned <- new_pinned(
    ctx$page,
    els$object_id,
    els$count,
    description,
    locs = narrow_locs(scoped$locs, which)
  )
  push_scope(ctx, pinned)
}
# Resolve locs eagerly, pin the whole matched set, and push it.
find_push <- function(ctx, locs, from_root, call = caller_env()) {
  els <- loc_resolve(
    ctx,
    locs,
    multiple = "all",
    object_group = ctx$page$object_group,
    from_root = from_root,
    call = call
  )
  push_scope(ctx, new_pinned(ctx$page, els$object_id, els$count, els$description, locs))
}

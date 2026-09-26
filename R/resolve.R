# The resolver runs in the page and returns a JS array of matched elements.
# The specs arrive as a JSON array baked into the function text; NULL
# qualifiers are omitted from the JSON entirely, so JS sees them as
# undefined. The function's `this` is the roots array: [document] on the
# root path, the pinned element set of the current scope when invoked via
# callFunctionOn on one. loc_resolver_js() returns function TEXT; the
# callers never see an expression, only the function.
loc_resolver_js <- function(locs) {
  specs <- jsonlite::toJSON(lapply(locs, loc_spec_fields), auto_unbox = TRUE)
  sprintf(
    r"(function() {
const specs = %s;
const collapse = (s) => s.replace(/\s+/g, ' ');
const matchesText = (el, text) =>
  text == null || collapse(el.textContent).indexOf(collapse(text)) !== -1;

// Resolve one spec to a deduped array of elements, in DOM order.
// Without `within`, roots come from `this`; a spec's own `within`
// resolves inside the same invocation, so a `within` chain bottoms
// out in the current scope, not the document.
const resolveSpec = (spec) => {
  let roots;
  if (spec.within) {
    roots = resolveSpec(spec.within);
    if (roots.length === 0) return [];
  } else {
    roots = this && this.length ? this : [document];
  }
  const seen = new Set();
  let els = [];
  for (const root of roots) {
    for (const el of root.querySelectorAll(spec.css)) {
      if (!seen.has(el)) { seen.add(el); els.push(el); }
    }
  }
  // The recording overlay lives under this host; it is never page content.
  els = els.filter((el) => el.closest('#paparazzi-overlay-root') === null);
  if (spec.has_text != null) {
    els = els.filter((el) => matchesText(el, spec.has_text));
  }
  if (spec.which != null) {
    if (spec.which === 'first') {
      els = els.slice(0, 1);
    } else if (spec.which === 'last') {
      els = els.slice(-1);
    } else if (spec.which >= 1 && spec.which <= els.length) {
      els = [els[spec.which - 1]];
    } else {
      els = [];
    }
  }
  return els;
};

// Union: concatenate per-spec matches, deduped across specs.
const seen = new Set();
const out = [];
for (const spec of specs) {
  for (const el of resolveSpec(spec)) {
    if (!seen.has(el)) { seen.add(el); out.push(el); }
  }
}
// Null (not an empty array) on no match, so the caller can skip the
// count read entirely and never holds an empty remote object.
return out.length ? out : null;
})",
    specs
  )
}

# The target = NULL seam, shared by expect_impl() and get_impl(): NULL
# means the current context. Scoped consumers handle NULL before
# resolving (the pinned set itself), so this root-only meaning -- the
# implicit document.body element -- stays as it was. Returns function
# TEXT whose `this` is the roots array; loc_resolve_once() invokes it
# against [document] or a pinned scope set.
target_resolver_expr <- function(target, call = caller_env()) {
  if (is.null(target)) {
    return(list(
      fn = "function() { return [document.body]; }",
      description = "document.body"
    ))
  }
  locs <- as_loc_list(target, call = call)
  list(fn = loc_resolver_js(locs), description = format_loc(locs))
}

# A spec as a plain nested list (jsonlite won't serialize classed lists);
# NULL qualifiers are dropped so they never reach the JSON.
loc_spec_fields <- function(loc) {
  spec <- list(css = loc$css)
  if (!is.null(loc$has_text)) {
    spec$has_text <- loc$has_text
  }
  if (!is.null(loc$which)) {
    spec$which <- loc$which
  }
  if (!is.null(loc$within)) {
    spec$within <- loc_spec_fields(loc$within)
  }
  spec
}

#' Resolve a target to a remote element array, auto-waiting for a match
#'
#' The resolver function text is built once; each poll iteration is then a
#' single `Runtime$evaluate` (with `returnByValue = FALSE`) at the root,
#' or a `Runtime$callFunctionOn` on the current scope's pinned array, and
#' the count read happens only once a match exists -- an empty set comes
#' back as JS `null`, so there is no empty remote object to read or
#' release. `target = NULL` follows the target seam
#' (target_resolver_expr()): the root-only document.body meaning.
#' `object_group` tags every remote object the resolve creates with the
#' page's object group (the pz_find() pin); transient resolutions pass
#' none and release individually. `from_root = TRUE` resolves from the
#' document instead of the current scope. The scope (if any) is probed
#' once per loc_resolve() call -- one use, one check. Per-command
#' timeouts are the page's `default_timeout`, separate from the wait
#' budget. The result holds the objectId of the remote element array;
#' free it with release_elements() unless it is pinned.
#'
#' @noRd
loc_resolve <- function(
  ctx,
  target,
  ...,
  timeout = NULL,
  multiple = c("error", "all"),
  object_group = NULL,
  from_root = FALSE,
  call = caller_env()
) {
  check_context(ctx, call = call)
  check_dots_empty()
  check_bool(from_root, call = call)
  multiple <- arg_match(multiple)
  target_expr <- target_resolver_expr(target, call = call)
  fn <- target_expr$fn
  description <- target_expr$description
  timeout <- resolve_timeout(timeout, ctx$page, call = call)

  # One use, one check: `from_root = TRUE` skips the scope entirely so
  # the target resolves from the document instead of the pinned set.
  root <- if (from_root) NULL else scope_root(ctx, call = call)

  resolved <- NULL
  pz_poll(
    fn = function() {
      res <- loc_resolve_once(
        ctx,
        fn,
        description,
        call,
        root = root,
        object_group = object_group
      )
      if (res$count == 0) {
        FALSE
      } else {
        resolved <<- res
        TRUE
      }
    },
    timeout = timeout,
    loop = ctx$page$child_loop,
    what = description,
    call = call
  )

  if (multiple == "error" && resolved$count > 1) {
    # The caller never sees the handle, so release before aborting.
    release_elements(resolved)
    cli::cli_abort(
      c(
        "Found {resolved$count} elements matching {description}.",
        i = "Narrow the target with {.arg has_text}, {.arg which}, or {.arg within}."
      ),
      class = "paparazzi_error_multiple",
      call = call
    )
  }

  resolved
}

#' One resolution attempt
#'
#' Invokes the resolver function text once. With `root = NULL` its `this`
#' is `document`, reached via one `Runtime$evaluate`; with a pinned set
#' its `this` is that array, reached via `Runtime$callFunctionOn` on its
#' objectId -- the same resolver covers every rooting. JS `null` (empty
#' match set, no objectId) becomes a zero-count elements object with no
#' handle; a match runs one `callFunctionOn` length read and returns the
#' live handle. `object_group` tags the result with the page's object
#' group (the pz_find() pin); transient resolutions pass none. Each CDP
#' command gets the page's `default_timeout`; a chromote command timeout
#' is re-raised as a `paparazzi_error_timeout` naming the description,
#' with the original error as its parent.
#'
#' @noRd
loc_resolve_once <- function(
  ctx,
  fn,
  description,
  call = caller_env(),
  root = NULL,
  object_group = NULL
) {
  timeout <- ctx$page$default_timeout

  # A chromote command timeout (slow or hung renderer) is a timeout
  # condition of the resolve, not a raw chromote error.
  run_cdp <- function(cmd) {
    tryCatch(
      cmd,
      error = function(e) {
        if (grepl("timed out", conditionMessage(e), ignore.case = TRUE)) {
          cli::cli_abort(
            "Timed out after {timeout}s resolving {description}.",
            class = "paparazzi_error_timeout",
            call = call,
            parent = e
          )
        }
        stop(e)
      }
    )
  }

  if (is.null(root)) {
    res <- run_cdp(ctx$page$session$Runtime$evaluate(
      paste0("(", fn, ").call([document])"),
      awaitPromise = FALSE,
      returnByValue = FALSE,
      objectGroup = object_group,
      timeout_ = timeout
    ))
  } else {
    res <- run_cdp(ctx$page$session$Runtime$callFunctionOn(
      fn,
      objectId = root$object_id,
      returnByValue = FALSE,
      objectGroup = object_group,
      timeout_ = timeout
    ))
  }
  err <- res$exceptionDetails
  if (!is.null(err)) {
    cli::cli_abort(
      "JavaScript error while resolving {description}: {err$exception$description %||% err$text %||% 'unknown error'}.",
      class = "paparazzi_error_js",
      call = call
    )
  }
  object_id <- res$result$objectId
  if (is.null(object_id)) {
    return(new_elements(ctx$page, NULL, 0L, description))
  }
  count <- run_cdp(ctx$page$session$Runtime$callFunctionOn(
    "function() { return this.length; }",
    objectId = object_id,
    returnByValue = TRUE,
    timeout_ = timeout
  ))$result$value
  new_elements(ctx$page, object_id, count, description)
}

new_elements <- function(page, object_id, count, description) {
  structure(
    list(
      page = page,
      object_id = object_id,
      count = as.integer(count),
      description = description
    ),
    class = "paparazzi_elements"
  )
}

release_elements <- function(els) {
  if (!is.null(els$object_id) && !els$page$is_closed()) {
    try(els$page$session$Runtime$releaseObject(els$object_id), silent = TRUE)
  }
  invisible(els)
}

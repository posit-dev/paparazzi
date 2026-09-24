# The resolver runs in the page and returns a JS array of matched elements.
# The spec arrives as a JSON array; NULL qualifiers are omitted from the
# JSON entirely, so JS sees them as undefined.
loc_resolver_js <- "(function(specs) {
  const collapse = (s) => s.replace(/\\s+/g, ' ');
  const matchesText = (el, text) =>
    text == null || collapse(el.textContent).indexOf(collapse(text)) !== -1;

  // Resolve one spec to a deduped array of elements, in DOM order.
  const resolveSpec = (spec) => {
    let roots;
    if (spec.within) {
      roots = resolveSpec(spec.within);
      if (roots.length === 0) return [];
    } else {
      roots = [document];
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
})"

# The scope seam: the resolver JS takes its roots as an argument, so the
# same function object covers every rooting. Today the only root is
# `document`, reached via `Runtime$evaluate`; scoped contexts will
# instead invoke the same JS through `Runtime$callFunctionOn`, passing
# pinned element handles as the root argument.
loc_resolver_expr <- function(locs) {
  specs <- jsonlite::toJSON(lapply(locs, loc_spec_fields), auto_unbox = TRUE)
  paste0("(", loc_resolver_js, ")(\n", specs, "\n)")
}

# The target = NULL seam, shared by expect_impl() and get_impl(): NULL
# means the current context, which today is the root, where it stands
# for the implicit document.body element -- a one-element JS array that
# resolves without the loc resolver. The scoping task revisits this.
target_resolver_expr <- function(target, call = caller_env()) {
  if (is.null(target)) {
    return(list(expr = "[document.body]", description = "document.body"))
  }
  locs <- as_loc_list(target, call = call)
  list(expr = loc_resolver_expr(locs), description = format_loc(locs))
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
#' The resolver expression is built once; each poll iteration is then a
#' single `Runtime$evaluate` (with `returnByValue = FALSE`), and the
#' `callFunctionOn` count read happens only once a match exists -- an
#' empty set comes back as JS `null`, so there is no empty remote object
#' to read or release. `target = NULL` follows the target seam
#' (target_resolver_expr()): the current context is the root, which
#' resolves to document.body. Per-command timeouts are the page's
#' `default_timeout`, separate from the wait budget. The result holds the
#' objectId of the remote element array; free it with release_elements().
#'
#' @noRd
loc_resolve <- function(
  ctx,
  target,
  ...,
  timeout = NULL,
  multiple = c("error", "all"),
  call = caller_env()
) {
  check_context(ctx, call = call)
  check_dots_empty()
  multiple <- arg_match(multiple)
  target_expr <- target_resolver_expr(target, call = call)
  expr <- target_expr$expr
  description <- target_expr$description
  timeout <- resolve_timeout(timeout, ctx$page, call = call)

  resolved <- NULL
  pz_poll(
    fn = function() {
      res <- loc_resolve_once(ctx, expr, description, call)
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
#' Evaluates the resolver expression once. JS `null` (empty match set,
#' no objectId) becomes a zero-count elements object with no handle; a
#' match runs one `callFunctionOn` length read and returns the live
#' handle. Each CDP command gets the page's `default_timeout`; a chromote
#' command timeout is re-raised as a `paparazzi_error_timeout` naming the
#' description, with the original error as its parent.
#'
#' @noRd
loc_resolve_once <- function(ctx, expr, description, call) {
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

  res <- run_cdp(ctx$page$session$Runtime$evaluate(
    expr,
    awaitPromise = FALSE,
    returnByValue = FALSE,
    timeout_ = timeout
  ))
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
    # The resolver returns `null` for an empty set, so no handle exists.
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

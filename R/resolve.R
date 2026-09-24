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
  return out;
})"

# The scope seam: the resolver expression is built in exactly one place.
# Scoped contexts (the pz_find*() task) will root the resolver at pinned
# handles instead of `document`; that change happens here alone.
loc_resolver_expr <- function(locs) {
  specs <- jsonlite::toJSON(lapply(locs, loc_spec_fields), auto_unbox = TRUE)
  paste0("(", loc_resolver_js, ")(\n", specs, "\n)")
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
#' Each poll iteration is one `Runtime$evaluate` (with
#' `returnByValue = FALSE`) plus one `callFunctionOn` to read the match
#' count. Per-command timeouts are the session default, not the remaining
#' wait budget. Empty handles are released before the next iteration so
#' auto-wait doesn't accumulate them. The result holds the objectId of
#' the remote element array; free it with release_elements().
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
  check_context(ctx)
  check_dots_empty()
  multiple <- arg_match(multiple)
  locs <- as_loc_list(target, call = call)
  description <- format_loc(locs)
  timeout <- resolve_timeout(timeout, ctx$page, call = call)
  expr <- loc_resolver_expr(locs)

  resolved <- NULL
  pz_poll(
    fn = function() {
      res <- ctx$page$session$Runtime$evaluate(
        expr,
        awaitPromise = FALSE,
        returnByValue = FALSE
      )
      err <- res$exceptionDetails
      if (!is.null(err)) {
        cli::cli_abort(
          "JavaScript error while resolving {description}: {err$exception$description %||% err$text %||% 'unknown error'}.",
          class = "paparazzi_error_js",
          call = call
        )
      }
      object_id <- res$result$objectId
      count <- ctx$page$session$Runtime$callFunctionOn(
        "function() { return this.length; }",
        objectId = object_id,
        returnByValue = TRUE
      )$result$value
      if (count == 0) {
        # Release the empty handle so auto-waiting doesn't accumulate them.
        ctx$page$session$Runtime$releaseObject(object_id)
        FALSE
      } else {
        resolved <<- new_elements(ctx$page, object_id, count, description)
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

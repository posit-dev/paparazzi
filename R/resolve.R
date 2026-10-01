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
  els = els.filter((el) => el.closest('#%s') === null);
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

const seen = new Set();
const out = [];
for (const spec of specs) {
  for (const el of resolveSpec(spec)) {
    if (!seen.has(el)) { seen.add(el); out.push(el); }
  }
}
return out.length ? out : null;
})",
    specs,
    OVERLAY_HOST_ID
  )
}

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

# A spec as a plain nested list (jsonlite won't serialize classed lists).
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

loc_resolve_once <- function(
  ctx,
  fn,
  description,
  call = caller_env(),
  root = NULL,
  object_group = NULL
) {
  timeout <- ctx$page$default_timeout

  if (is.null(root)) {
    res <- cdp_call(
      ctx$page$session$Runtime$evaluate(
        paste0("(", fn, ").call([document])"),
        awaitPromise = FALSE,
        returnByValue = FALSE,
        objectGroup = object_group,
        timeout_ = timeout
      ),
      timeout,
      paste("resolving", description),
      call = call
    )
  } else {
    res <- cdp_call(
      ctx$page$session$Runtime$callFunctionOn(
        fn,
        objectId = root$object_id,
        returnByValue = FALSE,
        objectGroup = object_group,
        timeout_ = timeout
      ),
      timeout,
      paste("resolving", description),
      call = call
    )
  }
  cdp_check_exception(res, paste("resolving", description), call = call)
  object_id <- res$result$objectId
  if (is.null(object_id)) {
    return(new_elements(ctx$page, NULL, 0L, description))
  }
  count <- cdp_call(
    ctx$page$session$Runtime$callFunctionOn(
      "function() { return this.length; }",
      objectId = object_id,
      returnByValue = TRUE,
      timeout_ = timeout
    ),
    timeout,
    paste("resolving", description),
    call = call
  )$result$value
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

# Getters end the chain: they return values, not the context. The
# target-based ones share get_impl(), which auto-waits for at least one
# match via loc_resolve(), reads values through a `read` callback that
# may assume a live handle, and releases the handle on exit. Per the
# confirmed signatures they take no `timeout` argument: the auto-wait
# runs on the session default timeout.

# Driver for the target-based getters. `read(els)` pulls values into R;
# it never sees an empty set, because loc_resolve() errors on timeout.
# `target = NULL` means the current context: at a scoped context that is
# the pinned set itself, used as-is, never released (its scope owns it),
# and detach-checked here once; at the root, NULL keeps the implicit
# document.body meaning through loc_resolve(). Explicit targets resolve
# lazily inside the current scope -- loc_resolve() probes the scope once
# per call.
get_impl <- function(ctx, target, timeout, read, call = caller_env()) {
  if (is.null(target)) {
    scoped <- scope_root(ctx, call = call)
    if (!is.null(scoped)) {
      return(read(scoped))
    }
  }
  els <- loc_resolve(
    ctx,
    target,
    timeout = timeout,
    multiple = "all",
    call = call
  )
  on.exit(release_elements(els), add = TRUE)
  read(els)
}

# JS null/undefined reads become NA_character_, preserving positions:
# unlist() silently drops NULLs.
chr_or_na <- function(x) {
  vapply(
    x,
    function(v) if (is.null(v)) NA_character_ else as.character(v),
    character(1)
  )
}

# Pin one single-element set off a matched array: the element column's
# per-match scope. The slice is tagged with the page's object group, so
# it outlives the getter's transient handle and is released with every
# other pinned object; the array it was sliced from stays with its
# caller. `i` is 1-based, so it always picks a live element.
pin_match_id <- function(els, i, call = caller_env()) {
  timeout <- els$page$default_timeout
  res <- tryCatch(
    els$page$session$Runtime$callFunctionOn(
      paste0("function() { return [this[", i, " - 1]]; }"),
      objectId = els$object_id,
      returnByValue = FALSE,
      objectGroup = els$page$object_group,
      timeout_ = timeout
    ),
    error = function(e) {
      if (grepl("timed out", conditionMessage(e), ignore.case = TRUE)) {
        cli::cli_abort(
          "Timed out after {timeout}s pinning match {i} of {els$description}.",
          class = "paparazzi_error_timeout",
          call = call,
          parent = e
        )
      }
      stop(e)
    }
  )
  err <- res$exceptionDetails
  if (!is.null(err)) {
    cli::cli_abort(
      "JavaScript error while pinning match {i} of {els$description}: {err$exception$description %||% err$text %||% 'unknown error'}.",
      class = "paparazzi_error_js",
      call = call
    )
  }
  res$result$objectId
}

# Wrap one pinned match as the element column's entry: a context whose
# stack is the getter context's whole stack plus that match. The
# description narrows the getter's locs with `which = i`, so a later
# detach names the row. One extra CDP round trip per match, accepted:
# contexts sharing the getter's array handle would break the uniform
# one-array-per-scope wrapper contract.
pin_match <- function(ctx, els, locs, i, call = caller_env()) {
  pinned <- new_pinned(
    els$page,
    pin_match_id(els, i, call = call),
    1L,
    narrow_description(locs, els$description, i),
    locs = narrow_locs(locs, i)
  )
  push_scope(ctx, pinned)
}

# The locs the per-match element scopes narrow from: the promoted
# target for an explicit target, and the scope's own locs for
# target = NULL on a scoped context (the pinned set itself). At the
# root, target = NULL is the provisional document.body match, whose
# single element is the body.
get_element_locs <- function(els, target, call = caller_env()) {
  if (is.null(target)) {
    if (inherits(els, "paparazzi_pinned")) {
      els$locs
    } else {
      list(pz_loc("body"))
    }
  } else {
    as_loc_list(target, call = call)
  }
}

# Tibble factory for the getters: while the getter's transient handle
# is still live (inside get_impl()'s read, before the on-exit release),
# pin one single-element set per match off the matched array and store
# one context per match in the trailing `element` list-column.
new_get_tibble <- function(ctx, els, target, ..., call = caller_env()) {
  out <- tibble::tibble(...)
  locs <- get_element_locs(els, target, call = call)
  out$element <- lapply(
    seq_len(els$count),
    function(i) pin_match(ctx, els, locs, i, call = call)
  )
  out
}

#' Count matching elements
#'
#' `pz_get_count()` returns the number of elements matching `target`,
#' counted inside the current scope. Unlike the other getters it
#' doesn't wait for a match: `0` is a valid answer, so it resolves once
#' and returns immediately. One exception: on a scope whose pinned
#' elements have left the page it raises `paparazzi_error_detached`
#' instead of returning `0`, because the pinned set promises a live set
#' and is never silently re-queried.
#'
#' @param ctx A paparazzi context.
#' @param ... Checked empty; reserved for future use.
#' @param target A CSS selector string, a [pz_loc()] spec, or a list of
#'   specs and strings (a union matching any of them). `NULL` means the
#'   current context: the pinned set at a scoped context, whose count
#'   comes back without a re-query, or the page body at the root.
#' @return An integer.
#' @export
pz_get_count <- function(ctx, ..., target = NULL) {
  check_dots_empty()
  call <- current_env()
  check_context(ctx, call = call)
  resolved <- target_resolver_expr(target, call = call)
  # One use, one check: the scope is probed once per call, so a
  # detached scope raises its classed error through the count getter
  # too instead of counting nothing.
  root <- scope_root(ctx, call = call)
  if (is.null(target) && !is.null(root)) {
    # The scope's own count, without re-querying the pinned set.
    return(root$count)
  }
  els <- loc_resolve_once(
    ctx,
    resolved$fn,
    resolved$description,
    call = call,
    root = root
  )
  on.exit(release_elements(els), add = TRUE)
  els$count
}

#' Read the text of matching elements
#'
#' `pz_get_text()` returns the `textContent` of every element matching
#' `target`, one entry per match. By default runs of whitespace are
#' collapsed to single spaces and trimmed, matching `pz_expect_text()`;
#' `raw = TRUE` returns the text exactly as the browser holds it.
#'
#' @param ctx A paparazzi context.
#' @param ... Checked empty; reserved for future use.
#' @param target A CSS selector string, a [pz_loc()] spec, or a list of
#'   specs and strings (a union matching any of them). `NULL` means the
#'   current context: the pinned set at a scoped context, or the page
#'   body at the root.
#' @param raw Return the text without collapsing whitespace?
#' @return A character vector, one entry per match.
#' @export
pz_get_text <- function(ctx, ..., target = NULL, raw = FALSE) {
  check_dots_empty()
  check_bool(raw)
  call <- current_env()
  get_impl(
    ctx = ctx,
    target = target,
    timeout = NULL,
    read = function(els) {
      texts <- els_call(els, expect_text_js, call = call)
      if (raw) texts else collapse_ws(texts)
    },
    call = call
  )
}

#' Read the value of matching elements
#'
#' `pz_get_value()` returns the `value` property of every element
#' matching `target`, one entry per match. Elements without a value
#' property (non-form elements) give `NA`.
#'
#' @param ctx A paparazzi context.
#' @param ... Checked empty; reserved for future use.
#' @param target A CSS selector string, a [pz_loc()] spec, or a list of
#'   specs and strings (a union matching any of them). `NULL` means the
#'   current context: the pinned set at a scoped context, or the page
#'   body at the root.
#' @return A character vector, one entry per match.
#' @export
pz_get_value <- function(ctx, ..., target = NULL) {
  check_dots_empty()
  call <- current_env()
  get_impl(
    ctx = ctx,
    target = target,
    timeout = NULL,
    read = function(els) chr_or_na(els_values(els, get_value_js, call = call)),
    call = call
  )
}

#' Read an attribute of matching elements
#'
#' `pz_get_attr()` returns the named attribute of every element matching
#' `target`, one entry per match. Missing attributes give `NA`.
#'
#' @param ctx A paparazzi context.
#' @param name The attribute name.
#' @param ... Checked empty; reserved for future use.
#' @param target A CSS selector string, a [pz_loc()] spec, or a list of
#'   specs and strings (a union matching any of them). `NULL` means the
#'   current context: the pinned set at a scoped context, or the page
#'   body at the root.
#' @return A character vector, one entry per match.
#' @export
pz_get_attr <- function(ctx, name, ..., target = NULL) {
  check_dots_empty()
  check_string(name)
  call <- current_env()
  # The name reaches JS JSON-encoded, so quotes and specials can't break
  # out of the function string.
  js <- paste0(
    "function() { return this.map((el) => el.getAttribute(",
    jsonlite::toJSON(name, auto_unbox = TRUE),
    ")); }"
  )
  get_impl(
    ctx = ctx,
    target = target,
    timeout = NULL,
    read = function(els) chr_or_na(els_values(els, js, call = call)),
    call = call
  )
}

#' Read the geometry of matching elements
#'
#' `pz_get_rect()` returns the bounding box of every element matching
#' `target`, one row per match in match order.
#'
#' @param ctx A paparazzi context.
#' @param ... Checked empty; reserved for future use.
#' @param target A CSS selector string, a [pz_loc()] spec, or a list of
#'   specs and strings (a union matching any of them). `NULL` means the
#'   current context: the pinned set at a scoped context, or the page
#'   body at the root.
#' @return A tibble with columns `x`, `y`, `width`, `height` (doubles,
#'   CSS pixels, viewport-relative), one row per match, plus an
#'   `element` list-column. Each `element` entry is a context scoped
#'   to that one match, pinned at get time, so a chain can continue
#'   from it: `rects$element[[2]] |> pz_hover()`.
#' @export
pz_get_rect <- function(ctx, ..., target = NULL) {
  check_dots_empty()
  call <- current_env()
  get_impl(
    ctx = ctx,
    target = target,
    timeout = NULL,
    read = function(els) {
      rects <- el_rects(els, call = call)
      new_get_tibble(ctx, els, target, !!!rects, call = call)
    },
    call = call
  )
}

#' Describe matching elements
#'
#' `pz_get_elements()` returns a summary of every element matching
#' `target`, one row per match in match order: the lowercased tag name,
#' the `id` and `class` attributes, and the whitespace-collapsed text.
#' `id` and `class` are `NA` when the attribute is absent.
#'
#' @param ctx A paparazzi context.
#' @param ... Checked empty; reserved for future use.
#' @param target A CSS selector string, a [pz_loc()] spec, or a list of
#'   specs and strings (a union matching any of them). `NULL` means the
#'   current context: the pinned set at a scoped context, or the page
#'   body at the root.
#' @return A tibble with columns `tag`, `id`, `class`, `text`, one row
#'   per match, plus an `element` list-column of contexts scoped to
#'   each match, pinned at get time (see [pz_get_rect()]).
#' @export
pz_get_elements <- function(ctx, ..., target = NULL) {
  check_dots_empty()
  call <- current_env()
  get_impl(
    ctx = ctx,
    target = target,
    timeout = NULL,
    read = function(els) {
      vals <- els_values(els, get_elements_js, call = call)
      field <- function(name) chr_or_na(lapply(vals, `[[`, name))
      new_get_tibble(
        ctx,
        els,
        target,
        tag = field("tag"),
        id = field("id"),
        class = field("class"),
        text = collapse_ws(field("text")),
        call = call
      )
    },
    call = call
  )
}

#' Read the HTML of matching elements
#'
#' `pz_get_html()` returns the outer HTML of every element matching
#' `target`, one entry per match.
#'
#' @param ctx A paparazzi context.
#' @param ... Checked empty; reserved for future use.
#' @param target A CSS selector string, a [pz_loc()] spec, or a list of
#'   specs and strings (a union matching any of them). `NULL` means the
#'   current context: the pinned set at a scoped context, or the page
#'   body at the root.
#' @return A character vector, one entry per match.
#' @export
pz_get_html <- function(ctx, ..., target = NULL) {
  check_dots_empty()
  call <- current_env()
  get_impl(
    ctx = ctx,
    target = target,
    timeout = NULL,
    read = function(els) els_call(els, get_html_js, call = call),
    call = call
  )
}

#' Read the page URL
#'
#' `pz_get_url()` returns the page's current URL.
#'
#' @param ctx A paparazzi context.
#' @return A character vector of length one.
#' @export
pz_get_url <- function(ctx) {
  check_context(ctx)
  pz_js(ctx, "location.href")
}

#' Read the page title
#'
#' `pz_get_title()` returns the page's current title.
#'
#' @param ctx A paparazzi context.
#' @return A character vector of length one.
#' @export
pz_get_title <- function(ctx) {
  check_context(ctx)
  pz_js(ctx, "document.title")
}

get_value_js <- "function() {
  return this.map((el) => el.value === undefined ? null : String(el.value));
}"

# id/class come back as JS null when the attribute is absent, so the
# getter can map them to NA like pz_get_attr() does.
get_elements_js <- "function() {
  return this.map((el) => ({
    tag: el.tagName.toLowerCase(),
    id: el.getAttribute('id'),
    class: el.getAttribute('class'),
    text: el.textContent
  }));
}"

get_html_js <- "function() {
  return this.map((el) => el.outerHTML);
}"

# Getters end the chain: they return values, not the context. The
# target-based ones share get_impl(), which auto-waits for at least one
# match via loc_resolve(), reads values through a `read` callback that
# may assume a live handle, and releases the handle on exit. Per the
# confirmed signatures they take no `timeout` argument: the auto-wait
# runs on the session default timeout.

# Driver for the target-based getters. `read(els)` pulls values into R;
# it never sees an empty set, because loc_resolve() errors on timeout.
get_impl <- function(ctx, target, timeout, read, call = caller_env()) {
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

# Tibble factory for the getters: the trailing `element` list-column is
# reserved for the scoping task, which will pin one context per match.
# Until then it holds NULLs and is documented as not yet populated.
new_get_tibble <- function(..., n) {
  out <- tibble::tibble(...)
  out$element <- vector("list", n)
  out
}

#' Count matching elements
#'
#' `pz_get_count()` returns the number of elements matching `target`.
#' Unlike the other getters it doesn't wait for a match: `0` is a valid
#' answer, so it resolves once and returns immediately.
#'
#' @param ctx A paparazzi context.
#' @param ... Checked empty; reserved for future use.
#' @param target A CSS selector string, a [pz_loc()] spec, or a list of
#'   specs and strings (a union matching any of them). `NULL` means the
#'   page body.
#' @return An integer.
#' @export
pz_get_count <- function(ctx, ..., target = NULL) {
  check_dots_empty()
  call <- current_env()
  check_context(ctx, call = call)
  resolved <- target_resolver_expr(target, call = call)
  els <- loc_resolve_once(ctx, resolved$fn, resolved$description, call = call)
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
#'   page body.
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
#'   page body.
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
#'   page body.
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
#'   page body.
#' @return A tibble with columns `x`, `y`, `width`, `height` (doubles,
#'   CSS pixels, viewport-relative), one row per match, plus an
#'   `element` list-column. The `element` column is reserved for scoped
#'   contexts and is not yet populated.
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
      new_get_tibble(!!!rects, n = els$count)
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
#'   page body.
#' @return A tibble with columns `tag`, `id`, `class`, `text`, one row
#'   per match, plus an `element` list-column. The `element` column is
#'   reserved for scoped contexts and is not yet populated.
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
        tag = field("tag"),
        id = field("id"),
        class = field("class"),
        text = collapse_ws(field("text")),
        n = els$count
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
#'   page body.
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

#' Count matching elements
#'
#' [pz_get_count()] returns the number of elements matching `target`,
#' counted inside the current scope. Unlike the other getters it
#' doesn't wait for a match: `0` is a valid answer, so it resolves once
#' and returns immediately. One exception: on a scope whose pinned
#' elements have left the page it raises `paparazzi_error_detached`
#' instead of returning `0`, because the pinned set promises a live set
#' and is never silently re-queried.
#'
#' @inheritParams pz_act_click
#' @param target A CSS selector string, a [pz_loc()] spec, or a list of
#'   specs and strings (a union matching any of them). `NULL` means the
#'   current context: the pinned set at a scoped context, whose count
#'   comes back without a re-query, or the page body at the root.
#'
#' @return An integer.
#'
#' @examplesIf paparazzi:::examples_run(site = TRUE)
#' page <- pz_open(pz_example("tasks"))
#' pz_get_count(page, target = ".task")
#'
#' # Zero is an answer, so pz_get_count() never waits
#' pz_get_count(page, target = ".error-message")
#'
#' # Counts are relative to the current scope
#' page |>
#'   pz_find(".task-list") |>
#'   pz_get_count(target = ".task.done")
#' pz_close(page)
#'
#' @export
pz_get_count <- function(ctx, target = NULL, ...) {
  check_dots_empty()
  check_context(ctx)
  resolved <- target_resolver(target)
  root <- scope_connected(ctx)
  if (is.null(target) && !is.null(root)) {
    return(root$count)
  }
  els <- loc_resolve_once(
    ctx,
    resolved$fn,
    resolved$description,
    root = root
  )
  withr::defer(release_elements(els))
  els$count
}

#' Read the text of matching elements
#'
#' [pz_get_text()] returns the `textContent` of every element matching
#' `target`, one entry per match. By default runs of whitespace are
#' collapsed to single spaces and trimmed, matching [pz_expect_text()];
#' `raw = TRUE` returns the text exactly as the browser holds it.
#'
#' @param ctx A paparazzi context.
#' @param target A CSS selector string, a [pz_loc()] spec, or a list of
#'   specs and strings (a union matching any of them). `NULL` means the
#'   current context: the pinned set at a scoped context, or the page
#'   body at the root.
#' @param ... Checked empty; reserved for future use.
#' @param raw Return the text without collapsing whitespace?
#'
#' @return A character vector, one entry per match.
#'
#' @examplesIf paparazzi:::examples_run(site = TRUE)
#' page <- pz_open(pz_example("tasks"))
#' pz_get_text(page, target = "h1")
#'
#' # One string per match
#' pz_get_text(page, target = ".task[data-priority='high'] .task-title")
#'
#' # Whitespace is collapsed unless raw = TRUE
#' pz_get_text(page, target = "#help")
#' pz_get_text(page, target = "#help", raw = TRUE)
#' pz_close(page)
#'
#' @export
pz_get_text <- function(ctx, target = NULL, ..., raw = FALSE) {
  check_dots_empty()
  check_bool(raw)
  get_impl(
    ctx = ctx,
    target = target,
    timeout = NULL,
    read = function(els, call) {
      texts <- els_values_flat(els, expect_text_js, call = call)
      if (raw) texts else collapse_ws(texts)
    }
  )
}

#' Read the value of matching elements
#'
#' [pz_get_value()] returns the `value` property of every element
#' matching `target`, one entry per match. Elements without a value
#' property (non-form elements) give `NA`.
#'
#' @inheritParams pz_get_text
#'
#' @return A character vector, one entry per match.
#'
#' @examplesIf paparazzi:::examples_run(site = TRUE)
#' page <- pz_open(pz_example("tasks"))
#' page |> pz_act_type("Buy milk", target = "#task-title")
#' pz_get_value(page, target = list("#task-title", "#task-priority"))
#' pz_close(page)
#'
#' @export
pz_get_value <- function(ctx, target = NULL, ...) {
  check_dots_empty()
  get_impl(
    ctx = ctx,
    target = target,
    timeout = NULL,
    read = function(els, call) {
      chr_or_na(els_values(els, get_value_js, call = call))
    }
  )
}

#' Read an attribute of matching elements
#'
#' [pz_get_attr()] returns the named attribute of every element matching
#' `target`, one entry per match. Missing attributes give `NA`.
#'
#' @inheritParams pz_get_text
#' @param name The attribute name.
#'
#' @return A character vector, one entry per match.
#'
#' @examplesIf paparazzi:::examples_run(site = TRUE)
#' page <- pz_open(pz_example("tasks"))
#' pz_get_attr(page, "data-priority", target = ".task")
#'
#' # Missing attributes are NA
#' pz_get_attr(page, "aria-label", target = "select, input[type='text']")
#' pz_close(page)
#'
#' @export
pz_get_attr <- function(ctx, name, target = NULL, ...) {
  check_dots_empty()
  check_string(name)
  js <- paste0(
    "function() { return this.map((el) => el.getAttribute(",
    js_literal(name),
    ")); }"
  )
  get_impl(
    ctx = ctx,
    target = target,
    timeout = NULL,
    read = function(els, call) chr_or_na(els_values(els, js, call = call))
  )
}

#' Read the geometry of matching elements
#'
#' [pz_get_rect()] returns the bounding box of every element matching
#' `target`, one row per match in match order.
#'
#' @inheritParams pz_get_text
#'
#' @return A tibble with columns `x`, `y`, `width`, `height` (doubles,
#'   CSS pixels, viewport-relative), one row per match, plus an
#'   `element` list-column. Each `element` entry is a context scoped
#'   to that one match, pinned at get time, so a chain can continue
#'   from it: `rects$element[[2]] |> pz_act_hover()`.
#'
#' @examplesIf paparazzi:::examples_run(site = TRUE)
#' page <- pz_open(pz_example("tasks"))
#' rects <- pz_get_rect(page, target = ".filters a")
#' rects
#'
#' # Each row's element column is a context scoped to that match
#' rects$element[[3]] |>
#'   pz_act_click() |>
#'   pz_expect_url("#done")
#' pz_close(page)
#'
#' @export
pz_get_rect <- function(ctx, target = NULL, ...) {
  check_dots_empty()
  get_tibble_impl(ctx = ctx, target = target, read = el_rects)
}

#' Describe matching elements
#'
#' [pz_get_elements()] returns a summary of every element matching
#' `target`, one row per match in match order: the lowercased tag name,
#' the `id` and `class` attributes, and the whitespace-collapsed text.
#' `id` and `class` are `NA` when the attribute is absent.
#'
#' @inheritParams pz_get_text
#'
#' @return A tibble with columns `tag`, `id`, `class`, `text`, one row
#'   per match, plus an `element` list-column of contexts scoped to
#'   each match, pinned at get time (see [pz_get_rect()]).
#'
#' @examplesIf paparazzi:::examples_run(site = TRUE)
#' page <- pz_open(pz_example("tasks"))
#' pz_get_elements(page, target = "#new-task > *")
#' pz_close(page)
#'
#' @export
pz_get_elements <- function(ctx, target = NULL, ...) {
  check_dots_empty()
  get_tibble_impl(
    ctx = ctx,
    target = target,
    read = function(els, call) {
      vals <- els_values(els, get_elements_js, call = call)
      field <- function(name) chr_or_na(lapply(vals, `[[`, name))
      list(
        tag = field("tag"),
        id = field("id"),
        class = field("class"),
        text = collapse_ws(field("text"))
      )
    }
  )
}

#' Read the HTML of matching elements
#'
#' [pz_get_html()] returns the outer HTML of every element matching
#' `target`, one entry per match.
#'
#' @inheritParams pz_get_text
#'
#' @return A character vector, one entry per match.
#'
#' @examplesIf paparazzi:::examples_run(site = TRUE)
#' page <- pz_open(pz_example("tasks"))
#' pz_get_html(page, target = pz_loc(".task", which = "first"))
#' pz_close(page)
#'
#' @export
pz_get_html <- function(ctx, target = NULL, ...) {
  check_dots_empty()
  get_impl(
    ctx = ctx,
    target = target,
    timeout = NULL,
    read = function(els, call) els_values_flat(els, get_html_js, call = call)
  )
}

#' Read the page URL
#'
#' [pz_get_url()] returns the page's current URL.
#'
#' @inheritParams pz_act_click
#'
#' @return A character vector of length one.
#'
#' @examplesIf paparazzi:::examples_run(site = TRUE)
#' page <- pz_open(pz_example("tasks"))
#' page |> pz_act_click(pz_loc(".filters a", has_text = "Open"))
#' basename(pz_get_url(page))
#' pz_close(page)
#'
#' @export
pz_get_url <- function(ctx) {
  check_context(ctx)
  pz_js(ctx, "location.href")
}

#' Read the page title
#'
#' [pz_get_title()] returns the page's current title.
#'
#' @inheritParams pz_act_click
#'
#' @return A character vector of length one.
#'
#' @examplesIf paparazzi:::examples_run(site = TRUE)
#' page <- pz_open(pz_example("tasks"))
#' pz_get_title(page)
#' pz_close(page)
#'
#' @export
pz_get_title <- function(ctx) {
  check_context(ctx)
  pz_js(ctx, "document.title")
}

get_impl <- function(ctx, target, timeout, read, call = caller_env()) {
  if (is.null(target)) {
    scoped <- scope_connected(ctx, call = call)
    if (!is.null(scoped)) {
      return(read(scoped, call))
    }
  }
  els <- loc_resolve(
    ctx,
    target,
    timeout = timeout,
    multiple = "all",
    call = call
  )
  withr::defer(release_elements(els))
  read(els, call)
}

chr_or_na <- function(x) {
  map_chr(x, function(v) if (is.null(v)) NA_character_ else as.character(v))
}

pin_match_id <- function(els, i, call = caller_env()) {
  timeout <- els$page$default_timeout
  doing <- sprintf("pinning match %d of %s", i, els$description)
  res <- cdp_call(
    els$page$session$Runtime$callFunctionOn(
      paste0("function() { return [this[", i, " - 1]]; }"),
      objectId = els$object_id,
      returnByValue = FALSE,
      objectGroup = els$page$object_group,
      timeout_ = timeout
    ),
    timeout,
    doing,
    call
  )
  cdp_check_exception(res, doing, call)
  res$result$objectId
}

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

get_tibble_impl <- function(ctx, target, read, call = caller_env()) {
  get_impl(
    ctx = ctx,
    target = target,
    timeout = NULL,
    read = function(els, call) {
      out <- tibble::tibble(!!!read(els, call))
      locs <- get_element_locs(els, target, call = call)
      out$element <- lapply(
        seq_len(els$count),
        function(i) pin_match(ctx, els, locs, i, call = call)
      )
      out
    },
    call = call
  )
}

get_value_js <- "function() {
  return this.map((el) => el.value === undefined ? null : String(el.value));
}"

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

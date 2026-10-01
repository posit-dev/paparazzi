#' Set a bound Shiny input
#'
#' Uses the input's registered Shiny binding to update the visible control
#' and notify the server. The `id` is the complete DOM ID, including any
#' module prefix (for example, `"mod-text"`); it is searched only in the
#' current scope, including the scope element itself. This does not set
#' unbound inputs, action buttons, or file inputs.
#'
#' @inheritParams pz_act_click
#' @param id Full DOM ID of a bound Shiny input.
#' @param value Value accepted by the binding's `setValue()`. Date ranges
#'   accept `c(start, end)` or `list(start = ..., end = ...)`, with ISO date
#'   strings. Date-valued sliders accept ISO date strings, converted to
#'   JavaScript timestamps. Top-level `NULL` and atomic `NA` are rejected.
#' @param wait If `TRUE`, call [pz_wait_for_shiny_idle()] after the change.
#'   If `FALSE`, return immediately after dispatching the change.
#' @return `ctx`, invisibly.
#' @examplesIf paparazzi:::examples_run("shiny")
#' page <- pz_open(pz_example("tasks-app"))
#'
#' # Each call waits for Shiny to go idle, so the server has seen the value
#' page |>
#'   pz_set_shiny_input("title", "Buy milk") |>
#'   pz_set_shiny_input("priority", "high") |>
#'   pz_act_click("#add") |>
#'   pz_expect_text("3 tasks", target = "#summary")
#' pz_get_attr(page, "data-priority", target = ".task")
#' pz_close(page)
#'
#' @export
pz_set_shiny_input <- function(ctx, id, value, ..., wait = TRUE) {
  check_context(ctx)
  check_dots_empty()
  check_string(id)
  check_bool(wait)
  if (!nzchar(id)) {
    cli::cli_abort(
      "{.arg id} must not be empty.",
      class = "paparazzi_error_input"
    )
  }
  if (
    is.null(value) ||
      !(is.atomic(value) || is.list(value)) ||
      (is.atomic(value) && anyNA(value))
  ) {
    stop_input_type(value, "a non-missing atomic vector or list")
  }
  record_pre_action_loader(ctx)
  scoped <- scope_root(ctx)
  scope <- if (is.null(scoped)) "document" else scoped$description
  id_json <- as.character(jsonlite::toJSON(id, auto_unbox = TRUE))
  value_json <- as.character(jsonlite::toJSON(
    value,
    auto_unbox = TRUE,
    null = "null",
    digits = NA
  ))
  invocation <- paste0(
    "(",
    shiny_input_set_js,
    ").call(this, ",
    id_json,
    ", ",
    value_json,
    ")"
  )
  result <- if (is.null(scoped)) {
    pz_js(
      ctx,
      paste0(
        "(",
        shiny_input_set_js,
        ").call([document], ",
        id_json,
        ", ",
        value_json,
        ")"
      )
    )
  } else {
    els_values(
      scoped,
      paste0("function() { return ", invocation, "; }"),
      doing = "working with"
    )
  }
  if (identical(result, "invalid-date-range")) {
    cli::cli_abort(
      "Input {.val {id}} in scope {.val {scope}} requires two date-range endpoints.",
      class = "paparazzi_error_input"
    )
  }
  if (!identical(result, "ok")) {
    why <- if (identical(result, "unsupported")) {
      "does not support binding-based setting"
    } else {
      "has no bound Shiny input binding"
    }
    cli::cli_abort(
      "Input {.val {id}} in scope {.val {scope}} {why}.",
      class = "paparazzi_error_binding"
    )
  }
  if (wait) {
    pz_wait_for_shiny_idle(ctx)
  }
  ctx_return(ctx)
}

shiny_input_set_js <- "function(id, value) {
  const roots = this;
  const el = roots.flatMap(root => [root, ...root.querySelectorAll('[id]')])
    .find(node => node.id === id);
  if (!el || !window.jQuery || !window.Shiny) return 'missing';
  const $el = window.jQuery(el);
  const binding = $el.data('shinyInputBinding');
  if (!binding || typeof binding.setValue !== 'function') return 'missing';
  if (['shiny.fileInputBinding', 'shiny.actionButtonInput', 'bslib.task-button'].includes(binding.name)) return 'unsupported';
  if (binding.name === 'shiny.dateRangeInput') {
    if (Array.isArray(value)) {
      if (value.length !== 2) return 'invalid-date-range';
      value = {start: value[0], end: value[1]};
    }
    if (!value || typeof value !== 'object' ||
        !Object.hasOwn(value, 'start') || !Object.hasOwn(value, 'end')) return 'invalid-date-range';
  }
  if (binding.name === 'shiny.sliderInput') {
    const date = x => typeof x === 'string' && /^\\d{4}-\\d{2}-\\d{2}$/.test(x)
      ? new Date(x).getTime() : x;
    value = Array.isArray(value) ? value.map(date) : date(value);
  }
  binding.setValue(el, value);
  $el.trigger('change');
  return 'ok';
}"

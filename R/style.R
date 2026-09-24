# Computed-style reading and checking. Expected values are normalized
# through a probe element inside a closed shadow root, created and
# removed within the one synchronous JS call that reads the target, so
# the browser itself resolves em/%/currentColor against the same
# context the target sees -- and the probe is never observable in the
# app's DOM, and never paints. Vocabulary is "style", not "css": CSS already
# means selectors here, and the values compared are the applied
# (computed) styles, like Playwright's toHaveCSS() and jQuery's
# .css().
#' Read computed styles of matching elements
#'
#' [pz_get_style()] returns the **computed** styles of every element
#' matching `target` -- what the browser actually applied, the same
#' values Playwright's `toHaveCSS()` and jQuery's `.css()` read -- one
#' row per match in match order. Like all getters it auto-waits for at
#' least one match.
#'
#' Property names accept snake_case, converted to the CSS kebab-case
#' spelling (`font_size` becomes `font-size`, also the column name, so
#' select it with ``df$`font-size` ``); custom properties
#' (``"--bs-primary"``) pass through unchanged. `props = NULL` returns
#' every computed property the browser reports (longhands only).
#'
#' @param ctx A paparazzi context.
#' @param props A character vector of CSS property names, or `NULL` for
#'   all computed properties. With `NULL` the columns are the union of
#'   property names across matches, first-seen order (standard
#'   computed properties are the same for every element, but custom
#'   properties vary); a match that doesn't report a property reads as
#'   `""` (empty string).
#' @param ... Checked empty; reserved for future use.
#' @param target A CSS selector string, a [pz_loc()] spec, or a list of
#'   specs and strings (a union matching any of them). `NULL` means the
#'   current context: the pinned set at a scoped context, or the page
#'   body at the root.
#'
#' @return A tibble with one row per match, one character column per
#'   property, plus an `element` list-column: each entry is a context
#'   scoped to that one match, pinned at get time, so a chain can
#'   continue from it (see [pz_get_rect()]).
#'
#' @seealso [pz_expect_style()]
#'
#' @export
pz_get_style <- function(ctx, props = NULL, ..., target = NULL) {
  check_dots_empty()
  if (!is.null(props)) {
    check_character(props)
    props <- style_prop_name(props)
    style_check_shorthand(props)
    style_check_duplicated(props)
  }
  get_impl(
    ctx = ctx,
    target = target,
    timeout = NULL,
    read = function(els, call) {
      vals <- els_values(els, style_get_js(props), call = call)
      out_props <- if (is.null(props)) {
        # Union across matches, first-seen order: standard computed
        # properties are enumerated for every element, but a custom
        # property appears only where it's set or inherited, so the
        # first match's set can miss columns later matches have.
        unique(unlist(lapply(vals, names)))
      } else {
        props
      }
      # Missing = "" (empty string), not NA: the property simply
      # isn't in that match's computed style.
      cols <- lapply(
        out_props,
        function(p) vapply(vals, function(v) v[[p]] %||% "", character(1))
      )
      names(cols) <- out_props
      new_get_tibble(ctx, els, target, !!!cols, call = call)
    }
  )
}
#' Expect computed styles
#'
#' @description
#' [pz_expect_style()] passes when at least one element matches
#' `target` and every match has every named property set to the
#' expected value, comparing **computed** styles -- what the browser
#' actually applied, the same values Playwright's `toHaveCSS()` and
#' jQuery's `.css()` read.
#'
#' Property names accept snake_case, converted to the CSS kebab-case
#' spelling (`font_size` becomes `font-size`); custom properties
#' (`` `--bs-primary` = "#0d6efd" ``) pass through unchanged. By
#' default the expected values are normalized in the browser: what you
#' write (`"1.5rem"`, `"#0d6efd"`, `"50%"`, `"currentColor"`) is
#' resolved against the same context the target sees, so it matches
#' the computed value the browser reports. Numeric pixel values
#' compare with a 0.5px tolerance.
#'
#' Outside of testthat, a failure aborts with a classed error of class
#' `"paparazzi_expectation_failure"`; inside testthat, the failure is
#' reported as a test failure instead. See [pz_expect_exists()] for
#' the retry, timeout, and bridge behavior shared by all expectations.
#'
#' @details
#' With `not = TRUE` the expectation passes when at least one
#' property/value pair doesn't match (including when nothing matches).
#' With `normalize = FALSE` the expected values are compared as raw
#' strings against the browser's computed output, for contexts the
#' probe can't reproduce (unusual `%` cases, container query units);
#' the pixel tolerance still applies.
#'
#' Shorthand properties (`margin`, `border`, `background`, ...) are
#' unreliable in computed styles and error with a longhand suggestion;
#' check the longhand properties instead. A value the browser rejects
#' errors immediately as invalid CSS, without retrying (only detected
#' with `normalize = TRUE`).
#'
#' @inheritParams pz_click
#' @param ... Property/value pairs, e.g. `color = "red"`. Dynamic
#'   dots: a list spliced in with `!!!` works. Names are the CSS
#'   property names, snake_case accepted.
#' @inheritParams pz_expect_exists
#' @param normalize Normalize expected values in the browser before
#'   comparing? See Details.
#'
#' @return `ctx`, invisibly.
#' @examples
#' \dontrun{
#' page <- pz_open("https://example.com")
#' page |> pz_expect_style(color = "#0d6efd", target = ".btn-primary")
#' page |> pz_expect_style(font_size = "1rem", border_color = "currentColor", target = ".btn")
#' styles <- list(display = "block", margin_top = "0")
#' page |> pz_expect_style(!!!styles, target = "header")
#' }
#'
#' @seealso [pz_get_style()]
#'
#' @export
pz_expect_style <- function(
  ctx,
  ...,
  target = NULL,
  not = FALSE,
  timeout = NULL,
  normalize = TRUE
) {
  check_bool(normalize)
  pairs <- style_expect_pairs(list2(...), call = environment())
  expect_impl(
    ctx = ctx,
    target = target,
    not = not,
    timeout = timeout,
    check = check_style(pairs, not, normalize, call = environment()),
    description = expect_headline_style(pairs, not)
  )
}
# snake_case -> kebab-case; names starting with -- (custom properties)
# pass through untouched.
style_prop_name <- function(name) {
  ifelse(startsWith(name, "--"), name, gsub("_", "-", name, fixed = TRUE))
}
# Shorthands are unreliable in computed styles (and Chrome's computed
# style doesn't even enumerate them); the error points at longhands.
style_check_shorthand <- function(props, call = caller_env()) {
  bad <- intersect(props, style_shorthand_props)
  if (length(bad) == 0L) {
    return(invisible(NULL))
  }
  longhand <-
    style_shorthand_longhands[[bad[[1]]]] %||% "its longhand properties"
  cli::cli_abort(
    c(
      "{.val {bad[[1]]}} is a shorthand property; computed styles are unreliable for shorthands.",
      i = "Check the longhand properties instead, e.g. {.val {longhand}} for {.val {bad[[1]]}}."
    ),
    class = "paparazzi_error_input",
    call = call
  )
}
style_shorthand_props <- c(
  "animation", "background", "border", "border-image", "columns",
  "flex", "flex-flow", "font", "gap", "grid", "inset", "list-style",
  "margin", "mask", "outline", "overscroll-behavior", "padding",
  "place-content", "place-items", "place-self", "scroll-margin",
  "scroll-padding", "text-decoration", "text-emphasis", "transition"
)
style_shorthand_longhands <- c(
  animation = "animation-name, animation-duration",
  background = "background-color, background-image",
  border = "border-width, border-style, border-color",
  "border-image" = "border-image-source, border-image-width",
  columns = "column-count, column-width",
  flex = "flex-grow, flex-shrink, flex-basis",
  "flex-flow" = "flex-direction, flex-wrap",
  font = "font-size, font-family, font-weight",
  gap = "row-gap, column-gap",
  grid = "grid-template-columns, grid-template-rows",
  inset = "top, right, bottom, left",
  "list-style" = "list-style-type, list-style-position",
  margin = "margin-top, margin-right, margin-bottom, margin-left",
  mask = "mask-image, mask-size",
  outline = "outline-width, outline-style, outline-color",
  "overscroll-behavior" = "overscroll-behavior-x, overscroll-behavior-y",
  padding = "padding-top, padding-right, padding-bottom, padding-left",
  "place-content" = "align-content, justify-content",
  "place-items" = "align-items, justify-items",
  "place-self" = "align-self, justify-self",
  "scroll-margin" = "scroll-margin-top, scroll-margin-left",
  "scroll-padding" = "scroll-padding-top, scroll-padding-left",
  "text-decoration" = "text-decoration-line, text-decoration-color",
  "text-emphasis" = "text-emphasis-style, text-emphasis-color",
  transition = "transition-property, transition-duration"
)
style_check_duplicated <- function(props, call = caller_env()) {
  i <- anyDuplicated(props)
  if (i > 0L) {
    cli::cli_abort(
      "Duplicated style property {.val {props[[i]]}}.",
      class = "paparazzi_error_input",
      call = call
    )
  }
  invisible(NULL)
}
# The ... pairs: at least one, all named, all string values. Returns a
# named character vector, names normalized to CSS property names.
style_expect_pairs <- function(dots, call = caller_env()) {
  if (length(dots) == 0L) {
    cli::cli_abort(
      "{.arg ...} must hold at least one property/value pair, e.g. {.code color = \"red\"}.",
      class = "paparazzi_error_input",
      call = call
    )
  }
  nms <- names(dots)
  if (is.null(nms) || any(!nzchar(nms))) {
    cli::cli_abort(
      "Every style pair must be named, like {.code color = \"red\"}.",
      class = "paparazzi_error_input",
      call = call
    )
  }
  values <- vapply(
    dots,
    function(v) if (is_string(v)) v else NA_character_,
    character(1)
  )
  if (anyNA(values)) {
    cli::cli_abort(
      "Style values must be strings, e.g. {.code color = \"red\"}.",
      class = "paparazzi_error_input",
      call = call
    )
  }
  names(values) <- style_prop_name(nms)
  style_check_shorthand(names(values), call = call)
  style_check_duplicated(names(values), call = call)
  values
}
# One expectation check: reads the target's computed values and, when
# normalizing, resolves the expected values through the probe, in one
# synchronous JS call. Comparison happens in R (see the expectation
# core note): the classed failure gets real last-seen values.
check_style <- function(pairs, not, normalize, call = caller_env()) {
  js <- style_expect_js(pairs, normalize)
  props <- names(pairs)
  function(els) {
    if (els$count == 0L) {
      return(list(pass = not, observed = expect_seen_count(0L)))
    }
    vals <- els_values(els, js)
    style_abort_invalid(vals, pairs, call = call)
    hits <- style_hits(vals, pairs, normalize)
    pass <- if (not) !all(hits) else all(hits)
    list(pass = pass, observed = style_observed(vals, props))
  }
}
# Invalid CSS aborts immediately, outside the retry loop: the browser's
# verdict on a declaration never changes. Acceptance is a property of
# the (property, value) pair, so the first match's answers decide.
style_abort_invalid <- function(vals, pairs, call = caller_env()) {
  for (p in seq_along(pairs)) {
    if (identical(vals[[1]][[p]]$accepted, FALSE)) {
      cli::cli_abort(
        "Invalid CSS: the browser rejects {.val {pairs[[p]]}} for {.val {names(pairs)[[p]]}}.",
        class = "paparazzi_error_input",
        call = call
      )
    }
  }
  invisible(NULL)
}
# Comparison matrix [match, pair]: identical strings pass; px values
# compare numerically with a 0.5px tolerance; anything else is exact.
style_hits <- function(vals, pairs, normalize) {
  out <- matrix(TRUE, nrow = length(vals), ncol = length(pairs))
  for (e in seq_along(vals)) {
    for (p in seq_along(pairs)) {
      actual <- vals[[e]][[p]]$actual %||% ""
      expected <- if (normalize) vals[[e]][[p]]$normalized %||% "" else pairs[[p]]
      out[e, p] <- style_compare(actual, expected)
    }
  }
  out
}
style_compare <- function(actual, expected) {
  if (identical(actual, expected)) {
    return(TRUE)
  }
  a <- style_px(actual)
  e <- style_px(expected)
  !is.na(a) && !is.na(e) && abs(a - e) <= style_px_tolerance
}
style_px_tolerance <- 0.5
style_px <- function(x) {
  if (!is_string(x) || !grepl("^[+-]?[0-9]+(\\.[0-9]+)?px$", x)) {
    return(NA_real_)
  }
  as.numeric(sub("px$", "", x))
}
style_observed <- function(vals, props) {
  rows <- vapply(
    vals,
    function(el) {
      actuals <- vapply(el, function(v) v$actual %||% "", character(1))
      paste0(props, ": ", actuals, collapse = "; ")
    },
    character(1)
  )
  expect_truncate(paste0(rows, collapse = " | "))
}
expect_headline_style <- function(pairs, not) {
  what <- paste0(names(pairs), ": \"", pairs, "\"", collapse = ", ")
  paste0("Expected style", if (not) " not", " to match ", what)
}
# One synchronous callFunctionOn on the matched element array: read the
# targets, set the expected values inline on the probe, copy only the
# context each value needs (SPEC table), read the probe back. Nothing
# persists between calls: the probe host is created at the top of the
# call and removed in a finally block, so the app's DOM is untouched
# once the call returns.
style_expect_js <- function(pairs, normalize) {
  pairs_json <- jsonlite::toJSON(
    lapply(
      seq_along(pairs),
      function(i) list(prop = names(pairs)[[i]], value = unname(pairs)[[i]])
    ),
    auto_unbox = TRUE
  )
  paste0(
    "function() {\n",
    "const pairs = ", pairs_json, ";\n",
    "const normalize = ", if (normalize) "true" else "false", ";\n",
    style_probe_js,
    "}"
  )
}
style_probe_js <- "
  // The probe lives in a closed shadow root under a zero-size host at
  // the document root, for the duration of this one synchronous call
  // only: JS runs to completion, so no selector, :empty check, style
  // recalc, screenshot, or recording frame can ever observe the host.
  // The MutationObserver add/remove records are the accepted residual:
  // a rendered, attached probe is required for percentage resolution.
  // visibility: hidden keeps the subtree laid out (display: none would
  // leave raw percentages in the computed read) and zero size plus
  // overflow hidden means nothing ever paints.
  const host = document.createElement('div');
  host.style.cssText = 'position:fixed;left:0;top:0;width:0;height:0;overflow:hidden;visibility:hidden';
  document.documentElement.appendChild(host);
  const root = host.attachShadow({mode: 'closed'});
  const container = document.createElement('div');
  const probe = document.createElement('div');
  container.appendChild(probe);
  root.appendChild(container);
  try {
    return this.map((el) => {
      const cs = getComputedStyle(el);
      return pairs.map((p) => {
        const actual = cs.getPropertyValue(p.prop);
        if (!normalize) {
          return {actual: actual, normalized: null, accepted: true};
        }
        probe.style.cssText = '';
        container.style.cssText = '';
        probe.style.setProperty(p.prop, p.value);
        // An empty inline style means the browser rejected the
        // declaration (bad value or unknown property).
        if (probe.style.getPropertyValue(p.prop) === '') {
          return {actual: actual, normalized: null, accepted: false};
        }
        // Context needs are independent, not exclusive: calc(50% - 1em)
        // wants the parent's size and the element's font at once. The
        // contexts touch different container styles, so they compose.
        if (/currentcolor/i.test(p.value)) {
          container.style.color = cs.color;
        }
        const fontUnits = /[0-9.](em|ex|ch)([^a-z]|$)/i.test(p.value);
        const percent = p.value.indexOf('%') !== -1;
        // Relative units on font-size and line-height resolve against
        // fonts, not sizes: the parent's font for font-size (its em and
        // % context), the element's own font for line-height and every
        // other property.
        if (fontUnits || (percent && (p.prop === 'font-size' || p.prop === 'line-height'))) {
          const fcs = p.prop === 'font-size'
            ? getComputedStyle(el.parentElement || document.documentElement)
            : cs;
          container.style.fontSize = fcs.fontSize;
          container.style.fontFamily = fcs.fontFamily;
        }
        if (percent && p.prop !== 'font-size' && p.prop !== 'line-height') {
          const pcs = getComputedStyle(el.parentElement || document.documentElement);
          container.style.width = pcs.width;
          container.style.height = pcs.height;
        }
        return {
          actual: actual,
          normalized: getComputedStyle(probe).getPropertyValue(p.prop),
          accepted: true
        };
      });
    });
  } finally {
    host.remove();
  }
"
style_get_js <- function(props) {
  props_json <- if (is.null(props)) "null" else jsonlite::toJSON(props)
  paste0(
    "function() {
      const props = ", props_json, ";
      return this.map((el) => {
        const cs = getComputedStyle(el);
        const out = {};
        if (props === null) {
          for (let i = 0; i < cs.length; i++) {
            out[cs[i]] = cs.getPropertyValue(cs[i]);
          }
        } else {
          for (const p of props) {
            out[p] = cs.getPropertyValue(p);
          }
        }
        return out;
      });
    }"
  )
}

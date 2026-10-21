#' Share a regular expression across locators and expectations
#'
#' @description
#' Use [pz_regex()] to describe a text pattern for a locator or expectation. Set
#' `ignore_case = TRUE` to match "Save", "save", and "SAVE" alike. For a literal
#' substring rather than a regex pattern, use `fixed = TRUE`.
#'
#' Before comparing text, paparazzi replaces runs of whitespace with a single
#' space and removes whitespace at the start and end. It leaves your regex
#' pattern unchanged. Missing values never match, even with an empty pattern.
#'
#' Pass the pattern to a locator or an expectation to use it; the same pattern
#' applies to every selected element. paparazzi checks regex syntax when you use
#' the pattern, so an invalid pattern raises an error then, even if no elements
#' match your selector.
#'
#' @param pattern A single string containing a regular expression, or a literal
#'   substring when `fixed = TRUE`. Patterns use JavaScript regular expression
#'   syntax in Unicode-aware mode, not R's regex syntax. An empty pattern is
#'   valid. Use R string escaping, e.g. `"\\d+"` for digits.
#' @param ignore_case Ignore case differences when matching?
#' @param fixed Match `pattern` as a literal substring rather than a regular
#'   expression? With `fixed = TRUE`, characters such as `(`, `.`, and `*` match
#'   themselves rather than having their regex meanings. paparazzi collapses and
#'   trims whitespace in the substring as well as the text being checked. For
#'   exact literal matching, use a bare string instead of [pz_regex()].
#' @inheritParams pz_act_click
#'
#' @return A regular expression object of class `paparazzi_regex`. Supply this
#'   object on its own, not in a vector or list of patterns.
#' @seealso
#' * [pz_loc()] accepts a regex in `match` to find elements by their text.
#' * [pz_expect_text()], [pz_expect_value()], and [pz_expect_attr()] accept
#'   regexes to check element text, input values, and attributes.
#' * [pz_expect_url()] and [pz_expect_title()] accept regexes to check the
#'   page's URL and title.
#'
#' @examples
#' ready <- pz_regex("^Report \\d+ ready$", ignore_case = TRUE)
#' pz_loc(".report", match = ready)
#' pz_loc("button", match = "Save")
#' pz_loc("button", match = pz_regex("Save (draft)", fixed = TRUE))
#'
#' @export
pz_regex <- function(pattern, ..., ignore_case = FALSE, fixed = FALSE) {
  check_dots_empty()
  check_string(pattern)
  check_bool(ignore_case)
  check_bool(fixed)
  structure(
    list(pattern = pattern, ignore_case = ignore_case, fixed = fixed),
    class = "paparazzi_regex"
  )
}

#' @export
print.paparazzi_regex <- function(x, ...) {
  cli::cat_line("<paparazzi_regex> ", format_regex(x))
  invisible(x)
}

is_regex <- function(x) {
  inherits(x, "paparazzi_regex")
}

regex_spec_fields <- function(x) {
  list(
    type = "regex",
    pattern = x$pattern,
    ignore_case = x$ignore_case,
    fixed = x$fixed
  )
}

format_regex <- function(x) {
  paste0(
    "pz_regex(",
    encodeString(x$pattern, quote = '"'),
    if (x$ignore_case) ", ignore_case = TRUE",
    if (x$fixed) ", fixed = TRUE",
    ")"
  )
}

regex_js_helpers <- r"(const normalizeText = (value) => String(value).replace(/\s+/g, ' ').trim();
const matchesExact = (value, expected) => value != null &&
  normalizeText(value) === normalizeText(expected);
const compileRegex = (spec) => {
  const pattern = spec.fixed ?
    normalizeText(spec.pattern).replace(/[.*+?^${}()|[\]\\]/g, '\\$&') : spec.pattern;
  try {
    return new RegExp(pattern, spec.ignore_case ? 'iu' : 'u');
  } catch (err) {
    throw new Error('Invalid pz_regex(' + JSON.stringify(spec.pattern) + '): ' + String(err));
  }
};
const matchesRegex = (value, regex) => value != null &&
  regex.test(normalizeText(value));
)"

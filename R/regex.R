#' Share a regular expression across locators and expectations
#'
#' [pz_regex()] creates a scalar, page-independent matcher for [pz_loc()]'s
#' `match` and [pz_expect_text()], [pz_expect_value()], [pz_expect_attr()],
#' [pz_expect_url()], and [pz_expect_title()]. Chrome matches JavaScript
#' `RegExp` syntax in Unicode-aware mode. paparazzi collapses whitespace and
#' trims observed strings, but never changes regex pattern source.
#'
#' With `fixed = TRUE`, paparazzi treats `pattern` as a literal substring,
#' collapses and trims its whitespace, and escapes regex metacharacters.
#' Use a bare string instead of [pz_regex()] for exact literal matching.
#' Missing values do not match, even an empty pattern.
#'
#' Construction checks the inputs without opening a browser. Chrome checks
#' pattern syntax when you use the value, including when the target matches
#' no elements. One value applies to all selected elements; collections of
#' regex values and mixed string/regex vectors are not supported.
#'
#' @param pattern A single string of JavaScript regular expression source,
#'   or a literal substring when `fixed = TRUE`. An empty pattern is valid.
#'   Use R string escaping, e.g. `"\\d+"` for digits.
#' @param ignore_case Ignore case differences when matching?
#' @param fixed Match a literal substring rather than a regular expression?
#' @inheritParams pz_act_click
#'
#' @return An S3 object of class `paparazzi_regex`.
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

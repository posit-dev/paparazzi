#' Share a JavaScript regular expression across locators and expectations
#'
#' [pz_regex()] creates a scalar, page-independent matcher for
#' [pz_loc()]'s `has_text` and [pz_expect_text()], [pz_expect_value()],
#' [pz_expect_attr()], [pz_expect_url()], and [pz_expect_title()].
#' Chrome uses JavaScript `RegExp` syntax to match it. paparazzi collapses
#' whitespace and trims observed strings before matching, but never changes
#' the pattern source. Missing values do not match, even an empty pattern.
#'
#' A regex value carries its own matching semantics: `match` and `.match`
#' govern only plain strings. Existing string-based `match = "regex"`
#' and `.match = "regex"` expectations still use R's [grepl()] and their
#' existing whitespace normalization. Use a regex value to share a matcher
#' with a locator.
#'
#' Construction checks the inputs without opening a browser. Chrome checks
#' pattern syntax and flag support when you use the value, including when
#' the target matches no elements. One value applies to all selected elements;
#' collections of regex values and mixed string/regex vectors are not supported.
#'
#' @param pattern A single string of JavaScript regular expression source.
#'   An empty pattern is valid. Use R string escaping, e.g. `"\\d+"` for digits.
#' @param flags A single string of distinct JavaScript flags: `d`, `i`, `m`,
#'   `s`, `u`, or `v`. Matching is case-sensitive unless you include `i`.
#'   Stateful flags `g` and `y`, duplicate flags, and combining `u` with `v`
#'   are errors. Support for individual flags depends on your Chrome version.
#'
#' @return An S3 object of class `paparazzi_regex`, containing pattern and flags.
#' @examples
#' ready <- pz_regex("^Report \\d+ ready$", flags = "i")
#' pz_loc(".report", has_text = ready)
#' pz_loc("button", has_text = pz_regex("^Save$"))
#'
#' @export
pz_regex <- function(pattern, flags = "") {
  check_string(pattern)
  check_string(flags)
  chars <- strsplit(flags, "", fixed = TRUE)[[1]]
  if (any(chars %in% c("g", "y"))) {
    cli::cli_abort(
      "{.arg flags} must not include stateful flags {.val g} or {.val y}."
    )
  }
  if (!all(chars %in% c("d", "i", "m", "s", "u", "v"))) {
    cli::cli_abort(
      "{.arg flags} may contain only {.val d}, {.val i}, {.val m}, {.val s}, {.val u}, or {.val v}."
    )
  }
  if (anyDuplicated(chars)) {
    cli::cli_abort("{.arg flags} must not contain duplicate flags.")
  }
  if (all(c("u", "v") %in% chars)) {
    cli::cli_abort("{.arg flags} must not combine {.val u} and {.val v}.")
  }
  structure(list(pattern = pattern, flags = flags), class = "paparazzi_regex")
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
  list(type = "regex", pattern = x$pattern, flags = x$flags)
}

format_regex <- function(x) {
  paste0(
    "pz_regex(",
    encodeString(x$pattern, quote = '"'),
    ", flags = ",
    encodeString(x$flags, quote = '"'),
    ")"
  )
}

regex_js_helpers <- r"(const compileRegex = (spec) => {
  try {
    return new RegExp(spec.pattern, spec.flags);
  } catch (err) {
    throw new Error('Invalid pz_regex(' + JSON.stringify(spec.pattern) +
      ', flags = ' + JSON.stringify(spec.flags) + '): ' + String(err));
  }
};
const matchesRegex = (value, regex) => value != null &&
  regex.test(String(value).replace(/\s+/g, ' ').trim());
)"

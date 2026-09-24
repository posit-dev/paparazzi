#' Locate elements by CSS, with text, position, and scope qualifiers
#'
#' @description
#' [pz_loc()] builds a page-independent element spec: a CSS selector,
#' optionally narrowed by required text content (`has_text`), a match
#' position (`which`), and an ancestor scope (`within`). Specs are lazy --
#' they resolve at use time, so they follow DOM changes between uses --
#' and can be defined once and reused across sessions.
#'
#' Wherever a spec is accepted, a bare string is promoted to
#' `pz_loc(string)`, and a list of specs and strings is a union that
#' matches the elements of any member.
#'
#' @param css A CSS selector string.
#' @inheritParams pz_click
#' @param has_text Substring the element's text content must contain.
#'   Case-sensitive; whitespace collapses on both sides, so
#'   `has_text = "Save now"` matches text reading "Save   now".
#' @param which Pick one match by position: `"first"`, `"last"`, or a
#'   1-based positive integer. Applied after `css` and `has_text`
#'   filtering; an out-of-range position means *no* match, not an error.
#' @param within Only match descendants of elements matching this spec
#'   (a string or [pz_loc()], itself fully qualified). If `within`
#'   matches nothing, the whole spec matches nothing.
#'
#' @return An S3 object of class `paparazzi_loc`.
#' @examples
#' pz_loc("#chat_user_input .ProseMirror")
#' pz_loc(".shiny-chat-assistant-message", which = "last")
#' pz_loc(
#'   ".shiny-tool-request",
#'   has_text = "get_weather",
#'   which = "last",
#'   within = ".chat"
#' )
#'
#' @export
pz_loc <- function(css, ..., has_text = NULL, which = NULL, within = NULL) {
  check_dots_empty()
  check_string(css)
  if (!is.null(has_text)) {
    check_string(has_text)
  }
  if (!is.null(which)) {
    which <- check_which(which)
  }
  if (!is.null(within)) {
    within <- as_loc(within, arg = "within")
  }
  structure(
    list(css = css, has_text = has_text, which = which, within = within),
    class = "paparazzi_loc"
  )
}
#' @export
print.paparazzi_loc <- function(x, ...) {
  cli::cat_line("<paparazzi_loc> ", format_loc(x))
  invisible(x)
}
as_loc <- function(target, arg = caller_arg(target), call = caller_env()) {
  if (inherits(target, "paparazzi_loc")) {
    return(target)
  }
  if (is_string(target)) {
    return(pz_loc(target))
  }
  stop_input_type(
    target,
    "a CSS selector string or pz_loc() spec",
    arg = arg,
    call = call
  )
}
# A target accepted by the resolver: one spec, or a list of specs/strings
# (the union form). Names are dropped so the union serializes as a JSON
# array, not an object.
as_loc_list <- function(target, arg = caller_arg(target), call = caller_env()) {
  if (inherits(target, "paparazzi_loc")) {
    return(list(target))
  }
  if (is_list(target)) {
    if (length(target) == 0) {
      # An empty union matches nothing, so auto-waiting on it would never
      # resolve -- fail fast instead.
      cli::cli_abort(
        "{.arg {arg}} can't be an empty list of targets; it matches nothing, so there would be nothing to wait for.",
        class = "paparazzi_error_target",
        call = call
      )
    }
    return(unname(lapply(target, as_loc, arg = arg, call = call)))
  }
  list(as_loc(target, arg = arg, call = call))
}
# Target description, e.g.
#   `.shiny-tool-request` (has_text: "get_weather", which: last, within: `.chat`)
# Qualifiers appear in a fixed order; `within` is recursive. Used by the
# resolver errors, the print method, and (later) expectation failures and
# the detached-scope error.
format_loc <- function(loc) {
  if (is_list(loc) && !inherits(loc, "paparazzi_loc")) {
    # Union target: one description per spec, in order.
    return(paste(vapply(loc, format_loc, character(1)), collapse = " | "))
  }
  if (!inherits(loc, "paparazzi_loc")) {
    # Only promoted targets reach here; a bare string would otherwise be
    # treated as a union and recursed on forever.
    cli::cli_abort(
      "Internal error: the target must be a {.fn pz_loc} spec or a list of specs, not {.obj_type_friendly {loc}}. Promote it with {.fn as_loc_list} first.",
      class = "paparazzi_error_internal"
    )
  }
  out <- paste0("`", loc$css, "`")
  quals <- character()
  if (!is.null(loc$has_text)) {
    quals <- c(quals, paste0('has_text: "', loc$has_text, '"'))
  }
  if (!is.null(loc$which)) {
    quals <- c(quals, paste0("which: ", loc$which))
  }
  if (!is.null(loc$within)) {
    quals <- c(quals, paste0("within: ", format_loc(loc$within)))
  }
  if (length(quals)) {
    out <- paste0(out, " (", paste(quals, collapse = ", "), ")")
  }
  out
}

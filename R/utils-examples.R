examples_run <- function(...) {
  rlang::is_interactive() &&
    !is.null(suppressMessages(chromote::find_chrome())) &&
    all(vapply(c(...), rlang::is_installed, logical(1)))
}

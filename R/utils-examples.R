examples_run <- function(..., site = FALSE) {
  check_bool(site)
  (rlang::is_interactive() || (site && in_pkgdown())) &&
    !is.null(suppressMessages(chromote::find_chrome())) &&
    all(vapply(c(...), rlang::is_installed, logical(1)))
}

in_pkgdown <- function() {
  rlang::is_installed("pkgdown") && pkgdown::in_pkgdown()
}

if (isTRUE(as.logical(Sys.getenv("CI")))) {
  # Best-effort warm-up; the browser tests still verify successful startup.
  try(pz_with_page("about:blank", function(page) {
    pz_js(page, "document.readyState")
  }))
}

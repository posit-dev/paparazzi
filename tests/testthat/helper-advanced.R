advanced_fixture_file <- function() {
  test_path("fixtures", "advanced.html")
}

# Open the advanced interactions fixture and close it when the calling
# test exits.
local_advanced_page <- function(.env = parent.frame()) {
  local_page(advanced_fixture_file(), .env = .env)
}

# The advanced fixture records real browser events into window
# .__pzAdvLog: one entry per event, {type, id, isTrusted}. isTrusted
# separates CDP-dispatched input from JS-synthesized events.
adv_log <- function(page) {
  pz_js(page, "window.__pzAdvLog")
}

# Log entry types, optionally narrowed to one element id.
adv_log_types <- function(log, id = NULL) {
  keep <- vapply(
    log,
    function(e) is.null(id) || identical(e$id, id),
    logical(1)
  )
  vapply(log[keep], function(e) e$type, character(1))
}

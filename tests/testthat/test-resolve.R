test_that("loc_resolve promotes a bare string", {
  page <- local_elements_page()
  els <- loc_resolve(page, ".btn", multiple = "all")
  withr::defer(release_elements(els))
  expect_s3_class(els, "paparazzi_elements")
  expect_identical(els$count, 6L)
  expect_identical(els$description, "`.btn`")
  expect_identical(els$page, page)
  expect_false(is.null(els$object_id))
})

test_that("loc_resolve checks its inputs", {
  page <- local_elements_page()
  expect_error(loc_resolve(page, ".btn", extra = 1), "empty")
  expect_error(loc_resolve(page, 1, timeout = 0), "CSS selector")
  expect_error(
    loc_resolve("not a page", ".btn", timeout = 0),
    class = "paparazzi_error_context"
  )
})

test_that("loc_resolve resolves has_text, collapsed and case-sensitive", {
  page <- local_elements_page()
  els <- loc_resolve(page, pz_loc(".btn", has_text = "Save"), multiple = "all")
  withr::defer(release_elements(els))
  expect_identical(els$count, 3L)
  expect_identical(elements_text(els), c("Save", "Save   now", "Save"))

  # Whitespace collapses on both sides of the match.
  collapsed <- loc_resolve(
    page,
    pz_loc(".btn", has_text = "Save   now"),
    multiple = "all"
  )
  withr::defer(release_elements(collapsed))
  expect_identical(collapsed$count, 1L)
  expect_identical(elements_text(collapsed), "Save   now")

  # Case-sensitive: "save" matches nothing.
  expect_error(
    loc_resolve(page, pz_loc(".btn", has_text = "save"), timeout = 0),
    class = "paparazzi_error_timeout"
  )
})

test_that("loc_resolve applies which after filtering", {
  page <- local_elements_page()
  # .message makes first and last distinguishable: first is the user's
  # question, last is the final assistant reply.
  first <- loc_resolve(page, pz_loc(".message", which = "first"))
  withr::defer(release_elements(first))
  expect_identical(first$count, 1L)
  expect_identical(elements_text(first), "What's the weather?")

  last <- loc_resolve(page, pz_loc(".message", which = "last"))
  withr::defer(release_elements(last))
  expect_identical(last$count, 1L)
  expect_identical(elements_text(last), "Bring a hat.")

  nth <- loc_resolve(page, pz_loc(".btn", which = 2))
  withr::defer(release_elements(nth))
  expect_identical(nth$count, 1L)
  expect_identical(elements_text(nth), "Cancel")
})

test_that("which applies after has_text filtering", {
  page <- local_elements_page()
  # Matching .btn[has_text = Save] is "Save", "Save   now", "Save"; which = 2
  # picks the second *filtered* match, not the second .btn overall.
  els <- loc_resolve(page, pz_loc(".btn", has_text = "Save", which = 2))
  withr::defer(release_elements(els))
  expect_identical(els$count, 1L)
  expect_identical(elements_text(els), "Save   now")
})

test_that("an out-of-range which means no match, checked once", {
  page <- local_elements_page()
  start <- Sys.time()
  expect_error(
    loc_resolve(page, pz_loc(".btn", which = 100), timeout = 0),
    class = "paparazzi_error_timeout"
  )
  # timeout = 0 is "check once": pz_poll evaluates fn() before the deadline
  # check, so this returns as fast as a single JS round-trip.
  expect_lt(as.numeric(difftime(Sys.time(), start, units = "secs")), 1)
})

test_that("loc_resolve scopes within a container, recursively", {
  page <- local_elements_page()
  els <- loc_resolve(
    page,
    pz_loc(".btn", within = "#panel-inner"),
    multiple = "all"
  )
  withr::defer(release_elements(els))
  expect_identical(els$count, 2L)
  expect_identical(elements_text(els), c("Save   now", "Reset"))

  # Nested containers: descendants of any .panel, deduped across roots.
  nested <- loc_resolve(
    page,
    pz_loc(".btn", within = ".panel"),
    multiple = "all"
  )
  withr::defer(release_elements(nested))
  expect_identical(nested$count, 6L)

  # A fully qualified within spec resolves recursively.
  qualified <- loc_resolve(
    page,
    pz_loc(
      ".btn",
      within = pz_loc(".panel", has_text = "Delete"),
      which = "last"
    )
  )
  withr::defer(release_elements(qualified))
  expect_identical(qualified$count, 1L)
  expect_identical(elements_text(qualified), "Save")

  # A within that matches nothing matches nothing overall.
  expect_error(
    loc_resolve(page, pz_loc(".btn", within = ".missing"), timeout = 0),
    class = "paparazzi_error_timeout"
  )
})

test_that("loc_resolve accepts a union of specs and strings", {
  page <- local_elements_page()
  els <- loc_resolve(
    page,
    list(".message", pz_loc(".btn", within = "#panel-inner")),
    multiple = "all"
  )
  withr::defer(release_elements(els))
  expect_identical(els$count, 5L)
  expect_identical(
    elements_text(els),
    c(
      "What's the weather?",
      "The weather is sunny.",
      "Bring a hat.",
      "Save   now",
      "Reset"
    )
  )
  expect_identical(
    els$description,
    "`.message` | `.btn` (within: `#panel-inner`)"
  )
})

test_that("resolution ignores elements inside #paparazzi-overlay-root", {
  page <- local_elements_page()
  els <- loc_resolve(page, ".shiny-tool-request", multiple = "all")
  withr::defer(release_elements(els))
  expect_identical(els$count, 3L)

  first <- loc_resolve(page, pz_loc(".shiny-tool-request", which = "first"))
  withr::defer(release_elements(first))
  expect_identical(elements_text(first), "get_weather")

  # The SPEC's example shape, against the fixture's .chat containers.
  example <- loc_resolve(
    page,
    pz_loc(
      ".shiny-tool-request",
      has_text = "get_weather",
      which = "last",
      within = ".chat"
    ),
    multiple = "all"
  )
  withr::defer(release_elements(example))
  expect_identical(example$count, 1L)
})

test_that("multiple = 'error' aborts with count, description, and a hint", {
  page <- local_elements_page()
  target <- pz_loc(".btn", has_text = "Save")
  err <- expect_error(
    loc_resolve(page, target),
    class = "paparazzi_error_multiple"
  )
  msg <- conditionMessage(err)
  expect_match(msg, "3 elements", fixed = TRUE)
  expect_match(msg, format_loc(target), fixed = TRUE)
  expect_match(msg, "has_text", fixed = TRUE)
  expect_match(msg, "which", fixed = TRUE)
  expect_match(msg, "within", fixed = TRUE)
})

test_that("multiple = 'all' returns the whole set", {
  page <- local_elements_page()
  els <- loc_resolve(page, ".message", multiple = "all")
  withr::defer(release_elements(els))
  expect_identical(els$count, 3L)
})

test_that("loc_resolve times out with a classed error showing the description", {
  page <- local_elements_page()
  target <- pz_loc(".never", has_text = "get_weather")
  err <- expect_error(
    loc_resolve(page, target, timeout = 0.1),
    class = "paparazzi_error_timeout"
  )
  msg <- conditionMessage(err)
  expect_match(msg, "Timed out after 0.1s", fixed = TRUE)
  # `what` is interpolated as plain text, so the quotes has_text adds
  # reach the message verbatim.
  expect_match(
    msg,
    '`.never` (has_text: "get_weather")',
    fixed = TRUE
  )
})

test_that("loc_resolve auto-waits for a late insert", {
  page <- local_elements_page()
  pz_js(
    page,
    "setTimeout(() => document.body.insertAdjacentHTML('beforeend', '<p class=\"late\">x</p>'), 300)",
    await = FALSE
  )
  els <- loc_resolve(page, ".late", timeout = 5)
  withr::defer(release_elements(els))
  expect_identical(els$count, 1L)
})

test_that("re-resolving the same spec follows DOM changes", {
  page <- local_elements_page()
  spec <- pz_loc(".message")
  before <- loc_resolve(page, spec, multiple = "all")
  withr::defer(release_elements(before))
  expect_identical(before$count, 3L)

  pz_js(page, "document.querySelector('.message').remove()")

  # Specs are lazy: the same object resolves against the current DOM.
  after <- loc_resolve(page, spec, multiple = "all")
  withr::defer(release_elements(after))
  expect_identical(after$count, 2L)
})

test_that("release_elements frees the remote handle", {
  page <- local_elements_page()
  els <- loc_resolve(page, ".btn", multiple = "all")
  expect_false(is.null(els$object_id))

  # The handle is unusable after release.
  oid <- els$object_id
  expect_no_error(release_elements(els))
  expect_error(
    els$page$session$Runtime$callFunctionOn(
      "function() { return this.length; }",
      objectId = oid,
      returnByValue = TRUE
    )
  )

  # A double release is a no-op.
  expect_no_error(release_elements(els))
})

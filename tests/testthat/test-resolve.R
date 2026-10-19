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
  pz_evaluate(
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

  pz_evaluate(page, "document.querySelector('.message').remove()")

  # Specs are lazy: the same object resolves against the current DOM.
  after <- loc_resolve(page, spec, multiple = "all")
  withr::defer(release_elements(after))
  expect_identical(after$count, 2L)
})

test_that("regex locators anchor normalized text and honor flags", {
  page <- local_page(test_path("fixtures", "matching.html"))
  expect_identical(
    pz_get_attr(
      page,
      "id",
      pz_loc(".label", has_text = pz_regex("^Save now$"))
    ),
    c("first", "second")
  )
  expect_identical(
    pz_get_attr(
      page,
      "id",
      pz_loc(".label", has_text = pz_regex("^save now$", "i"))
    ),
    c("first", "second", "lower")
  )
  expect_identical(
    pz_get_attr(
      page,
      "id",
      pz_loc("tr", has_text = pz_regex("Report \\d+ ready"))
    ),
    "ready"
  )
  expect_identical(
    pz_get_attr(
      page,
      "id",
      pz_loc(".label", has_text = pz_regex("^(Save|save) now$"))
    ),
    c("first", "second", "lower")
  )
  expect_identical(
    pz_get_count(page, pz_loc(".label", has_text = pz_regex(""))),
    5L
  )
})

test_that("regex transport preserves escapes, quotes, Unicode and source whitespace", {
  page <- local_elements_page()
  source <- '^雪 "quoted" `tick` \\{2\\} \\\\ path$'
  pz_evaluate(
    page,
    paste0(
      "document.querySelector('.story').textContent = ",
      js_literal('雪 "quoted" `tick` {2} \\ path')
    )
  )
  expect_identical(
    pz_get_count(page, pz_loc(".story", has_text = pz_regex(source))),
    1L
  )
  expect_identical(
    pz_get_count(page, pz_loc(".story", has_text = pz_regex("  雪"))),
    0L
  )
  expect_identical(
    pz_get_count(page, pz_loc(".story", has_text = pz_regex("雪  "))),
    0L
  )
})

test_that("Unicode regex flags and invalid Unicode escapes reach Chrome", {
  page <- local_elements_page()
  pz_evaluate(page, "document.querySelector('.story').textContent = '雪'")
  expect_identical(
    pz_get_count(
      page,
      pz_loc(".story", has_text = pz_regex("^\\p{Letter}+$", "u"))
    ),
    1L
  )
  expect_error(
    pz_get_count(page, pz_loc(".never", has_text = pz_regex("\\q", "u"))),
    "Invalid pz_regex",
    class = "paparazzi_error_js"
  )
})

test_that("plain has_text still collapses whitespace without trimming", {
  page <- local_elements_page()
  expect_identical(pz_get_count(page, pz_loc(".btn", has_text = " Save ")), 1L)
  expect_identical(pz_get_count(page, pz_loc(".btn", has_text = " save ")), 0L)
})

test_that("invalid regex source errors even with empty nested scopes and unions", {
  page <- local_elements_page()
  bad <- pz_regex("[")
  expect_error(
    pz_get_count(page, pz_loc(".never", has_text = bad)),
    "Invalid pz_regex",
    class = "paparazzi_error_js"
  )
  expect_error(
    loc_resolve(
      page,
      pz_loc(".btn", has_text = bad, within = ".never"),
      timeout = 0
    ),
    "Invalid pz_regex",
    class = "paparazzi_error_js"
  )
  expect_error(
    pz_get_count(
      page,
      pz_loc(".never", within = pz_loc(".never", has_text = bad))
    ),
    "Invalid pz_regex",
    class = "paparazzi_error_js"
  )
  expect_error(
    pz_get_count(page, list(".btn", pz_loc(".never", has_text = bad))),
    "Invalid pz_regex",
    class = "paparazzi_error_js"
  )
  expect_error(
    pz_expect_exists(
      page,
      pz_loc(".never", has_text = bad),
      not = TRUE,
      timeout = 0
    ),
    class = "paparazzi_error_js"
  )
})

test_that("text and predicate filters run before all positional selections", {
  page <- local_page(test_path("fixtures", "matching.html"))
  spec <- pz_loc(
    ".label",
    has_text = pz_regex("^Save(?: now)?$"),
    predicate = "el => el.dataset.ready === 'yes'"
  )
  expect_identical(pz_get_attr(page, "id", spec), c("first", "second"))
  first <- spec
  first$which <- "first"
  expect_identical(pz_get_attr(page, "id", first), "first")
  last <- spec
  last$which <- "last"
  expect_identical(pz_get_attr(page, "id", last), "second")
  second <- spec
  second$which <- 2L
  expect_identical(pz_get_attr(page, "id", second), "second")
  past <- spec
  past$which <- 3L
  expect_identical(pz_get_count(page, past), 0L)
  expect_error(
    loc_resolve(page, spec, timeout = 0),
    "predicate",
    class = "paparazzi_error_multiple"
  )
  expect_identical(
    pz_get_attr(page, "id", list(last, spec, "#draft")),
    c("second", "first", "draft")
  )
})

test_that("predicate invocations happen after text filtering and overlay exclusion", {
  page <- local_page(test_path("fixtures", "matching.html"))
  spec <- pz_loc(
    ".label",
    has_text = pz_regex("^Save now$"),
    predicate = "el => { if (!el.id) throw new Error('overlay'); return true; }"
  )
  expect_identical(pz_get_attr(page, "id", spec), c("first", "second"))
  expect_identical(
    pz_get_count(
      page,
      pz_loc(
        ".label",
        has_text = "no survivors",
        predicate = "el => { throw new Error('should not run'); }"
      )
    ),
    0L
  )
})

test_that("predicates distinguish status children from whole-row notes", {
  page <- local_page(test_path("fixtures", "matching.html"))
  spec <- pz_loc(
    "tr",
    has_text = "Ready",
    predicate = 'function(el) { return el.querySelector(".status")?.textContent === "Ready"; }',
    within = pz_loc("tbody", within = "#reports")
  )
  expect_identical(
    pz_get_count(page, pz_loc("tr", has_text = "Ready", within = "#reports")),
    3L
  )
  expect_identical(pz_get_attr(page, "id", spec), "ready")
  scope <- pz_find(page, "#reports")
  scoped_spec <- pz_loc(
    "tr",
    has_text = "Ready",
    predicate = spec$predicate,
    within = "tbody"
  )
  expect_identical(pz_get_attr(scope, "id", scoped_spec), "ready")
})

test_that("candidate scopes do not restrict parent and page inspection", {
  page <- local_page(test_path("fixtures", "matching.html"))
  predicate <- "el => el.closest('#outside').dataset.ready === 'yes' && document.querySelector('#ready') !== null && getComputedStyle(el).display !== 'none'"
  spec <- pz_loc(".label", predicate = predicate, within = "#scope")
  expect_identical(pz_get_count(page, spec), 5L)
  scope <- pz_find(page, "#scope")
  expect_identical(
    pz_get_count(scope, pz_loc(".label", predicate = predicate)),
    5L
  )
  expect_identical(pz_get_count(page), 1L)
})

test_that("predicate compilation works at root and pinned scope under restrictive CSP", {
  page <- local_page(test_path("fixtures", "matching.html"))
  pz_evaluate(
    page,
    "(() => { const script = document.createElement('script'); script.textContent = 'window.cspScriptRan = true'; document.body.append(script); })()"
  )
  expect_true(pz_evaluate(page, "window.cspScriptRan === undefined"))
  spec <- pz_loc(".label", predicate = "el => el.id === 'second'")
  expect_identical(pz_get_attr(page, "id", spec), "second")
  scope <- pz_find(page, "#scope")
  expect_identical(pz_get_attr(scope, "id", spec), "second")
})

test_that("malformed and non-function predicates error without candidates", {
  page <- local_elements_page()
  expect_error(
    pz_get_count(page, pz_loc(".never", predicate = "el => {")),
    "predicate",
    class = "paparazzi_error_js"
  )
  expect_error(
    pz_get_count(page, pz_loc(".btn", predicate = "42", within = ".never")),
    "must evaluate to a function",
    class = "paparazzi_error_js"
  )
  expect_error(
    pz_get_count(
      page,
      pz_loc(".never", within = pz_loc(".never", predicate = "null"))
    ),
    "must evaluate to a function",
    class = "paparazzi_error_js"
  )
  expect_error(
    pz_expect_exists(
      page,
      list(".btn", pz_loc(".never", predicate = "true")),
      not = TRUE,
      timeout = 0
    ),
    "must evaluate to a function",
    class = "paparazzi_error_js"
  )
})

invalid_predicate_returns <- c(
  missing = "el => {}",
  undefined = "el => undefined",
  null = "el => null",
  number = "el => 1",
  string = "el => 'yes'",
  element = "el => el",
  boolean_object = "el => new Boolean(true)",
  promise = "el => Promise.resolve(true)",
  async = "async el => true"
)
for (name in names(invalid_predicate_returns)) {
  source <- invalid_predicate_returns[[name]]
  test_that(paste("locator predicates reject", name, "returns"), {
    page <- local_elements_page()
    expect_error(
      loc_resolve(page, pz_loc(".btn", predicate = source), timeout = 0),
      "must return primitive true or false",
      class = "paparazzi_error_js"
    )
    expect_identical(
      pz_get_count(page, pz_loc(".never", predicate = source)),
      0L
    )
  })
}

test_that("predicate exceptions abort immediately with target and thrown value", {
  page <- local_elements_page()
  source <- "el => { throw new Error('status failed'); }"
  err <- expect_error(
    loc_resolve(
      page,
      pz_loc(".btn", predicate = source, within = "#panel-inner"),
      timeout = 5
    ),
    "status failed",
    class = "paparazzi_error_js"
  )
  expect_match(conditionMessage(err), "#panel-inner", fixed = TRUE)
  expect_match(conditionMessage(err), source, fixed = TRUE)
  expect_error(
    pz_get_count(
      page,
      pz_loc(".btn", predicate = "el => { throw 'plain failure'; }")
    ),
    "plain failure",
    class = "paparazzi_error_js"
  )
  expect_error(
    pz_get_count(page, pz_loc(".btn", predicate = "el => { throw 42; }")),
    "42",
    class = "paparazzi_error_js"
  )
  expect_error(
    pz_get_count(page, pz_loc(".btn", predicate = "el => { throw null; }")),
    "null",
    class = "paparazzi_error_js"
  )
  expect_error(
    pz_get_count(page, pz_loc(".btn", predicate = "el => { throw 42n; }")),
    "42",
    class = "paparazzi_error_js"
  )
  expect_error(
    pz_get_count(
      page,
      pz_loc(
        ".btn",
        predicate = "el => { const err = {}; err.self = err; throw err; }"
      )
    ),
    "Locator predicate threw \\[object Object\\]",
    class = "paparazzi_error_js"
  )
})

test_that("late eligibility re-runs regex and predicate during normal auto-wait", {
  page <- local_elements_page()
  spec <- pz_loc(
    ".late-text",
    has_text = pz_regex("^Ready \\d+$"),
    predicate = "el => el.querySelector('.status')?.textContent === 'Ready 42'"
  )
  pz_evaluate(
    page,
    "setTimeout(() => { document.querySelector('.late-text').innerHTML = '<span class=\"status\">Ready 42</span>'; }, 100)",
    await = FALSE
  )
  expect_identical(pz_get_text(page, spec), "Ready 42")
})

test_that("reusing qualifiers follows replaced nodes and changed live properties", {
  page <- local_page(test_path("fixtures", "matching.html"))
  spec <- pz_loc("#invoice", predicate = "el => el.value === 'INV-42'")
  pz_evaluate(
    page,
    "setTimeout(() => { document.querySelector('#invoice').value = 'INV-42'; }, 100)",
    await = FALSE
  )
  expect_identical(pz_get_value(page, spec), "INV-42")
  pz_evaluate(
    page,
    "document.querySelector('#invoice').outerHTML = '<input id=\"invoice\" value=\"INV-1\">'"
  )
  expect_identical(pz_get_count(page, spec), 0L)
  pz_evaluate(page, "document.querySelector('#invoice').value = 'INV-42'")
  expect_identical(pz_get_value(page, spec), "INV-42")
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

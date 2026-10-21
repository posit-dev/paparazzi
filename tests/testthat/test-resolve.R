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

test_that("literal match is exact, normalized and case-sensitive", {
  page <- local_elements_page()
  els <- loc_resolve(page, pz_loc(".btn", match = "Save"), multiple = "all")
  withr::defer(release_elements(els))
  expect_identical(els$count, 2L)
  expect_identical(elements_text(els), c("Save", "Save"))

  # Whitespace collapses on both sides of the match.
  collapsed <- loc_resolve(
    page,
    pz_loc(".btn", match = "  Save   now  "),
    multiple = "all"
  )
  withr::defer(release_elements(collapsed))
  expect_identical(collapsed$count, 1L)
  expect_identical(elements_text(collapsed), "Save   now")

  # Case-sensitive: "save" matches nothing.
  expect_error(
    loc_resolve(page, pz_loc(".btn", match = "save"), timeout = 0),
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

test_that("which applies after substring matching", {
  page <- local_elements_page()
  els <- loc_resolve(
    page,
    pz_loc(".btn", match = pz_regex("Save", fixed = TRUE), which = 2)
  )
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
      within = pz_loc(".panel", match = pz_regex("Delete", fixed = TRUE)),
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
      match = "get_weather",
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
  target <- pz_loc(".btn", match = pz_regex("Save", fixed = TRUE))

  err <- expect_error(
    loc_resolve(page, target),
    class = "paparazzi_error_multiple"
  )
  msg <- conditionMessage(err)
  expect_match(msg, "3 elements", fixed = TRUE)
  expect_match(msg, format_loc(target), fixed = TRUE)
  expect_match(msg, "match", fixed = TRUE)
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
  target <- pz_loc(".never", match = "get_weather")

  err <- expect_error(
    loc_resolve(page, target, timeout = 0.1),
    class = "paparazzi_error_timeout"
  )
  msg <- conditionMessage(err)
  expect_match(msg, "Timed out after 0.1s", fixed = TRUE)
  # `what` is interpolated as plain text, so the quotes match adds
  # reach the message verbatim.
  expect_match(
    msg,
    '`.never` (match: "get_weather")',
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

test_that("regex locators anchor normalized text and honor ignore_case", {
  page <- local_page(test_path("fixtures", "matching.html"))
  expect_identical(
    pz_get_attr(
      page,
      "id",
      pz_loc(".label", match = pz_regex("^Save now$"))
    ),
    c("first", "second")
  )
  expect_identical(
    pz_get_attr(
      page,
      "id",
      pz_loc(".label", match = pz_regex("^save now$", ignore_case = TRUE))
    ),
    c("first", "second", "lower")
  )
  expect_identical(
    pz_get_attr(
      page,
      "id",
      pz_loc("tr", match = pz_regex("Report \\d+ ready"))
    ),
    "ready"
  )
  expect_identical(
    pz_get_attr(
      page,
      "id",
      pz_loc(".label", match = pz_regex("^(Save|save) now$"))
    ),
    c("first", "second", "lower")
  )
  expect_identical(
    pz_get_count(page, pz_loc(".label", match = pz_regex(""))),
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
    pz_get_count(page, pz_loc(".story", match = pz_regex(source))),
    1L
  )
  expect_identical(
    pz_get_count(page, pz_loc(".story", match = pz_regex("  雪"))),
    0L
  )
  expect_identical(
    pz_get_count(page, pz_loc(".story", match = pz_regex("雪  "))),
    0L
  )
})

test_that("regexes are always Unicode-aware and reject invalid Unicode escapes", {
  page <- local_elements_page()
  pz_evaluate(page, "document.querySelector('.story').textContent = '雪'")
  expect_identical(
    pz_get_count(
      page,
      pz_loc(".story", match = pz_regex("^\\p{Letter}+$"))
    ),
    1L
  )
  expect_error(
    pz_get_count(page, pz_loc(".never", match = pz_regex("\\q"))),
    "Invalid pz_regex",
    class = "paparazzi_error_js"
  )
})

test_that("literal matching trims both sides without matching longer labels", {
  page <- local_elements_page()
  expect_identical(pz_get_count(page, pz_loc(".btn", match = " Save ")), 2L)
  expect_identical(pz_get_count(page, pz_loc(".btn", match = " save ")), 0L)
  expect_identical(pz_get_count(page, pz_loc(".btn", match = "Save now")), 1L)
  expect_identical(
    pz_get_count(page, pz_loc(".btn", match = pz_regex("Save", fixed = TRUE))),
    3L
  )
})

test_that("invalid regex source errors even with empty nested scopes and unions", {
  page <- local_elements_page()
  bad <- pz_regex("[")
  expect_error(
    pz_get_count(page, pz_loc(".never", match = bad)),
    "Invalid pz_regex",
    class = "paparazzi_error_js"
  )
  expect_error(
    loc_resolve(
      page,
      pz_loc(".btn", match = bad, within = ".never"),
      timeout = 0
    ),
    "Invalid pz_regex",
    class = "paparazzi_error_js"
  )
  expect_error(
    pz_get_count(
      page,
      pz_loc(".never", within = pz_loc(".never", match = bad))
    ),
    "Invalid pz_regex",
    class = "paparazzi_error_js"
  )
  expect_error(
    pz_get_count(page, list(".btn", pz_loc(".never", match = bad))),
    "Invalid pz_regex",
    class = "paparazzi_error_js"
  )
  expect_error(
    pz_expect_exists(
      page,
      pz_loc(".never", match = bad),
      not = TRUE,
      timeout = 0
    ),
    class = "paparazzi_error_js"
  )
})

test_that("a combined JS condition runs before all positional selections", {
  page <- local_page(test_path("fixtures", "matching.html"))
  spec <- pz_loc(
    ".label",
    match = pz_js(
      r"(el => /^Save(?: now)?$/u.test(el.textContent.replace(/\s+/g, ' ').trim()) && el.dataset.ready === 'yes')"
    )
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
    "pz_js",
    class = "paparazzi_error_multiple"
  )
  expect_identical(
    pz_get_attr(page, "id", list(last, spec, "#draft")),
    c("second", "first", "draft")
  )
})

test_that("predicates run after overlay exclusion and not without candidates", {
  page <- local_page(test_path("fixtures", "matching.html"))
  spec <- pz_loc(
    ".label",
    match = pz_js(
      r"(el => { if (!el.id) throw new Error('overlay'); return /^Save now$/u.test(el.textContent.replace(/\s+/g, ' ').trim()); })"
    )
  )
  expect_identical(pz_get_attr(page, "id", spec), c("first", "second"))
  expect_identical(
    pz_get_count(
      page,
      pz_loc(
        ".never",
        match = pz_js("el => { throw new Error('should not run'); }")
      )
    ),
    0L
  )
})

test_that("predicates distinguish status children from whole-row notes", {
  page <- local_page(test_path("fixtures", "matching.html"))
  spec <- pz_loc(
    "tr",
    match = pz_js(
      'function(el) { return el.querySelector(".status")?.textContent === "Ready"; }'
    ),
    within = pz_loc("tbody", within = "#reports")
  )
  expect_identical(
    pz_get_count(
      page,
      pz_loc("tr", match = pz_regex("Ready", fixed = TRUE), within = "#reports")
    ),
    3L
  )
  expect_identical(pz_get_attr(page, "id", spec), "ready")
  scope <- pz_find(page, "#reports")
  scoped_spec <- pz_loc(
    "tr",
    match = spec$match,
    within = "tbody"
  )
  expect_identical(pz_get_attr(scope, "id", scoped_spec), "ready")
})

test_that("candidate scopes do not restrict parent and page inspection", {
  page <- local_page(test_path("fixtures", "matching.html"))
  predicate <- "el => el.closest('#outside').dataset.ready === 'yes' && document.querySelector('#ready') !== null && getComputedStyle(el).display !== 'none'"
  spec <- pz_loc(".label", match = pz_js(predicate), within = "#scope")
  expect_identical(pz_get_count(page, spec), 5L)
  scope <- pz_find(page, "#scope")
  expect_identical(
    pz_get_count(scope, pz_loc(".label", match = pz_js(predicate))),
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
  spec <- pz_loc(".label", match = pz_js("el => el.id === 'second'"))
  expect_identical(pz_get_attr(page, "id", spec), "second")
  scope <- pz_find(page, "#scope")
  expect_identical(pz_get_attr(scope, "id", spec), "second")
})

test_that("malformed and non-function predicates error without candidates", {
  page <- local_elements_page()
  expect_error(
    pz_get_count(page, pz_loc(".never", match = pz_js("el => {"))),
    "pz_js",
    class = "paparazzi_error_js"
  )
  expect_error(
    pz_get_count(page, pz_loc(".btn", match = pz_js("42"), within = ".never")),
    "must evaluate to a function",
    class = "paparazzi_error_js"
  )
  expect_error(
    pz_get_count(
      page,
      pz_loc(".never", within = pz_loc(".never", match = pz_js("null")))
    ),
    "must evaluate to a function",
    class = "paparazzi_error_js"
  )
  expect_error(
    pz_expect_exists(
      page,
      list(".btn", pz_loc(".never", match = pz_js("true"))),
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
      loc_resolve(page, pz_loc(".btn", match = pz_js(source)), timeout = 0),
      "must return primitive true or false",
      class = "paparazzi_error_js"
    )
    expect_identical(
      pz_get_count(page, pz_loc(".never", match = pz_js(source))),
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
      pz_loc(".btn", match = pz_js(source), within = "#panel-inner"),
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
      pz_loc(".btn", match = pz_js("el => { throw 'plain failure'; }"))
    ),
    "plain failure",
    class = "paparazzi_error_js"
  )
  expect_error(
    pz_get_count(page, pz_loc(".btn", match = pz_js("el => { throw 42; }"))),
    "42",
    class = "paparazzi_error_js"
  )
  expect_error(
    pz_get_count(page, pz_loc(".btn", match = pz_js("el => { throw null; }"))),
    "null",
    class = "paparazzi_error_js"
  )
  expect_error(
    pz_get_count(page, pz_loc(".btn", match = pz_js("el => { throw 42n; }"))),
    "42",
    class = "paparazzi_error_js"
  )
  expect_error(
    pz_get_count(
      page,
      pz_loc(
        ".btn",
        match = pz_js("el => { const err = {}; err.self = err; throw err; }")
      )
    ),
    "Locator predicate threw \\[object Object\\]",
    class = "paparazzi_error_js"
  )
})

test_that("late text eligibility re-runs a regex matcher during auto-wait", {
  page <- local_elements_page()
  spec <- pz_loc(".late-text", match = pz_regex("^Ready \\d+$"))
  pz_evaluate(
    page,
    "setTimeout(() => { document.querySelector('.late-text').textContent = 'Ready 42'; }, 100)",
    await = FALSE
  )
  expect_identical(pz_get_text(page, spec), "Ready 42")
})

test_that("late eligibility re-runs a combined matcher during normal auto-wait", {
  page <- local_elements_page()
  spec <- pz_loc(
    ".late-text",
    match = pz_js(
      r"(el => /^Ready \d+$/u.test(el.textContent.replace(/\s+/g, ' ').trim()) && el.querySelector('.status')?.textContent === 'Ready 42')"
    )
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
  spec <- pz_loc("#invoice", match = pz_js("el => el.value === 'INV-42'"))
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

test_that("an empty literal matches only normalized empty text", {
  page <- local_elements_page()
  expect_identical(
    pz_get_count(page, pz_loc(".late-text, .story", match = "")),
    1L
  )
  expect_identical(pz_get_count(page, pz_loc(".story", match = " ")), 0L)
  expect_identical(
    pz_get_count(page, pz_loc(".late-text, .story", match = pz_regex(""))),
    2L
  )
})

test_that("bare-string equality treats regex metacharacters as literal data", {
  page <- local_elements_page()
  literal <- "C++ [preview]"
  pz_evaluate(
    page,
    paste0(
      "document.querySelector('.story').textContent = ",
      js_literal(literal)
    )
  )
  expect_identical(pz_get_count(page, pz_loc(".story", match = literal)), 1L)
})

test_that("fixed matching escapes punctuation and preserves literal substring intent", {
  page <- local_elements_page()
  literal <- 'C++ [draft] (a.b)? ^$ {2} | * \\ / - 雪'
  pz_evaluate(
    page,
    paste0(
      "document.querySelector('.story').textContent = ",
      js_literal(paste0("Before ", literal, " after"))
    )
  )
  expect_identical(pz_get_count(page, pz_loc(".story", match = literal)), 0L)
  expect_identical(
    pz_get_count(
      page,
      pz_loc(".story", match = pz_regex(literal, fixed = TRUE))
    ),
    1L
  )
  expect_identical(
    pz_get_count(
      page,
      pz_loc(
        ".story",
        match = pz_regex("  c++  [DRAFT]  ", fixed = TRUE, ignore_case = TRUE)
      )
    ),
    1L
  )
})

test_that("literal and fixed matching share Unicode whitespace normalization", {
  page <- local_page(test_path("fixtures", "matching.html"))
  expect_identical(
    pz_get_attr(page, "id", pz_loc(".label", match = " Save\u00a0\u2003now ")),
    c("first", "second")
  )
  literal <- pz_regex(" SAVE\u00a0\u2003now ", fixed = TRUE, ignore_case = TRUE)
  expect_identical(
    pz_get_attr(page, "id", pz_loc(".label", match = literal)),
    c("first", "second", "lower")
  )
})

test_that("Unicode mode treats an astral character as one code point", {
  page <- local_elements_page()
  pz_evaluate(page, "document.querySelector('.story').textContent = '😀'")
  expect_identical(
    pz_get_count(page, pz_loc(".story", match = pz_regex("^.$"))),
    1L
  )
})

test_that("preformatted and code text follow the same normalization contract", {
  page <- local_elements_page()
  pz_evaluate(
    page,
    r"(document.body.insertAdjacentHTML('beforeend', '<pre>first\n    second</pre><code>first\n    second</code>'))"
  )
  expect_identical(
    pz_get_count(page, pz_loc("pre, code", match = "first second")),
    2L
  )
  expect_identical(
    pz_get_text(page, "pre, code", raw = TRUE),
    rep("first\n    second", 2)
  )
  expect_identical(
    pz_get_count(page, pz_loc("pre, code", match = pz_regex("\\n"))),
    0L
  )
  expect_identical(
    pz_get_count(
      page,
      pz_loc(
        "pre, code",
        match = pz_js(r"(el => el.textContent.includes('\n    '))")
      )
    ),
    2L
  )
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

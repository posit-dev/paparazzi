# The pz_get_*() getters end the chain: they return values, not the
# context. Everything here runs against getters.html, whose exact
# shape is pinned in .agents/phases/getters.md: three p.item (with
# whitespace wrinkles), three .field controls covering value/""/NA,
# two a.link (one missing data-role), two absolutely-positioned
# #box* divs, #rich, and a p.padded with leading/trailing whitespace.
# (The auto-wait test schedules its own late element via pz_js(); the
# fixture itself stays static.)

test_that("pz_get_count returns the number of matches as an integer", {
  page <- local_getters_page()
  expect_type(pz_get_count(page, target = ".item"), "integer")
  expect_identical(pz_get_count(page, target = ".item"), 3L)
})

test_that("pz_get_count at the root counts the body", {
  page <- local_getters_page()
  expect_identical(pz_get_count(page), 1L)
})

test_that("pz_get_count returns 0 for a missing target without waiting", {
  # A waiting implementation would burn the session default timeout
  # and raise paparazzi_error_timeout; 0 comes back immediately.
  # Opening gets the normal budget; only the getter's wait is shortened,
  # so a slow page load under a parallel suite can't fail the open.
  page <- local_page(getters_fixture_file())
  page$default_timeout <- 0.3
  expect_identical(pz_get_count(page, target = ".never"), 0L)
})

test_that("pz_get_count validates its inputs", {
  page <- local_getters_page()
  expect_error(pz_get_count(page, "extra"), class = "rlang_error")
  expect_error(pz_get_count("not a page"), class = "paparazzi_error_context")
})

test_that("target-based getters validate context before reading the scope", {
  expect_error(pz_get_text(1), class = "paparazzi_error_context")
  expect_error(pz_get_attr(1, "id"), class = "paparazzi_error_context")
})

test_that("pz_get_text collapses and trims whitespace by default", {
  page <- local_getters_page()
  text <- pz_get_text(page, target = ".item")
  expect_type(text, "character")
  expect_identical(text, c("first item", "second item", "third item"))
})

test_that("pz_get_text(raw = TRUE) preserves the browser's whitespace", {
  page <- local_getters_page()
  raw <- pz_get_text(page, target = ".item", raw = TRUE)
  expect_identical(length(raw), 3L)
  # Inner spaces are kept...
  expect_identical(raw[[1]], "first   item")
  # ...and so is the newline + indentation of the second item.
  expect_match(raw[[2]], "second\n +item")
})

test_that("pz_get_text at the root returns the body text as one string", {
  page <- local_getters_page()
  text <- pz_get_text(page)
  expect_type(text, "character")
  expect_length(text, 1)
  expect_match(text, "third item", fixed = TRUE)
})

test_that("pz_get_value maps value to '', and a non-control to NA", {
  page <- local_getters_page()
  expect_identical(
    pz_get_value(page, target = ".field"),
    c("alpha", "", NA_character_)
  )
})

test_that("pz_get_attr returns one entry per match in order", {
  page <- local_getters_page()
  expect_identical(
    pz_get_attr(page, "href", target = ".link"),
    c("#top", "#bottom")
  )
})

test_that("pz_get_attr maps a missing attribute to NA", {
  page <- local_getters_page()
  expect_identical(
    pz_get_attr(page, "data-role", target = ".link"),
    c("primary", NA_character_)
  )
})

test_that("pz_get_attr validates its inputs", {
  page <- local_getters_page()
  expect_error(pz_get_attr(page, 1, target = ".link"), class = "rlang_error")
  expect_error(
    pz_get_attr(page, "href", target = ".link", extra = 1),
    class = "rlang_error"
  )
})

test_that("pz_get_rect returns the exact CSS-pixel geometry of one match", {
  page <- local_getters_page()
  rect <- pz_get_rect(page, target = "#box1")
  expect_s3_class(rect, "tbl_df")
  expect_identical(nrow(rect), 1L)
  expect_equal(rect$x, 10)
  expect_equal(rect$y, 20)
  expect_equal(rect$width, 100)
  expect_equal(rect$height, 40)
})

test_that("pz_get_rect returns one row per match with scoped element entries", {
  page <- local_getters_page()
  rects <- pz_get_rect(page, target = "div[id^='box']")
  expect_identical(nrow(rects), 2L)
  expect_named(rects, c("x", "y", "width", "height", "element"))
  # Document order: box1 first, box2 second.
  expect_equal(rects$x, c(10, 50))
  expect_equal(rects$y, c(20, 100))
  expect_equal(rects$width, c(100, 200))
  expect_equal(rects$height, c(40, 80))
  # One scoped context per match: the element column is live.
  expect_type(rects$element, "list")
  expect_identical(length(rects$element), nrow(rects))
  expect_true(all(vapply(rects$element, inherits, logical(1), "PaparazziContext"))
  )
})

test_that("pz_get_elements summarizes every match", {
  page <- local_getters_page()
  els <- pz_get_elements(page, target = ".item")
  expect_s3_class(els, "tbl_df")
  expect_identical(nrow(els), 3L)
  expect_named(els, c("tag", "id", "class", "text", "element"))
  expect_identical(els$tag, rep("p", 3))
  expect_identical(els$id, rep(NA_character_, 3))
  expect_identical(els$class, rep("item", 3))
  # Text is collapsed exactly as pz_get_text() collapses it.
  expect_identical(els$text, c("first item", "second item", "third item"))
  expect_type(els$element, "list")
})

test_that("pz_get_elements reads tag, id, and class from a form control", {
  page <- local_getters_page()
  el <- pz_get_elements(page, target = "#field-a")
  expect_identical(nrow(el), 1L)
  expect_identical(el$tag, "input")
  expect_identical(el$id, "field-a")
  expect_identical(el$class, "field")
})

test_that("pz_get_html returns the exact outerHTML of matches", {
  page <- local_getters_page()
  expect_identical(
    pz_get_html(page, target = "#rich"),
    '<div id="rich"><b>bold</b> and <i>italic</i></div>'
  )
})

test_that("pz_get_html returns every match in document order", {
  page <- local_getters_page()
  html <- pz_get_html(page, target = ".item")
  expect_length(html, 3)
  expect_match(html[[1]], '<p class="item">first   item</p>', fixed = TRUE)
  expect_match(html[[2]], "second\n", fixed = TRUE)
  expect_identical(html[[3]], '<p class="item">third item</p>')
})

test_that("pz_get_url returns the current page URL", {
  page <- local_getters_page()
  url <- pz_get_url(page)
  expect_type(url, "character")
  expect_length(url, 1)
  expect_match(url, "getters\\.html$")
})

test_that("pz_get_title returns the document title", {
  page <- local_getters_page()
  expect_identical(pz_get_title(page), "Getters fixture")
})

test_that("target-based getters auto-wait for elements to appear", {
  page <- local_getters_page()
  # Scheduled after the page is open, so the element provably does
  # not exist when the getter is called.
  pz_js(
    page,
    "setTimeout(function() {
      const el = document.createElement('p');
      el.className = 'later';
      el.textContent = 'arrived even later';
      document.body.appendChild(el);
    }, 300)"
  )
  expect_identical(pz_get_count(page, target = ".later"), 0L)
  expect_identical(pz_get_text(page, target = ".later"), "arrived even later")
})

test_that("pz_get_text trims leading and trailing whitespace by default", {
  page <- local_getters_page()
  expect_identical(pz_get_text(page, target = ".padded"), "padded text")
  expect_match(
    pz_get_text(page, target = ".padded", raw = TRUE),
    "^\\s+padded text\\s+$"
  )
})

test_that("target-based getters time out with a classed error", {
  # Short session default timeout keeps the suite fast: the getters
  # take no per-call timeout and wait on the session default.
  # Opening gets the normal budget; only the getter's wait is shortened,
  # so a slow page load under a parallel suite can't fail the open.
  page <- local_page(getters_fixture_file())
  page$default_timeout <- 0.3
  expect_error(
    pz_get_text(page, target = ".never"),
    class = "paparazzi_error_timeout"
  )
})

test_that("getters return values, not the context", {
  page <- local_getters_page()
  expect_type(pz_get_text(page, target = ".item"), "character")
  expect_type(pz_get_count(page, target = ".item"), "integer")
  expect_type(pz_get_url(page), "character")
  expect_s3_class(pz_get_rect(page, target = "#box1"), "tbl_df")
})

# Scoped getters and the element list-column run against scopes.html
# (#scope-a/#scope-b with parallel repeated .sc-item classes), so
# in-scope counts and match positions are unambiguous.

test_that("target = NULL on a scope returns one row per pinned match", {
  page <- local_scopes_page()
  ctx <- pz_find(page, "#scope-a .sc-item")

  expect_identical(
    pz_get_text(ctx),
    c("A1", "A2", "A3", "nested-a", "shared target", "get_weather")
  )
  rects <- pz_get_rect(ctx)
  expect_identical(nrow(rects), 6L)
  expect_identical(pz_get_value(ctx), rep(NA_character_, 6L))
})

test_that("pz_get_count on a scope returns the pinned count immediately", {
  page <- local_scopes_page()
  ctx <- pz_find(page, "#scope-a .sc-item")

  # The scope's own count, without re-querying the pinned set.
  expect_identical(pz_get_count(ctx), 6L)
  # An explicit target counts lazily inside the scope: 0 without waiting.
  expect_identical(pz_get_count(ctx, target = ".sc-label"), 1L)
  expect_identical(pz_get_count(ctx, target = ".never"), 0L)
  # A detached scope raises instead of returning 0: the pinned set
  # promises a live set and is never silently re-queried.
  pz_js(page, "document.querySelectorAll('#scope-a .sc-item')[0].remove()")
  expect_error(pz_get_count(ctx), class = "paparazzi_error_detached")
})

test_that("an explicit target resolves lazily inside the scope", {
  page <- local_scopes_page()
  ctx <- pz_find(page, "#scope-b")

  # .sc-label matches once inside #scope-b, twice at the root.
  expect_identical(pz_get_text(ctx, target = ".sc-label"), "nested-b")
  # Auto-wait still applies inside the scope.
  pz_js(
    page,
    "setTimeout(function() {
      const el = document.createElement('div');
      el.className = 'late';
      el.textContent = 'late B';
      document.getElementById('scope-b').appendChild(el);
    }, 300)"
  )
  expect_identical(pz_get_text(ctx, target = ".late"), "late B")
})

test_that("the element column holds one scoped context per match", {
  page <- local_scopes_page()
  rects <- pz_get_rect(page, target = "#scope-a .sc-item")

  expect_identical(nrow(rects), 6L)
  entries <- rects$element
  expect_true(all(vapply(entries, inherits, logical(1), "PaparazziContext")))
  expect_true(all(vapply(entries, function(ctx) length(ctx$scope), integer(1)) == 1L))
  # One single-element pinned set per match, each its own array.
  expect_identical(
    vapply(entries, function(ctx) ctx$scope[[1]]$count, integer(1)),
    rep(1L, 6)
  )
  # The per-match description names the row, so a later detach does.
  expect_identical(
    vapply(entries, function(ctx) ctx$scope[[1]]$description, character(1)),
    paste0("`#scope-a .sc-item` (which: ", 1:6, ")")
  )
  ids <- vapply(entries, function(ctx) ctx$scope[[1]]$object_id, character(1))
  expect_length(unique(ids), 6L)
})

test_that("the element column continues the chain from one match", {
  page <- local_scopes_page()
  rects <- pz_get_rect(page, target = "#scope-a .sc-item")

  # The acceptance criterion: the pinned match drives a real action.
  second <- rects$element[[2]]
  expect_identical(pz_get_text(second), "A2")
  expect_invisible(pz_hover(second))
  expect_identical(
    pz_js(page, "document.querySelector('#scope-a .sc-item:hover').textContent"),
    "A2"
  )
})

test_that("a union target's element entries take the match-suffix form", {
  page <- local_scopes_page()
  els <- pz_get_elements(page, target = list(".sc-target", "[data-task]"))
  expect_identical(nrow(els), 4L)
  expect_identical(
    els$element[[3]]$scope[[1]]$description,
    "`.sc-target` | `[data-task]` (match: 3)"
  )
})

test_that("a detached element-column context names its row", {
  page <- local_scopes_page()
  els <- pz_get_elements(page, target = "#scope-a .sc-item")
  ctx <- els$element[[3]]

  # Drop the row's element; the pinned match is stale, never re-queried.
  pz_js(page, "document.querySelectorAll('#scope-a .sc-item')[2].remove()")
  err <- expect_error(pz_click(ctx), class = "paparazzi_error_detached")
  msg <- paste(conditionMessage(err), collapse = " ")
  expect_match(msg, "Scope: `#scope-a \\.sc-item` \\(which: 3\\)")
})

test_that("a which-loc's element entry names its original match when detached", {
  page <- local_scopes_page()
  els <- pz_get_elements(page, target = pz_loc("#scope-a .sc-item", which = "last"))
  ctx <- els$element[[1]]

  # The target already picked its match, so the entry keeps that
  # selection instead of being re-labeled match 1; a later detach
  # names the real match, not the first one.
  pz_js(page, "document.querySelectorAll('#scope-a .sc-item')[5].remove()")
  err <- expect_error(pz_click(ctx), class = "paparazzi_error_detached")
  msg <- paste(conditionMessage(err), collapse = " ")
  expect_match(msg, "Scope: `#scope-a \\.sc-item` \\(which: last\\)")
})

test_that("target = NULL on a scope narrows the scope's own locs", {
  page <- local_scopes_page()
  ctx <- pz_find(page, "#scope-b .sc-item")
  rects <- pz_get_rect(ctx)
  # The entry's stack is the getter context's whole stack plus the
  # match: the parent scope, then the per-match set.
  entry <- rects$element[[2]]
  expect_identical(length(entry$scope), 2L)
  expect_identical(entry$scope[[1]]$description, "`#scope-b .sc-item`")
  expect_identical(entry$scope[[2]]$description, "`#scope-b .sc-item` (which: 2)")
})

test_that("the element column renders its contexts through pillar", {
  page <- local_scopes_page()
  rects <- pz_get_rect(page, target = "#scope-a .sc-item")
  out <- paste(capture.output(print(rects)), collapse = "\n")
  expect_match(out, "<pz_ctx>", fixed = TRUE)
})

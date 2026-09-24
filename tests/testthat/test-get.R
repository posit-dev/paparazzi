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
  page <- local_page(getters_fixture_file(), timeout = 0.3)
  expect_identical(pz_get_count(page, target = ".never"), 0L)
})

test_that("pz_get_count validates its inputs", {
  page <- local_getters_page()
  expect_error(pz_get_count(page, "extra"), class = "rlang_error")
  expect_error(pz_get_count("not a page"), class = "paparazzi_error_context")
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

test_that("pz_get_rect returns one row per match with a trailing element stub", {
  page <- local_getters_page()
  rects <- pz_get_rect(page, target = "div[id^='box']")
  expect_identical(nrow(rects), 2L)
  expect_named(rects, c("x", "y", "width", "height", "element"))
  # Document order: box1 first, box2 second.
  expect_equal(rects$x, c(10, 50))
  expect_equal(rects$y, c(20, 100))
  expect_equal(rects$width, c(100, 200))
  expect_equal(rects$height, c(40, 80))
  # The element column is a list of NULLs, reserved for scoped contexts.
  expect_type(rects$element, "list")
  expect_identical(length(rects$element), nrow(rects))
  expect_true(all(vapply(rects$element, is.null, logical(1))))
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
  page <- local_page(getters_fixture_file(), timeout = 0.3)
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

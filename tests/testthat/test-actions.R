# The actions fixture records real browser events into window.__pzLog:
# one entry per event, {type, id, key, mods, isTrusted, value}, with
# null for fields that don't apply. isTrusted is what separates
# CDP-dispatched input from JS-synthesized events.

log_entries <- function(page) {
  pz_js(page, "window.__pzLog")
}

log_types <- function(log) {
  vapply(log, function(e) e$type, character(1))
}

# Entries for one element id, optionally narrowed to one event type.
log_ids <- function(log, id, type = NULL) {
  keep <- vapply(
    log,
    function(e) {
      identical(e$id, id) && (is.null(type) || identical(e$type, type))
    },
    logical(1)
  )
  log[keep]
}

test_that("the actions chain through the context invisibly", {
  page <- local_actions_page()
  # Each action returns its context invisibly, so the chain carries on:
  # expect_invisible() gives the value back and the next call in the
  # chain proves it's the same context.
  page <- expect_invisible(pz_type(page, "Ada", target = "#name"))
  page <- expect_invisible(pz_click(page, "#save"))
  page <- expect_invisible(pz_press(page, "Enter"))
  page <- expect_invisible(pz_focus(page, "#bio"))
  page <- expect_invisible(pz_blur(page))

  expect_equal(pz_js(page, "document.getElementById('name').value"), "Ada")

  # The whole chain happened, in order.
  log <- log_entries(page)
  i_input <- which(vapply(
    log,
    function(e) identical(e$type, "input") && identical(e$value, "Ada"),
    logical(1)
  ))[1]
  i_click <- which(vapply(
    log,
    function(e) identical(e$type, "click") && identical(e$id, "save"),
    logical(1)
  ))[1]
  i_enter <- which(vapply(
    log,
    function(e) identical(e$type, "keydown") && identical(e$key, "Enter"),
    logical(1)
  ))[1]
  i_focus_bio <- which(vapply(
    log,
    function(e) identical(e$type, "focus") && identical(e$id, "bio"),
    logical(1)
  ))[1]
  i_blur_bio <- which(vapply(
    log,
    function(e) identical(e$type, "blur") && identical(e$id, "bio"),
    logical(1)
  ))[1]
  expect_lt(i_input, i_click)
  expect_lt(i_click, i_enter)
  expect_lt(i_enter, i_focus_bio)
  expect_lt(i_focus_bio, i_blur_bio)
})

test_that("pz_click produces trusted mouse events in order", {
  page <- local_actions_page()
  pz_click(page, "#save")
  log <- log_entries(page)
  save <- log_ids(log, "save")
  # The pointer events, in dispatch order. (On some platforms mousedown
  # also focuses the button, adding a `focus` entry; only the pointer
  # sequence is asserted.)
  pointer <- save[vapply(
    save,
    function(e) e$type %in% c("mousemove", "mousedown", "mouseup", "click"),
    logical(1)
  )]
  expect_identical(
    log_types(pointer),
    c("mousemove", "mousedown", "mouseup", "click")
  )
  expect_true(all(vapply(save, function(e) isTRUE(e$isTrusted), logical(1))))
})

test_that("pz_click scrolls off-screen elements into view first", {
  page <- local_actions_page()
  expect_equal(pz_js(page, "window.scrollY"), 0)
  pz_click(page, "#below-fold")
  expect_gt(pz_js(page, "window.scrollY"), 0)
  log <- log_entries(page)
  expect_length(log_ids(log, "below-fold", "click"), 1)
})

test_that("pz_hover moves the pointer without pressing", {
  page <- local_actions_page()
  res <- withVisible(pz_hover(page, "#save"))
  expect_false(res$visible)
  expect_identical(res$value, page)

  log <- log_entries(page)
  save <- log_ids(log, "save")
  # Only a move for the button: nothing was pressed, so no mousedown or
  # click reached it.
  expect_identical(log_types(save), "mousemove")
})

test_that("pz_type clicks to focus, then inserts the text", {
  page <- local_actions_page()
  pz_type(page, "Ada", target = "#name")
  expect_equal(pz_js(page, "document.getElementById('name').value"), "Ada")

  log <- log_entries(page)
  # Focus came from the real click pipeline: a trusted focus event.
  focus <- log_ids(log, "name", "focus")
  expect_length(focus, 1)
  expect_true(focus[[1]]$isTrusted)
  input <- log_ids(log, "name", "input")
  expect_identical(input[[1]]$value, "Ada")
})

test_that("pz_type with target = NULL types into the focused element", {
  page <- local_actions_page()
  pz_focus(page, "#bio")
  pz_type(page, "hello")
  expect_equal(pz_js(page, "document.getElementById('bio').value"), "hello")
})

test_that("pz_type with nothing focused is a no-op", {
  page <- local_actions_page()
  pz_type(page, "zzz")
  expect_equal(pz_js(page, "document.getElementById('name').value"), "")
  expect_equal(pz_js(page, "document.getElementById('bio').value"), "")
})

test_that("pz_press sends keydown and keyup to the focused element", {
  page <- local_actions_page()
  pz_click(page, "#name")
  pz_press(page, "Enter")
  log <- log_entries(page)
  keys <- Filter(function(e) e$type %in% c("keydown", "keyup"), log)
  enter <- Filter(function(e) identical(e$key, "Enter"), keys)
  expect_identical(log_types(enter), c("keydown", "keyup"))
  expect_true(all(vapply(enter, function(e) isTRUE(e$isTrusted), logical(1))))
})

test_that("pz_press implies Shift for uppercase keys", {
  page <- local_actions_page()
  pz_click(page, "#name")
  pz_press(page, "Control+A")
  log <- log_entries(page)
  keydowns <- Filter(function(e) identical(e$type, "keydown"), log)
  keys <- vapply(keydowns, function(e) e$key, character(1))
  i_ctrl <- which(keys == "Control")[1]
  i_a <- which(keys == "A")[1]
  expect_gte(i_a, 1)
  # The Control keydown precedes the "A" keydown, and the "A" carries
  # Control plus the implied Shift, exactly like Playwright.
  expect_lt(i_ctrl, i_a)
  expect_true(all(c("Control", "Shift") %in% keydowns[[i_a]]$mods))
})

test_that("pz_press presses a vector of keys in order", {
  page <- local_actions_page()
  pz_click(page, "#name")
  pz_press(page, c("ArrowDown", "Enter"))
  log <- log_entries(page)
  keydowns <- Filter(function(e) identical(e$type, "keydown"), log)
  keys <- vapply(keydowns, function(e) e$key, character(1))
  expect_identical(keys, c("ArrowDown", "Enter"))
})

test_that("pz_focus and pz_blur move document.activeElement", {
  page <- local_actions_page()
  pz_focus(page, "#name")
  expect_equal(pz_js(page, "document.activeElement.id"), "name")
  expect_length(log_ids(log_entries(page), "name", "focus"), 1)

  pz_blur(page)
  log <- log_entries(page)
  expect_length(log_ids(log, "name", "blur"), 1)
  expect_equal(pz_js(page, "document.activeElement.tagName"), "BODY")
})

test_that("pz_blur at the root with nothing focused is a no-op", {
  page <- local_actions_page()
  expect_invisible(pz_blur(page))
  expect_equal(pz_js(page, "document.activeElement.tagName"), "BODY")
})

test_that("element actions need a target at the root context", {
  page <- local_actions_page()
  expect_error(pz_click(page), class = "paparazzi_error_target")
  expect_error(pz_hover(page), class = "paparazzi_error_target")
  expect_error(pz_focus(page), class = "paparazzi_error_target")
})

test_that("element actions error on multiple matches", {
  page <- local_actions_page()
  expect_error(pz_click(page, ".dup"), class = "paparazzi_error_multiple")
  expect_error(pz_hover(page, ".dup"), class = "paparazzi_error_multiple")
  expect_error(pz_type(page, "x", target = ".dup"), class = "paparazzi_error_multiple")
  expect_error(pz_focus(page, ".dup"), class = "paparazzi_error_multiple")
})

test_that("pz_blur on a scoped context", {
  page <- local_actions_page()

  els <- loc_resolve(page, ".dup", multiple = "all")
  on.exit(release_elements(els), add = TRUE)
  ctx <- PaparazziContext$new(page)
  ctx$scope <- list(els)
  expect_error(pz_blur(ctx), class = "paparazzi_error_multiple")

  els1 <- loc_resolve(page, "#name", multiple = "error")
  on.exit(release_elements(els1), add = TRUE)
  ctx <- PaparazziContext$new(page)
  ctx$scope <- list(els1)
  pz_focus(page, "#name")
  expect_equal(pz_js(page, "document.activeElement.id"), "name")
  pz_blur(ctx)
  expect_equal(pz_js(page, "document.activeElement.tagName"), "BODY")
})

test_that("actions reject extra arguments", {
  page <- local_actions_page()
  expect_error(pz_click(page, "#save", "bogus"), "empty")
  expect_error(pz_type(page, "a", "bogus"), "empty")
  expect_error(pz_press(page, "Enter", "bogus"), "empty")
  expect_error(pz_blur(page, "bogus"), "empty")
})

test_that("pz_type and pz_press validate their inputs", {
  page <- local_actions_page()
  expect_error(pz_type(page, 42), class = "rlang_error")
  expect_error(pz_type(page, c("a", "b")), class = "rlang_error")
  expect_error(pz_press(page, ""), class = "paparazzi_error_key")
  expect_error(pz_press(page, "Control+Foo"), class = "paparazzi_error_key")
  expect_error(pz_press(page, character(0)), "at least one")
  expect_error(pz_press(page, NA_character_), "NA")
})

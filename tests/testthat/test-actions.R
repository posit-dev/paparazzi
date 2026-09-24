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
  expect_error(
    pz_type(page, "x", target = ".dup"),
    class = "paparazzi_error_multiple"
  )
  expect_error(pz_focus(page, ".dup"), class = "paparazzi_error_multiple")
})

test_that("pz_blur on a scoped context", {
  page <- local_actions_page()

  els <- loc_resolve(page, ".dup", multiple = "all")
  withr::defer(release_elements(els))
  ctx <- PaparazziContext$new(page)
  ctx$scope <- list(els)
  expect_error(pz_blur(ctx), class = "paparazzi_error_multiple")

  els1 <- loc_resolve(page, "#name", multiple = "error")
  withr::defer(release_elements(els1))
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
  expect_error(pz_press(page, character(0)), "at least 1 element")
  expect_error(pz_press(page, NA_character_), "NA")
})

test_that("an explicit target resolves lazily inside a pinned scope", {
  page <- local_actions_page()
  page$default_timeout <- 0.5
  ctx <- pz_find(page, "form")

  # The explicit target resolves against the pinned scope, not the
  # document: #save lives inside the form, #below-fold outside it.
  expect_invisible(pz_click(ctx, "#save"))
  expect_length(log_ids(log_entries(page), "save", "click"), 1)
  expect_error(pz_click(ctx, "#below-fold"), class = "paparazzi_error_timeout")
})

test_that("a detached scope surfaces through an action as a classed error", {
  page <- local_actions_page()
  ctx <- pz_find(page, "#save")

  # Re-render the form so the pinned element drops out of the page; the
  # next action must raise, never silently re-query the scope.
  pz_js(page, "document.querySelector('form').innerHTML = ''")
  err <- expect_error(pz_click(ctx), class = "paparazzi_error_detached")
  expect_match(
    paste(conditionMessage(err), collapse = " "),
    "Scope element is no longer in the page"
  )
  expect_length(log_ids(log_entries(page), "save", "click"), 0)
})

# The actionability fixture (actionability.html) exercises the
# auto-wait that stands between resolution and pointer dispatch:
# #never is permanently display:none, #zero is visible by
# checkVisibility() but has an empty box, and #reveals is hidden and
# shown 500ms after the test arms the reveal. A pointer action on a
# non-actionable element must time out rather than dispatch at (0, 0).

# The same "visible" the actionability wait and pz_expect_visible()
# use, read directly off the fixture for the hidden-before assertions.
hidden_js <- function(id) {
  paste0(
    "document.getElementById('",
    id,
    "')",
    ".checkVisibility({ checkVisibilityCSS: true })"
  )
}

test_that("pz_click waits out a hidden element's transition to visible", {
  page <- local_actionability_page()
  # #reveals is display:none; arm the 500ms reveal on demand and prove
  # it is hidden when the click starts, so the click genuinely waits.
  expect_false(pz_js(page, hidden_js("reveals")))
  pz_js(page, "window.__pzReveal()")
  expect_invisible(pz_click(page, "#reveals"))
  log <- log_entries(page)
  expect_length(log_ids(log, "reveals", "click"), 1)
  expect_true(log_ids(log, "reveals", "click")[[1]]$isTrusted)
  # Nothing was dispatched at (0, 0) while the element was hidden.
  expect_length(log, 1)
})

test_that("pz_click on an element that never becomes visible times out", {
  page <- local_actionability_page()
  page$default_timeout <- 0.5
  err <- expect_error(
    pz_click(page, "#never"),
    class = "paparazzi_error_timeout"
  )
  expect_match(paste(conditionMessage(err), collapse = " "), "#never")
  # No dispatch ever happened, at (0, 0) or anywhere else.
  expect_length(log_entries(page), 0)
})

test_that("pz_click refuses a zero-sized element", {
  page <- local_actionability_page()
  page$default_timeout <- 0.5
  # #zero passes checkVisibility() but has an empty box, so the center
  # point is not a place on the element; the click must time out
  # without dispatching into whatever sits at that point.
  expect_error(pz_click(page, "#zero"), class = "paparazzi_error_timeout")
  expect_length(log_entries(page), 0)
})

test_that("pz_hover on a hidden element times out", {
  page <- local_actionability_page()
  page$default_timeout <- 0.5
  # Hover shares the click pipeline's actionability wait.
  expect_error(pz_hover(page, "#never"), class = "paparazzi_error_timeout")
})

test_that("a scoped pointer action waits out its pinned element's reveal", {
  page <- local_actionability_page()
  # A hidden element matches a scope pin (it is in the DOM); the
  # pointer action on the pinned set must wait for it too.
  ctx <- pz_find(page, "#reveals")
  expect_false(pz_js(page, hidden_js("reveals")))
  pz_js(page, "window.__pzReveal()")
  expect_invisible(pz_click(ctx))
  log <- log_entries(page)
  expect_length(log_ids(log, "reveals", "click"), 1)
  expect_true(log_ids(log, "reveals", "click")[[1]]$isTrusted)
})

test_that("pz_type with a hidden target times out before typing", {
  page <- local_actionability_page()
  page$default_timeout <- 0.5
  expect_error(
    pz_type(page, "Ada", target = "#never"),
    class = "paparazzi_error_timeout"
  )
  expect_length(log_entries(page), 0)
})

# The form fixture (form.html) exercises value setting end to end: a
# form with every control pz_set_value() covers, a framework-style
# controlled input whose instance-level value accessor is trapped
# (window.__pzTraps counts trap hits -- the native prototype setter
# must never trigger it), and a contenteditable div. The sink logs
# input and change with {type, id, isTrusted, value, checked}.

test_that("pz_set_value sets a text input and dispatches input then change", {
  page <- local_form_page()
  page <- expect_invisible(pz_set_value(page, "Ada", target = "#text"))
  expect_equal(pz_js(page, "document.getElementById('text').value"), "Ada")

  text <- log_ids(log_entries(page), "text")
  expect_identical(log_types(text), c("input", "change"))
  expect_equal(text[[1]]$value, "Ada")
  # focus came first: the element is focused after the set
  expect_equal(pz_js(page, "document.activeElement.id"), "text")
})

test_that("pz_set_value sets and clears a textarea", {
  page <- local_form_page()
  pz_set_value(page, "a bio", target = "#textarea")
  expect_equal(
    pz_js(page, "document.getElementById('textarea').value"),
    "a bio"
  )
  # Clearing is pz_set_value("") -- there is no pz_clear().
  pz_set_value(page, "", target = "#textarea")
  expect_equal(pz_js(page, "document.getElementById('textarea').value"), "")
})

test_that("pz_set_value selects a native select by option value", {
  page <- local_form_page()
  pz_set_value(page, "b", target = "#select")
  el <- "document.getElementById('select')"
  expect_equal(pz_js(page, paste0(el, ".value")), "b")
  expect_equal(
    pz_js(page, paste0(el, ".selectedOptions[0].textContent")),
    "Beta"
  )

  err <- expect_error(
    pz_set_value(page, "zz", target = "#select"),
    class = "paparazzi_error_value"
  )
  expect_match(
    paste(conditionMessage(err), collapse = " "),
    "No option with value"
  )
})

test_that("pz_set_value checks and unchecks a checkbox", {
  page <- local_form_page()
  pz_set_value(page, TRUE, target = "#check")
  expect_true(pz_js(page, "document.getElementById('check').checked"))
  check <- log_ids(log_entries(page), "check", "change")
  expect_length(check, 1)

  pz_set_value(page, FALSE, target = "#check")
  expect_false(pz_js(page, "document.getElementById('check').checked"))
})

test_that("pz_set_value maintains radio groups", {
  page <- local_form_page()
  radios <- c("radio1", "radio2", "radio3")
  state <- function() {
    vapply(
      radios,
      function(id) {
        pz_js(page, paste0("document.getElementById('", id, "').checked"))
      },
      logical(1)
    )
  }

  pz_set_value(page, TRUE, target = "#radio1")
  expect_identical(state(), c(radio1 = TRUE, radio2 = FALSE, radio3 = FALSE))

  # Checking radio2 unchecks radio1 but leaves the other-named group
  # alone; the native checked setter doesn't do this by itself.
  pz_set_value(page, TRUE, target = "#radio2")
  expect_identical(state(), c(radio1 = FALSE, radio2 = TRUE, radio3 = FALSE))
})

test_that("pz_set_value radio groups stop at the form owner", {
  page <- local_form_page()
  # Same name in two different forms: separate groups, even though the
  # candidates for a formless radio come from the whole document.
  pz_set_value(page, TRUE, target = "#orphan-free")
  expect_true(pz_js(page, "document.getElementById('orphan-free').checked"))
  expect_false(pz_js(page, "document.getElementById('orphan-form').checked"))

  pz_set_value(page, TRUE, target = "#orphan-form")
  # Different form owners (one formless, one inside the-form): neither
  # is in the other's group, so both stay checked.
  expect_true(pz_js(page, "document.getElementById('orphan-free').checked"))
  expect_true(pz_js(page, "document.getElementById('orphan-form').checked"))

  # Same again for formless radios associated via the form="..."
  # attribute: peers are found through the tree root and matched by
  # form owner, so loose-b and loose-c stay independent.
  pz_set_value(page, TRUE, target = "#loose-b")
  expect_true(pz_js(page, "document.getElementById('loose-b').checked"))
  expect_false(pz_js(page, "document.getElementById('loose-c').checked"))

  pz_set_value(page, TRUE, target = "#loose-c")
  # form-b and form-c are distinct form owners, so loose-c's set does
  # not uncheck loose-b.
  expect_true(pz_js(page, "document.getElementById('loose-b').checked"))
  expect_true(pz_js(page, "document.getElementById('loose-c').checked"))
})

test_that("pz_set_value covers range and number inputs", {
  page <- local_form_page()
  pz_set_value(page, 75, target = "#range")
  expect_equal(pz_js(page, "document.getElementById('range').value"), "75")
  pz_set_value(page, 5, target = "#number")
  expect_equal(pz_js(page, "document.getElementById('number').value"), "5")

  # A value the browser clamps or rejects is an error, not a silent set.
  err <- expect_error(
    pz_set_value(page, 150, target = "#range"),
    class = "paparazzi_error_value"
  )
  expect_match(paste(conditionMessage(err), collapse = " "), "kept")
})

test_that("pz_set_value covers date inputs and rejects malformed dates", {
  page <- local_form_page()
  pz_set_value(page, "2026-01-01", target = "#date")
  expect_equal(
    pz_js(page, "document.getElementById('date').value"),
    "2026-01-01"
  )
  expect_error(
    pz_set_value(page, "not a date", target = "#date"),
    class = "paparazzi_error_value"
  )
})

test_that("pz_set_value leaves a control untouched when the set fails", {
  page <- local_form_page()
  # A failed set must not leave the element mutated: the browser
  # clamps or coerces before rejecting, so the JS restores the
  # previous value before returning the error.
  pz_set_value(page, "2026-01-01", target = "#date")
  expect_error(
    pz_set_value(page, "not a date", target = "#date"),
    class = "paparazzi_error_value"
  )
  expect_equal(
    pz_js(page, "document.getElementById('date').value"),
    "2026-01-01"
  )

  pz_set_value(page, 5, target = "#number")
  expect_error(
    pz_set_value(page, "abc", target = "#number"),
    class = "paparazzi_error_value"
  )
  expect_equal(pz_js(page, "document.getElementById('number').value"), "5")

  # No events either: the element never observes a failed set.
  n <- length(log_entries(page))
  expect_error(pz_set_value(page, "not a date", target = "#date"))
  expect_length(log_entries(page), n)
})

test_that("pz_set_value rejects file inputs", {
  page <- local_form_page()
  err <- expect_error(
    pz_set_value(page, "x", target = "#file"),
    class = "paparazzi_error_value"
  )
  expect_match(
    paste(conditionMessage(err), collapse = " "),
    "use pz_set_files\\(\\)"
  )
  # The error fires before the element is focused or mutated.
  expect_equal(pz_js(page, "document.activeElement.id"), "")
})

test_that("pz_set_value bypasses a framework's controlled input", {
  page <- local_form_page()
  # The controlled input traps instance-level value assignment, the way
  # a framework that owns the value property does. The native prototype
  # setter must bypass the trap entirely: the trap counter stays at 0
  # while the native getter reads back the new value.
  pz_set_value(page, "via native", target = "#controlled")
  expect_equal(pz_js(page, "window.__pzTraps"), 0)
  expect_equal(
    pz_js(
      page,
      paste(
        "Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')",
        ".get.call(document.getElementById('controlled'))"
      )
    ),
    "via native"
  )
  # The trap's own backing value never moved.
  expect_equal(pz_js(page, "document.getElementById('controlled').value"), "")
  controlled <- log_ids(log_entries(page), "controlled")
  expect_identical(log_types(controlled), c("input", "change"))
})

test_that("pz_set_value replaces contenteditable content in one step", {
  page <- local_form_page()
  pz_set_value(page, "new text", target = "#editor")
  expect_equal(
    pz_js(page, "document.getElementById('editor').textContent"),
    "new text"
  )
  # The fallback goes through CDP insertText, so the input event is a
  # real, trusted one.
  ed <- log_ids(log_entries(page), "editor", "input")
  expect_length(ed, 1)
  expect_true(ed[[1]]$isTrusted)

  # An empty value selects all and deletes, leaving the element empty.
  pz_set_value(page, "", target = "#editor")
  expect_equal(pz_js(page, "document.getElementById('editor').textContent"), "")
})

test_that("pz_set_value rejects mismatched values and targets", {
  page <- local_form_page()
  expect_error(
    pz_set_value(page, TRUE, target = "#text"),
    class = "paparazzi_error_value"
  )
  expect_error(
    pz_set_value(page, "yes", target = "#check"),
    class = "paparazzi_error_value"
  )
  err <- expect_error(
    pz_set_value(page, "x", target = "#para"),
    class = "paparazzi_error_value"
  )
  expect_match(
    paste(conditionMessage(err), collapse = " "),
    "not a form control"
  )
})

test_that("pz_set_value validates its input", {
  page <- local_form_page()
  expect_error(pz_set_value(page, c("a", "b"), target = "#text"), "single")
  expect_error(pz_set_value(page, NA, target = "#text"), "NA")
  expect_error(pz_set_value(page, 42, "bogus", target = "#text"), "empty")
  expect_error(pz_set_value(page, list()), class = "rlang_error")
})

test_that("pz_set_value needs a target at the root and errors on multiple matches", {
  page <- local_form_page()
  f <- tempfile()
  writeLines("x", f)
  expect_error(pz_set_value(page, "x"), class = "paparazzi_error_target")
  expect_error(pz_set_files(page, f), class = "paparazzi_error_target")
  expect_error(
    pz_set_value(page, "x", target = "#the-form input[type=radio]"),
    class = "paparazzi_error_multiple"
  )
  expect_error(
    pz_set_files(page, f, target = ".dupfile"),
    class = "paparazzi_error_multiple"
  )
})

test_that("pz_set_value acts on the scope element of a scoped context", {
  page <- local_form_page()
  ctx <- pz_find(page, "#text")
  pz_set_value(ctx, "scoped")
  expect_equal(pz_js(page, "document.getElementById('text').value"), "scoped")
})

test_that("pz_set_files attaches files to a file input", {
  page <- local_form_page()
  f1 <- tempfile(fileext = ".txt")
  writeLines("hello", f1)
  f2 <- tempfile(fileext = ".txt")
  writeLines("world", f2)

  pz_set_files(page, f1, target = "#file")
  el <- "document.getElementById('file')"
  expect_equal(pz_js(page, paste0(el, ".files.length")), 1)
  expect_equal(pz_js(page, paste0(el, ".files[0].name")), basename(f1))
  expect_equal(pz_js(page, paste0(el, ".files[0].size")), 6)
  # setFileInputFiles produces a genuine, trusted change event.
  change <- log_ids(log_entries(page), "file", "change")
  expect_length(change, 1)
  expect_true(change[[1]]$isTrusted)

  pz_set_files(page, c(f1, f2), target = "#file-multi")
  el <- "document.getElementById('file-multi')"
  expect_equal(pz_js(page, paste0(el, ".files.length")), 2)
  expect_equal(
    pz_js(
      page,
      paste0("Array.from(", el, ".files).map((f) => f.name).join('|')")
    ),
    paste(c(basename(f1), basename(f2)), collapse = "|")
  )
})

test_that("pz_set_files rejects non-file inputs and validates paths", {
  page <- local_form_page()
  f <- tempfile()
  writeLines("x", f)
  expect_error(
    pz_set_files(page, f, target = "#text"),
    class = "paparazzi_error_value"
  )
  expect_error(
    pz_set_files(page, tempfile(), target = "#file"),
    class = "paparazzi_error_input"
  )
  expect_error(pz_set_files(page, character(0), target = "#file"), "at least 1")
  expect_error(pz_set_files(page, NA, target = "#file"), "NA")
  expect_error(pz_set_files(page, f, "bogus", target = "#file"), "empty")
})

# --- Advanced interactions (pz_select_text, pz_scroll, pz_drag) on the
# advanced.html fixture; helpers in helper-advanced.R. ---

test_that("pz_select_text selects an exact substring across inline tags", {
  page <- local_advanced_page()
  page <- expect_invisible(
    pz_select_text(page, "galapagos penguins", target = "#rich")
  )
  # The window selection is the real thing: the match starts inside the
  # <em> and ends inside the <strong>, and reads back as one string.
  expect_equal(pz_js(page, "window.getSelection().toString()"), "galapagos penguins")
  expect_equal(
    pz_js(page, "window.getSelection().anchorNode.parentElement.tagName"),
    "EM"
  )
  expect_equal(
    pz_js(page, "window.getSelection().extentNode.parentElement.tagName"),
    "STRONG"
  )
})

test_that("pz_select_text lets typing replace the selection", {
  page <- local_advanced_page()
  pz_select_text(page, "otters", target = "#editor")
  pz_type(page, "penguins")
  expect_equal(
    pz_js(page, "document.getElementById('editor').textContent"),
    "penguins are playful"
  )
})

test_that("pz_select_text errors on absent text, emptiness, and multiple matches", {
  page <- local_advanced_page()
  expect_error(
    pz_select_text(page, "no such text", target = "#rich"),
    class = "paparazzi_error_text"
  )
  expect_error(
    pz_select_text(page, ""),
    class = "paparazzi_error_input"
  )
  expect_error(
    pz_select_text(page, "duplicate", target = ".dup-select"),
    class = "paparazzi_error_multiple"
  )
  expect_error(
    pz_select_text(page, "otters"),
    class = "paparazzi_error_target"
  )
})

test_that("pz_scroll scrolls the page by, to a direction, and a target into view", {
  page <- local_advanced_page()

  # by: a pixel delta against the root container, the document.
  page <- expect_invisible(pz_scroll(page, by = c(0, 300)))
  expect_equal(pz_js(page, "window.scrollY"), 300)

  # to: the direction vocabulary, straight to the edge.
  pz_scroll(page, to = "bottom")
  expect_true(pz_js(page,
    "window.scrollY === document.documentElement.scrollHeight - window.innerHeight"
  ))
  pz_scroll(page, to = "top")
  expect_equal(pz_js(page, "window.scrollY"), 0)

  # target: auto-scrolls a below-fold element into view.
  pz_scroll(page, target = "#tall-bottom")
  y <- pz_js(page, "document.getElementById('tall-bottom').getBoundingClientRect().y")
  expect_true(y >= 0 && y < pz_js(page, "window.innerHeight"))
})

test_that("pz_scroll by and to act on the scope's scroll container", {
  page <- local_advanced_page()

  # The scope element itself is scrollable: it is the container.
  ctx <- pz_find(page, "#scroller")
  ctx <- expect_invisible(pz_scroll(ctx, by = c(0, 120)))
  expect_equal(pz_js(page, "document.getElementById('scroller').scrollTop"), 120)
  pz_scroll(ctx, to = "bottom")
  expect_true(pz_js(page, paste(
    "document.getElementById('scroller').scrollTop ===",
    "document.getElementById('scroller').scrollHeight -",
    "document.getElementById('scroller').clientHeight"
  )))

  # A scope inside a scrollable container resolves up to it, and the
  # page never moves.
  ctx <- pz_find(page, "#deep-item")
  pz_scroll(ctx, to = "top")
  pz_scroll(ctx, by = c(0, 40))
  expect_equal(pz_js(page, "document.getElementById('scroller').scrollTop"), 40)
  expect_equal(pz_js(page, "window.scrollY"), 0)
})

test_that("pz_scroll validates its modes", {
  page <- local_advanced_page()
  expect_error(pz_scroll(page), class = "paparazzi_error_input")
  expect_error(
    pz_scroll(page, target = "#rich", by = c(0, 100)),
    class = "paparazzi_error_input"
  )
  expect_error(
    pz_scroll(page, to = "bottom", by = c(0, 100)),
    class = "paparazzi_error_input"
  )
  # by and to reuse the shared offset and direction checkers.
  expect_error(pz_scroll(page, by = "lots"), class = "paparazzi_error_input")
  expect_error(pz_scroll(page, to = "sideways"), class = "paparazzi_error_input")
})

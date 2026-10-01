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
  page <- expect_invisible(pz_act_type(page, "Ada", target = "#name"))
  page <- expect_invisible(pz_act_click(page, "#save"))
  page <- expect_invisible(pz_act_press(page, "Enter"))
  page <- expect_invisible(pz_act_focus(page, "#bio"))
  page <- expect_invisible(pz_act_blur(page))

  expect_equal(pz_js(page, "document.getElementById('name').value"), "Ada")

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

test_that("pz_act_click produces trusted mouse events in order", {
  page <- local_actions_page()
  pz_act_click(page, "#save")
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

test_that("pz_act_click validates effect and effect_color", {
  page <- local_cursor_page()
  expect_error(
    pz_act_click(page, "#btn", effect = "slide"),
    class = "rlang_error"
  )
  expect_error(
    pz_act_click(page, "#btn", effect = NA_character_),
    class = "rlang_error"
  )
  expect_error(
    pz_act_click(page, "#btn", effect_color = ""),
    "effect_color.*empty string"
  )
  expect_error(
    pz_act_click(page, "#btn", effect_color = 7),
    class = "rlang_error"
  )

  # A valid staged value does not excuse a bad per-call one.
  pz_stage(page, click_effect = "ring")
  expect_error(
    pz_act_click(page, "#btn", effect = "slide"),
    class = "rlang_error"
  )
})

test_that("click effects draw nothing without a recording", {
  page <- local_cursor_page()
  page |> pz_act_click("#btn", effect = "ring", effect_color = "#2563eb")
  page |> pz_stage(click_effect = "ring") |> pz_act_click("#btn")
  expect_equal(pz_js(page, "window.__log.clicks"), 2)
  expect_null(cursor_overlay_state(page))
})

test_that("the click effect resolves per call and styles only pz_act_click", {
  page <- local_cursor_page()
  page |>
    pz_stage(click_effect = "none", click_effect_color = "#2563eb") |>
    pz_cursor_move("#btn")

  calls <- list()
  local_mocked_bindings(
    recorder_active = function(page) TRUE,
    cursor_press = function(ctx, pressed) {
      calls <<- c(calls, list(list(kind = "press", pressed = pressed)))
      ctx_return(ctx)
    },
    cursor_ring = function(ctx, point, color) {
      calls <<- c(calls, list(list(kind = "ring", color = color)))
      ctx_return(ctx)
    }
  )
  kinds <- function() {
    vapply(calls, `[[`, character(1), "kind")
  }

  # The staged "none": neither a press nor a ring.
  page |> pz_act_click("#btn")
  expect_length(calls, 0)

  # A per-call effect overrides the staged value; the color falls back
  # to the staged one.
  page |> pz_act_click("#btn", effect = "ring")
  expect_length(calls, 1)
  expect_identical(calls[[1]]$kind, "ring")
  expect_identical(calls[[1]]$color, "#2563eb")

  calls <- list()
  page |> pz_act_click("#btn", effect = "ring", effect_color = "#123456")
  expect_identical(calls[[1]]$color, "#123456")

  calls <- list()
  page |> pz_act_click("#btn", effect = "press")
  expect_identical(kinds(), c("press", "press"))
  expect_identical(
    vapply(calls, `[[`, logical(1), "pressed"),
    c(TRUE, FALSE)
  )

  # pz_act_type()'s focus click shares dispatch_click() but keeps the
  # press scale.
  calls <- list()
  page |> pz_act_type("hi", target = "#name")
  expect_identical(kinds(), c("press", "press"))

  # So do drags, which press through cursor_press() directly.
  adv <- local_advanced_page()
  pz_stage(adv, click_effect = "none")
  calls <- list()
  pz_act_drag(adv, "#dragbox", "#dropzone")
  expect_true("press" %in% kinds())
})

test_that("pz_act_click scrolls off-screen elements into view first", {
  page <- local_actions_page()
  expect_equal(pz_js(page, "window.scrollY"), 0)
  pz_act_click(page, "#below-fold")
  expect_gt(pz_js(page, "window.scrollY"), 0)
  log <- log_entries(page)
  expect_length(log_ids(log, "below-fold", "click"), 1)
})

test_that("pz_act_hover moves the pointer without pressing", {
  page <- local_actions_page()
  res <- withVisible(pz_act_hover(page, "#save"))
  expect_false(res$visible)
  expect_identical(res$value, page)

  log <- log_entries(page)
  save <- log_ids(log, "save")
  # Only a move for the button: nothing was pressed, so no mousedown or
  # click reached it.
  expect_identical(log_types(save), "mousemove")
})

test_that("pz_act_type clicks to focus, then inserts the text", {
  page <- local_actions_page()
  pz_act_type(page, "Ada", target = "#name")
  expect_equal(pz_js(page, "document.getElementById('name').value"), "Ada")

  log <- log_entries(page)
  # Focus came from the real click pipeline: a trusted focus event.
  focus <- log_ids(log, "name", "focus")
  expect_length(focus, 1)
  expect_true(focus[[1]]$isTrusted)
  input <- log_ids(log, "name", "input")
  expect_identical(input[[1]]$value, "Ada")
})

test_that("pz_act_type with target = NULL types into the focused element", {
  page <- local_actions_page()
  pz_act_focus(page, "#bio")
  pz_act_type(page, "hello")
  expect_equal(pz_js(page, "document.getElementById('bio').value"), "hello")
})

test_that("pz_act_type with nothing focused is a no-op", {
  page <- local_actions_page()
  pz_act_type(page, "zzz")
  expect_equal(pz_js(page, "document.getElementById('name').value"), "")
  expect_equal(pz_js(page, "document.getElementById('bio').value"), "")
})

test_that("pz_act_press sends keydown and keyup to the focused element", {
  page <- local_actions_page()
  pz_act_click(page, "#name")
  pz_act_press(page, "Enter")
  log <- log_entries(page)
  keys <- Filter(function(e) e$type %in% c("keydown", "keyup"), log)
  enter <- Filter(function(e) identical(e$key, "Enter"), keys)
  expect_identical(log_types(enter), c("keydown", "keyup"))
  expect_true(all(vapply(enter, function(e) isTRUE(e$isTrusted), logical(1))))
})

test_that("pz_act_press resolves Mod using the browser's reported platform", {
  page <- local_actions_page()
  pz_js(
    page,
    paste0(
      "window.__modKeys = []; document.addEventListener('keydown', e => {",
      "if (e.key.toLowerCase() === 'k') window.__modKeys.push({metaKey: e.metaKey, ctrlKey: e.ctrlKey, shiftKey: e.shiftKey});",
      "});"
    )
  )
  pz_act_click(page, "#name")

  platforms <- list(
    list(ua = "macOS", legacy = "Win32", meta = TRUE),
    list(ua = "Windows", legacy = "MacIntel", meta = FALSE),
    list(ua = "", legacy = "MacIntel", meta = TRUE),
    list(ua = "", legacy = "Win32", meta = FALSE)
  )
  for (platform in platforms) {
    pz_js(
      page,
      sprintf(
        paste0(
          "Object.defineProperty(navigator, 'userAgentData', ",
          "{configurable: true, value: {platform: '%s'}}); ",
          "Object.defineProperty(navigator, 'platform', ",
          "{configurable: true, value: '%s'});"
        ),
        platform$ua,
        platform$legacy
      )
    )
    pz_js(page, "window.__modKeys = []")
    pz_act_press(
      page,
      if (identical(platform$ua, "macOS")) "Mod+K" else "Mod+k"
    )
    keys <- pz_js(page, "window.__modKeys")
    expect_length(keys, 1L)
    key <- keys[[1]]
    expect_identical(key$metaKey, platform$meta)
    expect_identical(key$ctrlKey, !platform$meta)
    if (identical(platform$ua, "macOS")) {
      expect_identical(key$shiftKey, TRUE)
    }
  }

  pz_js(
    page,
    "Object.defineProperty(navigator, 'userAgentData', {configurable: true, value: undefined})"
  )
  pz_js(page, "window.__modKeys = []")
  pz_act_press(page, "Mod+k")
  keys <- pz_js(page, "window.__modKeys")
  expect_length(keys, 1L)
  key <- keys[[1]]
  expect_identical(key$metaKey, FALSE)
  expect_identical(key$ctrlKey, TRUE)

  pz_js(page, "window.__modKeys = []")
  pz_act_press(page, "Control+k")
  keys <- pz_js(page, "window.__modKeys")
  expect_length(keys, 1L)
  expect_identical(keys[[1]]$ctrlKey, TRUE)
  expect_identical(keys[[1]]$metaKey, FALSE)
  pz_js(page, "window.__modKeys = []")
  pz_act_press(page, "Meta+k")
  keys <- pz_js(page, "window.__modKeys")
  expect_length(keys, 1L)
  expect_identical(keys[[1]]$metaKey, TRUE)
  expect_identical(keys[[1]]$ctrlKey, FALSE)
})

test_that("Enter implicitly submits a form from a text input", {
  page <- local_actions_page()
  pz_js(
    page,
    "document.querySelector('form').addEventListener('submit', function(e) { e.preventDefault(); window.__submitted = true; })"
  )
  pz_act_click(page, "#name")
  pz_act_press(page, "Enter")

  expect_true(pz_js(page, "window.__submitted === true"))
})

test_that("Enter inserts a newline in a textarea", {
  page <- local_actions_page()
  pz_act_click(page, "#bio")
  pz_act_type(page, "a")
  pz_act_press(page, "Enter")
  pz_act_type(page, "b")

  expect_identical(pz_js(page, "document.getElementById('bio').value"), "a\nb")
})

test_that("Shift+Enter inserts a newline in a textarea", {
  page <- local_actions_page()
  pz_act_click(page, "#bio")
  pz_act_type(page, "a")
  pz_act_press(page, "Shift+Enter")
  pz_act_type(page, "b")

  expect_identical(pz_js(page, "document.getElementById('bio').value"), "a\nb")
})

test_that("pz_act_press implies Shift for uppercase keys", {
  page <- local_actions_page()
  pz_act_click(page, "#name")
  pz_act_press(page, "Control+A")
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

test_that("pz_act_press presses a vector of keys in order", {
  page <- local_actions_page()
  pz_act_click(page, "#name")
  pz_act_press(page, c("ArrowDown", "Enter"))
  log <- log_entries(page)
  keydowns <- Filter(function(e) identical(e$type, "keydown"), log)
  keys <- vapply(keydowns, function(e) e$key, character(1))
  expect_identical(keys, c("ArrowDown", "Enter"))
})

test_that("pz_act_focus and pz_act_blur move document.activeElement", {
  page <- local_actions_page()
  pz_act_focus(page, "#name")
  expect_equal(pz_js(page, "document.activeElement.id"), "name")
  expect_length(log_ids(log_entries(page), "name", "focus"), 1)

  pz_act_blur(page)
  log <- log_entries(page)
  expect_length(log_ids(log, "name", "blur"), 1)
  expect_equal(pz_js(page, "document.activeElement.tagName"), "BODY")
})

test_that("pz_act_blur at the root with nothing focused is a no-op", {
  page <- local_actions_page()
  expect_invisible(pz_act_blur(page))
  expect_equal(pz_js(page, "document.activeElement.tagName"), "BODY")
})

test_that("action element resolution validates context before reading the scope", {
  expect_error(action_elements(1, NULL), class = "paparazzi_error_context")
  expect_error(pz_act_click(1), class = "paparazzi_error_context")
})

test_that("element actions need a target at the root context", {
  page <- local_actions_page()
  expect_error(pz_act_click(page), class = "paparazzi_error_target")
  expect_error(pz_act_hover(page), class = "paparazzi_error_target")
  expect_error(pz_act_focus(page), class = "paparazzi_error_target")
})

test_that("element actions error on multiple matches", {
  page <- local_actions_page()
  expect_error(pz_act_click(page, ".dup"), class = "paparazzi_error_multiple")
  expect_error(pz_act_hover(page, ".dup"), class = "paparazzi_error_multiple")
  expect_error(
    pz_act_type(page, "x", target = ".dup"),
    class = "paparazzi_error_multiple"
  )
  expect_error(pz_act_focus(page, ".dup"), class = "paparazzi_error_multiple")
})

test_that("pz_act_blur on a scoped context", {
  page <- local_actions_page()

  els <- loc_resolve(page, ".dup", multiple = "all")
  withr::defer(release_elements(els))
  ctx <- PaparazziContext$new(page)
  ctx$scope <- list(els)
  expect_error(pz_act_blur(ctx), class = "paparazzi_error_multiple")

  els1 <- loc_resolve(page, "#name", multiple = "error")
  withr::defer(release_elements(els1))
  ctx <- PaparazziContext$new(page)
  ctx$scope <- list(els1)
  pz_act_focus(page, "#name")
  expect_equal(pz_js(page, "document.activeElement.id"), "name")
  pz_act_blur(ctx)
  expect_equal(pz_js(page, "document.activeElement.tagName"), "BODY")
})

test_that("actions reject extra arguments", {
  page <- local_actions_page()
  expect_error(pz_act_click(page, "#save", "bogus"), "empty")
  expect_error(pz_act_type(page, "a", "bogus"), "empty")
  expect_error(pz_act_press(page, "Enter", "bogus"), "empty")
  expect_error(pz_act_blur(page, "bogus"), "empty")
})

test_that("pz_act_type and pz_act_press validate their inputs", {
  page <- local_actions_page()
  expect_error(pz_act_type(page, 42), class = "rlang_error")
  expect_error(pz_act_type(page, c("a", "b")), class = "rlang_error")
  expect_error(pz_act_press(page, ""), class = "paparazzi_error_key")
  expect_error(pz_act_press(page, "Control+Foo"), class = "paparazzi_error_key")
  expect_error(pz_act_press(page, character(0)), "at least 1 element")
  expect_error(pz_act_press(page, NA_character_), "NA")
})

test_that("an explicit target resolves lazily inside a pinned scope", {
  page <- local_actions_page()
  page$default_timeout <- 0.5
  ctx <- pz_find(page, "form")

  # The explicit target resolves against the pinned scope, not the
  # document: #save lives inside the form, #below-fold outside it.
  expect_invisible(pz_act_click(ctx, "#save"))
  expect_length(log_ids(log_entries(page), "save", "click"), 1)
  expect_error(
    pz_act_click(ctx, "#below-fold"),
    class = "paparazzi_error_timeout"
  )
})

test_that("a detached scope surfaces through an action as a classed error", {
  page <- local_actions_page()
  ctx <- pz_find(page, "#save")

  # Re-render the form so the pinned element drops out of the page; the
  # next action must raise, never silently re-query the scope.
  pz_js(page, "document.querySelector('form').innerHTML = ''")
  err <- expect_error(pz_act_click(ctx), class = "paparazzi_error_detached")
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

test_that("pz_act_click waits out a hidden element's transition to visible", {
  page <- local_actionability_page()
  # #reveals is display:none; arm the 500ms reveal on demand and prove
  # it is hidden when the click starts, so the click genuinely waits.
  expect_false(pz_js(page, hidden_js("reveals")))
  pz_js(page, "window.__pzReveal()")
  expect_invisible(pz_act_click(page, "#reveals"))
  log <- log_entries(page)
  expect_length(log_ids(log, "reveals", "click"), 1)
  expect_true(log_ids(log, "reveals", "click")[[1]]$isTrusted)
  # Nothing was dispatched at (0, 0) while the element was hidden.
  expect_length(log, 1)
})

test_that("pz_act_click on an element that never becomes visible times out", {
  page <- local_actionability_page()
  page$default_timeout <- 0.5
  err <- expect_error(
    pz_act_click(page, "#never"),
    class = "paparazzi_error_timeout"
  )
  expect_match(paste(conditionMessage(err), collapse = " "), "#never")
  # No dispatch ever happened, at (0, 0) or anywhere else.
  expect_length(log_entries(page), 0)
})

test_that("pz_act_click refuses a zero-sized element", {
  page <- local_actionability_page()
  page$default_timeout <- 0.5
  # #zero passes checkVisibility() but has an empty box, so the center
  # point is not a place on the element; the click must time out
  # without dispatching into whatever sits at that point.
  expect_error(pz_act_click(page, "#zero"), class = "paparazzi_error_timeout")
  expect_length(log_entries(page), 0)
})

test_that("pz_act_hover on a hidden element times out", {
  page <- local_actionability_page()
  page$default_timeout <- 0.5
  # Hover shares the click pipeline's actionability wait.
  expect_error(pz_act_hover(page, "#never"), class = "paparazzi_error_timeout")
})

test_that("a scoped pointer action waits out its pinned element's reveal", {
  page <- local_actionability_page()
  # A hidden element matches a scope pin (it is in the DOM); the
  # pointer action on the pinned set must wait for it too.
  ctx <- pz_find(page, "#reveals")
  expect_false(pz_js(page, hidden_js("reveals")))
  pz_js(page, "window.__pzReveal()")
  expect_invisible(pz_act_click(ctx))
  log <- log_entries(page)
  expect_length(log_ids(log, "reveals", "click"), 1)
  expect_true(log_ids(log, "reveals", "click")[[1]]$isTrusted)
})

test_that("pz_act_type with a hidden target times out before typing", {
  page <- local_actionability_page()
  page$default_timeout <- 0.5
  expect_error(
    pz_act_type(page, "Ada", target = "#never"),
    class = "paparazzi_error_timeout"
  )
  expect_length(log_entries(page), 0)
})

hit_pointer_log <- function(page) {
  pz_js(page, "window.__pzPointerLog")
}

test_that("obscured click and hover wait without dispatching to the cover", {
  page <- local_actionability_page()
  page$default_timeout <- 0.5
  for (action in list(pz_act_click, pz_act_hover)) {
    err <- expect_error(
      action(page, "#hit-target"),
      class = "paparazzi_error_obstructed"
    )
    expect_s3_class(err, "paparazzi_error_timeout")
    expect_match(conditionMessage(err), "#hit-target", fixed = TRUE)
    expect_match(conditionMessage(err), "div#hit-cover.scrim", fixed = TRUE)
  }
  expect_length(log_entries(page), 0)
  expect_length(hit_pointer_log(page), 0)
})

test_that("the obstruction description omits a class suffix when none exists", {
  page <- local_actionability_page()
  page$default_timeout <- 0.5
  pz_js(page, "document.getElementById('hit-cover').className = ''")
  err <- expect_error(
    pz_act_click(page, "#hit-target"),
    class = "paparazzi_error_obstructed"
  )
  expect_match(conditionMessage(err), "blocked by div#hit-cover.", fixed = TRUE)
  expect_false(grepl("div#hit-cover..", conditionMessage(err), fixed = TRUE))
  expect_length(hit_pointer_log(page), 0)
})

test_that("click retries the blocked center until the cover disappears", {
  page <- local_actionability_page()
  pz_js(page, "window.__pzUncover()")
  expect_invisible(pz_act_click(page, "#hit-target"))
  clicks <- log_ids(log_entries(page), "hit-target", "click")
  expect_length(clicks, 1)
  expect_true(clicks[[1]]$isTrusted)
  expect_length(log_ids(hit_pointer_log(page), "hit-cover"), 0)
})

test_that("targeted type and drag refuse a covered source", {
  page <- local_actionability_page()
  page$default_timeout <- 0.5
  err <- expect_error(
    pz_act_type(page, "Ada", target = "#hit-input"),
    class = "paparazzi_error_obstructed"
  )
  expect_match(conditionMessage(err), "div#input-cover.scrim", fixed = TRUE)
  expect_equal(pz_js(page, "document.getElementById('hit-input').value"), "")
  expect_error(
    pz_act_drag(page, "#hit-target", by = c(20, 0)),
    class = "paparazzi_error_obstructed"
  )
  expect_length(hit_pointer_log(page), 0)
})

test_that("shadow children, pointer-transparent overlays and labels receive events", {
  page <- local_actionability_page()
  pz_js(
    page,
    "document.getElementById('hit-cover').style.pointerEvents = 'none'"
  )
  expect_invisible(pz_act_click(page, "#hit-target"))
  expect_length(log_ids(log_entries(page), "hit-target", "click"), 1)
  expect_invisible(pz_act_click(page, "#shadow-host"))
  shadow_clicks <- log_ids(log_entries(page), "shadow-child", "click")
  expect_length(shadow_clicks, 1)
  expect_true(shadow_clicks[[1]]$isTrusted)
  expect_invisible(pz_act_click(page, "#hit-label"))
  expect_length(log_ids(log_entries(page), "label-child", "click"), 1)
})

test_that("the hit test runs after scrolling a target under a fixed cover", {
  page <- local_actionability_page()
  page$default_timeout <- 0.5
  pz_js(page, "document.getElementById('fixed-cover').style.display = 'block'")
  err <- expect_error(
    pz_act_click(page, "#below-hit"),
    class = "paparazzi_error_obstructed"
  )
  expect_match(conditionMessage(err), "div#fixed-cover.scrim", fixed = TRUE)
  expect_length(log_entries(page), 0)
  expect_length(hit_pointer_log(page), 0)
})

# The form fixture (form.html) exercises value setting end to end: a
# form with every control pz_set_value() covers, a framework-style
# controlled input whose instance-level value SETTER is trapped
# (window.__pzTraps counts trap hits -- the native prototype setter
# must never trigger it), and a contenteditable div. The sink logs
# input and change with {type, id, isTrusted, value, checked}.

# Every successful pz_set_value() dispatches input then change; helper
# for the per-control assertions. `times` is the number of sets.
expect_value_events <- function(page, id, times = 1) {
  expect_identical(
    log_types(log_ids(log_entries(page), id)),
    rep(c("input", "change"), times)
  )
}

test_that("pz_set_value sets a text input and dispatches input then change", {
  page <- local_form_page()
  page <- expect_invisible(pz_set_value(page, "Ada", target = "#text"))
  expect_equal(pz_js(page, "document.getElementById('text').value"), "Ada")

  text <- log_ids(log_entries(page), "text")
  expect_identical(log_types(text), c("input", "change"))
  expect_equal(text[[1]]$value, "Ada")
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
  expect_value_events(page, "textarea", times = 2)
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
  expect_value_events(page, "select")

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
  expect_value_events(page, "check")

  pz_set_value(page, FALSE, target = "#check")
  expect_false(pz_js(page, "document.getElementById('check').checked"))
  # Both states dispatched the full event sequence.
  expect_value_events(page, "check", times = 2)
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

  # Check the other-named group first, so leaving it alone is really
  # observable: switching radio1/radio2 must not clear it.
  pz_set_value(page, TRUE, target = "#radio3")

  pz_set_value(page, TRUE, target = "#radio1")
  expect_identical(state(), c(radio1 = TRUE, radio2 = FALSE, radio3 = TRUE))

  # Checking radio2 unchecks radio1 but leaves the other-named group
  # alone.
  pz_set_value(page, TRUE, target = "#radio2")
  expect_identical(state(), c(radio1 = FALSE, radio2 = TRUE, radio3 = TRUE))

  # Each set radio dispatched its own pair; unchecking a sibling (or
  # leaving it alone) dispatches nothing on it.
  expect_value_events(page, "radio1")
  expect_value_events(page, "radio2")
  expect_value_events(page, "radio3")
})

test_that("pz_set_value radio groups stop at the form owner", {
  page <- local_form_page()
  # Same name in two different forms: separate groups.
  pz_set_value(page, TRUE, target = "#orphan-free")
  expect_true(pz_js(page, "document.getElementById('orphan-free').checked"))
  expect_false(pz_js(page, "document.getElementById('orphan-form').checked"))

  pz_set_value(page, TRUE, target = "#orphan-form")
  # Different form owners (one formless, one inside the-form): neither
  # is in the other's group, so both stay checked.
  expect_true(pz_js(page, "document.getElementById('orphan-free').checked"))
  expect_true(pz_js(page, "document.getElementById('orphan-form').checked"))

  # Same again for formless radios associated via the form="..."
  # attribute: loose-b and loose-c stay independent.
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
  expect_value_events(page, "range")
  expect_value_events(page, "number")

  # A value the browser clamps or rejects is an error, not a silent set,
  # and dispatches nothing.
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
  # The controlled input overrides the instance-level value setter (a
  # framework's trap), keeping the native getter. The native prototype
  # setter must bypass the trap entirely -- the counter stays at 0 --
  # while the getter and the event listeners observe the new value.
  pz_set_value(page, "via native", target = "#controlled")
  expect_equal(pz_js(page, "window.__pzTraps"), 0)
  expect_equal(
    pz_js(page, "document.getElementById('controlled').value"),
    "via native"
  )
  controlled <- log_ids(log_entries(page), "controlled")
  expect_identical(log_types(controlled), c("input", "change"))
  expect_equal(controlled[[1]]$value, "via native")
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
  expect_equal(pz_js(page, paste0(el, ".files[0].size")), file.info(f1)$size)
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
  dir <- withr::local_tempdir()
  expect_error(
    pz_set_files(page, dir, target = "#file"),
    "is a directory, not a file",
    class = "paparazzi_error_input"
  )
  dir2 <- withr::local_tempdir()
  expect_error(
    pz_set_files(page, c(dir, dir2), target = "#file"),
    "are directories, not files",
    class = "paparazzi_error_input"
  )
  expect_error(
    pz_set_files(page, c(dir, tempfile()), target = "#file"),
    "doesn't exist",
    class = "paparazzi_error_input"
  )
  expect_error(pz_set_files(page, character(0), target = "#file"), "at least 1")
  expect_error(pz_set_files(page, NA, target = "#file"), "NA")
  expect_error(pz_set_files(page, f, "bogus", target = "#file"), "empty")
})

# --- Advanced interactions (pz_act_select_text, pz_act_scroll, pz_act_drag) on the
# advanced.html fixture; helpers in helper-advanced.R. ---

test_that("pz_act_select_text selects an exact substring across inline tags", {
  page <- local_advanced_page()
  page <- expect_invisible(
    pz_act_select_text(page, "galapagos penguins", target = "#rich")
  )
  # The window selection is the real thing: the match starts inside the
  # <em> and ends inside the <strong>, and reads back as one string.
  expect_equal(
    pz_js(page, "window.getSelection().toString()"),
    "galapagos penguins"
  )
  expect_equal(
    pz_js(page, "window.getSelection().anchorNode.parentElement.tagName"),
    "EM"
  )
  expect_equal(
    pz_js(page, "window.getSelection().extentNode.parentElement.tagName"),
    "STRONG"
  )
})

test_that("pz_act_select_text lets typing replace the selection", {
  page <- local_advanced_page()
  pz_act_select_text(page, "otters", target = "#editor")
  pz_act_type(page, "penguins")
  expect_equal(
    pz_js(page, "document.getElementById('editor').textContent"),
    "penguins are playful"
  )
  # Scoped too: the focusing click pz_act_type() makes would collapse the
  # selection before the insert, so a scope element holding an active
  # selection is typed into directly.
  pz_js(
    page,
    "document.getElementById('editor').textContent = 'otters are playful'"
  )
  ctx <- pz_find(page, "#editor")
  pz_act_select_text(ctx, "otters")
  pz_act_type(ctx, "penguins")
  expect_equal(
    pz_js(page, "document.getElementById('editor').textContent"),
    "penguins are playful"
  )
  # Without a selection, the scoped path still clicks to focus: a
  # trusted mousedown on the editor, the insert at the click's caret.
  pz_js(
    page,
    "document.getElementById('editor').textContent = 'otters are playful'"
  )
  ctx <- pz_find(page, "#editor")
  pz_act_type(ctx, "x")
  log <- adv_log(page)
  expect_true(any(vapply(
    log,
    function(e) {
      identical(e$type, "mousedown") &&
        identical(e$id, "editor") &&
        isTRUE(e$isTrusted)
    },
    logical(1)
  )))
  expect_equal(
    pz_js(page, "document.getElementById('editor').textContent"),
    "otters are playfulx"
  )
})

test_that("pz_act_select_text errors on absent text, emptiness, and multiple matches", {
  page <- local_advanced_page()
  expect_error(
    pz_act_select_text(page, "no such text", target = "#rich"),
    class = "paparazzi_error_text"
  )
  expect_error(
    pz_act_select_text(page, ""),
    class = "paparazzi_error_input"
  )
  expect_error(
    pz_act_select_text(page, "duplicate", target = ".dup-select"),
    class = "paparazzi_error_multiple"
  )
  expect_error(
    pz_act_select_text(page, "otters"),
    class = "paparazzi_error_target"
  )
})

test_that("pz_act_scroll scrolls the page by, to a direction, and a target into view", {
  page <- local_advanced_page()

  page <- expect_invisible(pz_act_scroll(page, by = c(0, 300), duration = 0.1))
  expect_equal(pz_js(page, "window.scrollY"), 300)

  pz_act_scroll(page, to = "bottom")
  expect_true(pz_js(
    page,
    "window.scrollY === document.documentElement.scrollHeight - window.innerHeight"
  ))
  pz_act_scroll(page, to = "top")
  expect_equal(pz_js(page, "window.scrollY"), 0)

  pz_act_scroll(page, target = "#tall-bottom")
  y <- pz_js(
    page,
    "document.getElementById('tall-bottom').getBoundingClientRect().y"
  )
  expect_true(y >= 0 && y < pz_js(page, "window.innerHeight"))
})

test_that("pz_act_scroll by and to act on the scope's scroll container", {
  page <- local_advanced_page()

  # The scope element itself is scrollable: it is the container.
  ctx <- pz_find(page, "#scroller")
  ctx <- expect_invisible(pz_act_scroll(ctx, by = c(0, 120)))
  expect_equal(
    pz_js(page, "document.getElementById('scroller').scrollTop"),
    120
  )
  pz_act_scroll(ctx, to = "bottom")
  expect_true(pz_js(
    page,
    paste(
      "document.getElementById('scroller').scrollTop ===",
      "document.getElementById('scroller').scrollHeight -",
      "document.getElementById('scroller').clientHeight"
    )
  ))

  # A scope inside a scrollable container resolves up to it, and the
  # page never moves.
  ctx <- pz_find(page, "#deep-item")
  pz_act_scroll(ctx, to = "top")
  pz_act_scroll(ctx, by = c(0, 40))
  expect_equal(pz_js(page, "document.getElementById('scroller').scrollTop"), 40)
  expect_equal(pz_js(page, "window.scrollY"), 0)
})

test_that("pz_act_scroll validates its modes", {
  page <- local_advanced_page()
  expect_error(pz_act_scroll(page), class = "paparazzi_error_input")
  expect_error(
    pz_act_scroll(page, target = "#rich", by = c(0, 100)),
    class = "paparazzi_error_input"
  )
  expect_error(
    pz_act_scroll(page, to = "bottom", by = c(0, 100)),
    class = "paparazzi_error_input"
  )
  expect_error(
    pz_act_scroll(page, by = "lots"),
    class = "paparazzi_error_input"
  )
  expect_error(
    pz_act_scroll(page, by = 100, duration = -1),
    class = "rlang_error"
  )
  expect_error(
    pz_act_scroll(page, to = "top", duration = Inf),
    class = "rlang_error"
  )
  expect_error(
    pz_act_scroll(page, target = "#rich", duration = "slow"),
    class = "rlang_error"
  )
  expect_error(
    pz_act_scroll(page, to = "sideways"),
    class = "paparazzi_error_input"
  )
  # A multi-match scope has no single container to scroll: both
  # modes error instead of acting on the first match.
  ctx <- pz_find(page, ".dup-select")
  expect_error(
    pz_act_scroll(ctx, by = c(0, 50)),
    class = "paparazzi_error_multiple"
  )
  expect_error(
    pz_act_scroll(ctx, to = "top"),
    class = "paparazzi_error_multiple"
  )
  expect_equal(pz_js(page, "window.scrollY"), 0)
})

test_that("pz_act_scroll by takes an integer offset and surfaces page errors", {
  page <- local_advanced_page()
  # A scalar integer offset is a JSON number, not the invalid literal
  # "100L" the old serialization produced.
  pz_act_scroll(page, by = 100L)
  expect_equal(pz_js(page, "window.scrollY"), 100)
  # A page-side evaluation error surfaces instead of the scroll
  # silently not happening.
  pz_js(
    page,
    "document.documentElement.scrollBy = function () { throw new Error('no scrolling'); };"
  )
  expect_error(
    pz_act_scroll(page, by = c(0, 100)),
    class = "paparazzi_error_js"
  )
})

test_that("pz_act_drag moves a mouse-dragged element onto the destination", {
  page <- local_advanced_page()
  page <- expect_invisible(pz_act_drag(page, "#dragbox", "#dropzone"))

  # The fixture's box follows the pointer while held, so it ends
  # centered where the drag dropped it.
  box <- element_center(page, "#dragbox")
  zone <- element_center(page, "#dropzone")
  expect_lt(abs(box[[1]] - zone[[1]]), 2)
  expect_lt(abs(box[[2]] - zone[[2]]), 2)

  # Real, trusted pointer input in order: down on the box, a move, up.
  log <- adv_log(page)
  expect_true(all(
    adv_log_types(log) %in%
      c("mousemove", "mousedown", "mouseup")
  ))
  box_types <- adv_log_types(log, "dragbox")
  expect_true("mousedown" %in% box_types)
  expect_lt(
    match("mousedown", box_types),
    match("mouseup", box_types)
  )
  moused <- log[vapply(
    log,
    function(e) {
      identical(e$type, "mousedown") && identical(e$id, "dragbox")
    },
    logical(1)
  )][[1]]
  expect_true(moused$isTrusted)
  # A non-draggable source never starts an HTML5 drag.
  expect_false("dragstart" %in% adv_log_types(log))
})

test_that("pz_act_drag moves the cursor to the source before the destination", {
  page <- local_advanced_page()
  source <- element_center(page, "#dragbox")
  destination <- element_center(page, "#dropzone")
  seen <- list()
  local_mocked_bindings(
    stage_move_cursor = function(ctx, point) {
      seen <<- c(seen, list(point))
      invisible(ctx)
    }
  )

  pz_act_drag(page, "#dragbox", to = "#dropzone")

  expect_false(isTRUE(all.equal(source, destination, check.attributes = FALSE)))
  # The seam's point now carries the resolved target's rect for
  # glide-entry timing; compare the coordinates only.
  expect_equal(unname(seen[[1]]), unname(source), ignore_attr = TRUE)
  expect_equal(length(seen), 1L)
})

test_that("pz_act_drag drops at a by offset from the source", {
  page <- local_advanced_page()
  before <- pz_js(
    page,
    paste(
      "(() => { const r = document.getElementById('dragbox').getBoundingClientRect();",
      "return [r.x + r.width / 2, r.y + r.height / 2]; })()"
    )
  )
  pz_act_drag(page, "#dragbox", by = c(80, 0))
  after <- pz_js(
    page,
    paste(
      "(() => { const r = document.getElementById('dragbox').getBoundingClientRect();",
      "return [r.x + r.width / 2, r.y + r.height / 2]; })()"
    )
  )
  expect_lt(abs(after[[1]] - (before[[1]] + 80)), 2)
  expect_lt(abs(after[[2]] - before[[2]]), 2)
})

test_that("pz_act_drag routes an HTML5 source through the drag pipeline", {
  page <- local_advanced_page()
  pz_act_drag(page, "#draggable", "#dropzone")

  # The page's own dragstart ran (trusted) and its payload survived to
  # the drop, which the dropzone records.
  expect_equal(
    pz_js(page, "document.getElementById('dropzone').textContent"),
    "got:payload-123"
  )
  log <- adv_log(page)
  types <- adv_log_types(log)
  expect_true("dragstart" %in% types)
  expect_true("dragend" %in% types)
  expect_true("drop" %in% types)
  starts <- log[vapply(
    log,
    function(e) {
      identical(e$type, "dragstart") && identical(e$id, "draggable")
    },
    logical(1)
  )][[1]]
  expect_true(starts$isTrusted)
  drops <- log[vapply(
    log,
    function(e) {
      identical(e$type, "drop") && identical(e$id, "dropzone")
    },
    logical(1)
  )][[1]]
  expect_true(drops$isTrusted)
})

test_that("pz_act_drag glides the cursor while holding an HTML5 drag when recording", {
  skip_if_no_av()
  page <- local_advanced_page()
  page |> pz_stage(pause = 0)
  page |>
    pz_record_start(
      withr::local_tempfile(fileext = ".mp4"),
      fps = 10,
      hold = c(0, 0)
    )
  defer_record_stop(page)

  # Cursor pre-placed on the source, so the timed stretch is the carry,
  # not the approach glide.
  page |> pz_cursor_move("#draggable", duration = 0)
  t0 <- proc.time()[["elapsed"]]
  pz_act_drag(page, "#draggable", "#dropzone")
  recorded <- proc.time()[["elapsed"]] - t0

  # The drop still lands with the page's payload.
  expect_equal(
    pz_js(page, "document.getElementById('dropzone').textContent"),
    "got:payload-123"
  )
  # The carry is staged: the press beats plus the holding glide (the
  # staged glide floor is 0.5s) on top of the dispatch.
  expect_true(recorded >= 1)
  # The overlay cursor ends on the drop point.
  state <- cursor_overlay_state(page)
  drop <- unlist(pz_js(
    page,
    paste(
      "(() => { const r = document.getElementById('dropzone').getBoundingClientRect();",
      "return [r.x + r.width / 2, r.y + r.height / 2]; })()"
    )
  ))
  expect_lt(abs(state[[2]] - drop[[1]]), 2)
  expect_lt(abs(state[[3]] - drop[[2]]), 2)
  pz_record_stop(page)
})

test_that("pz_act_drag glides the cursor while holding a mouse drag when recording", {
  skip_if_no_av()
  page <- local_advanced_page()
  page |> pz_stage(pause = 0)
  page |>
    pz_record_start(
      withr::local_tempfile(fileext = ".mp4"),
      fps = 10,
      hold = c(0, 0)
    )
  defer_record_stop(page)

  page |> pz_cursor_move("#dragbox", duration = 0)
  t0 <- proc.time()[["elapsed"]]
  pz_act_drag(page, "#dragbox", "#dropzone")
  recorded <- proc.time()[["elapsed"]] - t0

  # The page sees held moves streamed along the carry, so the box
  # follows the pointer through the glide and ends at the zone.
  box <- element_center(page, "#dragbox")
  zone <- element_center(page, "#dropzone")
  expect_lt(abs(box[[1]] - zone[[1]]), 2)
  expect_lt(abs(box[[2]] - zone[[2]]), 2)
  expect_true(recorded >= 1)
  # The overlay cursor ends on the drop point.
  state <- cursor_overlay_state(page)
  expect_lt(abs(state[[2]] - zone[[1]]), 2)
  expect_lt(abs(state[[3]] - zone[[2]]), 2)
  pz_record_stop(page)
})

test_that("a recorded mouse drag streams held moves that follow the cursor", {
  skip_if_no_av()
  page <- local_advanced_page()
  page |> pz_stage(pause = 0)
  page |>
    pz_record_start(
      withr::local_tempfile(fileext = ".mp4"),
      fps = 10,
      hold = c(0, 0)
    )
  defer_record_stop(page)

  page |> pz_cursor_move("#dragbox", duration = 0)
  from <- element_center(page, "#dragbox")
  to <- element_center(page, "#dropzone")
  # Page-side rAF log of the box and the overlay cursor's rendered
  # position, read after the drag so sampling can't disturb the carry.
  pz_js(
    page,
    "(() => {
      window.__carryLog = [];
      window.__carryDone = false;
      document.addEventListener('mouseup', () => { window.__carryDone = true; }, true);
      (function sample() {
        const glide = document.getElementById('paparazzi-overlay-root')?.shadowRoot?.querySelector('.pz-glide');
        let cursor = [-1, -1];
        if (glide) {
          const m = new DOMMatrixReadOnly(getComputedStyle(glide).transform);
          cursor = [m.e, m.f];
        }
        const r = document.getElementById('dragbox').getBoundingClientRect();
        window.__carryLog.push({ cursor: cursor, box: [r.x + r.width / 2, r.y + r.height / 2] });
        if (!window.__carryDone) requestAnimationFrame(sample);
      })();
      return true;
    })()"
  )
  pz_act_drag(page, "#dragbox", "#dropzone")

  # More than one held move lands between the press and the release.
  types <- adv_log_types(adv_log(page))
  down <- match("mousedown", types)
  up <- match("mouseup", types)
  between <- if (up - down > 1) types[(down + 1):(up - 1)] else character(0)
  expect_gt(sum(between == "mousemove"), 1)

  # The box tracks the cursor through the carry, not just at arrival:
  # samples taken while the cursor is mid-path have the box near it.
  samples <- jsonlite::fromJSON(
    pz_js(page, "JSON.stringify(window.__carryLog)"),
    simplifyVector = FALSE
  )
  cur <- t(vapply(samples, function(s) unlist(s$cursor), numeric(2)))
  box <- t(vapply(samples, function(s) unlist(s$box), numeric(2)))
  seg <- to - from
  along <- as.vector(sweep(cur, 2, from) %*% seg) / sum(seg^2)
  mid <- along > 0.15 & along < 0.85 & cur[, 1] >= 0
  expect_gte(sum(mid), 1)
  drift <- sqrt((box[mid, 1] - cur[mid, 1])^2 + (box[mid, 2] - cur[mid, 2])^2)
  expect_lt(median(drift), 80)
  pz_record_stop(page)
})

test_that("a recorded HTML5 drag streams drag events along the carry", {
  skip_if_no_av()
  page <- local_page(pz_example("tasks"), width = 800, height = 900)
  page |> pz_stage(pause = 0)
  page |>
    pz_record_start(
      withr::local_tempfile(fileext = ".mp4"),
      fps = 10,
      hold = c(0, 0)
    )
  defer_record_stop(page)

  from <- element_center(page, ".task:nth-child(5)")
  to <- element_center(page, ".task:first-child")
  page |> pz_cursor_move(".task:nth-child(5)", duration = 0)
  # Event log and a hover/dragging/cursor sampler, both page-side and
  # read after the drag.
  pz_js(
    page,
    "(() => {
      const row = (el) => {
        const li = el && el.closest ? el.closest('.task') : null;
        const t = li && li.querySelector('.task-title');
        return t ? t.textContent.trim() : null;
      };
      window.__dragLog = [];
      ['dragstart', 'dragenter', 'dragover', 'dragleave', 'drop', 'dragend', 'mouseup', 'click']
        .forEach((type) => {
          document.addEventListener(type, (e) => {
            window.__dragLog.push({ type: type, row: row(e.target) });
          }, true);
        });
      window.__carrySamples = [];
      window.__carryDone = false;
      document.addEventListener('dragend', () => { window.__carryDone = true; }, true);
      const titles = (sel) => [...document.querySelectorAll(sel)]
        .map((li) => li.querySelector('.task-title').textContent.trim());
      (function sample() {
        const glide = document.getElementById('paparazzi-overlay-root')?.shadowRoot?.querySelector('.pz-glide');
        let cursor = [-1, -1];
        if (glide) {
          const m = new DOMMatrixReadOnly(getComputedStyle(glide).transform);
          cursor = [m.e, m.f];
        }
        window.__carrySamples.push({
          cursor: cursor,
          hover: titles('.task:hover'),
          dragging: titles('.task.dragging')
        });
        if (!window.__carryDone) setTimeout(sample, 40);
      })();
      return true;
    })()"
  )
  pz_act_drag(page, ".task:nth-child(5)", ".task:first-child")

  # Mid-carry samples: the overlay cursor is travelling between source
  # and drop. The drop row never shows hover styling during the carry
  # (the real pointer stays by the source), and the dragstart styling
  # persists.
  samples <- jsonlite::fromJSON(
    pz_js(page, "JSON.stringify(window.__carrySamples)"),
    simplifyVector = FALSE
  )
  cur <- t(vapply(samples, function(s) unlist(s$cursor), numeric(2)))
  seg <- to - from
  along <- as.vector(sweep(cur, 2, from) %*% seg) / sum(seg^2)
  mid <- along > 0.15 & along < 0.85 & cur[, 1] >= 0
  expect_gte(sum(mid), 1)
  mid_samples <- samples[mid]
  hovers <- function(s) unlist(s$hover)
  expect_false(any(vapply(
    mid_samples,
    function(s) "Renew passport" %in% hovers(s),
    logical(1)
  )))
  expect_true(all(vapply(
    mid_samples,
    function(s) "Water the plants" %in% unlist(s$dragging),
    logical(1)
  )))

  # Intermediate rows see dragenter in path order on the way up.
  log <- jsonlite::fromJSON(
    pz_js(page, "JSON.stringify(window.__dragLog)"),
    simplifyVector = FALSE
  )
  types <- vapply(log, function(e) e$type, character(1))
  rows <- vapply(log, function(e) e$row %||% NA_character_, character(1))
  enters <- rows[types == "dragenter" & !is.na(rows)]
  enters <- enters[c(TRUE, enters[-1] != enters[-length(enters)])]
  at <- match(
    c("Return library books", "Book dentist appointment", "File tax return"),
    enters
  )
  expect_false(anyNA(at))
  expect_true(all(diff(at) > 0))

  # The drop and dragend land with the payload, and the release around
  # the intercepted drag produces no stray mouseup or click.
  expect_true("drop" %in% types)
  expect_true("dragend" %in% types)
  expect_false(any(types %in% c("mouseup", "click")))
  expect_equal(
    pz_js(
      page,
      "document.querySelector('.task:first-child .task-title').textContent.trim()"
    ),
    "Water the plants"
  )
  # The real pointer ends at the drop point with the cursor: the row
  # now there shows hover.
  expect_equal(
    unlist(pz_js(
      page,
      "[...document.querySelectorAll('.task:hover')].map((li) => li.querySelector('.task-title').textContent.trim())"
    )),
    "Water the plants"
  )
  pz_record_stop(page)
})

test_that("a failed staged mouse press does not dispatch a stray mouseup", {
  skip_if_no_av()
  page <- local_advanced_page()
  page |> pz_stage(pause = 0)
  page |>
    pz_record_start(
      withr::local_tempfile(fileext = ".mp4"),
      fps = 10,
      hold = c(0, 0)
    )
  defer_record_stop(page)
  page |> pz_cursor_move("#dragbox", duration = 0)

  real_dispatch_mouse <- dispatch_mouse
  local_mocked_bindings(
    dispatch_mouse = function(ctx, action, target, type, ...) {
      if (type == "mousePressed") {
        cli::cli_abort("simulated mouse press failure")
      }
      real_dispatch_mouse(ctx, action, target, type, ...)
    }
  )
  expect_error(
    pz_act_drag(page, "#dragbox", "#dropzone"),
    "simulated mouse press failure"
  )
  expect_false("mouseup" %in% adv_log_types(adv_log(page)))
  expect_false(page_cursor(page)$pressed)
  expect_equal(cursor_overlay_scale(page), page_stage(page)$cursor_scale)
  pz_record_stop(page)
})

test_that("a mid-carry dispatch failure propagates and the drag still releases", {
  skip_if_no_av()
  page <- local_advanced_page()
  page |> pz_stage(pause = 0)
  page |>
    pz_record_start(
      withr::local_tempfile(fileext = ".mp4"),
      fps = 10,
      hold = c(0, 0)
    )
  defer_record_stop(page)

  page |> pz_cursor_move("#dragbox", duration = 0)
  real_dispatch_mouse <- dispatch_mouse
  held <- 0L
  local_mocked_bindings(
    dispatch_mouse = function(
      ctx,
      action,
      target,
      type,
      point,
      button,
      buttons,
      clickCount,
      call = caller_env()
    ) {
      if (type == "mouseMoved" && buttons == 1) {
        held <<- held + 1L
        if (held == 2L) {
          cli::cli_abort("simulated mid-carry dispatch failure")
        }
      }
      real_dispatch_mouse(
        ctx,
        action,
        target,
        type,
        point,
        button,
        buttons,
        clickCount,
        call = call
      )
    }
  )
  expect_error(
    pz_act_drag(page, "#dragbox", "#dropzone"),
    "simulated mid-carry dispatch failure"
  )
  expect_equal(cursor_overlay_scale(page), page_stage(page)$cursor_scale)

  # The exit defer released the held button: the page saw a mouseup
  # after the press, so a following drag works.
  types <- adv_log_types(adv_log(page))
  up <- match("mouseup", types)
  expect_false(is.na(up))
  expect_gt(up, match("mousedown", types))
  pz_act_drag(page, "#dragbox", "#dropzone")
  box <- element_center(page, "#dragbox")
  zone <- element_center(page, "#dropzone")
  expect_lt(abs(box[[1]] - zone[[1]]), 2)
  expect_lt(abs(box[[2]] - zone[[2]]), 2)
  pz_record_stop(page)
})

test_that("without a recording both drag paths stay instant", {
  page <- local_advanced_page()
  pauses <- numeric()
  local_mocked_bindings(
    pump_loop = function(loop, duration, ...) {
      pauses <<- c(pauses, duration)
    }
  )
  # HTML5 first: the mouse drag parks #dragbox over #dropzone, which
  # would then block the HTML5 drag's destination probe.
  pz_act_drag(page, "#draggable", "#dropzone")
  pz_act_drag(page, "#dragbox", "#dropzone")
  expect_length(pauses, 0L)
  expect_equal(
    pz_js(page, "document.getElementById('dropzone').textContent"),
    "got:payload-123"
  )
})

test_that("pz_act_drag validates its input and errors on multiple matches", {
  page <- local_advanced_page()
  expect_error(pz_act_drag(page, "#dragbox"), class = "paparazzi_error_input")
  expect_error(
    pz_act_drag(page, "#dragbox", "#dropzone", by = c(10, 10)),
    class = "paparazzi_error_input"
  )
  expect_error(
    pz_act_drag(page, ".dup-select", "#dropzone"),
    class = "paparazzi_error_multiple"
  )
  expect_error(
    pz_act_drag(page, "#dragbox", ".dup-select"),
    class = "paparazzi_error_multiple"
  )
})

test_that("pz_act_drag requires a destination when `to` is NULL", {
  page <- local_advanced_page()
  # An explicit to = NULL is absent, not document.body.
  expect_error(
    pz_act_drag(page, "#dragbox", NULL),
    class = "paparazzi_error_input"
  )
})

test_that("pz_act_drag handles uppercase draggable values case-insensitively", {
  page <- local_advanced_page()
  # An uppercase draggable keyword still routes through the HTML5 pipeline.
  pz_act_drag(page, "#draggable-uc", "#dropzone")
  expect_equal(
    pz_js(page, "document.getElementById('dropzone').textContent"),
    "got:payload-uc"
  )
})

test_that("pz_act_drag refuses a destination outside the viewport after scrolling the source", {
  page <- local_advanced_page()
  # Bringing a far source into view pushes the destination out of the
  # viewport; the drag errors instead of dropping on empty space.
  expect_error(
    pz_act_drag(page, "#tall-bottom", "#editor"),
    regexp = "outside the viewport",
    class = "paparazzi_error_target"
  )
})

test_that("pz_act_drag refuses a destination clipped by the source's scroll", {
  for (html5 in c(TRUE, FALSE)) {
    page <- local_page(test_path("fixtures", "drag-clipped.html"))
    if (!html5) {
      pz_js(page, "document.querySelector('#last').draggable = false")
    }
    expect_identical(
      pz_js(page, "document.querySelector('#last').draggable"),
      html5
    )

    error <- expect_error(
      pz_act_drag(page, "#last", "#first"),
      class = "paparazzi_error_obstructed"
    )
    expect_s3_class(error, "paparazzi_error_target")
    expect_match(conditionMessage(error), "#first", fixed = TRUE)
    expect_match(conditionMessage(error), "input#overlap-input", fixed = TRUE)
    expect_gt(pz_js(page, "document.querySelector('#task-list').scrollTop"), 0)
    events <- pz_js(page, "window.dragEvents")
    expect_length(events, 0L)
    pz_close(page)
  }
})

test_that("pz_act_drag errors when the destination hides after the source's scroll", {
  page <- local_advanced_page()
  # The fixture hides #vanishing-zone the moment #tall-bottom is
  # scrolled into view, so the final destination probe fails; the
  # drag errors instead of dropping at the zone's earlier point.
  expect_error(
    pz_act_drag(page, "#tall-bottom", "#vanishing-zone"),
    regexp = "no longer visible",
    class = "paparazzi_error_target"
  )
  # Nothing was dispatched: the error fires before any press.
  expect_false("mousedown" %in% adv_log_types(adv_log(page)))
})

test_that("press records original and resolved keys only while unpaused", {
  skip_if_no_av()
  page <- local_record_page()
  pz_stage(page, show_keys = "both")
  pz_act_press(page, "Mod+k")
  expect_null(page_recorder(page))
  pz_record_start(page, tempfile(fileext = ".mp4"), fps = 10, hold = c(0, 0.1))
  defer_record_stop(page)
  rec <- page_recorder(page)
  pz_act_press(page, c("Mod+k", "Enter"))
  expect_length(rec$keypresses, 1L)
  event <- rec$keypresses[[1]]
  expect_identical(event$style, "both")
  expect_identical(
    vapply(event$keys, `[[`, character(1), "spec"),
    c("Mod+k", "Enter")
  )
  mac <- pz_js(
    page,
    "/^mac/i.test(navigator.userAgentData?.platform || navigator.platform || '')"
  )
  expect_identical(
    event$keys[[1]]$resolved$pressed_modifiers,
    if (isTRUE(mac)) "Meta" else "Control"
  )
  expect_gte(event$last, event$vt)
  pz_record_pause(page)
  pz_act_press(page, "Shift+Tab")
  expect_length(rec$keypresses, 1L)
  pz_record_resume(page)
  pz_act_press(page, "Tab", show_keys = "none")
  expect_length(rec$keypresses, 1L)
  pz_act_press(page, "Tab", show_keys = "mac")
  expect_length(rec$keypresses, 2L)
  expect_identical(rec$keypresses[[2]]$style, "mac")
})

test_that("key callouts keep the font_family staged at press time", {
  skip_if_no_av()
  page <- local_record_page()
  # Silkscreen 400 (latin subset), OFL 1.1 -- see fixtures/fonts/
  pz_stage_fonts(
    page,
    pz_font_file(
      "Silkscreen",
      test_path("fixtures", "fonts", "silkscreen-400.woff2")
    )
  )
  pz_record_start(page, tempfile(fileext = ".mp4"), fps = 10, hold = c(0, 0.1))
  defer_record_stop(page)

  pz_stage_annotate(page, font_family = '"Silkscreen", sans-serif')
  pz_act_press(page, "a", show_keys = "words")
  # Changing the staged default after the press must not retroactively
  # restyle the recorded callout
  pz_stage_annotate(page, font_family = "monospace")

  events <- page_recorder(page)$keypresses
  expect_length(events, 1)
  expect_equal(events[[1]]$font_family, '"Silkscreen", sans-serif')
})

test_that("root scroll source retains arrays and full numeric precision", {
  expect_identical(scroll_arg_json(by = 1.23456789), '{"by":[1.23456789]}')
  expect_identical(scroll_arg_json(to = c(3, 4)), '{"to":[3,4]}')
  expect_identical(scroll_arg_json(by = numeric()), '{"by":[]}')
})

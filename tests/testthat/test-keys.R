test_that("key_parse resolves named keys from the key table", {
  keys <- c(
    Enter = 13L,
    Tab = 9L,
    Escape = 27L,
    Backspace = 8L,
    Delete = 46L,
    Insert = 45L,
    Home = 36L,
    End = 35L,
    PageUp = 33L,
    PageDown = 34L,
    ArrowLeft = 37L,
    ArrowUp = 38L,
    ArrowRight = 39L,
    ArrowDown = 40L,
    F1 = 112L,
    F12 = 123L
  )
  for (name in names(keys)) {
    parsed <- key_parse(name)
    expect_identical(parsed$modifiers, character(0), label = name)
    expect_identical(parsed$pressed_modifiers, character(0), label = name)
    expect_identical(parsed$key$key, name, label = name)
    expect_identical(parsed$key$code, name, label = name)
    expect_identical(parsed$key$keyCode, keys[[name]], label = name)
  }
})

test_that("key_parse parses a plain key without modifiers", {
  parsed <- key_parse("Enter")
  expect_identical(parsed$modifiers, character(0))
  expect_identical(parsed$pressed_modifiers, character(0))
  expect_identical(
    parsed$key,
    list(key = "Enter", code = "Enter", keyCode = 13L, text = "\r")
  )
})

test_that("Space is a named key that still produces its character", {
  parsed <- key_parse("Space")
  expect_identical(
    parsed$key,
    list(key = " ", code = "Space", keyCode = 32L, text = " ")
  )
})

test_that("key_parse parses single characters", {
  lower <- key_parse("a")
  expect_identical(lower$modifiers, character(0))
  expect_identical(
    lower$key,
    list(key = "a", code = "KeyA", keyCode = 65L, text = "a")
  )

  # An uppercase letter implies Shift, like Playwright's USKeyboardLayout.
  upper <- key_parse("A")
  expect_identical(upper$modifiers, "Shift")
  expect_identical(upper$pressed_modifiers, character(0))
  expect_identical(
    upper$key,
    list(key = "A", code = "KeyA", keyCode = 65L, text = "A")
  )

  digit <- key_parse("5")
  expect_identical(
    digit$key,
    list(key = "5", code = "Digit5", keyCode = 53L, text = "5")
  )

  # Shifted digit symbols map to the digit's key with Shift implied.
  bang <- key_parse("!")
  expect_identical(bang$modifiers, "Shift")
  expect_identical(bang$pressed_modifiers, character(0))
  expect_identical(
    bang$key,
    list(key = "!", code = "Digit1", keyCode = 49L, text = "!")
  )

  # Punctuation, unshifted and shifted.
  expect_identical(
    key_parse("-")$key,
    list(key = "-", code = "Minus", keyCode = 189L, text = "-")
  )
  question <- key_parse("?")
  expect_identical(question$modifiers, "Shift")
  expect_identical(
    question$key,
    list(key = "?", code = "Slash", keyCode = 191L, text = "?")
  )
})

test_that("key_parse parses modifier combos", {
  ctrl_a <- key_parse("Control+A")
  # "A" implies Shift on top of the written Control.
  expect_identical(ctrl_a$modifiers, c("Control", "Shift"))
  expect_identical(ctrl_a$pressed_modifiers, "Control")
  expect_identical(ctrl_a$key$key, "A")

  meta_enter <- key_parse("Meta+Enter")
  expect_identical(meta_enter$modifiers, "Meta")
  expect_identical(meta_enter$pressed_modifiers, "Meta")
  expect_identical(
    meta_enter$key,
    list(key = "Enter", code = "Enter", keyCode = 13L, text = "\r")
  )

  # Explicit Shift doesn't double up with an implied one.
  shift_tab <- key_parse("Shift+Tab")
  expect_identical(shift_tab$modifiers, "Shift")
  expect_identical(shift_tab$pressed_modifiers, "Shift")
  expect_identical(shift_tab$key$key, "Tab")
})

test_that("Mod resolves to a physical modifier before generating events", {
  mac <- key_parse("mOd+k", mod = "Meta")
  expect_identical(mac$modifiers, "Meta")
  expect_identical(mac$pressed_modifiers, "Meta")
  expect_identical(mac$key$key, "k")
  expect_identical(key_events(mac)[[2]]$modifiers, 4L)

  other <- key_parse("Shift+Mod+k", mod = "Control")
  expect_identical(other$modifiers, c("Control", "Shift"))
  expect_identical(other$pressed_modifiers, c("Shift", "Control"))
  expect_identical(key_events(other)[[3]]$modifiers, 10L)
  expect_identical(
    key_parse("Mod+Control+k", mod = "Meta")$pressed_modifiers,
    c("Meta", "Control")
  )

  expect_error(
    key_parse("Mod+Control+k", mod = "Control"),
    "Mod.*resolved to.*Control"
  )
  expect_error(key_parse("Meta+Mod+k", mod = "Meta"), "Mod.*resolved to.*Meta")
  expect_error(key_parse("Mod+k"), "Mod")
  expect_error(key_parse("Mod"), class = "paparazzi_error_key")
})

test_that("modifiers match case-insensitively and normalize", {
  parsed <- key_parse("cOnTrOl+aLt+Delete")
  expect_identical(parsed$pressed_modifiers, c("Control", "Alt"))
  # The full set comes back in canonical order: Alt, Control, Meta, Shift.
  expect_identical(parsed$modifiers, c("Alt", "Control"))
  expect_identical(parsed$key$key, "Delete")
})

test_that("a bare modifier is pressable as the main key", {
  parsed <- key_parse("Control")
  expect_identical(parsed$modifiers, character(0))
  expect_identical(
    parsed$key,
    list(key = "Control", code = "ControlLeft", keyCode = 17L, text = NULL)
  )
})

test_that("key_parse takes one spec per call", {
  # A character vector is the caller's loop, not key_parse's.
  expect_error(key_parse(c("Enter", "Tab")), "single string")
  expect_error(key_parse(NA), "single string")
})

test_that("key_parse rejects bad specs with paparazzi_error_key", {
  # Unknown key: the bad token and the full spec are both named.
  expect_error(key_parse("Homey"), class = "paparazzi_error_key")
  expect_error(key_parse("Homey"), "Homey")
  expect_error(key_parse("Meta+Homey"), class = "paparazzi_error_key")
  expect_error(key_parse("Meta+Homey"), "Meta\\+Homey")

  # Unknown modifier.
  expect_error(key_parse("CapsLock+A"), class = "paparazzi_error_key")
  expect_error(key_parse("CapsLock+A"), "Mod")
  expect_error(key_parse("CapsLock+A"), "CapsLock")
  expect_error(key_parse("Meta+Enter"), NA)

  # Duplicate modifier (implied Shift from "A" doesn't count).
  expect_error(key_parse("Control+Control+A"), class = "paparazzi_error_key")
  expect_error(key_parse("Shift+Shift+Tab"), class = "paparazzi_error_key")
  expect_false(inherits(
    tryCatch(key_parse("Shift+A"), error = identity),
    "error"
  ))

  # Empty spec.
  expect_error(key_parse(""), class = "paparazzi_error_key")

  # A multi-character token that isn't a named key.
  expect_error(key_parse("F13"), class = "paparazzi_error_key")

  # A trailing separator would otherwise swallow the key token.
  expect_error(key_parse("Control+"), class = "paparazzi_error_key")
  expect_error(key_parse("Control+"), "Control\\+")
  expect_error(key_parse("Shift+Control+"), class = "paparazzi_error_key")
})

test_that("a lone plus presses the plus key", {
  parsed <- key_parse("+")
  # Like "!" and "A", the shifted symbol implies Shift.
  expect_identical(parsed$modifiers, "Shift")
  expect_identical(
    parsed$key,
    list(key = "+", code = "Equal", keyCode = 187L, text = "+")
  )
})

test_that("explicit Shift shifts the main character", {
  shifted_a <- key_parse("Shift+a")
  expect_identical(shifted_a$modifiers, "Shift")
  expect_identical(shifted_a$pressed_modifiers, "Shift")
  expect_identical(
    shifted_a$key,
    list(key = "A", code = "KeyA", keyCode = 65L, text = "A")
  )

  bang <- key_parse("Shift+1")
  expect_identical(
    bang$key,
    list(key = "!", code = "Digit1", keyCode = 49L, text = "!")
  )

  # Keys without a shifted form are unchanged.
  shift_tab <- key_parse("Shift+Tab")
  expect_identical(shift_tab$key$key, "Tab")
  expect_null(shift_tab$key$text)
  shift_space <- key_parse("Shift+Space")
  expect_identical(shift_space$key$key, " ")
  expect_identical(shift_space$key$text, " ")

  # Already-shifted entries aren't doubled or un-shifted.
  shift_upper <- key_parse("Shift+A")
  expect_identical(
    shift_upper$key,
    list(key = "A", code = "KeyA", keyCode = 65L, text = "A")
  )
  shift_bang <- key_parse("Shift+!")
  expect_identical(
    shift_bang$key,
    list(key = "!", code = "Digit1", keyCode = 49L, text = "!")
  )

  # The shifted character flows through to the dispatched events.
  events <- key_events(key_parse("Shift+a"))
  expect_identical(events[[2]]$type, "keyDown")
  expect_identical(events[[2]]$key, "A")
  expect_identical(events[[2]]$text, "A")
  expect_identical(events[[2]]$code, "KeyA")
  expect_identical(events[[2]]$modifiers, 8L)
})

test_that("modifier keyUps drop their own bit", {
  events <- key_events(key_parse("Control+A"))
  expect_identical(events[[4]]$key, "Control")
  expect_identical(events[[4]]$type, "keyUp")
  expect_false(bitwAnd(events[[4]]$modifiers, 2L) == 2L)
  # The main key's keyUp keeps the full mask.
  expect_identical(events[[3]]$modifiers, 10L)
})

test_that("the text field is present only for text-producing keys", {
  expect_identical(key_parse("a")$key$text, "a")
  expect_identical(key_parse("A")$key$text, "A")
  expect_identical(key_parse("Space")$key$text, " ")
  expect_identical(key_parse("Enter")$key$text, "\r")
  expect_null(key_parse("Tab")$key$text)
  expect_null(key_parse("ArrowLeft")$key$text)
  expect_null(key_parse("Control")$key$text)
})

test_that("key_modifiers_mask maps modifiers to their CDP bits", {
  expect_identical(key_modifiers_mask("Alt"), 1L)
  expect_identical(key_modifiers_mask("Control"), 2L)
  expect_identical(key_modifiers_mask("Meta"), 4L)
  expect_identical(key_modifiers_mask("Shift"), 8L)
  expect_identical(key_modifiers_mask(c("Control", "Shift")), 10L)
  expect_identical(key_modifiers_mask(character(0)), 0L)
  expect_identical(
    key_modifiers_mask(c("Alt", "Control", "Meta", "Shift")),
    15L
  )
})

test_that("key_events produces a down/up pair for a plain text key", {
  events <- key_events(key_parse("a"))
  expect_length(events, 2)
  expect_identical(
    events[[1]],
    list(
      type = "keyDown",
      modifiers = 0L,
      windowsVirtualKeyCode = 65L,
      key = "a",
      code = "KeyA",
      text = "a"
    )
  )
  expect_identical(
    events[[2]],
    list(
      type = "keyUp",
      modifiers = 0L,
      windowsVirtualKeyCode = 65L,
      key = "a",
      code = "KeyA"
    )
  )
})

test_that("Enter is dispatched as a text-producing key", {
  events <- key_events(key_parse("Enter"))
  expect_length(events, 2)
  expect_identical(events[[1]]$type, "keyDown")
  expect_identical(events[[1]]$text, "\r")
  expect_identical(events[[2]]$type, "keyUp")
})

test_that("the main keyDown drops text when Control or Meta is held", {
  # Plain: keyDown with text.
  plain <- key_events(key_parse("a"))
  expect_identical(plain[[1]]$type, "keyDown")
  expect_identical(plain[[1]]$text, "a")

  # Control held: rawKeyDown, no text.
  ctrl <- key_events(key_parse("Control+a"))
  expect_identical(ctrl[[2]]$type, "rawKeyDown")
  expect_null(ctrl[[2]]$text)

  # Meta held: rawKeyDown, no text.
  meta <- key_events(key_parse("Meta+a"))
  expect_identical(meta[[2]]$type, "rawKeyDown")
  expect_null(meta[[2]]$text)

  # Only Control and Meta suppress text; Alt does not.
  alt <- key_events(key_parse("Alt+a"))
  expect_identical(alt[[2]]$type, "keyDown")
  expect_identical(alt[[2]]$text, "a")
})

test_that("key_events wraps the main key with modifier down/up events", {
  events <- key_events(key_parse("Control+A"))
  expect_length(events, 4)
  expect_identical(
    events[[1]],
    list(
      type = "rawKeyDown",
      modifiers = 2L,
      windowsVirtualKeyCode = 17L,
      key = "Control",
      code = "ControlLeft"
    )
  )
  # The main events carry the full mask, implied Shift included: 2 + 8.
  expect_identical(
    events[[2]],
    list(
      type = "rawKeyDown",
      modifiers = 10L,
      windowsVirtualKeyCode = 65L,
      key = "A",
      code = "KeyA"
    )
  )
  expect_identical(
    events[[3]],
    list(
      type = "keyUp",
      modifiers = 10L,
      windowsVirtualKeyCode = 65L,
      key = "A",
      code = "KeyA"
    )
  )
  # Control's keyUp no longer reports its own bit, like a real browser
  # keyup (ctrlKey false once the key is up).
  expect_identical(
    events[[4]],
    list(
      type = "keyUp",
      modifiers = 0L,
      windowsVirtualKeyCode = 17L,
      key = "Control",
      code = "ControlLeft"
    )
  )
})

test_that("Control and Meta suppress Enter text while Shift retains it", {
  control <- key_events(key_parse("Control+Enter"))
  expect_identical(control[[2]]$type, "rawKeyDown")
  expect_null(control[[2]]$text)

  meta <- key_events(key_parse("Meta+Enter"))
  expect_identical(meta[[2]]$type, "rawKeyDown")
  expect_null(meta[[2]]$text)

  shift <- key_events(key_parse("Shift+Enter"))
  expect_identical(shift[[2]]$type, "keyDown")
  expect_identical(shift[[2]]$text, "\r")
})

test_that("explicit Shift gets real down/up events", {
  events <- key_events(key_parse("Shift+Tab"))
  expect_length(events, 4)
  expect_identical(
    events[[1]],
    list(
      type = "rawKeyDown",
      modifiers = 8L,
      windowsVirtualKeyCode = 16L,
      key = "Shift",
      code = "ShiftLeft"
    )
  )
  # Tab produces no text, so the main event is raw even with Shift held.
  expect_identical(events[[2]]$type, "rawKeyDown")
  expect_null(events[[2]]$text)
  expect_identical(events[[4]]$key, "Shift")
})

test_that("implied Shift raises the mask without its own events", {
  events <- key_events(key_parse("A"))
  expect_length(events, 2)
  expect_identical(
    events[[1]],
    list(
      type = "keyDown",
      modifiers = 8L,
      windowsVirtualKeyCode = 65L,
      key = "A",
      code = "KeyA",
      text = "A"
    )
  )
  expect_identical(events[[2]]$type, "keyUp")
  expect_identical(events[[2]]$modifiers, 8L)
})

test_that("modifier keyUps fire in reverse order with a cumulative mask", {
  events <- key_events(key_parse("Control+Alt+Delete"))
  expect_identical(
    vapply(events, function(event) event$type, character(1)),
    c("rawKeyDown", "rawKeyDown", "rawKeyDown", "keyUp", "keyUp", "keyUp")
  )
  # Downs accumulate in spec order: Control (2), then Alt (+1).
  expect_identical(events[[1]]$modifiers, 2L)
  expect_identical(events[[2]]$modifiers, 3L)
  expect_identical(events[[3]]$modifiers, 3L)
  # The main keyUp still reports the full mask, then ups unwind in
  # reverse, each dropping its own bit first: Alt (2), then Control (0).
  expect_identical(events[[4]]$key, "Delete")
  expect_identical(events[[4]]$modifiers, 3L)
  expect_identical(events[[5]]$key, "Alt")
  expect_identical(events[[5]]$modifiers, 2L)
  expect_identical(events[[6]]$key, "Control")
  expect_identical(events[[6]]$modifiers, 0L)
})

test_that("a bare modifier dispatches rawKeyDown/keyUp as the main key", {
  events <- key_events(key_parse("Control"))
  expect_length(events, 2)
  expect_identical(events[[1]]$type, "rawKeyDown")
  expect_identical(events[[1]]$key, "Control")
  expect_null(events[[1]]$text)
  expect_identical(events[[2]]$type, "keyUp")
})

test_that("key callout labels preserve Mod while following the selected style", {
  mac <- key_parse("sHiFt+MoD+k", mod = "Meta")
  other <- key_parse("sHiFt+MoD+k", mod = "Control")
  expect_identical(
    key_callout_labels("sHiFt+MoD+k", mac, "words"),
    c("Shift", "Meta", "K")
  )
  expect_identical(
    key_callout_labels("sHiFt+MoD+k", other, "words"),
    c("Shift", "Ctrl", "K")
  )
  expect_identical(
    key_callout_labels("sHiFt+MoD+k", mac, "mac"),
    c("⇧", "⌘", "K")
  )
  expect_identical(
    key_callout_labels("sHiFt+MoD+k", other, "mac"),
    c("⇧", "⌃", "K")
  )
  expect_identical(
    key_callout_labels("sHiFt+MoD+k", other, "both"),
    c("Shift", "Ctrl / ⌘", "K")
  )
  expect_identical(
    key_callout_labels("sHiFt+MoD+k", mac, "both"),
    c("Shift", "Ctrl / ⌘", "K")
  )
  expect_identical(
    key_callout_labels(
      "Control+Alt+Meta+Enter",
      key_parse("Control+Alt+Meta+Enter"),
      "mac"
    ),
    c("⌃", "⌥", "⌘", "Enter")
  )
  expect_identical(
    key_callout_labels(
      "Control+Shift+Alt+Meta+Enter",
      key_parse("Control+Shift+Alt+Meta+Enter"),
      "words"
    ),
    c("Ctrl", "Shift", "Alt", "Meta", "Enter")
  )
  expect_identical(key_callout_labels("A", key_parse("A"), "words"), "A")
  expect_identical(
    key_callout_labels("Control", key_parse("Control"), "mac"),
    "⌃"
  )
})

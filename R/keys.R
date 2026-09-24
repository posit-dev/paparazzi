# Key specs for pz_press(): "Mod+Mod+Key" strings like "Control+A" or
# "Meta+Enter", parsed into Input.dispatchKeyEvent argument lists.

# Canonical modifier order, also the order of the mask bits below.
key_modifiers <- c("Alt", "Control", "Meta", "Shift")

# The `modifiers` bitmask values Input.dispatchKeyEvent expects.
key_modifier_bits <- c(Alt = 1L, Control = 2L, Meta = 4L, Shift = 8L)

# Modifier tokens in a key spec match case-insensitively and normalize
# to these names.
key_modifier_names <- c(
  alt = "Alt",
  control = "Control",
  meta = "Meta",
  shift = "Shift"
)

# Key token -> CDP fields: `key`, `code`, and `keyCode` (sent as
# windowsVirtualKeyCode). `text` is the character the key produces,
# absent when it produces none. Uppercase letters and shifted symbols
# carry `implied_shift` so key_parse() can add Shift to the modifiers,
# following Playwright's USKeyboardLayout: "Control+A" is
# Control+Shift+A. The table is small by design; new keys are one more
# entry.
key_table <- list(
  Enter = list(key = "Enter", code = "Enter", keyCode = 13L),
  Tab = list(key = "Tab", code = "Tab", keyCode = 9L),
  Escape = list(key = "Escape", code = "Escape", keyCode = 27L),
  Backspace = list(key = "Backspace", code = "Backspace", keyCode = 8L),
  Delete = list(key = "Delete", code = "Delete", keyCode = 46L),
  Insert = list(key = "Insert", code = "Insert", keyCode = 45L),
  Home = list(key = "Home", code = "Home", keyCode = 36L),
  End = list(key = "End", code = "End", keyCode = 35L),
  PageUp = list(key = "PageUp", code = "PageUp", keyCode = 33L),
  PageDown = list(key = "PageDown", code = "PageDown", keyCode = 34L),
  ArrowLeft = list(key = "ArrowLeft", code = "ArrowLeft", keyCode = 37L),
  ArrowUp = list(key = "ArrowUp", code = "ArrowUp", keyCode = 38L),
  ArrowRight = list(key = "ArrowRight", code = "ArrowRight", keyCode = 39L),
  ArrowDown = list(key = "ArrowDown", code = "ArrowDown", keyCode = 40L),
  # The one named key that produces a character.
  Space = list(key = " ", code = "Space", keyCode = 32L, text = " "),
  # The modifier keys are pressable keys too (pz_press(ctx, "Control")
  # presses and releases Control itself).
  Control = list(key = "Control", code = "ControlLeft", keyCode = 17L),
  Shift = list(key = "Shift", code = "ShiftLeft", keyCode = 16L),
  Alt = list(key = "Alt", code = "AltLeft", keyCode = 18L),
  Meta = list(key = "Meta", code = "MetaLeft", keyCode = 91L)
)

# F1-F12 (Windows virtual key codes 112-123).
for (i in 1:12) {
  key_table[[paste0("F", i)]] <- list(
    key = paste0("F", i),
    code = paste0("F", i),
    keyCode = 111L + i
  )
}

# Letters: "a" and "A" are separate entries; the uppercase form implies
# Shift and shares the uppercase virtual key code.
for (letter in letters) {
  upper <- toupper(letter)
  code <- paste0("Key", upper)
  key_table[[letter]] <- list(
    key = letter,
    code = code,
    keyCode = utf8ToInt(upper),
    text = letter
  )
  key_table[[upper]] <- list(
    key = upper,
    code = code,
    keyCode = utf8ToInt(upper),
    text = upper,
    implied_shift = TRUE
  )
}

# Digits and the symbols on the shifted digit row (Shift implied).
digit_keys <- c("1", "2", "3", "4", "5", "6", "7", "8", "9", "0")
digit_symbols <- c("!", "@", "#", "$", "%", "^", "&", "*", "(", ")")
for (i in seq_along(digit_keys)) {
  code <- paste0("Digit", digit_keys[i])
  keyCode <- utf8ToInt(digit_keys[i])
  key_table[[digit_keys[i]]] <- list(
    key = digit_keys[i],
    code = code,
    keyCode = keyCode,
    text = digit_keys[i]
  )
  key_table[[digit_symbols[i]]] <- list(
    key = digit_symbols[i],
    code = code,
    keyCode = keyCode,
    text = digit_symbols[i],
    implied_shift = TRUE
  )
}

# Remaining US punctuation: c(unshifted, shifted, code, keyCode).
punctuation_keys <- list(
  c("-", "_", "Minus", "189"),
  c("=", "+", "Equal", "187"),
  c("[", "{", "BracketLeft", "219"),
  c("]", "}", "BracketRight", "221"),
  c("\\", "|", "Backslash", "220"),
  c(";", ":", "Semicolon", "186"),
  c("'", "\"", "Quote", "222"),
  c("`", "~", "Backquote", "192"),
  c(",", "<", "Comma", "188"),
  c(".", ">", "Period", "190"),
  c("/", "?", "Slash", "191")
)
for (punctuation in punctuation_keys) {
  code <- punctuation[3]
  keyCode <- as.integer(punctuation[4])
  key_table[[punctuation[1]]] <- list(
    key = punctuation[1],
    code = code,
    keyCode = keyCode,
    text = punctuation[1]
  )
  key_table[[punctuation[2]]] <- list(
    key = punctuation[2],
    code = code,
    keyCode = keyCode,
    text = punctuation[2],
    implied_shift = TRUE
  )
}

# Parse one key spec. Returns a list with:
#   $modifiers     character: the full modifier set, implied Shift
#                 included, in canonical order (Alt, Control, Meta, Shift)
#   $modifier_keys character: only the modifiers written in the spec, in
#                 spec order; these alone get their own down/up events
#   $key           the key table entry's key/code/keyCode plus `text`
key_parse <- function(spec, call = caller_env()) {
  check_string(spec, arg = "key", call = call)
  if (!nzchar(spec)) {
    cli::cli_abort(
      c(
        "{.arg key} can't be empty.",
        i = "Pass a key spec like {.val \"Enter\"} or {.val \"Control+A\"}."
      ),
      class = "paparazzi_error_key",
      call = call
    )
  }

  # A one-character spec is the key itself, so "+" presses "+" rather
  # than splitting into empty tokens.
  tokens <- if (nchar(spec) == 1L) {
    spec
  } else {
    if (substr(spec, nchar(spec), nchar(spec)) == "+") {
      cli::cli_abort(
        c(
          "{.val {spec}} ends with {.val +} but no key follows it.",
          i = "Pass a key spec like {.val \"Control+A\"}."
        ),
        class = "paparazzi_error_key",
        call = call
      )
    }
    strsplit(spec, "+", fixed = TRUE)[[1]]
  }
  modifier_tokens <- tokens[-length(tokens)]
  key_token <- tokens[length(tokens)]

  explicit <- unname(key_modifier_names[tolower(modifier_tokens)])
  unknown <- is.na(explicit)
  if (any(unknown)) {
    token <- modifier_tokens[which(unknown)[1]]
    cli::cli_abort(
      c(
        "{.val {token}} is not a modifier in {.val {spec}}.",
        i = "Modifiers are Control, Shift, Alt, and Meta, matched case-insensitively."
      ),
      class = "paparazzi_error_key",
      call = call
    )
  }
  if (anyDuplicated(explicit)) {
    token <- modifier_tokens[which(duplicated(explicit))[1]]
    cli::cli_abort(
      "{.val {token}} appears more than once in {.val {spec}}.",
      class = "paparazzi_error_key",
      call = call
    )
  }

  entry <- key_table[[key_token]]
  if (is.null(entry)) {
    cli::cli_abort(
      c(
        "{.val {key_token}} is not a supported key in {.val {spec}}.",
        i = "Use a named key (Enter, Tab, Escape, F1, ...) or a single character."
      ),
      class = "paparazzi_error_key",
      call = call
    )
  }

  # Explicit Shift shifts the main character, following Playwright's
  # USKeyboardLayout: the shifted sibling of the unshifted entry supplies
  # key/text while code/keyCode stay put. Entries that are already
  # shifted ("A", "!") and keys with no shifted form are untouched.
  if ("Shift" %in% explicit && is.null(entry$implied_shift)) {
    shifted <- key_shifted_sibling(entry)
    if (!is.null(shifted)) {
      entry <- list(
        key = shifted$key,
        code = entry$code,
        keyCode = entry$keyCode,
        text = shifted$text
      )
    }
  }

  # An uppercase letter or shifted symbol implies Shift on the main
  # events only; it never gets its own down/up.
  modifiers <- explicit
  if (isTRUE(entry$implied_shift)) {
    modifiers <- unique(c(modifiers, "Shift"))
  }

  list(
    modifiers = intersect(key_modifiers, modifiers),
    modifier_keys = explicit,
    key = list(
      key = entry$key,
      code = entry$code,
      keyCode = entry$keyCode,
      text = entry$text
    )
  )
}

# The key_table entry produced when Shift is held with `entry`: the
# shifted sibling sharing its code, or NULL when the key has none.
key_shifted_sibling <- function(entry) {
  for (candidate in key_table) {
    if (
      identical(candidate$code, entry$code) &&
        isTRUE(candidate$implied_shift) &&
        !identical(candidate$key, entry$key)
    ) {
      return(candidate)
    }
  }
  NULL
}

key_modifiers_mask <- function(modifiers) {
  sum(key_modifier_bits[modifiers], 0L)
}

# One Input.dispatchKeyEvent as a named argument list, ready to forward
# with `session$Input$dispatchKeyEvent(!!!event)`. `text` is only ever
# attached to a text-producing keyDown.
key_cdp_event <- function(type, modifiers, entry, text = NULL) {
  event <- list(
    type = type,
    modifiers = modifiers,
    windowsVirtualKeyCode = entry$keyCode,
    key = entry$key,
    code = entry$code
  )
  if (!is.null(text)) {
    event$text <- text
  }
  event
}

#' The full CDP key event sequence for one parsed key spec
#'
#' One call per spec element: the explicit modifier keyDowns in spec order
#' (rawKeyDown, cumulative mask), the main keyDown/keyUp, then the modifier
#' keyUps in reverse; a modifier's keyUp no longer reports its own bit, like
#' a real browser keyup (a Control keyup has ctrlKey false). The main keyDown
#' is type "keyDown" with `text` only when the key produces a character
#' and neither Control nor Meta is held; otherwise a "rawKeyDown" without
#' text. Implied Shift (from "A" or "!") raises the mask on the main events
#' only -- it never gets its own down/up events, exactly like Playwright.
#'
#' @noRd
key_events <- function(parsed) {
  events <- list()
  mask <- 0L
  for (modifier in parsed$modifier_keys) {
    mask <- mask + key_modifier_bits[[modifier]]
    events <- c(
      events,
      list(key_cdp_event("rawKeyDown", mask, key_table[[modifier]]))
    )
  }

  entry <- parsed$key
  text <- if (any(c("Control", "Meta") %in% parsed$modifiers)) {
    NULL
  } else {
    entry$text
  }
  full_mask <- key_modifiers_mask(parsed$modifiers)
  events <- c(
    events,
    list(
      key_cdp_event(
        if (is.null(text)) "rawKeyDown" else "keyDown",
        full_mask,
        entry,
        text
      ),
      key_cdp_event("keyUp", full_mask, entry)
    )
  )

  for (modifier in rev(parsed$modifier_keys)) {
    # Release the bit before the keyUp so it doesn't report itself held.
    mask <- mask - key_modifier_bits[[modifier]]
    events <- c(
      events,
      list(key_cdp_event("keyUp", mask, key_table[[modifier]]))
    )
  }

  events
}

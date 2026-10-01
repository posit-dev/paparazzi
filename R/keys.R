key_modifiers <- c("Alt", "Control", "Meta", "Shift")

# The `modifiers` bitmask values Input.dispatchKeyEvent expects.
key_modifier_bits <- c(Alt = 1L, Control = 2L, Meta = 4L, Shift = 8L)

key_modifier_names <- c(
  alt = "Alt",
  control = "Control",
  meta = "Meta",
  mod = "Mod",
  shift = "Shift"
)

key_table <- list(
  Enter = list(key = "Enter", code = "Enter", keyCode = 13L, text = "\r"),
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
  Space = list(key = " ", code = "Space", keyCode = 32L, text = " "),
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

digit_keys <- c("1", "2", "3", "4", "5", "6", "7", "8", "9", "0")
digit_symbols <- c("!", "@", "#", "$", "%", "^", "&", "*", "(", ")")

for (i in seq_along(digit_keys)) {
  code <- paste0("Digit", digit_keys[i])
  key_code <- utf8ToInt(digit_keys[i])
  key_table[[digit_keys[i]]] <- list(
    key = digit_keys[i],
    code = code,
    keyCode = key_code,
    text = digit_keys[i]
  )
  key_table[[digit_symbols[i]]] <- list(
    key = digit_symbols[i],
    code = code,
    keyCode = key_code,
    text = digit_symbols[i],
    implied_shift = TRUE
  )
}

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
  key_code <- as.integer(punctuation[4])
  key_table[[punctuation[1]]] <- list(
    key = punctuation[1],
    code = code,
    keyCode = key_code,
    text = punctuation[1]
  )
  key_table[[punctuation[2]]] <- list(
    key = punctuation[2],
    code = code,
    keyCode = key_code,
    text = punctuation[2],
    implied_shift = TRUE
  )
}

key_parse <- function(spec, mod = NULL, call = caller_env()) {
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

  tokens <- if (nchar(spec) == 1L) {
    spec
  } else {
    if (endsWith(spec, "+")) {
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
        i = "Modifiers are Control, Shift, Alt, Meta, and Mod, matched case-insensitively."
      ),
      class = "paparazzi_error_key",
      call = call
    )
  }
  if ("Mod" %in% explicit) {
    if (is.null(mod)) {
      cli::cli_abort(
        "{.val Mod} needs the browser platform to resolve in {.val {spec}}.",
        class = "paparazzi_error_key",
        call = call
      )
    }
    explicit[explicit == "Mod"] <- mod
  }
  if (anyDuplicated(explicit)) {
    token <- modifier_tokens[which(duplicated(explicit))[1]]
    if ("Mod" %in% key_modifier_names[tolower(modifier_tokens)]) {
      cli::cli_abort(
        "{.val Mod} resolved to {.val {mod}} on this platform; {.val {token}} appears more than once in {.val {spec}}.",
        class = "paparazzi_error_key",
        call = call
      )
    }
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

key_callout_labels <- function(spec, parsed, style) {
  tokens <- if (nchar(spec) == 1L) {
    spec
  } else {
    strsplit(spec, "+", fixed = TRUE)[[1]]
  }
  modifiers <- tokens[-length(tokens)]
  resolved <- parsed$modifier_keys
  names_words <- c(
    Alt = "Alt",
    Control = "Ctrl",
    Meta = "Meta",
    Shift = "Shift"
  )
  names_mac <- c(
    Alt = "\u2325",
    Control = "\u2303",
    Meta = "\u2318",
    Shift = "\u21e7"
  )
  labels <- if (style == "mac") names_mac else names_words
  prefix <- vapply(
    seq_along(modifiers),
    function(i) {
      if (style == "both" && tolower(modifiers[[i]]) == "mod") {
        "Ctrl / \u2318"
      } else {
        unname(labels[[resolved[[i]]]])
      }
    },
    character(1)
  )
  main <- parsed$key$key
  if (identical(main, " ")) {
    main <- "Space"
  }
  if (main %in% names(labels)) {
    main <- unname(labels[[main]])
  }
  c(prefix, main)
}

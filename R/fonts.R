#' Stage fonts for annotations and captions
#'
#' Loads one or more fonts into the page so that everything Chrome draws
#' for it — annotation badges, callout bubbles, captions, and key
#' callouts — can use them. Declare fonts with [pz_font_google()],
#' [pz_font_bunny()], or [pz_font_file()] and pass them in `...`.
#'
#' Staging is an ahead-of-time step: `pz_stage_fonts()` blocks until every
#' face has loaded (or fails per `on_error`), so annotating is never
#' slowed by a font load and never flashes a fallback font. Staged fonts
#' persist across recordings; after navigation they are re-added to the
#' new document lazily, the first time something is annotated there.
#'
#' Repeated calls add fonts. A face whose family, weight, and style are
#' already staged is replaced by the new one. There is no clear or reset.
#'
#' Remote stylesheets and font files are fetched by Chrome, not R, and
#' stay in Chrome's HTTP cache. On pages whose Content Security Policy
#' blocks the fetch (`connect-src` for the stylesheet, `font-src` for the
#' font files) the load fails and is routed through `on_error`.
#' [pz_font_file()] sidesteps CSP entirely because its bytes are handed to
#' the page directly.
#'
#' @inheritParams pz_act_click
#' @param ... Font objects from [pz_font_google()], [pz_font_bunny()], or
#'   [pz_font_file()].
#' @param on_error What to do when a font fails to load: `"stop"` (the
#'   default) aborts without staging any of the call's fonts, `"warn"`
#'   warns and stages the fonts that loaded, and `"ignore"` stages the
#'   fonts that loaded, silently. Set with
#'   `options(paparazzi.stage_fonts.on_error = )` to change the default.
#' @return `ctx`, invisibly.
#' @seealso [pz_stage_annotate()], whose `font_family` sets the default
#'   family for annotations and key callouts
#'
#' @examplesIf paparazzi:::examples_run(site = TRUE)
#' page <- pz_open(pz_example("tasks"))
#' page |>
#'   pz_stage_fonts(pz_font_google("Silkscreen")) |>
#'   # font_family takes a CSS family string; use the staged family with
#'   # a generic fallback
#'   pz_stage_annotate(font_family = '"Silkscreen", sans-serif') |>
#'   pz_annotate("#add-task", label = "New") |>
#'   pz_screenshot(file.path(tempdir(), "tasks.png"))
#' pz_close(page)
#'
#' @export
pz_stage_fonts <- function(
  ctx,
  ...,
  on_error = getOption("paparazzi.stage_fonts.on_error", "stop")
) {
  check_context(ctx)
  on_error <- arg_match(on_error, c("stop", "warn", "ignore"))
  fonts <- list(...)
  for (font in fonts) {
    if (!is_paparazzi_font(font)) {
      cli::cli_abort(
        paste0(
          "{.arg ...} must contain font objects from {.fn pz_font_google},",
          " {.fn pz_font_bunny}, or {.fn pz_font_file}."
        ),
        class = "paparazzi_error_input"
      )
    }
  }
  if (!length(fonts)) {
    return(ctx_return(ctx))
  }
  page <- ctx$page
  results <- fonts_ensure_session(page$session, fonts, page$default_timeout)
  ok <- vapply(results, is.null, logical(1))
  if (!all(ok)) {
    messages <- cli_escape(unlist(results[!ok]))
    problems <- c(
      "Failed to load {sum(!ok)} font face{?s}:",
      rlang::set_names(messages, rep("x", length(messages)))
    )
    if (on_error == "stop") {
      cli::cli_abort(problems)
    }
    if (on_error == "warn") {
      cli::cli_warn(problems)
    }
  }
  if (any(ok)) {
    page_stage_fonts_add(page, fonts[ok])
  }
  ctx_return(ctx)
}

#' Declare a font from Google Fonts
#'
#' Declares a font face for [pz_stage_fonts()]. The family is identified
#' by its Google Fonts name, and Chrome fetches the stylesheet and font
#' files at staging time; nothing is downloaded by R.
#'
#' @param family The font family name, exactly as Google Fonts spells it,
#'   e.g. `"Open Sans"`.
#' @param weight Font weight, a number from 1 to 1000 (400 is regular,
#'   700 is bold).
#' @param style `"normal"` (the default) or `"italic"`.
#' @return A font object for [pz_stage_fonts()].
#' @seealso [pz_stage_fonts()], [pz_font_bunny()], [pz_font_file()]
#'
#' @examples
#' pz_font_google("Inter", weight = 700)
#'
#' @export
pz_font_google <- function(family, weight = 400, style = "normal") {
  family <- check_font_family_name(family)
  weight <- check_font_weight(weight)
  style <- arg_match(style, c("normal", "italic"))
  new_font(
    family,
    weight,
    style,
    source = "google",
    url = font_google_url(family, weight, style)
  )
}

#' Declare a font from Bunny Fonts
#'
#' Declares a font face for [pz_stage_fonts()], served by Bunny Fonts
#' (<https://fonts.bunny.net>), a GDPR-friendly foundry that mirrors the
#' Google Fonts collection and stylesheet format.
#'
#' @inheritParams pz_font_google
#' @return A font object for [pz_stage_fonts()].
#' @seealso [pz_stage_fonts()], [pz_font_google()], [pz_font_file()]
#'
#' @examples
#' pz_font_bunny("Inter", style = "italic")
#'
#' @export
pz_font_bunny <- function(family, weight = 400, style = "normal") {
  family <- check_font_family_name(family)
  weight <- check_font_weight(weight)
  style <- arg_match(style, c("normal", "italic"))
  new_font(
    family,
    weight,
    style,
    source = "bunny",
    url = font_bunny_url(family, weight, style)
  )
}

#' Declare a font from a local file
#'
#' Declares a font face for [pz_stage_fonts()] from a local font file.
#' The bytes are read by R and handed to the page directly, so the file
#' works on `http` pages (which cannot load `file://` URLs) and is not
#' subject to Content Security Policy font restrictions. You are
#' responsible for the license of fonts you use.
#'
#' @inheritParams pz_font_google
#' @param path Path to a `.woff2`, `.woff`, `.ttf`, or `.otf` file.
#' @return A font object for [pz_stage_fonts()].
#' @seealso [pz_stage_fonts()], [pz_font_google()], [pz_font_bunny()]
#'
#' @examples
#' \dontrun{
#' pz_font_file("My Brand Sans", "~/fonts/my-brand-sans.woff2")
#' }
#'
#' @export
pz_font_file <- function(family, path, weight = 400, style = "normal") {
  family <- check_font_family_name(family)
  check_string(path, allow_empty = FALSE)
  weight <- check_font_weight(weight)
  style <- arg_match(style, c("normal", "italic"))
  if (!file.exists(path)) {
    cli::cli_abort(
      "{.arg path} does not exist: {.path {path}}.",
      class = "paparazzi_error_input"
    )
  }
  format <- switch(
    tolower(tools::file_ext(path)),
    woff2 = "woff2",
    woff = "woff",
    ttf = "truetype",
    otf = "opentype",
    cli::cli_abort(
      "{.arg path} must be a {.val .woff2}, {.val .woff}, {.val .ttf}, or {.val .otf} file.",
      class = "paparazzi_error_input"
    )
  )
  data <- jsonlite::base64_enc(readBin(path, "raw", file.size(path)))
  new_font(
    family,
    weight,
    style,
    source = "file",
    data = data,
    format = format,
    id = paste0("file:", rlang::hash(data))
  )
}

#' @export
format.paparazzi_font <- function(x, ...) {
  sprintf(
    "<paparazzi font> %s (%s, weight %s, %s)",
    x$family,
    x$source,
    x$weight,
    x$style
  )
}

#' @export
print.paparazzi_font <- function(x, ...) {
  cli::cat_line(format(x, ...))
  invisible(x)
}

new_font <- function(family, weight, style, source, ...) {
  structure(
    list(
      family = family,
      weight = weight,
      style = style,
      source = source,
      ...
    ),
    class = c(paste0("paparazzi_font_", source), "paparazzi_font")
  )
}

is_paparazzi_font <- function(x) {
  inherits(x, "paparazzi_font")
}

check_font_family_name <- function(
  x,
  arg = caller_arg(x),
  call = caller_env()
) {
  check_string(x, allow_empty = FALSE, arg = arg, call = call)
  gsub('"', "", x, fixed = TRUE)
}

check_font_weight <- function(x, arg = caller_arg(x), call = caller_env()) {
  check_number_whole(x, min = 1, max = 1000, arg = arg, call = call)
  as.integer(x)
}

check_font_family <- function(
  x,
  page,
  arg = caller_arg(x),
  call = caller_env()
) {
  if (is_paparazzi_font(x)) {
    if (is.null(page_fonts(page)[[x$family]])) {
      cli::cli_abort(
        c(
          "{.arg {arg}} uses the font {.val {x$family}}, which is not staged on this page.",
          i = "Stage it first with {.fn pz_stage_fonts}."
        ),
        call = call
      )
    }
    return(paste0('"', x$family, '", sans-serif'))
  }
  check_string(x, allow_empty = FALSE, arg = arg, call = call)
  x
}

page_fonts <- function(page) {
  page$staging$fonts
}

page_stage_fonts_add <- function(page, fonts) {
  staged <- page_fonts(page) %||% list()
  for (font in fonts) {
    faces <- staged[[font$family]] %||% list()
    faces[[paste0(font$weight, "/", font$style)]] <- font
    staged[[font$family]] <- faces
  }
  page$staging$fonts <- staged
  invisible(page)
}

fonts_faces <- function(page) {
  unlist(page_fonts(page), recursive = FALSE, use.names = FALSE)
}

font_face_spec <- function(font) {
  spec <- list(
    family = font$family,
    weight = font$weight,
    style = font$style,
    key = font_key(font)
  )
  if (!is.null(font$url)) {
    spec$url <- font$url
    spec$id <- font$url
  }
  if (!is.null(font$data)) {
    spec$data <- font$data
    spec$id <- font$id
  }
  spec
}

font_key <- function(font) {
  tolower(paste(font$family, font$weight, font$style, sep = "|"))
}

fonts_ensure_session <- function(session, fonts, timeout) {
  if (!length(fonts)) {
    return(list())
  }
  spec <- jsonlite::toJSON(
    lapply(fonts, font_face_spec),
    auto_unbox = TRUE
  )
  res <- cdp_call(
    session$Runtime$evaluate(
      paste0("(", FONTS_ENSURE_JS, ")(", spec, ")"),
      awaitPromise = TRUE,
      returnByValue = TRUE,
      timeout_ = timeout
    ),
    timeout,
    "loading staged fonts"
  )
  cdp_check_exception(res, "loading staged fonts")
  value <- res$result$value
  if (is.null(value)) {
    return(rep(list(NULL), length(fonts)))
  }
  value
}

fonts_ensure_page <- function(page) {
  fonts_ensure_page_session(page, page$session)
}

fonts_ensure_page_session <- function(page, session) {
  faces <- fonts_faces(page)
  if (!length(faces)) {
    return(invisible(NULL))
  }
  needed <- fonts_needed(session, faces, page$default_timeout)
  if (!length(needed)) {
    return(invisible(NULL))
  }
  results <- fonts_ensure_session(session, faces[needed], page$default_timeout)
  messages <- cli_escape(unlist(Filter(Negate(is.null), results)))
  if (length(messages)) {
    cli::cli_warn(c(
      "Failed to load staged fonts:",
      rlang::set_names(messages, rep("x", length(messages)))
    ))
  }
  invisible(NULL)
}

FONTS_NEEDED_JS <- paste0(
  "(pairs) => {",
  "const have = document.__paparazziFonts;",
  "const out = [];",
  "pairs.forEach((p, i) => {",
  "const e = have && have.get(p[0]);",
  "if (!e || e.id !== p[1]) out.push(i);",
  "});",
  "return out;",
  "}"
)

fonts_needed <- function(session, fonts, timeout) {
  pairs <- lapply(fonts, function(font) {
    list(font_key(font), font_face_spec(font)$id)
  })
  res <- cdp_call(
    session$Runtime$evaluate(
      paste0(
        "(",
        FONTS_NEEDED_JS,
        ")(",
        jsonlite::toJSON(pairs, auto_unbox = TRUE),
        ")"
      ),
      returnByValue = TRUE,
      timeout_ = timeout
    ),
    timeout,
    "checking staged fonts"
  )
  cdp_check_exception(res, "checking staged fonts")
  unlist(res$result$value) + 1L
}

FONTS_ENSURE_JS <- paste0(
  "async (spec) => {",
  "const have = document.__paparazziFonts ||",
  "(document.__paparazziFonts = new Map());",
  "const jobs = spec.map((f) => {",
  "const key = f.key;",
  "const entry = have.get(key);",
  "if (entry && entry.id === f.id) return Promise.resolve(null);",
  "return (async () => {",
  "const faces = [];",
  "if (f.url) {",
  "const res = await fetch(f.url);",
  "if (!res.ok) throw new Error('HTTP ' + res.status + ' fetching ' + f.url);",
  "const css = await res.text();",
  "const sheet = new CSSStyleSheet();",
  "sheet.replaceSync(css);",
  "for (const rule of sheet.cssRules) {",
  "if (!(rule instanceof CSSFontFaceRule)) continue;",
  "const src = rule.style.getPropertyValue('src');",
  "if (!src) continue;",
  # Google and Bunny split subsets by unicode-range; keeping it lets
  # Chrome pick the right subset file per glyph.
  "const descriptors = {weight: String(f.weight), style: f.style};",
  "const range = rule.style.getPropertyValue('unicode-range');",
  "if (range) descriptors.unicodeRange = range;",
  "faces.push(new FontFace(f.family, src, descriptors));",
  "}",
  "if (!faces.length) throw new Error('no @font-face rules at ' + f.url);",
  "} else {",
  "const bin = atob(f.data);",
  "const bytes = new Uint8Array(bin.length);",
  "for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);",
  "faces.push(new FontFace(f.family, bytes.buffer,",
  "{weight: String(f.weight), style: f.style}));",
  "}",
  "if (entry) for (const old of entry.faces) document.fonts.delete(old);",
  "const loads = faces.map((face) => {",
  "document.fonts.add(face);",
  "return face.load();",
  "});",
  "await Promise.all(loads);",
  "have.set(key, {id: f.id, faces});",
  "return null;",
  "})().catch((e) => f.family + ': ' + (e && e.message ? e.message : String(e)));",
  "});",
  "return await Promise.all(jobs);",
  "}"
)

font_google_url <- function(family, weight, style) {
  name <- gsub(" ", "+", family, fixed = TRUE)
  axis <- if (style == "italic") {
    paste0(":ital,wght@1,", weight)
  } else {
    paste0(":wght@", weight)
  }
  paste0(
    "https://fonts.googleapis.com/css2?family=",
    name,
    axis,
    "&display=swap"
  )
}

font_bunny_url <- function(family, weight, style) {
  name <- tolower(gsub(" ", "-", family, fixed = TRUE))
  suffix <- if (style == "italic") paste0(weight, "i") else as.character(weight)
  paste0("https://fonts.bunny.net/css?family=", name, ":", suffix)
}

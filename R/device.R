#' Emulate a device
#'
#' Configures device emulation for the page: viewport size, device scale
#' factor, mobile-ness, zoom, color scheme, reduced motion, locale and
#' time zone. Only **supplied** arguments change state: `NULL` (the
#' default) means "leave this setting alone", so `zoom = 1`, not
#' `zoom = NULL`, disables an active zoom. Whenever a viewport override
#' is applied, `scale` defaults to 2 (retina).
#'
#' The two zoom methods trade off differently:
#' * `zoom_method = "viewport"` (the default) shrinks the CSS viewport
#'   and raises the device scale factor, so `vh` stays correct but
#'   media queries can start (or stop) matching.
#' * `zoom_method = "css"` applies a CSS `zoom` to the page instead --
#'   on every document, so it survives navigation and reload: layout
#'   and media queries are untouched, but `vh`-sized elements no longer
#'   fit the viewport (a 50vh element covers the whole viewport at
#'   zoom 2).
#'
#' `reduced_motion = TRUE` gives deterministic stills (animations stop);
#' it's opt-in because it's usually wrong for videos.
#'
#' @inheritParams pz_act_click
#' @param width,height Viewport size in CSS pixels. Only the supplied
#'   one changes; the other keeps its current value.
#' @param scale Device scale factor. `NULL` retains the stored value, or
#'   uses 2 when applying the first override.
#' @param mobile Emulate a mobile device (touch input, mobile viewport
#'   semantics)? `NULL` retains the stored value, or uses `FALSE` when unset.
#' @param zoom Zoom factor; `1` disables zoom.
#' @param zoom_method `"viewport"` or `"css"`; see above. `NULL` retains the
#'   stored method, or uses `"viewport"` when unset. Used when a `zoom` is
#'   (or later becomes) active.
#' @param color_scheme `"light"` or `"dark"` for
#'   `prefers-color-scheme`.
#' @param reduced_motion Emulate `prefers-reduced-motion`? `TRUE` maps
#'   to `reduce`, `FALSE` to `no-preference`.
#' @param locale An ICU locale, e.g. `"de-DE"`.
#' @param timezone An IANA time zone, e.g. `"Pacific/Auckland"`.
#'
#' @return `ctx`, invisibly.
#'
#' @seealso [pz_open()] forwards its `...` here.
#'
#' @examplesIf paparazzi:::examples_run(site = TRUE)
#' page <- pz_open(pz_example("tasks"))
#'
#' # Only the settings you supply change
#' page |> pz_device(width = 390, height = 844, mobile = TRUE)
#' pz_js(page, "[window.innerWidth, window.devicePixelRatio]")
#'
#' page |> pz_device(color_scheme = "dark")
#' pz_get_style(page, "background-color", target = "body")
#' pz_close(page)
#'
#' @export
pz_device <- function(
  ctx,
  ...,
  width = NULL,
  height = NULL,
  scale = NULL,
  mobile = NULL,
  zoom = NULL,
  zoom_method = NULL,
  color_scheme = NULL,
  reduced_motion = NULL,
  locale = NULL,
  timezone = NULL
) {
  check_context(ctx)
  check_dots_empty()
  width <- check_dimension(width, "width")
  height <- check_dimension(height, "height")
  scale <- check_dimension(scale, "scale")
  zoom <- check_dimension(zoom, "zoom")
  if (!is.null(mobile)) {
    check_bool(mobile)
  }
  if (!is.null(zoom_method)) {
    zoom_method <- arg_match(zoom_method, values = c("viewport", "css"))
  }
  if (!is.null(color_scheme)) {
    color_scheme <- arg_match(color_scheme, values = c("light", "dark"))
  }
  if (!is.null(reduced_motion)) {
    check_bool(reduced_motion)
  }
  if (!is.null(locale)) {
    check_string(locale)
  }
  if (!is.null(timezone)) {
    check_string(timezone)
  }

  state <- device_state(ctx$page)
  device_step(state, {
    state$width <- width %||% state$width
    state$height <- height %||% state$height
    state$scale <- scale %||% state$scale
    state$mobile <- mobile %||% state$mobile
    state$zoom <- zoom %||% state$zoom
    state$zoom_method <- zoom_method %||% state$zoom_method
    device_apply_override(ctx$page, state)
  })
  # CSS zoom spans several CDP calls and records each as it succeeds, so
  # rolling it back would lose a script Chrome already registered.
  device_apply_css_zoom(ctx$page, state)
  device_step(
    state,
    device_apply_media(ctx$page, state, color_scheme, reduced_motion)
  )

  if (!is.null(locale)) {
    ctx$page$session$Emulation$setLocaleOverride(
      locale = locale,
      timeout_ = ctx$page$default_timeout
    )
  }
  if (!is.null(timezone)) {
    ctx$page$session$Emulation$setTimezoneOverride(
      timezoneId = timezone,
      timeout_ = ctx$page$default_timeout
    )
  }

  ctx_return(ctx)
}

# pz_open()'s dots are pz_device() settings, validated up front so a
# misspelling names the mistake instead of landing in check_dots_empty()
# as an anonymous unused argument. Unnamed dots error (settings must be
# named); unknown names error with a near-miss hint (adist, the same
# idea as match.arg's suggestion).
device_check_dots <- function(dots, call = caller_env()) {
  if (!length(dots)) {
    return(dots)
  }
  # Unnamed dots have no name at all, not an empty one.
  nms <- names(dots)
  if (is.null(nms) || !all(nzchar(nms))) {
    cli::cli_abort(
      "Device settings in {.arg ...} must be named, e.g. {.code width = 390}.",
      class = "paparazzi_error_input",
      call = call
    )
  }
  ok <- setdiff(names(formals(pz_device)), c("ctx", "..."))
  for (bad in setdiff(nms, ok)) {
    dist <- utils::adist(tolower(bad), tolower(ok))[1, ]
    near <- ok[dist > 0 & dist <= max(1, floor(nchar(bad) / 2))]
    cli::cli_abort(
      c(
        "Unknown device setting in {.arg ...}: {.arg {bad}}.",
        if (length(near)) {
          i <- cli::format_inline("Did you mean {.arg {near}}?")
        }
      ),
      class = "paparazzi_error_input",
      call = call
    )
  }
  dots
}

# pz_open() applies forwarded device settings right after the page is
# created, before any navigation, so media queries and layout are
# right at first render.
device_open <- function(page, dots) {
  if (length(dots)) {
    do.call(pz_device, c(list(ctx = page), dots))
  }
  invisible(page)
}

# pz_device()'s positive-numeric arguments (width, height, scale, zoom):
# rlang has no check_number_positive(), so this wraps check_number_decimal().
# 0 is rejected everywhere: a zero viewport is meaningless and a zero
# scale/zoom would silently reset the page.
check_dimension <- function(
  x,
  arg = caller_arg(x),
  call = caller_env()
) {
  if (is.null(x)) {
    return(NULL)
  }
  check_number_decimal(x, min = 0, arg = arg, call = call)
  if (x <= 0) {
    cli::cli_abort(
      "{.arg {arg}} must be positive, not {x}.",
      class = "paparazzi_error_input",
      call = call
    )
  }
  x
}

# Device state rides on the page as an attribute: R6 objects are
# environments, so the attribute travels with the page and dies with
# it, and no R6 field is needed for it. The state is an environment so
# device_apply_*() helpers can update it in place. Sticky base_width/
# base_height hold the pre-zoom viewport captured at the first
# viewport zoom (a live innerWidth read is already zoomed then);
# base_scale is not sticky because scale always carries a value
# whenever an override is applied.
device_state <- function(page) {
  state <- attr(page, "paparazzi_device")
  if (is.null(state)) {
    state <- new.env(parent = emptyenv())
    state$width <- NULL
    state$height <- NULL
    state$scale <- NULL
    state$mobile <- NULL
    state$zoom <- NULL
    state$zoom_method <- NULL
    state$base_width <- NULL
    state$base_height <- NULL
    state$overridden <- FALSE
    state$css_zoom <- NULL
    state$css_script <- NULL
    state$css_zoom_saved <- NULL
    state$color_scheme <- NULL
    state$reduced_motion <- NULL
    attr(page, "paparazzi_device") <- state
  }
  state
}

# Apply one step of a device change. The step records its settings in
# state before sending them, so a failed step puts the state back:
# otherwise a later partial pz_device() call would re-send settings the
# page never got. Earlier steps that succeeded stay recorded.
device_step <- function(state, code) {
  prev <- as.list(state, all.names = TRUE)
  tryCatch(code, error = function(e) {
    list2env(prev, envir = state)
    stop(e)
  })
}

# Recompute the full metrics override from state. CDP semantics (probed):
# width/height of 0 keep the current value; deviceScaleFactor of 0
# resets to 1, so the factor is always sent explicitly; width/height
# are protocol integers, hence the rounding.
device_apply_override <- function(page, state, call = caller_env()) {
  zoom <- state$zoom
  method <- state$zoom_method %||% "viewport"
  zoom_on <- !is.null(zoom) && !isTRUE(zoom == 1)
  viewport_zoom <- zoom_on && identical(method, "viewport")
  base_set <- !(is.null(state$width) &&
    is.null(state$height) &&
    is.null(state$scale) &&
    is.null(state$mobile))

  if (!viewport_zoom && !base_set) {
    if (isTRUE(state$overridden)) {
      # An in-flight capture restores the device metrics it saw at its start.
      record_hold(
        page,
        page$session$Emulation$clearDeviceMetricsOverride(
          timeout_ = page$default_timeout
        ),
        call = call
      )
      state$overridden <- FALSE
    }
    return(invisible(page))
  }

  if (
    viewport_zoom && (is.null(state$base_width) || is.null(state$base_height))
  ) {
    current <- device_viewport(page)
    state$base_width <- state$width %||% current$width
    state$base_height <- state$height %||% current$height
  }
  eff_width <- state$width %||% state$base_width %||% 0
  eff_height <- state$height %||% state$base_height %||% 0
  eff_scale <- state$scale %||% 2
  eff_mobile <- state$mobile %||% FALSE
  if (viewport_zoom) {
    eff_width <- eff_width / zoom
    eff_height <- eff_height / zoom
    eff_scale <- eff_scale * zoom
  }
  record_hold(
    page,
    page$session$Emulation$setDeviceMetricsOverride(
      width = round(eff_width),
      height = round(eff_height),
      deviceScaleFactor = eff_scale,
      mobile = eff_mobile,
      timeout_ = page$default_timeout
    ),
    call = call
  )
  state$overridden <- TRUE
  invisible(page)
}

# The CSS-zoom method: one style property on <html>, everything else
# untouched. The style dies with its document, so the zoom is carried
# by a script CDP evaluates on every NEW document (registered while a
# css zoom is active, removed when it disables) and an inline
# application covers the current one, which the registration alone
# never touches. The script guards on the top frame so iframes keep
# their own layout. Only touched when the desired zoom differs from
# the one in effect, or when a failed first apply left its script
# registered; a user's own html zoom style is overwritten while
# active, but never added or removed otherwise.
device_apply_css_zoom <- function(page, state, register = TRUE) {
  zoom <- state$zoom
  method <- state$zoom_method %||% "viewport"
  desired <- if (
    !is.null(zoom) && !isTRUE(zoom == 1) && identical(method, "css")
  ) {
    zoom
  }
  if (
    identical(desired, state$css_zoom) &&
      (!is.null(desired) || is.null(state$css_script))
  ) {
    return(invisible(page))
  }
  if (is.null(desired)) {
    # Disable: the injected script goes away with the effect, so
    # future documents stay at their own size too, and the current
    # document gets back the inline zoom paparazzi found at the first
    # application (or none).
    if (!is.null(state$css_script)) {
      page$session$Page$removeScriptToEvaluateOnNewDocument(
        identifier = state$css_script,
        timeout_ = page$default_timeout
      )
      state$css_script <- NULL
    }
    saved <- state$css_zoom_saved
    if (is.null(saved) || !nzchar(saved)) {
      device_eval(page, "document.documentElement.style.removeProperty('zoom')")
    } else {
      device_eval(
        page,
        paste0(
          "document.documentElement.style.zoom = ",
          jsonlite::toJSON(saved, auto_unbox = TRUE)
        )
      )
    }
    state$css_zoom_saved <- NULL
  } else {
    # Reapply after a navigation skips the registration: the script
    # in place already encodes the desired zoom (only pz_device()
    # changes the factor, and it re-registers).
    if (register || is.null(state$css_script)) {
      if (is.null(state$css_script)) {
        # First application: remember the page's own inline zoom so
        # disable can give it back (never re-captured once the script
        # is in place, so the settle reapplies keep the first save).
        state$css_zoom_saved <- device_eval(
          page,
          "document.documentElement.style.zoom || ''"
        )
      }
      if (!is.null(state$css_script)) {
        page$session$Page$removeScriptToEvaluateOnNewDocument(
          identifier = state$css_script,
          timeout_ = page$default_timeout
        )
      }
      # The script only runs on documents committed while the Page
      # domain is enabled; chromote auto-enables a domain on its
      # first event listener and auto-disables it when the last one
      # releases, so the enable is requested explicitly here to
      # cover commits no listener is waiting for.
      page$session$Page$enable(timeout_ = page$default_timeout)
      state$css_script <- page$session$Page$addScriptToEvaluateOnNewDocument(
        source = device_zoom_script(desired),
        timeout_ = page$default_timeout
      )$identifier
    }
    device_eval(
      page,
      paste0(
        "document.documentElement.style.zoom = ",
        format(desired, trim = TRUE, digits = 15)
      )
    )
  }
  state$css_zoom <- desired
  invisible(page)
}

# The script that carries a css zoom onto every new document. The
# top-frame guard keeps iframes at their own layout. The script runs
# before the document has an <html> element, so the application waits
# for readyState to move past "loading" in that case.
device_zoom_script <- function(zoom) {
  paste0(
    "if (window === window.top) {",
    "var z = ",
    format(zoom, trim = TRUE, digits = 15),
    ";",
    "if (document.documentElement) {",
    "document.documentElement.style.zoom = z;",
    "} else {",
    "document.addEventListener('readystatechange', function() {",
    "document.documentElement.style.zoom = z;",
    "}, { once: true });",
    "}",
    "}"
  )
}

# Reapply the css zoom on the document a navigation just settled on.
# The injected script covers commits while the Page domain is enabled,
# but chromote auto-disables it once its last event listener releases
# (a released frameNavigated promise), and a commit in that window
# runs no script -- so every paparazzi settle point re-applies the
# inline zoom instead. wait_nav_reset() clears the cache slot first:
# the inline style died with the outgoing document.
device_css_reapply <- function(page) {
  state <- attr(page, "paparazzi_device")
  if (is.null(state)) {
    return(invisible(FALSE))
  }
  device_apply_css_zoom(page, state, register = FALSE)
  invisible(TRUE)
}

# Emulated media features. CDP replaces the whole features set on every
# call (probed), so color scheme and reduced motion are tracked as one
# pair and the union of the active ones is sent whenever either changes.
# A "" value would clear a feature, but the API has no clear path yet.
device_apply_media <- function(page, state, color_scheme, reduced_motion) {
  changed <- (!is.null(color_scheme) &&
    !identical(color_scheme, state$color_scheme)) ||
    (!is.null(reduced_motion) &&
      !identical(reduced_motion, state$reduced_motion))
  state$color_scheme <- color_scheme %||% state$color_scheme
  state$reduced_motion <- reduced_motion %||% state$reduced_motion
  if (!changed) {
    return(invisible(page))
  }
  features <- list()
  if (!is.null(state$color_scheme)) {
    features <- c(
      features,
      list(list(name = "prefers-color-scheme", value = state$color_scheme))
    )
  }
  if (!is.null(state$reduced_motion)) {
    value <- if (isTRUE(state$reduced_motion)) "reduce" else "no-preference"
    features <- c(
      features,
      list(list(name = "prefers-reduced-motion", value = value))
    )
  }
  page$session$Emulation$setEmulatedMedia(
    features = features,
    timeout_ = page$default_timeout
  )
  invisible(page)
}

# Evaluate with returnByValue; JS failures in these one-line scripts
# surface as classed errors instead of raw chromote ones.
device_eval <- function(page, expr, call = caller_env()) {
  res <- cdp_call(
    page$session$Runtime$evaluate(
      expr,
      returnByValue = TRUE,
      timeout_ = page$default_timeout
    ),
    page$default_timeout,
    "evaluating JavaScript",
    call
  )
  cdp_check_exception(res, call = call)
  invisible(res$result$value)
}

device_viewport <- function(page) {
  jsonlite::fromJSON(
    device_eval(
      page,
      "JSON.stringify({width: innerWidth, height: innerHeight})"
    )
  )
}

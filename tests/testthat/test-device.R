js <- function(ctx, expr) {
  pz_js(ctx, expr)
}

test_that("pz_device validates its inputs", {
  page <- local_device_page()

  expect_error(pz_device(42), class = "paparazzi_error_context")
  expect_error(pz_device(page, widht = 390), class = "rlib_error_dots_nonempty")
  expect_error(
    pz_device(page, width = -1),
    regexp = "larger than or equal to 0"
  )
  expect_error(pz_device(page, width = 0), class = "paparazzi_error_input")
  expect_error(pz_device(page, height = 0), class = "paparazzi_error_input")
  expect_error(pz_device(page, scale = 0), class = "paparazzi_error_input")
  expect_error(pz_device(page, zoom = 0), class = "paparazzi_error_input")
  expect_error(pz_device(page, mobile = "yes"), regexp = "TRUE.+or.+FALSE")
  expect_error(pz_device(page, zoom_method = "lens"), regexp = "must be one of")
  expect_error(
    pz_device(page, color_scheme = "sepia"),
    regexp = "must be one of"
  )
  expect_error(pz_device(page, reduced_motion = 1), regexp = "TRUE.+or.+FALSE")
  expect_error(pz_device(page, locale = 42), regexp = "single string")
  expect_error(pz_device(page, timezone = 42), regexp = "single string")
})

test_that("pz_device returns its context invisibly, from any context", {
  page <- local_device_page()
  expect_invisible(pz_device(page, width = 800))

  scoped <- pz_find(page, "#px")
  expect_identical(pz_device(scoped, height = 600), scoped)
})

test_that("pz_device sets the viewport with a default retina scale", {
  page <- local_device_page()
  pz_device(page, width = 800, height = 600)

  expect_equal(js(page, "innerWidth"), 800)
  expect_equal(js(page, "innerHeight"), 600)
  expect_equal(js(page, "devicePixelRatio"), 2)

  pz_device(page, scale = 1)
  expect_equal(js(page, "devicePixelRatio"), 1)
})

test_that("only supplied dimensions change state", {
  page <- local_device_page()
  h0 <- js(page, "innerHeight")

  pz_device(page, width = 800)
  expect_equal(js(page, "innerWidth"), 800)
  expect_equal(js(page, "innerHeight"), h0)

  # A call that touches something else leaves the viewport alone.
  pz_device(page, color_scheme = "dark")
  expect_equal(js(page, "innerWidth"), 800)
  expect_equal(js(page, "innerHeight"), h0)
  expect_equal(js(page, "devicePixelRatio"), 2)
})

test_that("a failed device change doesn't leak into later partial changes", {
  page <- local_device_page()
  pz_device(page, width = 640, height = 560)

  with_mocked_bindings(
    record_hold = function(page, code, call) stop("override failed"),
    expect_error(pz_device(page, width = 800), "override failed")
  )
  pz_device(page, height = 500)
  expect_equal(js(page, "innerWidth"), 640)
  expect_equal(js(page, "innerHeight"), 500)

  session <- page$page$session
  emulation <- session$Emulation
  failing <- emulation
  failing$setEmulatedMedia <- function(...) stop("media failed")
  session$Emulation <- failing
  expect_error(pz_device(page, color_scheme = "dark"), "media failed")
  session$Emulation <- emulation
  pz_device(page, reduced_motion = TRUE)
  expect_false(js(page, "matchMedia('(prefers-color-scheme: dark)').matches"))
})

test_that("viewport zoom shrinks the CSS viewport and raises the scale factor", {
  page <- local_device_page()
  pz_device(page, width = 800, height = 600, scale = 2)
  pz_device(page, zoom = 2)

  expect_equal(js(page, "innerWidth"), 400)
  expect_equal(js(page, "innerHeight"), 300)
  expect_equal(js(page, "devicePixelRatio"), 4)

  # vh stays correct: a 50vh box is still half of innerHeight.
  expect_equal(
    js(page, "document.getElementById('vh').getBoundingClientRect().height"),
    150
  )
  # The shrunken CSS viewport can trigger media queries.
  expect_true(js(page, "matchMedia('(max-width: 500px)').matches"))

  # zoom = 1 (not NULL) disables the zoom and restores the base dims.
  pz_device(page, zoom = 1)
  expect_equal(js(page, "innerWidth"), 800)
  expect_equal(js(page, "devicePixelRatio"), 2)
  expect_false(js(page, "matchMedia('(max-width: 500px)').matches"))
})

test_that("css zoom keeps layout but breaks vh", {
  page <- local_device_page()
  pz_device(page, width = 800, height = 600, scale = 2)
  pz_device(page, zoom = 2, zoom_method = "css")

  # Viewport and media queries are untouched...
  expect_equal(js(page, "innerWidth"), 800)
  expect_equal(js(page, "innerHeight"), 600)
  expect_equal(js(page, "devicePixelRatio"), 2)
  expect_false(js(page, "matchMedia('(max-width: 500px)').matches"))

  # ...while the page itself is zoomed.
  expect_equal(js(page, "getComputedStyle(document.documentElement).zoom"), "2")
  # Layout sizes are preserved pre-zoom...
  expect_equal(js(page, "document.getElementById('px').offsetWidth"), 100)
  # ...rendered (rect) sizes carry the factor.
  expect_equal(
    js(page, "document.getElementById('px').getBoundingClientRect().width"),
    200
  )
  # A 50vh box now renders across the full viewport: vh is broken.
  expect_equal(
    js(page, "document.getElementById('vh').getBoundingClientRect().height"),
    600
  )

  # zoom = 1 removes the style again.
  pz_device(page, zoom = 1)
  expect_equal(js(page, "document.documentElement.style.zoom"), "")
  expect_equal(
    js(page, "document.getElementById('vh').getBoundingClientRect().height"),
    300
  )
})

test_that("css zoom survives navigation, reload, and disabling", {
  # Applied through pz_open()'s dots: the destination document must
  # arrive zoomed, not just the about:blank that was current at apply.
  page <- local_page(nav_fixture_url("a"), zoom = 2, zoom_method = "css")
  expect_identical(js(page, "document.title"), "paparazzi nav A")
  expect_equal(js(page, "getComputedStyle(document.documentElement).zoom"), "2")

  pz_nav_goto(page, nav_fixture_url("b"))
  expect_identical(js(page, "document.title"), "paparazzi nav B")
  expect_equal(js(page, "getComputedStyle(document.documentElement).zoom"), "2")

  pz_nav_reload(page)
  expect_equal(js(page, "getComputedStyle(document.documentElement).zoom"), "2")

  # zoom = 1 removes the effect, including for future documents.
  pz_device(page, zoom = 1)
  expect_equal(js(page, "getComputedStyle(document.documentElement).zoom"), "1")
  pz_nav_goto(page, nav_fixture_url("a"))
  expect_identical(js(page, "document.title"), "paparazzi nav A")
  expect_equal(js(page, "getComputedStyle(document.documentElement).zoom"), "1")
})

test_that("a css zoom that fails after registering its script can be disabled", {
  page <- local_page(nav_fixture_url("a"))
  real_eval <- device_eval
  with_mocked_bindings(
    device_eval = function(page, expr, ...) {
      if (grepl("style.zoom = ", expr, fixed = TRUE)) {
        stop("apply failed")
      }
      real_eval(page, expr, ...)
    },
    expect_error(pz_device(page, zoom = 2, zoom_method = "css"), "apply failed")
  )
  pz_device(page, zoom = 2, zoom_method = "css")
  pz_device(page, zoom = 1)
  pz_nav_goto(page, nav_fixture_url("b"))
  expect_equal(js(page, "getComputedStyle(document.documentElement).zoom"), "1")
})

test_that("disabling css zoom restores the page's own inline zoom", {
  # The fixture's <html> carries its own inline zoom; emulation must
  # give it back on disable, not remove it.
  page <- local_page(device_zoom_fixture_file())
  expect_equal(js(page, "document.documentElement.style.zoom"), "1.5")

  pz_device(page, zoom = 2, zoom_method = "css")
  expect_equal(js(page, "getComputedStyle(document.documentElement).zoom"), "2")

  # A factor change while active keeps the first save.
  pz_device(page, zoom = 3)
  expect_equal(js(page, "getComputedStyle(document.documentElement).zoom"), "3")

  pz_device(page, zoom = 1)
  expect_equal(js(page, "document.documentElement.style.zoom"), "1.5")
  expect_equal(
    js(page, "getComputedStyle(document.documentElement).zoom"),
    "1.5"
  )
})

test_that("zoom defaults to the viewport method", {
  page <- local_device_page()
  pz_device(page, width = 800, height = 600, scale = 2)
  pz_device(page, zoom = 2)

  expect_equal(js(page, "innerWidth"), 400)
  expect_equal(js(page, "getComputedStyle(document.documentElement).zoom"), "1")
})

test_that("color scheme emulation is observable in matchMedia and styles", {
  page <- local_device_page()

  pz_device(page, color_scheme = "light")
  expect_true(js(page, "matchMedia('(prefers-color-scheme: light)').matches"))
  expect_equal(
    js(page, "getComputedStyle(document.body).backgroundColor"),
    "rgb(255, 255, 255)"
  )

  pz_device(page, color_scheme = "dark")
  expect_true(js(page, "matchMedia('(prefers-color-scheme: dark)').matches"))
  expect_equal(
    js(page, "getComputedStyle(document.body).backgroundColor"),
    "rgb(34, 34, 34)"
  )
})

test_that("reduced motion emulation is observable in matchMedia and styles", {
  page <- local_device_page()

  # Emulate explicitly: the host OS could already prefer reduced motion.
  pz_device(page, reduced_motion = FALSE)
  expect_false(js(
    page,
    "matchMedia('(prefers-reduced-motion: reduce)').matches"
  ))
  expect_equal(
    js(page, "getComputedStyle(document.getElementById('spin')).animationName"),
    "spin"
  )

  pz_device(page, reduced_motion = TRUE)
  expect_true(js(
    page,
    "matchMedia('(prefers-reduced-motion: reduce)').matches"
  ))
  expect_equal(
    js(page, "getComputedStyle(document.getElementById('spin')).animationName"),
    "none"
  )
})

test_that("color scheme and reduced motion emulations coexist", {
  page <- local_device_page()
  # setEmulatedMedia replaces the whole feature set, so these must not
  # clobber each other.
  pz_device(page, color_scheme = "dark")
  pz_device(page, reduced_motion = TRUE)

  expect_true(js(page, "matchMedia('(prefers-color-scheme: dark)').matches"))
  expect_true(js(
    page,
    "matchMedia('(prefers-reduced-motion: reduce)').matches"
  ))
})

test_that("locale and timezone overrides apply", {
  page <- local_device_page()

  pz_device(page, locale = "de-DE")
  expect_identical(js(page, "(1.5).toLocaleString()"), "1,5")
  expect_identical(
    js(page, "Intl.DateTimeFormat().resolvedOptions().locale"),
    "de-DE"
  )

  pz_device(page, timezone = "Pacific/Auckland")
  expect_identical(
    js(page, "Intl.DateTimeFormat().resolvedOptions().timeZone"),
    "Pacific/Auckland"
  )
})

test_that("mobile emulation applies", {
  # about:blank has no meta viewport, so mobile layout uses the classic
  # 980px viewport: the one innerWidth-visible difference the metrics
  # override's mobile flag makes.
  page <- local_page("about:blank")
  pz_device(page, width = 800, height = 600)
  expect_equal(js(page, "innerWidth"), 800)

  pz_device(page, mobile = TRUE)
  expect_equal(js(page, "innerWidth"), 980)

  pz_device(page, mobile = FALSE)
  expect_equal(js(page, "innerWidth"), 800)
  expect_equal(js(page, "innerHeight"), 600)
})

test_that("pz_open forwards device settings to pz_device", {
  page <- local_device_page(width = 800, height = 600)
  expect_equal(js(page, "innerWidth"), 800)
  expect_equal(js(page, "innerHeight"), 600)
  expect_equal(js(page, "devicePixelRatio"), 2)

  # Forwarding works for a wrapped ChromoteSession too.
  session <- chromote::ChromoteSession$new()
  withr::defer(session$close())
  page2 <- pz_open(session, width = 390)
  expect_equal(js(page2, "innerWidth"), 390)
})

test_that("pz_open dots are checked for typos", {
  skip_if_no_chrome()
  expect_error(
    local_device_page(widht = 390),
    regexp = "Did you mean",
    class = "paparazzi_error_input"
  )
  expect_error(
    local_device_page(390),
    regexp = "must be named",
    class = "paparazzi_error_input"
  )
  expect_error(
    local_device_page(scalex = 2),
    regexp = "Did you mean",
    class = "paparazzi_error_input"
  )
})

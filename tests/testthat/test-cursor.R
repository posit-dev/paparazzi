test_that("cursor functions draw, hide, move, and leave the overlay cursor", {
  page <- local_cursor_page()

  # First show with no position: the viewport center, statically (no
  # recording, so no fade).
  page |> pz_cursor_show()
  v <- unlist(pz_js(page, "[window.innerWidth, window.innerHeight]"))
  st <- cursor_overlay_state(page)
  expect_equal(st[[1]], 1)
  expect_equal(st[[2]], v[[1]] / 2, tolerance = 1)
  expect_equal(st[[3]], v[[2]] / 2, tolerance = 1)

  page |> pz_cursor_hide()
  expect_equal(cursor_overlay_state(page)[[1]], 0)

  # Move centers on the target (#btn at left 600 top 300, 120 x 44).
  page |> pz_cursor_move("#btn")
  st <- cursor_overlay_state(page)
  expect_equal(st[[1]], 1)
  expect_equal(st[2:3], c(660, 322))

  # Leave sends the cursor off-frame on the named side, staying visible.
  page |> pz_cursor_leave("left")
  st <- cursor_overlay_state(page)
  expect_equal(st[[1]], 1)
  expect_true(st[[2]] < 0)
  expect_equal(st[[3]], 322)

  # The next action brings the cursor back to the pointer (not
  # recording, so it jumps) and the click still lands.
  page |> pz_act_click("#btn")
  expect_equal(pz_js(page, "window.__log.clicks"), 1)
  expect_equal(cursor_overlay_state(page)[2:3], c(660, 322))
})

test_that("pz_cursor_show() on a scoped context centers on the scope", {
  page <- local_cursor_page()
  page |> pz_find("#btn") |> pz_cursor_show()
  expect_equal(cursor_overlay_state(page)[2:3], c(660, 322))
})

test_that("pz_cursor_show(from =) starts off-frame on that side", {
  page <- local_cursor_page()
  # Not recording: the entrance collapses to a static jump to the target.
  page |> pz_cursor_show("#btn", from = "right")
  expect_equal(cursor_overlay_state(page)[2:3], c(660, 322))
})

test_that("corner directions enter and leave past both frame edges", {
  page <- local_cursor_page()

  # Leaving through a corner ends past both edges at once.
  page |> pz_cursor_show("#btn") |> pz_cursor_leave("top-left")
  st <- cursor_overlay_state(page)
  expect_true(st[[2]] < 0)
  expect_true(st[[3]] < 0)

  # A corner from re-enters to the target (static jump when not
  # recording); tokens normalize in either order and casing.
  page |> pz_cursor_show("#btn", from = "bottom right")
  expect_equal(cursor_overlay_state(page)[2:3], c(660, 322))

  page |> pz_stage(enter = "Left-top")
  expect_identical(page_stage(page)$enter, c("left", "top"))
})

test_that("pz_cursor_move rejects infinite durations", {
  page <- local_cursor_page()

  expect_error(
    pz_cursor_move(page, "#btn", duration = Inf),
    class = "rlang_error"
  )

  expect_no_error(pz_cursor_move(page, "#btn", duration = 0))
  expect_no_error(pz_cursor_move(page, "#btn", duration = NULL))
  expect_no_error(pz_cursor_move(page, "#btn", duration = 0.1))
})

test_that("cursor function and stage validation is classed", {
  page <- local_cursor_page()

  expect_error(pz_cursor_leave(page, "up"), class = "paparazzi_error_input")
  expect_error(
    pz_cursor_show(page, from = "middle"),
    class = "paparazzi_error_input"
  )
  expect_error(
    pz_cursor_move(page, "#btn", duration = -1),
    class = "rlang_error"
  )
  expect_error(pz_cursor_hide(page, 1), class = "rlang_error")

  page |> pz_stage(cursor = FALSE)
  expect_error(pz_cursor_show(page), class = "paparazzi_error_cursor")
  expect_error(pz_cursor_move(page, "#btn"), class = "paparazzi_error_cursor")
  expect_error(pz_cursor_leave(page), class = "paparazzi_error_cursor")
  # pz_cursor_hide() stays legal (it's how you retract an explicit show).
  expect_no_error(page |> pz_cursor_hide())
})

test_that("the cursor switches to a hand over cursor:pointer elements", {
  page <- local_cursor_page()
  page |> pz_cursor_move("#btn")
  expect_equal(attr(cursor_overlay_state(page), "icon"), "pointer")
  page |> pz_cursor_move("#plain")
  expect_equal(attr(cursor_overlay_state(page), "icon"), "default")
})

test_that("pointing cursor ink is visible on light and dark pointer targets", {
  # The dark button sits at x = 800..920, past every other fixture
  # element; pin the viewport so its coordinates cannot scroll.
  page <- local_page(cursor_fixture_file(), width = 1000, height = 700)
  shot <- withr::local_tempfile(fileext = ".png")

  page |> pz_cursor_move("#btn")
  page |> pz_screenshot(shot)
  light <- cursor_png_ink(
    page,
    shot,
    band = c(300, 344),
    x_range = c(600, 720)
  )
  expect_gt(light$count, 50)
  expect_lt(abs(light$x - 660), 25)
  expect_lt(abs(light$y - 322), 20)
  # The fingertip sits on the hotspot specified by the bundled SVG
  # metadata rather than the old artwork's hand-path coordinates.
  tip_light <- cursor_png_ink(
    page,
    shot,
    band = c(322, 330),
    x_range = c(658, 666)
  )
  expect_gt(tip_light$count, 0)

  page |> pz_cursor_move("#dark-btn")
  page |> pz_screenshot(shot)
  dark <- cursor_png_ink(
    page,
    shot,
    band = c(210, 254),
    x_range = c(800, 920),
    tone = "light"
  )
  expect_gt(dark$count, 10)
  expect_lt(abs(dark$x - 860), 25)
  expect_lt(abs(dark$y - 232), 20)
  tip_dark <- cursor_png_ink(
    page,
    shot,
    band = c(232, 240),
    x_range = c(858, 866),
    tone = "light"
  )
  expect_gt(tip_dark$count, 0)
})

test_that("recorded click frames keep pointing cursor ink at the target", {
  skip_if_no_av()
  page <- local_cursor_page()
  out <- withr::local_tempfile(fileext = ".mp4")
  page |> pz_record_start(out, fps = 10, hold = c(0, 0), keep_frames = TRUE)
  page |> pz_act_click("#btn")
  page |> pz_record_stop()

  frames_dir <- paste0(tools::file_path_sans_ext(out), "_frames")
  on.exit(unlink(frames_dir, recursive = TRUE), add = TRUE)
  frames <- list.files(frames_dir, full.names = TRUE)
  expect_gt(length(frames), 0)

  inks <- lapply(frames, function(frame) {
    cursor_png_ink(
      page,
      frame,
      band = c(300, 344),
      x_range = c(635, 700)
    )
  })
  at_target <- Filter(
    function(ink) {
      ink$count > 20 && abs(ink$x - 660) < 25 && abs(ink$y - 322) < 20
    },
    inks
  )
  expect_gt(length(at_target), 0)

  # The same fingertip window distinguishes the pointing hand on frame
  # captures: at least one kept frame carries tip ink at the landing
  # point, which the old four-finger silhouette would leave empty.
  tips <- lapply(frames, function(frame) {
    cursor_png_ink(
      page,
      frame,
      band = c(322, 330),
      x_range = c(658, 666)
    )
  })
  expect_gt(sum(unlist(lapply(tips, `[[`, "count")) > 0), 0)
})

test_that("cursor = TRUE draws a static cursor in screenshots; FALSE never draws", {
  page <- local_cursor_page()
  page |> pz_stage(cursor = TRUE)
  expect_equal(cursor_overlay_state(page)[[1]], 1)

  page |> pz_cursor_move("#btn")
  shot <- withr::local_tempfile(fileext = ".png")
  page |> pz_screenshot(shot)
  ink <- cursor_png_ink(page, shot, band = c(280, 370))
  expect_true(ink$count > 50)
  expect_true(abs(ink$x - 660) < 15)
  expect_true(abs(ink$y - 322) < 30)

  page2 <- local_cursor_page()
  page2 |> pz_stage(cursor = FALSE)
  shot2 <- withr::local_tempfile(fileext = ".png")
  page2 |> pz_screenshot(shot2)
  expect_equal(cursor_png_ink(page2, shot2, band = c(280, 370))$count, 0)
})

test_that("cursor_scale changes ink size and NULL restores the default", {
  page <- local_cursor_page()
  page |> pz_stage(cursor_scale = 1) |> pz_cursor_move("#btn")
  shot <- withr::local_tempfile(fileext = ".png")
  page |> pz_screenshot(shot)
  original <- cursor_png_ink(page, shot, band = c(280, 370))

  page |> pz_stage(cursor_scale = 2)
  shot2 <- withr::local_tempfile(fileext = ".png")
  page |> pz_screenshot(shot2)
  larger <- cursor_png_ink(page, shot2, band = c(280, 370))
  expect_gt(larger$height, original$height * 1.7)

  page |> pz_stage(cursor_scale = NULL)
  shot3 <- withr::local_tempfile(fileext = ".png")
  page |> pz_screenshot(shot3)
  restored <- cursor_png_ink(page, shot3, band = c(280, 370))
  expect_gt(restored$height, original$height * 1.4)
  expect_lt(restored$height, larger$height)
})

test_that("changing cursor_scale redraws a visible recording cursor", {
  skip_if_no_av()
  page <- local_cursor_page()
  page |>
    pz_record_start(
      withr::local_tempfile(fileext = ".mp4"),
      fps = 10,
      hold = c(0, 0)
    )
  page |> pz_cursor_move("#btn")
  page |> pz_stage(cursor_scale = 1)
  expect_equal(cursor_overlay_scale(page), 1)
  page |> pz_stage(cursor_scale = NULL)
  expect_equal(cursor_overlay_scale(page), 1.75)
  page |> pz_record_stop()
})

test_that("the overlay is excluded from resolution and hit-testing", {
  page <- local_cursor_page()
  before <- pz_get_count(page, target = "div")
  page |> pz_cursor_move("#btn")
  expect_equal(pz_get_count(page, target = "div"), before)
  # The cursor sits exactly over #btn; hit-testing reaches the page.
  expect_equal(pz_js(page, "document.elementFromPoint(660, 322).id"), "btn")
  expect_no_error(page |> pz_expect_count(before, target = "div"))
})

test_that("the overlay survives navigation with its size and last position", {
  page <- local_cursor_page()
  page |> pz_stage(cursor_scale = 2) |> pz_cursor_move("#btn")
  before_path <- withr::local_tempfile(fileext = ".png")
  page |> pz_screenshot(before_path)
  before <- cursor_png_ink(page, before_path, band = c(280, 370))

  pz_chromote(page)$Page$reload()
  pz_wait(page, 1)

  st <- cursor_overlay_state(page)
  expect_false(is.null(st))
  expect_equal(st[[1]], 1)
  expect_equal(st[2:3], c(660, 322))
  after_path <- withr::local_tempfile(fileext = ".png")
  page |> pz_screenshot(after_path)
  after <- cursor_png_ink(page, after_path, band = c(280, 370))
  expect_equal(after$height, before$height)
  # And the re-injected overlay is still excluded from resolution.
  expect_equal(pz_get_count(page, target = "div"), 5)
})

test_that("CSS zoom keeps the cursor aligned with the pointer", {
  page <- local_cursor_page()
  pz_js(page, "document.documentElement.style.zoom = '2'")
  page |> pz_cursor_move("#btn")
  # getBoundingClientRect coordinates double under zoom = 2, and the
  # cursor translate matches them exactly (counter-zoomed layer).
  rect <- unlist(pz_js(
    page,
    "(() => { const r = document.getElementById('btn').getBoundingClientRect(); return [r.x + r.width / 2, r.y + r.height / 2]; })()"
  ))
  st <- cursor_overlay_state(page)
  expect_equal(st[2:3], rect)
  # The real pointer still hits the button through the zoom.
  page |> pz_act_click("#btn")
  expect_equal(pz_js(page, "window.__log.clicks"), 1)
})

test_that("pz_inspect reports recording and cursor state", {
  skip_if_no_av()
  page <- local_cursor_page()

  line <- function(page) {
    out <- capture.output(print(page))
    grep("Recording", out, value = TRUE)
  }
  expect_match(line(page), "off · cursor hidden")

  page |> pz_cursor_show()
  expect_match(line(page), "off · cursor visible")

  out <- withr::local_tempfile(fileext = ".mp4")
  page |> pz_record_start(out, fps = 10, hold = c(0, 0))
  expect_match(line(page), "on · cursor visible")

  page |> pz_cursor_hide()
  expect_match(line(page), "on · cursor hidden")

  page |> pz_cursor_show() |> pz_cursor_leave("right")
  expect_match(line(page), "on · cursor off-frame")

  page |> pz_record_stop()
  expect_true(file.exists(out))
})

test_that("the press animation scales the cursor down", {
  page <- local_cursor_page()
  page |> pz_cursor_move("#btn")

  # The ink scan stays in the button's band (the fixture's scroller
  # holds near-black text elsewhere on the page).
  shot <- withr::local_tempfile(fileext = ".png")
  page |> pz_screenshot(shot)
  unpressed <- cursor_png_ink(page, shot, band = c(280, 370))
  expect_equal(cursor_overlay_scale(page), 1.75)

  cursor_press(page, TRUE)
  # The shrink is a 0.12s transition that starts once the press state is
  # rendered; poll the applied pixels instead of sampling after a fixed pump.
  pressed <- NULL
  result <- expect_retry(
    function() {
      shot2 <- withr::local_tempfile(fileext = ".png")
      page |> pz_screenshot(shot2)
      pressed <<- cursor_png_ink(page, shot2, band = c(280, 370))
      list(pass = pressed$height < unpressed$height * 0.9)
    },
    timeout = 2,
    loop = page$child_loop
  )
  if (!result$pass) {
    testthat::fail("the pressed cursor ink never shrank below 0.9x")
  }
  expect_equal(cursor_overlay_scale(page), 1.4)

  expect_true(pressed$count > 20)
  expect_true(pressed$height < unpressed$height * 0.9)
  expect_true(pressed$height > unpressed$height * 0.6)
})

# Pin transitions in the same browser task that creates the ring.
local_paused_cursor_ring <- function(.env = parent.frame()) {
  local_mocked_bindings(
    cursor_command_js = paste0(
      "function(state) { const icon = (",
      cursor_command_js,
      ")(state);",
      "if (state.anim && state.ring) {",
      "const r = document.getElementById('paparazzi-overlay-root').shadowRoot.querySelector('.pz-ring');",
      "r.getAnimations().forEach((a) => { a.pause(); a.currentTime = a.transitionProperty === 'opacity' ? 0 : 200; });",
      "} return icon; }"
    ),
    .env = .env
  )
}

# Ring pixels of `color` in a still, around the #btn click point
# (660, 322); the fixture has no reddish or green content there.
ring_pixels <- function(page, path, color) {
  cursor_png_color(page, path, color, band = c(290, 355), x_range = c(620, 700))
}

test_that("the ring effect draws a ring instead of scaling the cursor", {
  skip_if_no_av()
  local_paused_cursor_ring()
  page <- local_cursor_page()
  page |>
    pz_stage(click_effect = "ring") |>
    pz_cursor_move("#btn", duration = 0)
  # The ring only draws while recording.
  out <- withr::local_tempfile(fileext = ".mp4")
  page |> pz_record_start(out, fps = 10, hold = c(0, 0))
  defer_record_stop(page)

  before <- withr::local_tempfile(fileext = ".png")
  page |> pz_screenshot(before)
  unpressed <- cursor_png_ink(
    page,
    before,
    band = c(300, 344),
    x_range = c(635, 700)
  )

  page |> pz_act_click("#btn")
  shot <- withr::local_tempfile(fileext = ".png")
  page |> pz_screenshot(shot)
  page |> pz_record_stop()

  # A mid-expansion ring in the staged default color.
  expect_gt(ring_pixels(page, shot, "#e11d48"), 20)
  # The ring replaces the press scale: the cursor ink never shrank.
  expect_equal(cursor_overlay_scale(page), page_stage(page)$cursor_scale)
  ink <- cursor_png_ink(page, shot, band = c(300, 344), x_range = c(635, 700))
  expect_gte(ink$height, unpressed$height * 0.95)
})

test_that("effect none draws nothing, and per-call effects override the stage", {
  skip_if_no_av()
  local_paused_cursor_ring()
  page <- local_cursor_page()
  page |>
    pz_stage(click_effect = "none") |>
    pz_cursor_move("#btn", duration = 0)
  out <- withr::local_tempfile(fileext = ".mp4")
  page |> pz_record_start(out, fps = 10, hold = c(0, 0))
  defer_record_stop(page)

  page |> pz_act_click("#btn")
  none_shot <- withr::local_tempfile(fileext = ".png")
  page |> pz_screenshot(none_shot)
  page |> pz_act_click("#btn", effect = "ring", effect_color = "#16a34a")
  ring_shot <- withr::local_tempfile(fileext = ".png")
  page |> pz_screenshot(ring_shot)
  page |> pz_record_stop()

  # The staged "none" click drew no ring, while the per-call ring drew
  # one in its own color (green, not the staged default).
  expect_lte(ring_pixels(page, none_shot, "#e11d48"), 20)
  expect_gt(ring_pixels(page, ring_shot, "#16a34a"), 20)
  expect_lte(ring_pixels(page, ring_shot, "#e11d48"), 20)

  # Neither click scaled the cursor.
  expect_equal(cursor_overlay_scale(page), page_stage(page)$cursor_scale)
})

test_that("all CSS cursor presets validate and select their own layer", {
  page <- local_cursor_page()
  keywords <- c(
    "default",
    "pointer",
    "text",
    "not-allowed",
    "crosshair",
    "grab",
    "grabbing",
    "ew-resize",
    "ns-resize",
    "nesw-resize",
    "nwse-resize",
    "row-resize",
    "col-resize",
    "alias",
    "all-scroll",
    "cell",
    "context-menu",
    "copy",
    "e-resize",
    "help",
    "move",
    "n-resize",
    "ne-resize",
    "no-drop",
    "nw-resize",
    "progress",
    "s-resize",
    "se-resize",
    "sw-resize",
    "vertical-text",
    "w-resize",
    "wait",
    "zoom-in",
    "zoom-out",
    "auto",
    "none"
  )
  expect_setequal(names(CURSOR_ART), keywords)
  manifest <- jsonlite::fromJSON(
    system.file("cursors/cursors.json", package = "paparazzi"),
    simplifyVector = FALSE
  )
  for (entry in manifest$cursors) {
    if (is.null(entry$cursor)) {
      next
    }
    art <- CURSOR_ART[[entry$cursor]]
    expect_equal(c(art$x, art$y) + unlist(entry$hotspot) * 20 / 32, c(4, 2))
    expect_match(art$svg, 'viewBox="0 0 32 32"', fixed = TRUE)
  }
  for (keyword in keywords) {
    page |> pz_cursor_move("#plain", icon = keyword)
    expect_identical(attr(cursor_overlay_state(page), "icon"), keyword)
    expect_identical(page_cursor(page)$icon, keyword)
    expect_equal(
      pz_js(
        page,
        paste0(
          "document.getElementById('paparazzi-overlay-root').shadowRoot.querySelector('.pz-icon-",
          keyword,
          "').children.length"
        )
      ) >
        0,
      keyword != "none"
    )
    expect_equal(
      pz_js(
        page,
        "[...document.getElementById('paparazzi-overlay-root').shadowRoot.querySelectorAll('.pz-icon')].filter(e => getComputedStyle(e).visibility === 'visible').length"
      ),
      1
    )
  }
  for (fn in list(
    function(icon) pz_cursor_show(page, "#btn", icon = icon),
    function(icon) pz_cursor_move(page, "#btn", icon = icon),
    function(icon) pz_cursor_leave(page, icon = icon)
  )) {
    expect_error(fn("hand"), class = "rlang_error")
    expect_error(fn("mac-poof"), class = "rlang_error")
    expect_error(fn(1), class = "rlang_error")
    expect_no_error(fn(NULL))
  }
  expect_error(pz_cursor_hide(page, icon = "pointer"), class = "rlang_error")
})

test_that("decorative cursor icons are hidden from assistive technology", {
  page <- local_cursor_page()
  page |> pz_cursor_move("#plain")
  expect_identical(
    pz_js(
      page,
      "document.getElementById('paparazzi-overlay-root').shadowRoot.querySelector('.pz-cursor').getAttribute('aria-hidden')"
    ),
    "true"
  )
})

test_that("automatic icons follow computed CSS at the landing point", {
  page <- local_cursor_page()
  for (case in list(
    c("#btn", "pointer"),
    c("#name", "text"),
    c("#waiting", "wait"),
    c("#none", "none"),
    c("#zoom-in", "zoom-in"),
    c("#cell", "cell"),
    c("#url-fallback", "pointer"),
    c("#url-bare", "default"),
    c("#inherit-pointer span", "pointer"),
    c("#shadow-host", "pointer"),
    c("#plain", "default")
  )) {
    page |> pz_cursor_move(case[[1]])
    expect_identical(attr(cursor_overlay_state(page), "icon"), case[[2]])
  }
})

test_that("explicit icons hold for one call; later automatic calls infer again", {
  page <- local_cursor_page()
  page |> pz_cursor_show("#btn", icon = "crosshair")
  expect_identical(attr(cursor_overlay_state(page), "icon"), "crosshair")
  page |> pz_cursor_move("#plain", icon = "grabbing")
  expect_identical(attr(cursor_overlay_state(page), "icon"), "grabbing")
  page |> pz_cursor_move("#btn")
  expect_identical(attr(cursor_overlay_state(page), "icon"), "pointer")
  page |> pz_cursor_leave("left", icon = "not-allowed")
  expect_identical(attr(cursor_overlay_state(page), "icon"), "not-allowed")
  page |> pz_cursor_show("#plain")
  expect_identical(attr(cursor_overlay_state(page), "icon"), "default")
})

test_that("off-frame entries start with default and explicit icons can replace it", {
  skip_if_no_av()
  page <- local_cursor_page()
  page |> pz_stage(enter = "left")
  out <- withr::local_tempfile(fileext = ".mp4")
  page |> pz_record_start(out, fps = 10, hold = c(0, 0))
  # At the beginning of the glide the default icon remains visible;
  # after the landing the inferred pointer is the visible icon.
  page |> pz_cursor_move("#btn")
  expect_match(
    pz_js(
      page,
      "document.getElementById('paparazzi-overlay-root').shadowRoot.querySelector('.pz-icon-default').style.animation"
    ),
    "pz-icon-out"
  )
  expect_identical(page_cursor(page)$icon, "pointer")
  # The entrance flip applies at 100% of the entrance animation, which
  # can land a frame after the glide pump's grace on a loaded runner;
  # wait for the flip instead of sampling computed style once.
  expect_retry(
    function() {
      list(
        pass = identical(attr(cursor_overlay_state(page), "icon"), "pointer")
      )
    },
    timeout = 2,
    loop = page$child_loop
  )
  expect_identical(attr(cursor_overlay_state(page), "icon"), "pointer")
  page |> pz_cursor_move("#none", duration = 0.5)
  expect_identical(page_cursor(page)$icon, "none")
  expect_match(
    pz_js(
      page,
      "document.getElementById('paparazzi-overlay-root').shadowRoot.querySelector('.pz-icon-none').style.animation"
    ),
    "pz-icon-in"
  )
  page |> pz_cursor_move("#zoom-in", duration = 0.5)
  expect_identical(page_cursor(page)$icon, "zoom-in")
  page |> pz_cursor_leave("left", icon = "grab")
  expect_identical(page_cursor(page)$icon, "grab")
  page |> pz_cursor_move("#plain", duration = 0.5)
  # The landing icon flip applies at 100% of the glide animation, which
  # can land a frame after the pump's grace on a loaded runner; wait
  # for the flip instead of sampling computed style once.
  expect_retry(
    function() {
      list(
        pass = identical(attr(cursor_overlay_state(page), "icon"), "default")
      )
    },
    timeout = 2,
    loop = page$child_loop
  )
  expect_identical(attr(cursor_overlay_state(page), "icon"), "default")
  page |> pz_cursor_move("#btn", icon = "text", duration = 0.5)
  expect_identical(attr(cursor_overlay_state(page), "icon"), "text")
  page |> pz_record_stop()
  expect_true(file.exists(out))
})

test_that("a static still uses its inferred landing icon without a fade", {
  page <- local_cursor_page()
  shot <- withr::local_tempfile(fileext = ".png")
  page |> pz_cursor_move("#name") |> pz_screenshot(shot)
  expect_identical(attr(cursor_overlay_state(page), "icon"), "text")
  expect_equal(cursor_overlay_state(page)[[1]], 1)
  ink <- cursor_png_ink(page, shot, band = c(50, 100), x_range = c(100, 310))
  expect_gt(ink$count, 10)
})

test_that("CSS none has no ink and auto still infers through descendants", {
  page <- local_cursor_page()
  page |> pz_cursor_move("#none")
  expect_identical(attr(cursor_overlay_state(page), "icon"), "none")
  drawn <- pz_js(
    page,
    "(() => { const root = document.getElementById('paparazzi-overlay-root').shadowRoot; return root.querySelector('.pz-icon-none').children.length; })()"
  )
  expect_equal(drawn, 0)
  shot <- withr::local_tempfile(fileext = ".png")
  page |> pz_screenshot(shot)
  expect_equal(
    cursor_png_ink(page, shot, band = c(230, 260), x_range = c(580, 640))$count,
    0
  )
  page |> pz_cursor_move("#plain", icon = "auto")
  expect_identical(attr(cursor_overlay_state(page), "icon"), "auto")
  page |> pz_cursor_move("#inherit-pointer span")
  expect_identical(attr(cursor_overlay_state(page), "icon"), "pointer")
})

test_that("cursor state tracks presses, carries, and resets", {
  page <- local_cursor_page()
  expect_false(page_cursor(page)$pressed)
  page |> pz_cursor_move("#btn")
  cursor_press(page, TRUE)
  expect_true(page_cursor(page)$pressed)
  cursor_press(page, FALSE)
  expect_false(page_cursor(page)$pressed)

  cursor_apply(page, c(x = 200, y = 200), pressed = TRUE, pump = FALSE)
  expect_true(page_cursor(page)$pressed)
  expect_equal(cursor_overlay_scale(page), 1.4)
  page |> pz_cursor_hide()
  expect_false(page_cursor(page)$pressed)

  page |> pz_cursor_show()
  cursor_press(page, TRUE)
  page |> pz_cursor_leave()
  expect_false(page_cursor(page)$pressed)

  page |> pz_cursor_move("#btn")
  cursor_press(page, TRUE)
  page |> pz_stage(cursor = FALSE)
  expect_false(page_cursor(page)$pressed)
})

test_that("navigation redraws a pressed cursor unpressed", {
  page <- local_cursor_page()
  page |> pz_cursor_move("#btn")
  cursor_press(page, TRUE)
  pz_chromote(page)$Page$reload()
  pz_wait(page, 1)
  expect_equal(cursor_overlay_scale(page), 1.75)
})

test_that("explicit icon survives navigation and recorded press", {
  skip_if_no_av()
  page <- local_cursor_page()
  page |> pz_cursor_move("#btn", icon = "crosshair")
  pz_chromote(page)$Page$reload()
  pz_wait(page, 1)
  expect_identical(attr(cursor_overlay_state(page), "icon"), "crosshair")
  out <- withr::local_tempfile(fileext = ".mp4")
  page |> pz_record_start(out, fps = 10, hold = c(0, 0))
  page |> pz_cursor_move("#plain", icon = "not-allowed", duration = 0.5)
  expect_identical(attr(cursor_overlay_state(page), "icon"), "not-allowed")
  cursor_press(page, TRUE)
  expect_equal(cursor_overlay_scale(page), 1.4)
  expect_identical(attr(cursor_overlay_state(page), "icon"), "not-allowed")
  cursor_press(page, FALSE)
  expect_false(page_cursor(page)$pressed)
  cursor_apply(
    page,
    c(x = 200, y = 200),
    duration = 0.5,
    pressed = TRUE,
    pump = FALSE
  )
  expect_true(page_cursor(page)$pressed)
  cursor_press(page, FALSE)
  expect_false(page_cursor(page)$pressed)
  page |> pz_record_stop()
})

test_that("non-default artwork stays aligned under CSS zoom and DPR", {
  page <- local_page(cursor_fixture_file(), scale = 2)
  pz_js(page, "document.documentElement.style.zoom = '1.5'")
  page |> pz_cursor_move("#btn", icon = "crosshair")
  center <- unlist(pz_js(
    page,
    "(() => { const r = document.querySelector('#btn').getBoundingClientRect(); return [r.x + r.width/2, r.y + r.height/2] })()"
  ))
  expect_equal(cursor_overlay_state(page)[2:3], center)
  expect_identical(attr(cursor_overlay_state(page), "icon"), "crosshair")
  shot <- withr::local_tempfile(fileext = ".png")
  page |> pz_screenshot(shot)
  ink <- cursor_png_ink(
    page,
    shot,
    band = center[[2]] + c(-18, 20),
    x_range = center[[1]] + c(-18, 20)
  )
  expect_gt(ink$count, 10)
  expect_lt(abs(ink$x - center[[1]]), 12)
})


test_that("representative icon families put ink near their hotspots", {
  page <- local_cursor_page()
  shot <- withr::local_tempfile(fileext = ".png")
  for (icon in c(
    "text",
    "not-allowed",
    "crosshair",
    "grab",
    "grabbing",
    "ew-resize",
    "ns-resize",
    "nesw-resize"
  )) {
    page |> pz_cursor_move("#plain", icon = icon) |> pz_screenshot(shot)
    ink <- cursor_png_ink(page, shot, band = c(305, 348), x_range = c(145, 185))
    expect_gt(ink$count, 10)
    expect_lt(abs(ink$x - 160), 12)
    expect_lt(abs(ink$y - 322), 12)
  }
})

test_that("automatic glide switches icon on destination entry, not landing", {
  skip_if_no_av()
  page <- local_cursor_page()
  page |> pz_cursor_move("#plain")
  out <- withr::local_tempfile(fileext = ".mp4")
  page |> pz_record_start(out, fps = 10, hold = c(0, 0))
  cursor_command(
    page,
    list(
      x = 660,
      y = 322,
      visible = TRUE,
      icon = NULL,
      previous = "default",
      pressed = FALSE,
      duration = 2,
      switch = list(
        at = cursor_entry_time(
          c(x = 160, y = 322),
          c(x = 660, y = 322),
          c(x = 600, y = 300, width = 120, height = 44)
        ),
        from = "default",
        to = "pointer"
      ),
      anim = TRUE
    )
  )
  visible <- function() {
    unlist(pz_js(
      page,
      "[...document.getElementById('paparazzi-overlay-root').shadowRoot.querySelectorAll('.pz-icon')].filter(e => getComputedStyle(e).visibility === 'visible').map(e => e.classList[1])"
    ))
  }
  # Sample well short of the switch boundary (the entry fraction of the
  # glide, ~1.15s here): wall time overshoots the pump and the animation
  # clock jitters, so a sample stacked up to the boundary flakes.
  pump_loop(page$child_loop, 0.7)
  expect_identical(visible(), "pz-icon-default")
  # The flip applies at the entry boundary; the animation clock can lag the
  # pump past it, so poll for the applied state instead of sampling once.
  expect_retry(
    function() list(pass = identical(visible(), "pz-icon-pointer")),
    timeout = 2,
    loop = page$child_loop
  )
  expect_identical(visible(), "pz-icon-pointer")
  pump_loop(page$child_loop, 0.35)
  cursor_command(
    page,
    list(
      x = 160,
      y = 322,
      visible = TRUE,
      icon = NULL,
      previous = "pointer",
      pressed = FALSE,
      duration = 2,
      switch = list(
        at = cursor_entry_time(
          c(x = 660, y = 322),
          c(x = 160, y = 322),
          c(x = 100, y = 300, width = 120, height = 44)
        ),
        from = "pointer",
        to = "default"
      ),
      anim = TRUE
    )
  )
  # The return glide enters its rect at ~0.31 of the ease (~0.62s); pump
  # well short of that boundary for the pre-entry sample.
  pump_loop(page$child_loop, 0.3)
  expect_identical(visible(), "pz-icon-pointer")
  expect_retry(
    function() list(pass = identical(visible(), "pz-icon-default")),
    timeout = 2,
    loop = page$child_loop
  )
  expect_identical(visible(), "pz-icon-default")
  page |> pz_record_stop()
})

test_that("the glide ease inverts in both directions", {
  # x is the time fraction, y the eased progress; each bisects back to
  # the other's value at the same curve parameter.
  for (v in seq(0.02, 0.98, by = 0.04)) {
    expect_equal(
      glide_ease_invert(glide_ease_x(v), glide_ease_x, glide_ease_y),
      glide_ease_y(v),
      tolerance = 1e-9
    )
    expect_equal(
      glide_ease_invert(glide_ease_y(v), glide_ease_y, glide_ease_x),
      glide_ease_x(v),
      tolerance = 1e-9
    )
  }
  # The midpoint of the glide's ease is the half-time, half-progress
  # point of its symmetric control points.
  expect_equal(glide_ease_invert(0.5, glide_ease_x, glide_ease_y), 0.5)
})

test_that("entry inversion follows the CSS easing and clips to the rect", {
  rect <- c(x = 60, y = 10, width = 20, height = 20)
  start <- c(x = 0, y = 20)
  end <- c(x = 100, y = 20)
  expect_equal(cursor_entry_time(start, end, rect), 0.5585, tolerance = 0.0002)
  expect_equal(cursor_entry_time(end, start, rect), 0.31, tolerance = 0.002)
  expect_equal(
    cursor_entry_time(c(x = 65, y = 20), end, rect),
    0,
    tolerance = 1e-12
  )
  expect_null(cursor_entry_time(c(x = 0, y = 40), c(x = 100, y = 40), rect))
  expect_null(cursor_entry_time(c(x = 0, y = 20), c(x = 30, y = 20), rect))
  expect_equal(
    cursor_entry_time(c(x = 0, y = 20), c(x = 60, y = 20), rect),
    1,
    tolerance = 1e-12
  )
  times <- vapply(
    c(20, 40, 60, 80),
    function(x) {
      cursor_entry_time(start, end, c(x = x, y = 10, width = 5, height = 20))
    },
    numeric(1)
  )
  expect_true(all(diff(times) > 0))
})

test_that("recorded moves schedule one entry flip for the intended target", {
  skip_if_no_av()
  page <- local_cursor_page()
  page |> pz_cursor_move("#plain")
  out <- withr::local_tempfile(fileext = ".mp4")
  page |> pz_record_start(out, fps = 10, hold = c(0, 0))
  keyframes <- function() {
    pz_js(
      page,
      "document.getElementById('paparazzi-overlay-root').shadowRoot.querySelector('.pz-icon-keyframes').textContent"
    )
  }
  animations <- function() {
    unlist(pz_js(
      page,
      "[...document.getElementById('paparazzi-overlay-root').shadowRoot.querySelectorAll('.pz-icon')].filter(e => e.style.animation.includes('pz-icon-')).map(e => e.classList[1])"
    ))
  }
  page |> pz_cursor_move("#btn", duration = 0.5)
  expect_setequal(animations(), c("pz-icon-default", "pz-icon-pointer"))
  expect_match(keyframes(), "pz-icon-in")
  expect_match(keyframes(), "7[0-9]\\.")
  expect_identical(page_cursor(page)$icon, "pointer")
  page |> pz_cursor_move("#plain", duration = 0.5)
  expect_setequal(animations(), c("pz-icon-default", "pz-icon-pointer"))
  expect_match(keyframes(), "pz-icon-out")
  expect_identical(page_cursor(page)$icon, "default")
  # #crossed is cursor:pointer but lies between the two destinations.
  page |> pz_cursor_move("#btn", duration = 0.5)
  expect_length(animations(), 2)
  expect_identical(page_cursor(page)$icon, "pointer")
  page |> pz_cursor_move("#plain", icon = "crosshair", duration = 0.5)
  expect_identical(keyframes(), "")
  expect_identical(page_cursor(page)$icon, "crosshair")
  page |> pz_cursor_move("#btn", icon = "text", duration = 0.5)
  expect_identical(keyframes(), "")
  expect_identical(page_cursor(page)$icon, "text")
  page |> pz_record_stop()
})

test_that("off-frame entrances and staged actions use destination entry", {
  skip_if_no_av()
  page <- local_cursor_page()
  page |> pz_stage(enter = "left")
  out <- withr::local_tempfile(fileext = ".mp4")
  page |> pz_record_start(out, fps = 10, hold = c(0, 0))
  page |> pz_cursor_show("#btn", from = "left")
  animations <- unlist(pz_js(
    page,
    "[...document.getElementById('paparazzi-overlay-root').shadowRoot.querySelectorAll('.pz-icon')].filter(e => e.style.animation.includes('pz-icon-')).map(e => e.classList[1])"
  ))
  expect_setequal(animations, c("pz-icon-default", "pz-icon-pointer"))
  page |> pz_act_hover("#plain")
  expect_identical(page_cursor(page)$icon, "default")
  expect_match(
    pz_js(
      page,
      "document.getElementById('paparazzi-overlay-root').shadowRoot.querySelector('.pz-icon-keyframes').textContent"
    ),
    "pz-icon-in"
  )
  page |> pz_record_stop()
})

test_that("untargeted entrances keep the start icon until landing", {
  skip_if_no_av()
  page <- local_cursor_page()
  out <- withr::local_tempfile(fileext = ".mp4")
  page |> pz_record_start(out, fps = 10, hold = c(0, 0))
  page |> pz_cursor_show("#btn", icon = "crosshair")
  visible <- function() {
    unlist(pz_js(
      page,
      "[...document.getElementById('paparazzi-overlay-root').shadowRoot.querySelectorAll('.pz-icon')].filter(e => getComputedStyle(e).visibility === 'visible').map(e => e.classList[1])"
    ))
  }
  # No target means no destination rect: the flip must wait for the
  # landing instead of applying at the glide's dispatch. The glide
  # pumps inside the call, so the schedule itself is the assertion:
  # its boundary sits at 100% of the glide, not at the dispatch.
  page |> pz_cursor_show(from = "left")
  keyframes <- pz_js(
    page,
    "document.getElementById('paparazzi-overlay-root').shadowRoot.querySelector('.pz-icon-keyframes').textContent"
  )
  boundary <- as.numeric(
    regmatches(keyframes, regexec("pz-icon-in \\{ 0%, ([0-9.]+)%", keyframes))[[
      1
    ]][2]
  ) +
    0.1
  expect_lt(abs(boundary - 100), 0.2)
  # The flip applies at 100% of the entrance animation, which can land a
  # frame after the glide pump's 50ms grace on a slow runner; wait for the
  # flip instead of sampling computed style once.
  expect_retry(
    function() list(pass = setequal(visible(), 'pz-icon-pointer')),
    timeout = 2,
    loop = page$child_loop
  )
  expect_setequal(visible(), 'pz-icon-pointer')
  expect_identical(page_cursor(page)$icon, 'pointer')
  page |> pz_record_stop()
})

test_that("pointer actions switch at the resolved target's edge", {
  # The actionable point sits on #nested-core, a small descendant
  # covering the button's center; entry timing must use the button's
  # rect, not the span's.
  page <- local_cursor_page()
  els <- loc_resolve(page, "#nested")
  withr::defer(release_elements(els))
  point <- el_pointer_point(page, els)
  expect_identical(
    attr(point, "rect"),
    c(x = 440, y = 300, width = 120, height = 44)
  )

  skip_if_no_av()
  rec <- local_cursor_page()
  out <- withr::local_tempfile(fileext = ".mp4")
  rec |> pz_record_start(out, fps = 10, hold = c(0, 0))
  rec |> pz_cursor_move("#plain")
  rec |> pz_act_hover("#nested")
  keyframes <- pz_js(
    rec,
    "document.getElementById('paparazzi-overlay-root').shadowRoot.querySelector('.pz-icon-keyframes').textContent"
  )
  boundary <- as.numeric(
    regmatches(keyframes, regexec("pz-icon-in \\{ 0%, ([0-9.]+)%", keyframes))[[
      1
    ]][2]
  ) +
    0.1
  at_button <- cursor_entry_time(
    c(x = 160, y = 322),
    c(x = 500, y = 322),
    c(x = 440, y = 300, width = 120, height = 44)
  ) *
    100
  at_core <- cursor_entry_time(
    c(x = 160, y = 322),
    c(x = 500, y = 322),
    c(x = 480, y = 310, width = 40, height = 24)
  ) *
    100
  expect_lt(abs(boundary - at_button), 0.5)
  expect_gt(abs(boundary - at_core), 0.5)
  rec |> pz_record_stop()
})

test_that("cursor move offsets validate and land in viewport coordinates", {
  page <- local_cursor_page()
  for (bad in list(NA_real_, Inf, "10", numeric(), c(1, 2, 3))) {
    expect_error(
      pz_cursor_move(page, "#btn", offset = bad),
      class = "paparazzi_error_input"
    )
  }
  page |> pz_cursor_move("#btn", offset = -40)
  expect_equal(cursor_overlay_state(page)[2:3], c(620, 282))
  page |> pz_cursor_move("#btn", offset = c(-40, 15))
  expect_equal(cursor_overlay_state(page)[2:3], c(620, 337))
  expect_equal(c(page_cursor(page)$x, page_cursor(page)$y), c(620, 337))
  page |> pz_cursor_move("#btn", offset = c(0, 0))
  expect_equal(cursor_overlay_state(page)[2:3], c(660, 322))
  page |> pz_cursor_move("#btn")
  expect_equal(cursor_overlay_state(page)[2:3], c(660, 322))
})

test_that("offset still puts pointer ink beside the button label", {
  page <- local_cursor_page()
  shot <- withr::local_tempfile(fileext = ".png")
  page |> pz_cursor_move("#btn", offset = c(-40, 15)) |> pz_screenshot(shot)
  ink <- cursor_png_ink(page, shot, band = c(325, 344), x_range = c(605, 645))
  label <- cursor_png_ink(page, shot, band = c(325, 344), x_range = c(650, 685))
  expect_gt(ink$count, 5)
  expect_lt(abs(ink$x - 620), 22)
  expect_equal(label$count, 0)
  expect_identical(attr(cursor_overlay_state(page), "icon"), "pointer")
})

test_that("offset does not dispatch real pointer events", {
  page <- local_cursor_page()
  page |> pz_cursor_move("#plain", offset = c(500, 0))
  expect_equal(
    unlist(pz_js(
      page,
      "[window.__log.enters, window.__log.moves, window.__log.clicks]"
    )),
    c(0, 0, 0)
  )
  page |> pz_act_hover("#btn")
  events <- unlist(pz_js(
    page,
    "[window.__log.enters, window.__log.moves, window.__log.clicks]"
  ))
  expect_gt(events[[1]], 0)
  expect_gt(events[[2]], 0)
  expect_equal(events[[3]], 0)
})

test_that("off-frame offset stays shown and becomes the next glide start", {
  skip_if_no_av()
  page <- local_cursor_page()
  page |> pz_cursor_move("#btn", offset = c(-900, 15))
  expect_equal(cursor_overlay_state(page)[2:3], c(-240, 337))
  expect_equal(cursor_overlay_state(page)[[1]], 1)
  expect_identical(page_cursor(page)$visibility, "shown")
  out <- withr::local_tempfile(fileext = ".mp4")
  page |> pz_record_start(out, fps = 10, hold = c(0, 0))
  page |> pz_cursor_move("#btn", duration = 1)
  rules <- pz_js(
    page,
    "document.getElementById('paparazzi-overlay-root').shadowRoot.querySelector('.pz-icon-keyframes').textContent"
  )
  boundary <- as.numeric(regmatches(
    rules,
    regexec("pz-icon-in \\{ 0%, ([0-9.]+)%", rules)
  )[[1]][[2]]) +
    0.1
  # Crossing x = 600 from -240 to 660 is 93.33% of the segment,
  # reached at 81.88% of the CSS ease-in-out glide.
  expect_equal(boundary, 81.88, tolerance = 0.5)
  expect_equal(cursor_overlay_state(page)[2:3], c(660, 322))
  expect_equal(c(page_cursor(page)$x, page_cursor(page)$y), c(660, 322))
  page |> pz_record_stop()
})

test_that("offset records landing ink and two icon boundaries outside target", {
  skip_if_no_av()
  page <- local_cursor_page()
  page |> pz_cursor_show("#btn") |> pz_cursor_leave("left")
  out <- withr::local_tempfile(fileext = ".mp4")
  page |> pz_record_start(out, fps = 15, hold = c(0, 0), keep_frames = TRUE)
  page |> pz_cursor_move("#plain", offset = c(500, 0), duration = 0.8)
  rules <- pz_js(
    page,
    "document.getElementById('paparazzi-overlay-root').shadowRoot.querySelector('.pz-icon-keyframes').textContent"
  )
  expect_match(rules, "pz-icon-in")
  expect_match(rules, "pz-icon-out")
  expect_match(rules, "pz-icon-in.*100% \\{ visibility:hidden;")
  expect_match(rules, "pz-icon-out.*100% \\{ visibility:visible;")
  expect_identical(page_cursor(page)$icon, "pointer")
  # The cross-fade at the entry boundary can settle a frame after the
  # glide pump's grace on a loaded runner; wait for the flip instead of
  # sampling computed style once.
  expect_retry(
    function() {
      list(
        pass = identical(attr(cursor_overlay_state(page), "icon"), "pointer")
      )
    },
    timeout = 2,
    loop = page$child_loop
  )
  expect_identical(attr(cursor_overlay_state(page), "icon"), "pointer")
  page |> pz_record_stop()
  frames_dir <- paste0(tools::file_path_sans_ext(out), "_frames")
  on.exit(unlink(frames_dir, recursive = TRUE), add = TRUE)
  frames <- list.files(frames_dir, pattern = "[.]png$", full.names = TRUE)
  inks <- lapply(frames, function(frame) {
    cursor_png_ink(page, frame, band = c(300, 344), x_range = c(640, 710))
  })
  # At this speed (625px/s at 15fps) the glide crosses the 70px scan band
  # in only a couple of frames, so no frame count distinguishes a landing
  # from a transit. Stopping always captures one final frame with the
  # cursor at rest: require the landing in that terminal frame.
  ok <- vapply(
    inks,
    function(ink) {
      ink$count > 20 && abs(ink$x - 660) < 25 && abs(ink$y - 322) < 20
    },
    logical(1)
  )
  expect_true(ok[[length(ok)]])
})

test_that("inside-target offset has one entry flip and explicit icon has none", {
  skip_if_no_av()
  page <- local_cursor_page()
  page |> pz_cursor_move("#plain")
  out <- withr::local_tempfile(fileext = ".mp4")
  page |> pz_record_start(out, fps = 10, hold = c(0, 0))
  page |> pz_cursor_move("#btn", offset = c(-40, 15), duration = 0.5)
  rules <- function() {
    pz_js(
      page,
      "document.getElementById('paparazzi-overlay-root').shadowRoot.querySelector('.pz-icon-keyframes').textContent"
    )
  }
  expect_match(rules(), "pz-icon-in")
  expect_false(grepl("pz-icon-land", rules()))
  expect_identical(page_cursor(page)$icon, "pointer")
  page |>
    pz_cursor_move(
      "#plain",
      offset = c(500, 0),
      icon = "crosshair",
      duration = 0.5
    )
  expect_identical(rules(), "")
  expect_identical(page_cursor(page)$icon, "crosshair")
  page |> pz_record_stop()
})

test_that("entry and landing can schedule three distinct icon layers", {
  skip_if_no_av()
  page <- local_cursor_page()
  page |>
    pz_cursor_show("#plain", icon = "crosshair") |>
    pz_cursor_leave("left")
  out <- withr::local_tempfile(fileext = ".mp4")
  page |> pz_record_start(out, fps = 10, hold = c(0, 0))
  page |> pz_cursor_move("#plain", offset = c(500, 0), duration = 0.5)
  animations <- unlist(pz_js(
    page,
    "[...document.getElementById('paparazzi-overlay-root').shadowRoot.querySelectorAll('.pz-icon')].filter(e => e.style.animation.includes('pz-icon-')).map(e => e.style.animation.match(/pz-icon-(out|in|land)/)[0])"
  ))
  expect_setequal(animations, c("pz-icon-out", "pz-icon-in", "pz-icon-land"))
  expect_identical(page_cursor(page)$icon, "pointer")
  page |> pz_record_stop()
})

test_that("an explicitly hidden cursor stays hidden during recorded typing", {
  skip_if_no_av()
  page <- local_page(pz_example("tasks"))
  page |> pz_stage(pause = 0)
  page |>
    pz_record_start(
      withr::local_tempfile(fileext = ".mp4"),
      fps = 8,
      hold = c(0, 0)
    )
  defer_record_stop(page)

  page |> pz_act_click("#task-title")
  pz_js(
    page,
    paste0(
      "window.__cursorInputOpacity = [];",
      "document.querySelector('#task-title').addEventListener('input', () => {",
      "const inner = document.querySelector('#paparazzi-overlay-root')",
      ".shadowRoot.querySelector('.pz-inner');",
      "window.__cursorInputOpacity.push(getComputedStyle(inner).opacity);",
      "});"
    )
  )
  page |> pz_cursor_hide()
  # The hide fades the overlay over CURSOR_FADE seconds and the hide pump
  # leaves no margin, so the first keystroke can race the fade on a loaded
  # runner; poll for the settled opacity before typing.
  expect_retry(
    function() {
      list(
        pass = identical(
          pz_js(
            page,
            paste0(
              "getComputedStyle(document.getElementById('paparazzi-overlay-root')",
              ".shadowRoot.querySelector('.pz-inner')).opacity"
            )
          ),
          "0"
        )
      )
    },
    timeout = 2,
    loop = page$child_loop
  )
  page |> pz_act_type("abc", target = "#task-title")

  opacities <- unlist(pz_js(page, "window.__cursorInputOpacity"))
  expect_length(opacities, 3)
  expect_true(all(opacities == "0"))
  expect_identical(page_cursor(page)$visibility, "hidden")

  page |> pz_cursor_show()
  expect_identical(page_cursor(page)$visibility, "shown")
  expect_equal(cursor_overlay_state(page)[[1]], 1)
  page |> pz_record_stop()
})

test_that("recorded typing rests the cursor until the next move", {
  skip_if_no_av()
  page <- local_cursor_page()
  pz_stage(page, typing = "instant", pause = 0)
  line <- function(page) {
    out <- capture.output(print(page))
    grep("Recording", out, value = TRUE)
  }

  # Not recording: typing leaves a shown cursor alone.
  page |> pz_cursor_show() |> pz_act_type("a", target = "#name")
  expect_equal(cursor_overlay_state(page)[[1]], 1)
  expect_false(page_cursor(page)$resting)

  pz_record_start(page, withr::local_tempfile(fileext = ".mp4"), hold = c(0, 0))
  defer_record_stop(page)
  page |> pz_act_type("b", target = "#name")
  st <- cursor_overlay_state(page)
  expect_equal(st[[1]], 0)
  expect_true(page_cursor(page)$resting)
  expect_match(line(page), "on · cursor resting")

  # The next pointer action glides from where it rested, fading in.
  commands <- list()
  testthat::with_mocked_bindings(
    page |> pz_act_click("#btn"),
    cursor_command = function(ctx, state) {
      if (!isTRUE(state$resolveOnly)) {
        commands[[length(commands) + 1L]] <<- state
      }
      "pointer"
    }
  )
  glide <- commands[[1]]
  expect_true(glide$visible)
  expect_null(glide$from)
  expect_false(glide$fade)
  expect_gt(glide$duration, 0)
  expect_false(page_cursor(page)$resting)

  # A shown cursor resting at stop is drawn again for stills.
  page |> pz_cursor_show() |> pz_act_type("d", target = "#name")
  expect_true(page_cursor(page)$resting)
  pz_record_stop(page)
  expect_false(page_cursor(page)$resting)
  expect_equal(cursor_overlay_state(page)[[1]], 1)
  page |> pz_nav_reload()
  expect_equal(cursor_overlay_state(page)[[1]], 1)
  pz_record_start(page, withr::local_tempfile(fileext = ".mp4"), hold = c(0, 0))

  # An explicit hide is not a rest, and typing doesn't bring it back.
  page |> pz_cursor_hide() |> pz_act_type("c", target = "#name")
  expect_false(page_cursor(page)$resting)
  expect_match(line(page), "on · cursor hidden")
  pz_record_stop(page)
})

test_that("cursor move offset defaults to zero and rejects NULL", {
  page <- local_cursor_page()
  expect_error(pz_cursor_move(page, "#btn", offset = NULL), "offset.*NULL")
  pz_cursor_move(page, "#btn")
  omitted <- cursor_overlay_state(page)
  pz_cursor_move(page, "#btn", offset = c(0, 0))
  expect_equal(cursor_overlay_state(page), omitted)
  expect_equal(omitted[2:3], c(660, 322))
})

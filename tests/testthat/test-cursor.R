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
  page |> pz_click("#btn")
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
  # The pointing fingertip is the only ink in the window at the landing
  # point: at the 1.75x scale (transform-origin 4px 2px) the tip renders
  # just left of the hotspot, while the old four-finger hand's nearest
  # ink sat ~9px right of it, beyond the window's edge.
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
  page |> pz_click("#btn")
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
  page |> pz_click("#btn")
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
  pump_loop(page$child_loop, 0.2)
  shot2 <- withr::local_tempfile(fileext = ".png")
  page |> pz_screenshot(shot2)
  pressed <- cursor_png_ink(page, shot2, band = c(280, 370))
  expect_equal(cursor_overlay_scale(page), 1.4)

  expect_true(pressed$count > 20)
  expect_true(pressed$height < unpressed$height * 0.9)
  expect_true(pressed$height > unpressed$height * 0.6)
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
    "col-resize"
  )
  expect_setequal(names(CURSOR_ART), keywords)
  for (keyword in keywords) {
    page |> pz_cursor_move("#plain", icon = keyword)
    expect_identical(attr(cursor_overlay_state(page), "icon"), keyword)
    expect_identical(page_cursor(page)$icon, keyword)
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
    expect_error(fn("move"), "default.*pointer", class = "rlang_error")
    expect_error(fn("hand"), class = "rlang_error")
    expect_error(fn(1), class = "rlang_error")
    expect_no_error(fn(NULL))
  }
  expect_error(pz_cursor_hide(page, icon = "pointer"), class = "rlang_error")
})

test_that("automatic icons follow computed CSS at the landing point", {
  page <- local_cursor_page()
  for (case in list(
    c("#btn", "pointer"),
    c("#name", "text"),
    c("#unsupported", "default"),
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
  expect_identical(attr(cursor_overlay_state(page), "icon"), "pointer")
  page |> pz_cursor_leave("left", icon = "grab")
  expect_identical(page_cursor(page)$icon, "grab")
  page |> pz_cursor_move("#plain", duration = 0.5)
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
  pump_loop(page$child_loop, 0.7)
  expect_identical(visible(), "pz-icon-default")
  pump_loop(page$child_loop, 0.45)
  expect_identical(visible(), "pz-icon-default")
  pump_loop(page$child_loop, 0.55)
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
  pump_loop(page$child_loop, 0.7)
  expect_identical(visible(), "pz-icon-pointer")
  pump_loop(page$child_loop, 1)
  expect_identical(visible(), "pz-icon-default")
  page |> pz_record_stop()
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
  page |> pz_hover("#plain")
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
  expect_setequal(visible(), "pz-icon-pointer")
  expect_identical(page_cursor(page)$icon, "pointer")
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
  rec |> pz_hover("#nested")
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

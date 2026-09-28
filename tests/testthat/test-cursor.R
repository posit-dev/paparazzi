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
  expect_equal(cursor_overlay_state(page)[[4]], 1)
  page |> pz_cursor_move("#plain")
  expect_equal(cursor_overlay_state(page)[[4]], 0)
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
  scale <- function(page) {
    pz_js(
      page,
      paste0(
        "parseFloat(document.getElementById('paparazzi-overlay-root')",
        ".shadowRoot.querySelector('.pz-inner').style.transform.slice(6))"
      )
    )
  }
  expect_equal(scale(page), 1.75)

  cursor_press(page, TRUE)
  pump_loop(page$child_loop, 0.2)
  shot2 <- withr::local_tempfile(fileext = ".png")
  page |> pz_screenshot(shot2)
  pressed <- cursor_png_ink(page, shot2, band = c(280, 370))
  expect_equal(scale(page), 1.4)

  expect_true(pressed$count > 20)
  expect_true(pressed$height < unpressed$height * 0.9)
  expect_true(pressed$height > unpressed$height * 0.6)
})

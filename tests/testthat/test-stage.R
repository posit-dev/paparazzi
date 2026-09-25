test_that("pz_stage merges settings onto the defaults and validates", {
  page <- local_cursor_page()

  expect_identical(page_stage(page), STAGE_DEFAULTS)

  page |> pz_stage(cursor_speed = 800, typing_speed = 30, pause = 0.5)
  stage <- page_stage(page)
  expect_equal(stage$cursor_speed, 800)
  expect_equal(stage$typing_speed, 30)
  expect_equal(stage$pause, 0.5)
  # Only supplied arguments change.
  expect_null(stage$cursor)
  expect_null(stage$enter)
  expect_identical(stage$typing, "natural")

  page |> pz_stage(enter = "left", typing = "instant", cursor = TRUE)
  stage <- page_stage(page)
  expect_identical(stage$enter, "left")
  expect_identical(stage$typing, "instant")
  expect_true(stage$cursor)
  expect_equal(stage$cursor_speed, 800)

  # An explicit NULL removes the override (back to the default);
  # only omitted arguments leave a setting alone.
  page |> pz_stage(
    cursor = NULL, cursor_speed = NULL, enter = NULL,
    typing = NULL, typing_speed = NULL, pause = NULL
  )
  expect_identical(page_stage(page), STAGE_DEFAULTS)

  expect_error(pz_stage(page, cursor = "yes"), class = "rlang_error")
  expect_error(pz_stage(page, cursor_speed = 0), class = "rlang_error")
  expect_error(pz_stage(page, enter = "up"), class = "paparazzi_error_input")
  expect_error(pz_stage(page, typing = "slow"), class = "rlang_error")
  expect_error(pz_stage(page, typing_speed = -1), class = "rlang_error")
  expect_error(pz_stage(page, pause = -1), class = "rlang_error")
  expect_error(pz_stage(page, bogus = 1), class = "rlang_error")
})

test_that("natural typing is per-character while recording, instant otherwise", {
  skip_if_no_av()
  out <- withr::local_tempfile(fileext = ".mp4")

  page <- local_cursor_page()
  page |> pz_stage()
  page |> pz_record_start(out, fps = 10, hold = c(0, 0))
  page |>
    pz_type("otters", target = "#name") |>
    pz_type("abc", target = "#bio") |>
    pz_type("xy", target = "#edit")
  page |> pz_record_stop()

  expect_equal(pz_js(page, "document.getElementById('name').value"), "otters")
  expect_equal(pz_js(page, "document.getElementById('bio').value"), "abc")
  expect_equal(pz_js(page, "document.getElementById('edit').textContent"), "xy")
  expect_equal(pz_js(page, "window.__log.inputs.name"), 6)
  expect_equal(pz_js(page, "window.__log.inputs.bio"), 3)
  expect_equal(pz_js(page, "window.__log.inputs.edit"), 2)

  # typing = "instant" is one insertion even while recording.
  page2 <- local_cursor_page()
  page2 |> pz_stage(typing = "instant")
  page2 |> pz_record_start(withr::local_tempfile(fileext = ".mp4"), fps = 10, hold = c(0, 0))
  page2 |> pz_type("otters", target = "#name")
  page2 |> pz_record_stop()
  expect_equal(pz_js(page2, "window.__log.inputs.name"), 1)
  expect_equal(pz_js(page2, "document.getElementById('name').value"), "otters")

  # Not recording: instant whatever the setting.
  page3 <- local_cursor_page()
  page3 |> pz_stage()
  page3 |> pz_type("otters", target = "#name")
  expect_equal(pz_js(page3, "window.__log.inputs.name"), 1)
})

test_that("smooth scrolling uses real wheel events while recording", {
  skip_if_no_av()
  page <- local_cursor_page()
  page |> pz_stage()
  page |> pz_record_start(withr::local_tempfile(fileext = ".mp4"), fps = 10, hold = c(0, 0))

  page |> pz_scroll(by = c(0, 600))
  expect_equal(pz_js(page, "window.scrollY"), 600)
  expect_true(pz_js(page, "window.__log.wheels") > 0)
  expect_true(pz_js(page, "window.__log.wheelsTrusted"))

  page |> pz_scroll(to = "bottom")
  expect_equal(
    pz_js(page, "window.scrollY"),
    pz_js(page, "document.scrollingElement.scrollHeight - window.innerHeight")
  )

  # A scoped scroll wheels the scope's container, not the page.
  wheels <- pz_js(page, "window.__log.wheels")
  page |> pz_find("#scroller") |> pz_scroll(to = "bottom")
  expect_equal(pz_js(page, "document.getElementById('scroller').scrollTop"), 650)
  expect_true(pz_js(page, "window.__log.wheels") > wheels)

  page |> pz_record_stop()
})

test_that("the auto-scroll before actions is the same staged wheel scroll", {
  skip_if_no_av()
  page <- local_cursor_page()
  page |> pz_stage()
  page |> pz_record_start(withr::local_tempfile(fileext = ".mp4"), fps = 10, hold = c(0, 0))
  page |> pz_click("#below")
  page |> pz_record_stop()

  expect_equal(pz_js(page, "window.__log.belowClicks"), 1)
  expect_true(pz_js(page, "window.__log.wheels") > 0)
  expect_true(pz_js(page, "window.scrollY") > 500)
})

test_that("a target visible in a below-the-fold container is wheeled into view", {
  skip_if_no_av()
  page <- local_cursor_page()
  # A scrollable container beyond the fold whose target sits inside its
  # clip: the target is visible to the container yet off-screen, so the
  # auto-scroll must reach past the nearest scrollable ancestor to the
  # document.
  pz_js(page, paste0(
    "(() => {",
    "const d = document.createElement('div');",
    "d.id = 'deep';",
    "d.style.cssText = 'position:absolute;left:100px;",
    "top:calc(100vh + 300px);width:300px;height:250px;",
    "overflow:auto;border:1px solid #ccc;';",
    "const b = document.createElement('button');",
    "b.id = 'deep-btn';",
    "b.textContent = 'deep';",
    "b.style.cssText = 'margin-top:20px;width:120px;height:40px;';",
    "const tall = document.createElement('div');",
    "tall.style.cssText = 'height:900px;background:#f8f8f8;';",
    "d.appendChild(b); d.appendChild(tall);",
    "document.body.appendChild(d);",
    "b.addEventListener('click',", 
    "  () => window.__log.deepClicks = (window.__log.deepClicks || 0) + 1);",
    "})()"
  ))
  page |> pz_stage()
  page |> pz_record_start(withr::local_tempfile(fileext = ".mp4"), fps = 10, hold = c(0, 0))
  page |> pz_click("#deep-btn")
  page |> pz_record_stop()

  expect_equal(pz_js(page, "window.__log.deepClicks"), 1)
  # Only the document needed scrolling: the container was already
  # showing the target.
  expect_equal(pz_js(page, "document.getElementById('deep').scrollTop"), 0)
  expect_true(pz_js(page, "window.scrollY") > 0)
  expect_true(pz_js(page, "window.__log.wheels") > 0)
})

test_that("cursor = FALSE then cursor = NULL restores the auto behavior", {
  skip_if_no_av()
  page <- local_cursor_page()
  page |> pz_stage(cursor = FALSE)
  page |> pz_record_start(withr::local_tempfile(fileext = ".mp4"), fps = 10, hold = c(0, 0))
  page |> pz_click("#btn")
  # cursor = FALSE never draws, even while recording.
  expect_null(cursor_overlay_state(page))

  page |> pz_stage(cursor = NULL)
  page |> pz_click("#btn")
  # The NULL restored the default: auto draws while recording.
  st <- cursor_overlay_state(page)
  expect_equal(st[[1]], 1)
  expect_equal(st[2:3], c(660, 322))
  page |> pz_record_stop()
  expect_equal(pz_js(page, "window.__log.clicks"), 2)
})

test_that("a nested scroller over the viewport center never eats root wheels", {
  skip_if_no_av()
  # A FIXED scroller over the viewport center stays over it at every
  # scroll position and would consume every wheel aimed at the
  # document; with no point that reaches the container, the instant
  # application must run before any wheel fires, so recorded and
  # unrecorded chains end in the identical state.
  cover_center <- function(page) {
    pz_js(page, paste0(
      "(() => {",
      "const d = document.createElement('div');",
      "d.id = 'center-scroller';",
      "d.style.cssText = 'position:fixed;",
      "left:calc(50% - 150px);top:calc(50% - 100px);",
      "width:300px;height:200px;overflow:auto;';",
      "const tall = document.createElement('div');",
      "tall.style.cssText = 'height:2000px;background:#f8f8f8;';",
      "d.appendChild(tall);",
      "document.body.appendChild(d);",
      "})()"
    ))
  }

  page <- local_cursor_page()
  cover_center(page)
  page |> pz_stage()
  page |> pz_record_start(withr::local_tempfile(fileext = ".mp4"), fps = 10, hold = c(0, 0))
  page |> pz_scroll(by = c(0, 400))
  expect_equal(pz_js(page, "window.scrollY"), 400)
  # Not one wheel fired: the scroll was applied instantly, and the
  # covering scroller is untouched.
  expect_equal(pz_js(page, "window.__log.wheels"), 0)
  expect_equal(pz_js(page, "document.getElementById('center-scroller').scrollTop"), 0)
  # The auto-scroll before an action hits the same fallback: the fixed
  # scroller still covers every root wheel point.
  page |> pz_click("#below")
  expect_equal(pz_js(page, "window.__log.belowClicks"), 1)
  expect_equal(pz_js(page, "window.__log.wheels"), 0)
  expect_equal(pz_js(page, "document.getElementById('center-scroller').scrollTop"), 0)
  page |> pz_record_stop()
  recorded <- c(
    scrollY = pz_js(page, "window.scrollY"),
    scoped = pz_js(page, "document.getElementById('center-scroller').scrollTop")
  )

  page2 <- local_cursor_page()
  cover_center(page2)
  page2 |> pz_scroll(by = c(0, 400))
  page2 |> pz_click("#below")
  unrecorded <- c(
    scrollY = pz_js(page2, "window.scrollY"),
    scoped = pz_js(page2, "document.getElementById('center-scroller').scrollTop")
  )

  expect_equal(recorded, unrecorded)
})

test_that("an off-screen scope is brought into view with staged wheels too", {
  skip_if_no_av()
  page <- local_cursor_page()
  pz_js(page, paste0(
    "(() => {",
    "const d = document.createElement('div');",
    "d.id = 'deep-scope';",
    "d.style.cssText = 'position:absolute;left:100px;",
    "top:calc(100vh + 300px);width:300px;height:250px;",
    "overflow:auto;border:1px solid #ccc;';",
    "const tall = document.createElement('div');",
    "tall.style.cssText = 'height:900px;background:#f8f8f8;';",
    "d.appendChild(tall);",
    "document.body.appendChild(d);",
    "})()"
  ))
  page |> pz_stage()
  page |> pz_record_start(withr::local_tempfile(fileext = ".mp4"), fps = 10, hold = c(0, 0))
  # The scope's container is already at its target (top), so every
  # wheel has to come from the into-view: a recorded scoped scroll
  # must animate the scope on screen, not jump it with scrollIntoView.
  page |> pz_find("#deep-scope") |> pz_scroll(to = "top")
  page |> pz_record_stop()

  expect_true(pz_js(page, "window.__log.wheels") > 0)
  expect_equal(pz_js(page, "document.getElementById('deep-scope').scrollTop"), 0)
  expect_true(pz_js(page, "window.scrollY") > 0)
})

test_that("the stage pause holds after each action only while recording", {
  skip_if_no_av()
  page <- local_cursor_page()
  page |> pz_stage(pause = 0.5)
  page |> pz_record_start(withr::local_tempfile(fileext = ".mp4"), fps = 10, hold = c(0, 0))
  t0 <- proc.time()[["elapsed"]]
  page |> pz_click("#btn")
  recorded <- proc.time()[["elapsed"]] - t0
  page |> pz_record_stop()
  expect_true(recorded >= 0.45)

  page2 <- local_cursor_page()
  page2 |> pz_stage(pause = 0.5)
  page2 |> pz_click("#btn")
  expect_equal(pz_js(page2, "window.__log.clicks"), 1)
})

test_that("the stage pause holds after press, select_text, and drag too", {
  skip_if_no_av()
  page <- local_cursor_page()
  page |> pz_stage(pause = 0.5)
  page |> pz_record_start(withr::local_tempfile(fileext = ".mp4"), fps = 10, hold = c(0, 0))

  # Focus the field for the keypress (the click's own hold is outside
  # the timed stretch).
  page |> pz_click("#name")
  t0 <- proc.time()[["elapsed"]]
  page |> pz_press("a")
  t_press <- proc.time()[["elapsed"]] - t0

  t0 <- proc.time()[["elapsed"]]
  page |> pz_select_text("Go", target = "#btn")
  t_select <- proc.time()[["elapsed"]] - t0

  # The drag's glide time is timing noise, so two identical drags are
  # held against each other: the cursor pre-placed on the source (a
  # duration = 0 move), one drag with the pause and one without.
  page |> pz_stage(pause = 0)
  page |> pz_cursor_move("#plain", duration = 0)
  t0 <- proc.time()[["elapsed"]]
  page |> pz_drag("#plain", by = c(50, 0))
  t_drag0 <- proc.time()[["elapsed"]] - t0
  page |> pz_stage(pause = 0.5)
  page |> pz_cursor_move("#plain", duration = 0)
  t0 <- proc.time()[["elapsed"]]
  page |> pz_drag("#plain", by = c(50, 0))
  t_drag <- proc.time()[["elapsed"]] - t0

  page |> pz_record_stop()

  expect_true(t_press >= 0.45)
  expect_true(t_select >= 0.45)
  expect_true(t_drag - t_drag0 >= 0.4)
})

test_that("recorded demo glides, presses, types, and scrolls on camera", {
  skip_if_no_av()
  page <- local_cursor_page()
  out <- withr::local_tempfile(fileext = ".mp4")

  page |>
    pz_stage(enter = "left") |>
    pz_record_start(out, fps = 15, hold = c(0, 0.2), keep_frames = TRUE)
  page |>
    pz_click("#btn") |>
    pz_type("otters", target = "#name") |>
    pz_click("#below") |>
    pz_record_stop()

  # The final state is the chain's real work.
  expect_equal(pz_js(page, "window.__log.clicks"), 1)
  expect_equal(pz_js(page, "window.__log.belowClicks"), 1)
  expect_equal(pz_js(page, "document.getElementById('name').value"), "otters")
  expect_equal(pz_js(page, "window.__log.inputs.name"), 6)
  expect_true(pz_js(page, "window.__log.wheels") > 0)
  # The auto cursor belonged to the recording and left with it.
  expect_equal(cursor_overlay_state(page)[[1]], 0)

  info <- recorded_video_info(out)
  expect_true(info$duration >= 1.5)

  frames_dir <- paste0(tools::file_path_sans_ext(out), "_frames")
  on.exit(unlink(frames_dir, recursive = TRUE), add = TRUE)
  frames <- list.files(frames_dir, full.names = TRUE)
  expect_true(length(frames) >= 10)

  # The glide: cursor ink in the button's band enters from the left
  # (enter = "left") and travels to the button at x = 660.
  inks <- lapply(frames, function(f) cursor_png_ink(page, f, band = c(290, 360)))
  xs <- vapply(
    inks,
    function(ink) if (ink$count > 20) ink$x else NA_real_,
    numeric(1)
  )
  xs <- xs[!is.na(xs)]
  expect_true(length(xs) >= 2)
  expect_true(min(xs) < 200)
  expect_true(max(xs) > 550)

  # The scroll: a fixed viewport point darkens as the gradient rises.
  first_px <- cursor_png_pixel(page, frames[[1]], 200, 1000)
  last_px <- cursor_png_pixel(page, frames[[length(frames)]], 200, 1000)
  expect_true(last_px[[1]] < first_px[[1]] - 50)
})

test_that("without a recording the same chain runs straight to the final state", {
  page <- local_cursor_page()

  t0 <- proc.time()[["elapsed"]]
  page |>
    pz_stage(enter = "left") |>
    pz_click("#btn") |>
    pz_type("otters", target = "#name") |>
    pz_click("#below")
  elapsed <- proc.time()[["elapsed"]] - t0

  expect_true(elapsed < 5)
  expect_equal(pz_js(page, "window.__log.clicks"), 1)
  expect_equal(pz_js(page, "window.__log.belowClicks"), 1)
  expect_equal(pz_js(page, "document.getElementById('name').value"), "otters")
  # No staging happened: one insertion, no wheels, no cursor layer.
  expect_equal(pz_js(page, "window.__log.inputs.name"), 1)
  expect_equal(pz_js(page, "window.__log.wheels"), 0)
  expect_null(cursor_overlay_state(page))
})

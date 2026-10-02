# Near-black ink count in a RECTANGLE of a captured frame (the demo's
# text-growth check needs a rect that excludes the cursor and the scroller's text).
demo_rect_ink <- function(page, path, x0, x1, y0, y1, dpr = page_dpr(page)) {
  body <- paste0(
    "const d = c.getImageData(",
    sprintf(
      "%d, %d, %d, %d",
      round(x0 * dpr),
      round(y0 * dpr),
      round((x1 - x0) * dpr),
      round((y1 - y0) * dpr)
    ),
    ").data;",
    "let n = 0;",
    "for (let p = 0; p < d.length; p += 4) {",
    "  if (d[p] < 60 && d[p + 1] < 60 && d[p + 2] < 60 && d[p + 3] > 200) n++;",
    "}",
    "return n;"
  )
  png_canvas_eval(page, path, body)
}

test_that("pz_stage merges settings onto the defaults and validates", {
  page <- local_cursor_page()

  expect_identical(page_stage(page), STAGE_DEFAULTS)
  expect_equal(page_stage(page)$cursor_speed, 500)
  expect_equal(page_stage(page)$cursor_scale, 1.75)
  expect_true(page_stage(page)$camera_follow)

  page |>
    pz_stage(
      cursor_speed = 800,
      cursor_scale = 2,
      typing_speed = 30,
      pause = 0.5
    )
  stage <- page_stage(page)
  expect_equal(stage$cursor_speed, 800)
  expect_equal(stage$cursor_scale, 2)
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
  expect_equal(stage$cursor_scale, 2)

  # An explicit NULL removes the override (back to the default);
  # only omitted arguments leave a setting alone.
  page |>
    pz_stage(
      cursor = NULL,
      cursor_speed = NULL,
      cursor_scale = NULL,
      enter = NULL,
      typing = NULL,
      typing_speed = NULL,
      pause = NULL
    )
  expect_identical(page_stage(page), STAGE_DEFAULTS)

  page |> pz_stage(camera_follow = FALSE)
  expect_false(page_stage(page)$camera_follow)
  page |> pz_stage(camera_follow = NULL)
  expect_true(page_stage(page)$camera_follow)
  expect_error(pz_stage(page, camera_follow = "yes"), class = "rlang_error")
  expect_error(pz_stage(page, cursor = "yes"), class = "rlang_error")
  expect_error(pz_stage(page, cursor_speed = 0), class = "rlang_error")
  expect_error(pz_stage(page, cursor_scale = 0), class = "rlang_error")
  expect_error(pz_stage(page, cursor_scale = 5.1), class = "rlang_error")
  expect_error(pz_stage(page, cursor_scale = Inf), class = "rlang_error")
  expect_error(pz_stage(page, cursor_scale = "large"), class = "rlang_error")
  page |> pz_stage(cursor_scale = 5)
  expect_equal(page_stage(page)$cursor_scale, 5)
  expect_error(pz_stage(page, enter = "up"), class = "paparazzi_error_input")
  expect_error(pz_stage(page, typing = "slow"), class = "rlang_error")
  expect_error(pz_stage(page, typing_speed = -1), class = "rlang_error")
  expect_error(pz_stage(page, pause = -1), class = "rlang_error")
  expect_error(pz_stage(page, bogus = 1), class = "rlang_error")
})

test_that("omitted staging settings leave all overrides alone", {
  page <- local_cursor_page()
  page |>
    pz_stage(
      cursor = FALSE,
      cursor_speed = 800,
      cursor_scale = 2,
      enter = "left",
      typing = "instant",
      typing_speed = 30,
      pause = 0.5,
      camera_follow = FALSE,
      show_keys = "words"
    ) |>
    pz_stage_annotate(color = "green")
  before <- page_stage(page)

  page |> pz_stage()

  expect_identical(page_stage(page), before)
})

test_that("tri-state staging settings default to NULL in their signatures", {
  for (fn in list(pz_stage, pz_stage_annotate)) {
    settings <- formals(fn)[-c(1, 2)]
    expect_true(all(vapply(settings, is.null, logical(1))))
  }
})

test_that("pz_stage_annotate rejects invalid styles at assignment", {
  page <- local_cursor_page()
  expect_error(
    pz_stage_annotate(page, color = ""),
    "color.*empty string"
  )
  expect_error(
    pz_stage_annotate(page, font_family = ""),
    "font_family.*empty string"
  )
  expect_error(pz_stage_annotate(page, font_size = 0), class = "rlang_error")
  expect_error(pz_stage_annotate(page, bogus = 1), class = "rlang_error")
  expect_identical(page_stage(page), STAGE_DEFAULTS)
})

test_that("pz_stage_annotate sets defaults without changing other staging", {
  page <- local_cursor_page()
  page |> pz_stage(cursor_speed = 800)

  result <- withVisible(pz_stage_annotate(
    page,
    color = "green",
    font_family = "monospace",
    font_size = 20
  ))

  expect_identical(result$value, page)
  expect_false(result$visible)
  expect_identical(
    annotate_style(page, NULL, NULL, NULL),
    list(color = "green", font_family = "monospace", font_size = 20)
  )
  expect_equal(page_stage(page)$cursor_speed, 800)
})

test_that("omitted annotation defaults stay set", {
  page <- local_cursor_page()
  page |>
    pz_stage_annotate(
      color = "green",
      font_family = "monospace",
      font_size = 20
    )

  page |> pz_stage_annotate()

  expect_identical(
    annotate_style(page, NULL, NULL, NULL),
    list(color = "green", font_family = "monospace", font_size = 20)
  )
})

test_that("NULL resets only supplied annotation defaults", {
  page <- local_cursor_page()
  page |>
    pz_stage_annotate(
      color = "green",
      font_family = "monospace",
      font_size = 20
    )

  page |> pz_stage_annotate(color = NULL)

  expect_identical(
    annotate_style(page, NULL, NULL, NULL),
    list(color = "#e11d48", font_family = "monospace", font_size = 20)
  )
})

test_that("NULL restores all annotation defaults without resetting other staging", {
  page <- local_cursor_page()
  page |> pz_stage(cursor_speed = 800)
  page |>
    pz_stage_annotate(
      color = "green",
      font_family = "monospace",
      font_size = 20
    )

  page |> pz_stage_annotate(color = NULL, font_family = NULL, font_size = NULL)

  expect_identical(
    annotate_style(page, NULL, NULL, NULL),
    list(color = "#e11d48", font_family = "sans-serif", font_size = 14)
  )
  expect_equal(page_stage(page)$cursor_speed, 800)
})

test_that("pz_stage no longer accepts annotation style settings", {
  page <- local_cursor_page()

  expect_error(
    pz_stage(page, annotate_color = "red"),
    class = "rlib_error_dots_nonempty"
  )
  expect_error(
    pz_stage(page, annotate_font_family = "serif"),
    class = "rlib_error_dots_nonempty"
  )
  expect_error(
    pz_stage(page, annotate_font_size = 20),
    class = "rlib_error_dots_nonempty"
  )
  expect_identical(page_stage(page), STAGE_DEFAULTS)
})

test_that("the glide formula uses the new default and 0.5-2s limits", {
  point <- c(x = 0, y = 0)
  to <- function(x) c(x = x, y = 0)
  expect_equal(stage_glide_duration(point, to(300), 500), 0.85)
  expect_equal(stage_glide_duration(point, to(300), 400), 1)
  expect_equal(stage_glide_duration(point, to(0), 500), 0.5)
  expect_equal(stage_glide_duration(point, to(3000), 500), 2)
  expect_equal(stage_glide_duration(point, to(300), 1500), 0.5)
})

test_that("natural typing is per-character while recording, instant otherwise", {
  skip_if_no_av()
  out <- withr::local_tempfile(fileext = ".mp4")

  page <- local_cursor_page()
  page |> pz_stage()
  page |> pz_record_start(out, fps = 10, hold = c(0, 0))
  page |>
    pz_act_type("otters", target = "#name") |>
    pz_act_type("abc", target = "#bio") |>
    pz_act_type("xy", target = "#edit")
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
  page2 |>
    pz_record_start(
      withr::local_tempfile(fileext = ".mp4"),
      fps = 10,
      hold = c(0, 0)
    )
  page2 |> pz_act_type("otters", target = "#name")
  page2 |> pz_record_stop()
  expect_equal(pz_js(page2, "window.__log.inputs.name"), 1)
  expect_equal(pz_js(page2, "document.getElementById('name').value"), "otters")

  # Not recording: instant whatever the setting.
  page3 <- local_cursor_page()
  page3 |> pz_stage()
  page3 |> pz_act_type("otters", target = "#name")
  expect_equal(pz_js(page3, "window.__log.inputs.name"), 1)
})

test_that("smooth scrolling uses real wheel events while recording", {
  skip_if_no_av()
  page <- local_cursor_page()
  page |> pz_stage()
  page |>
    pz_record_start(
      withr::local_tempfile(fileext = ".mp4"),
      fps = 10,
      hold = c(0, 0)
    )

  page |> pz_act_scroll(by = c(0, 600))
  expect_equal(pz_js(page, "window.scrollY"), 600)
  expect_true(pz_js(page, "window.__log.wheels") > 0)
  expect_true(pz_js(page, "window.__log.wheelsTrusted"))

  page |> pz_act_scroll(to = "bottom")
  expect_equal(
    pz_js(page, "window.scrollY"),
    pz_js(
      page,
      "document.scrollingElement.scrollHeight - document.documentElement.clientHeight"
    )
  )

  # A scoped scroll wheels the scope's container, not the page.
  wheels <- pz_js(page, "window.__log.wheels")
  page |> pz_find("#scroller") |> pz_act_scroll(to = "bottom")
  expect_equal(
    pz_js(page, "document.getElementById('scroller').scrollTop"),
    650
  )
  expect_true(pz_js(page, "window.__log.wheels") > wheels)

  page |> pz_record_stop()
})

test_that("staged root offsets and directions correct incomplete wheels", {
  page <- local_cursor_page()
  pz_js(
    page,
    "document.head.insertAdjacentHTML('beforeend', '<style>::-webkit-scrollbar { width:15px; height:15px }</style>');
     document.getElementById('spacer').style.width = '2000px'"
  )
  local_mocked_bindings(stage_wheel = function(...) invisible(TRUE))

  scroll_staged(page, NULL, by = c(120, 300), to = NULL, duration = 0.01)
  expect_equal(
    unlist(pz_js(page, "[window.scrollX, window.scrollY]")),
    c(120, 300)
  )
  scroll_staged(page, NULL, by = c(-40, -100), to = NULL, duration = 0.01)
  expect_equal(
    unlist(pz_js(page, "[window.scrollX, window.scrollY]")),
    c(80, 200)
  )
  scroll_staged(
    page,
    NULL,
    by = NULL,
    to = c("right", "bottom"),
    duration = 0.01
  )
  expect_equal(
    unlist(pz_js(page, "[window.scrollX, window.scrollY]")),
    unlist(pz_js(
      page,
      "[document.scrollingElement.scrollWidth - document.documentElement.clientWidth, document.scrollingElement.scrollHeight - document.documentElement.clientHeight]"
    ))
  )
  scroll_staged(page, NULL, by = NULL, to = c("left", "top"), duration = 0.01)
  expect_equal(unlist(pz_js(page, "[window.scrollX, window.scrollY]")), c(0, 0))
})

test_that("staged scoped fallback uses offsets and directions without root serialization", {
  page <- local_cursor_page()
  pz_js(
    page,
    "document.head.insertAdjacentHTML('beforeend', '<style>::-webkit-scrollbar { width:15px; height:15px }</style>');
     document.querySelector('#scroller > div').style.width = '600px'"
  )
  ctx <- pz_find(page, "#scroller")
  scoped <- scope_connected(ctx)
  local_mocked_bindings(
    stage_wheel = function(...) invisible(TRUE),
    scroll_arg_json = function(...) {
      stop("root serialization used for scoped scroll")
    }
  )
  position <- function() {
    unlist(pz_js(
      page,
      "[document.getElementById('scroller').scrollLeft, document.getElementById('scroller').scrollTop]"
    ))
  }

  scroll_staged(ctx, scoped, by = c(100, 200), to = NULL, duration = 0.01)
  expect_equal(position(), c(100, 200))
  scroll_staged(ctx, scoped, by = c(-40, -50), to = NULL, duration = 0.01)
  expect_equal(position(), c(60, 150))
  scroll_staged(ctx, scoped, by = NULL, to = "center", duration = 0.01)
  expect_equal(
    position(),
    unlist(pz_js(
      page,
      "(() => { const s = document.getElementById('scroller'); return [Math.round((s.scrollWidth - s.clientWidth) / 2), Math.round((s.scrollHeight - s.clientHeight) / 2)]; })()"
    ))
  )
  scroll_staged(ctx, scoped, by = NULL, to = c("left", "top"), duration = 0.01)
  expect_equal(position(), c(0, 0))
})

test_that("a nested scroller obstructs a scoped wheel and stays untouched", {
  page <- local_cursor_page()
  pz_js(
    page,
    "(() => {
    const outer = document.getElementById('scroller');
    outer.style.position = 'fixed';
    outer.firstElementChild.innerHTML = '<div id=inner-scroller style=\"position:sticky;top:0;width:200px;height:150px;overflow:auto\"><div style=\"height:1000px\"></div></div>';
  })()"
  )
  ctx <- pz_find(page, "#scroller > div")
  scroll_staged(
    ctx,
    scope_connected(ctx),
    by = c(0, 200),
    to = NULL,
    duration = 0.01
  )
  expect_equal(
    pz_js(page, "document.getElementById('scroller').scrollTop"),
    200
  )
  expect_equal(
    pz_js(page, "document.getElementById('inner-scroller').scrollTop"),
    0
  )
  expect_equal(pz_js(page, "window.__log.wheels"), 0)
  expect_equal(pz_js(page, "window.scrollY"), 0)
})

test_that("pz_act_scroll duration overrides staged wheels for by, to, and target", {
  skip_if_no_av()
  page <- local_cursor_page()
  page |> pz_stage(cursor_speed = 500)
  page |>
    pz_record_start(
      withr::local_tempfile(fileext = ".mp4"),
      fps = 10,
      hold = c(0, 0)
    )

  wheel_durations <- numeric()
  original_wheel <- stage_wheel
  testthat::local_mocked_bindings(
    stage_wheel = function(ctx, point, dx, dy, duration, call = caller_env()) {
      wheel_durations <<- c(wheel_durations, duration)
      original_wheel(ctx, point, dx, dy, duration, call = call)
    }
  )

  page |> pz_act_scroll(by = c(0, 300), duration = 0.05)
  expect_equal(pz_js(page, "window.scrollY"), 300)
  expect_true(length(wheel_durations) > 0)
  expect_true(all(wheel_durations == 0.05))
  wheel_durations <- numeric()

  page |> pz_act_scroll(to = "bottom", duration = 0.05)
  expect_equal(
    pz_js(page, "window.scrollY"),
    pz_js(
      page,
      "document.scrollingElement.scrollHeight - document.documentElement.clientHeight"
    )
  )
  expect_true(length(wheel_durations) > 0)
  expect_true(all(wheel_durations == 0.05))
  wheel_durations <- numeric()

  page |> pz_act_scroll(target = "#plain", duration = 0.05)
  expect_true(pz_js(
    page,
    "document.getElementById('plain').getBoundingClientRect().y >= 0"
  ))
  expect_true(length(wheel_durations) > 0)
  expect_true(all(wheel_durations == 0.05))

  before <- pz_js(page, "window.scrollY")
  page |> pz_act_scroll(by = c(0, 0), duration = 0)
  expect_equal(pz_js(page, "window.scrollY"), before)
  page |> pz_record_stop()
})

test_that("zero-duration scrolls land instantly without queued wheel events", {
  skip_if_no_av()
  page <- local_cursor_page()
  page |>
    pz_record_start(
      withr::local_tempfile(fileext = ".mp4"),
      fps = 10,
      hold = c(0, 0)
    )

  page |> pz_act_scroll(by = c(0, 300), duration = 0L)
  expect_equal(pz_js(page, "window.scrollY"), 300)
  page |> pz_act_scroll(to = "bottom", duration = 0)
  expect_equal(
    pz_js(page, "window.scrollY"),
    pz_js(
      page,
      "document.scrollingElement.scrollHeight - document.documentElement.clientHeight"
    )
  )
  page |> pz_act_scroll(target = "#plain", duration = 0)
  expect_true(pz_js(
    page,
    "document.getElementById('plain').getBoundingClientRect().y >= 0"
  ))
  expect_equal(pz_js(page, "window.__log.wheels"), 0)
  page |> pz_record_stop()
})

test_that("the auto-scroll before actions is the same staged wheel scroll", {
  skip_if_no_av()
  page <- local_cursor_page()
  page |> pz_stage()
  page |>
    pz_record_start(
      withr::local_tempfile(fileext = ".mp4"),
      fps = 10,
      hold = c(0, 0)
    )
  page |> pz_act_click("#below")
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
  pz_js(
    page,
    paste0(
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
    )
  )
  page |> pz_stage()
  page |>
    pz_record_start(
      withr::local_tempfile(fileext = ".mp4"),
      fps = 10,
      hold = c(0, 0)
    )
  page |> pz_act_click("#deep-btn")
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
  page |>
    pz_record_start(
      withr::local_tempfile(fileext = ".mp4"),
      fps = 10,
      hold = c(0, 0)
    )
  page |> pz_act_click("#btn")
  # cursor = FALSE never draws, even while recording.
  expect_null(cursor_overlay_state(page))

  page |> pz_stage(cursor = NULL)
  page |> pz_act_click("#btn")
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
    pz_js(
      page,
      paste0(
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
      )
    )
  }

  page <- local_cursor_page()
  cover_center(page)
  page |> pz_stage()
  page |>
    pz_record_start(
      withr::local_tempfile(fileext = ".mp4"),
      fps = 10,
      hold = c(0, 0)
    )
  page |> pz_act_scroll(by = c(0, 400))
  expect_equal(pz_js(page, "window.scrollY"), 400)
  # Not one wheel fired: the scroll was applied instantly, and the
  # covering scroller is untouched.
  expect_equal(pz_js(page, "window.__log.wheels"), 0)
  expect_equal(
    pz_js(page, "document.getElementById('center-scroller').scrollTop"),
    0
  )
  # The auto-scroll before an action hits the same fallback: the fixed
  # scroller still covers every root wheel point.
  page |> pz_act_click("#below")
  expect_equal(pz_js(page, "window.__log.belowClicks"), 1)
  expect_equal(pz_js(page, "window.__log.wheels"), 0)
  expect_equal(
    pz_js(page, "document.getElementById('center-scroller').scrollTop"),
    0
  )
  page |> pz_record_stop()
  recorded <- c(
    scrollY = pz_js(page, "window.scrollY"),
    scoped = pz_js(page, "document.getElementById('center-scroller').scrollTop")
  )

  page2 <- local_cursor_page()
  cover_center(page2)
  page2 |> pz_act_scroll(by = c(0, 400))
  page2 |> pz_act_click("#below")
  unrecorded <- c(
    scrollY = pz_js(page2, "window.scrollY"),
    scoped = pz_js(
      page2,
      "document.getElementById('center-scroller').scrollTop"
    )
  )

  expect_equal(recorded, unrecorded)
})

test_that("an off-screen scope is brought into view with staged wheels too", {
  skip_if_no_av()
  page <- local_cursor_page()
  pz_js(
    page,
    paste0(
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
    )
  )
  page |> pz_stage()
  page |>
    pz_record_start(
      withr::local_tempfile(fileext = ".mp4"),
      fps = 10,
      hold = c(0, 0)
    )
  wheel_durations <- numeric()
  original_wheel <- stage_wheel
  testthat::local_mocked_bindings(
    stage_wheel = function(ctx, point, dx, dy, duration, call = caller_env()) {
      wheel_durations <<- c(wheel_durations, duration)
      original_wheel(ctx, point, dx, dy, duration, call = call)
    }
  )
  # The scope's container is already at its target (top), so every
  # wheel has to come from the into-view: a recorded scoped scroll
  # must animate the scope on screen, not jump it with scrollIntoView.
  page |> pz_find("#deep-scope") |> pz_act_scroll(to = "top", duration = 0.05)
  page |> pz_record_stop()

  expect_true(length(wheel_durations) > 0)
  expect_true(all(wheel_durations == 0.05))

  expect_true(pz_js(page, "window.__log.wheels") > 0)
  expect_equal(
    pz_js(page, "document.getElementById('deep-scope').scrollTop"),
    0
  )
  expect_true(pz_js(page, "window.scrollY") > 0)
})

test_that("the stage pause holds after each action only while recording", {
  skip_if_no_av()
  page <- local_cursor_page()
  page |> pz_stage(pause = 0.5)
  page |>
    pz_record_start(
      withr::local_tempfile(fileext = ".mp4"),
      fps = 10,
      hold = c(0, 0)
    )
  t0 <- proc.time()[["elapsed"]]
  page |> pz_act_click("#btn")
  recorded <- proc.time()[["elapsed"]] - t0
  page |> pz_record_stop()
  expect_true(recorded >= 0.45)

  page2 <- local_cursor_page()
  page2 |> pz_stage(pause = 0.5)
  page2 |> pz_act_click("#btn")
  expect_equal(pz_js(page2, "window.__log.clicks"), 1)
})

test_that("the stage pause holds after focus and root or scoped blur", {
  skip_if_no_av()
  page <- local_cursor_page()
  page |> pz_stage(pause = 0.5)
  page |>
    pz_record_start(
      withr::local_tempfile(fileext = ".mp4"),
      fps = 10,
      hold = c(0, 0)
    )

  t0 <- proc.time()[["elapsed"]]
  page |> pz_act_focus("#name")
  t_focus <- proc.time()[["elapsed"]] - t0
  expect_true(pz_js(page, "document.activeElement.id === 'name'"))

  t0 <- proc.time()[["elapsed"]]
  page |> pz_act_blur()
  t_blur <- proc.time()[["elapsed"]] - t0
  expect_false(pz_js(page, "document.activeElement.id === 'name'"))

  field <- pz_find(page, "#name")
  field |> pz_act_focus()
  t0 <- proc.time()[["elapsed"]]
  field |> pz_act_blur()
  t_scoped_blur <- proc.time()[["elapsed"]] - t0
  page |> pz_record_stop()

  expect_true(t_focus >= 0.45)
  expect_true(t_blur >= 0.45)
  expect_true(t_scoped_blur >= 0.45)

  pauses <- numeric()
  local_mocked_bindings(
    pump_loop = function(loop, duration, ...) {
      pauses <<- c(pauses, duration)
    }
  )
  page |> pz_act_focus("#name")
  page |> pz_act_blur()
  field |> pz_act_focus()
  field |> pz_act_blur()
  expect_length(pauses, 0)
})

test_that("the stage pause holds after root typing without a target", {
  skip_if_no_av()
  page <- local_cursor_page()
  page |> pz_stage(pause = 0.5, typing = "instant", camera_follow = FALSE)
  page |> pz_act_focus("#name")
  page |>
    pz_record_start(
      withr::local_tempfile(fileext = ".mp4"),
      fps = 10,
      hold = c(0, 0)
    )

  t0 <- proc.time()[["elapsed"]]
  page |> pz_act_type("a")
  recorded <- proc.time()[["elapsed"]] - t0
  page |> pz_record_stop()

  expect_equal(pz_get_value(page, target = "#name"), "a")
  expect_true(recorded >= 0.45)

  pauses <- numeric()
  local_mocked_bindings(
    pump_loop = function(loop, duration, ...) {
      pauses <<- c(pauses, duration)
    }
  )
  page |> pz_act_type("b")
  expect_equal(pz_get_value(page, target = "#name"), "ab")
  expect_length(pauses, 0)
})

test_that("the stage pause holds after press, select_text, and drag too", {
  skip_if_no_av()
  page <- local_cursor_page()
  pause <- 0.37
  page |> pz_stage(pause = pause)
  page |>
    pz_record_start(
      withr::local_tempfile(fileext = ".mp4"),
      fps = 10,
      hold = c(0, 0)
    )

  defer_record_stop(page)
  page |> pz_act_click("#name")
  holds <- numeric()
  original_pump <- pump_loop
  local_mocked_bindings(
    pump_loop = function(loop, duration, ...) {
      holds <<- c(holds, duration)
      original_pump(loop, duration, ...)
    }
  )

  page |> pz_act_press("a")
  expect_equal(tail(holds, 1), pause)
  expect_equal(pz_get_value(page, target = "#name"), "a")

  holds <- numeric()
  page |> pz_act_select_text("Go", target = "#btn")
  expect_equal(tail(holds, 1), pause)
  expect_equal(pz_js(page, "window.getSelection().toString()"), "Go")

  holds <- numeric()
  page |> pz_act_drag("#plain", by = c(50, 0))
  expect_equal(tail(holds, 1), pause)

  page |> pz_record_stop()
})

test_that("recorded demo glides, types, and scrolls on camera", {
  skip_if_no_av()
  page <- local_cursor_page()
  out <- withr::local_tempfile(fileext = ".mp4")

  # typing_speed = 6 spreads the characters over ~1-2s of frames, so
  # the growth is observable on camera.
  page |>
    pz_stage(enter = "left", typing_speed = 6) |>
    pz_record_start(out, fps = 15, hold = c(0, 0.2), keep_frames = TRUE)
  page |>
    pz_act_click("#btn") |>
    pz_act_type("otters", target = "#name") |>
    pz_act_click("#below") |>
    pz_record_stop()

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
  inks <- lapply(frames, function(f) {
    cursor_png_ink(page, f, band = c(290, 360))
  })
  xs <- vapply(
    inks,
    function(ink) if (ink$count > 20) ink$x else NA_real_,
    numeric(1)
  )
  xs <- xs[!is.na(xs)]
  expect_true(length(xs) >= 2)
  expect_true(min(xs) < 200)
  expect_true(max(xs) > 550)

  # The typing: near-black ink in the input's text rect (x 95-175;
  # the cursor sits at x 200 and the scroller's text at x 450+) grows
  # across frames as the characters land.
  txt <- vapply(
    frames,
    function(f) demo_rect_ink(page, f, 95, 175, 55, 90),
    numeric(1)
  )
  nz <- txt[txt > 0]
  expect_true(length(nz) >= 4)
  expect_true(length(unique(nz)) >= 3)
  expect_true(sum(diff(nz) > 0) >= 2)

  # The scroll: a fixed viewport point darkens as the gradient rises,
  # through intermediate values rather than in one jump.
  first_px <- png_pixel(page, frames[[1]], 200, 1000)
  last_px <- png_pixel(page, frames[[length(frames)]], 200, 1000)
  expect_true(last_px[[1]] < first_px[[1]] - 50)
  reds <- vapply(
    frames,
    function(f) png_pixel(page, f, 200, 1000)[[1]],
    numeric(1)
  )
  expect_true(length(unique(reds[reds < reds[[1]] - 10])) >= 3)
})

test_that("without a recording the same chain runs straight to the final state", {
  page <- local_cursor_page()

  t0 <- proc.time()[["elapsed"]]
  page |>
    pz_stage(enter = "left") |>
    pz_act_click("#btn") |>
    pz_act_type("otters", target = "#name") |>
    pz_act_click("#below")
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

test_that("click_effect and click_effect_color stage, validate, and reset", {
  page <- local_cursor_page()
  expect_identical(page_stage(page)$click_effect, "press")
  expect_identical(page_stage(page)$click_effect_color, "#e11d48")

  for (effect in c("ring", "none", "press")) {
    pz_stage(page, click_effect = effect)
    expect_identical(page_stage(page)$click_effect, effect)
  }
  expect_error(pz_stage(page, click_effect = "slide"), class = "rlang_error")

  pz_stage(page, click_effect_color = "#2563eb")
  expect_identical(page_stage(page)$click_effect_color, "#2563eb")
  expect_error(
    pz_stage(page, click_effect_color = ""),
    "click_effect_color.*empty string"
  )
  expect_error(pz_stage(page, click_effect_color = 7), class = "rlang_error")

  pz_stage(page, click_effect = NULL, click_effect_color = NULL)
  expect_identical(page_stage(page)$click_effect, "press")
  expect_identical(page_stage(page)$click_effect_color, "#e11d48")
})

test_that("show_keys defaults to none and restores its staged default", {
  page <- local_record_page()
  expect_identical(page_stage(page)$show_keys, "none")
  for (style in c("words", "mac", "both")) {
    pz_stage(page, show_keys = style)
    expect_identical(page_stage(page)$show_keys, style)
  }
  expect_error(pz_stage(page, show_keys = "nope"), "nope")
  pz_stage(page, show_keys = NULL)
  expect_identical(page_stage(page)$show_keys, "none")
})

test_that("pz_stage_annotate stages fill, text color, stroke width and distance", {
  page <- local_cursor_page()
  expect_error(pz_stage_annotate(page, fill = ""), "fill.*empty string")
  expect_error(
    pz_stage_annotate(page, text_color = ""),
    "text_color.*empty string"
  )
  expect_error(pz_stage_annotate(page, stroke_width = 0), "stroke_width")
  expect_error(pz_stage_annotate(page, stroke_width = -1), "stroke_width")
  expect_error(pz_stage_annotate(page, distance = -1), "distance")
  expect_identical(page_stage(page), STAGE_DEFAULTS)

  page |>
    pz_stage_annotate(
      fill = "red",
      text_color = "black",
      stroke_width = 5,
      distance = 30
    )
  expect_identical(page_stage(page)$annotate_fill, "red")
  expect_identical(page_stage(page)$annotate_text_color, "black")
  expect_identical(page_stage(page)$annotate_stroke_width, 5)
  expect_identical(page_stage(page)$annotate_distance, 30)

  page |> pz_stage_annotate()
  expect_identical(page_stage(page)$annotate_fill, "red")
  expect_identical(page_stage(page)$annotate_distance, 30)

  page |>
    pz_stage_annotate(
      fill = NULL,
      text_color = NULL,
      stroke_width = NULL,
      distance = NULL
    )
  expect_identical(page_stage(page)$annotate_fill, STAGE_DEFAULTS$annotate_fill)
  expect_identical(
    page_stage(page)$annotate_text_color,
    STAGE_DEFAULTS$annotate_text_color
  )
  expect_identical(
    page_stage(page)$annotate_stroke_width,
    STAGE_DEFAULTS$annotate_stroke_width
  )
  expect_identical(
    page_stage(page)$annotate_distance,
    STAGE_DEFAULTS$annotate_distance
  )
})

test_that("scrolling a zero-count set returns invisibly without probing CDP", {
  local_mocked_bindings(
    els_values = function(...) stop("Unexpected CDP probe")
  )
  els <- new_elements(NULL, NULL, 0L, "empty")
  expect_identical(
    withVisible(stage_wheel_into_view(NULL, els)),
    list(value = els, visible = FALSE)
  )
})

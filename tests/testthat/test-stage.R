# Near-black ink count in a RECTANGLE of a captured frame (the demo's
# text-growth check needs a rect that excludes the cursor and the scroller's text).
demo_rect_ink <- function(page, path, x0, x1, y0, y1, dpr = page_dpr(page)) {
  body <- sprintf(
    r"[
const data = c.getImageData(%d, %d, %d, %d).data;
let count = 0;
for (let i = 0; i < data.length; i += 4) {
  if (data[i] < 60 && data[i + 1] < 60 && data[i + 2] < 60 && data[i + 3] > 200) {
    count++;
  }
}
return count;
]",
    round(x0 * dpr),
    round(y0 * dpr),
    round((x1 - x0) * dpr),
    round((y1 - y0) * dpr)
  )
  png_canvas_eval(page, path, body)
}

test_that("staged settings are pipeline-scoped, not page state", {
  page <- local_cursor_page()

  # A stage mid-pipeline reaches only the pipeline it flows through;
  # a fresh pipeline from `page` observes the built-in defaults.
  page |> pz_stage(pause = 2)
  expect_identical(ctx_stage(page), STAGE_DEFAULTS)

  # Assignment is what makes staged settings page-wide: only the
  # returned context carries them.
  staged <- page |> pz_stage(pause = 2)
  expect_equal(ctx_stage(staged)$pause, 2)
  expect_equal(ctx_stage(page)$pause, 0)

  # Later stages build on the staged context, never on the page.
  staged <- staged |> pz_stage(cursor_speed = 800)
  expect_equal(ctx_stage(staged)$pause, 2)
  expect_equal(ctx_stage(staged)$cursor_speed, 800)
  expect_equal(ctx_stage(page)$cursor_speed, 500)
})

test_that("assignment carries a staged cursor into stills", {
  # A pinned viewport puts the never-shown cursor at (500, 350): the
  # band below holds only the cursor's ink, clear of the fixture's
  # dark button and inputs.
  page <- local_page(cursor_fixture_file(), width = 1000, height = 700)
  staged <- page |> pz_stage(cursor = TRUE)

  # The staged pipeline resolves cursor = TRUE at capture: the still
  # draws the static cursor at its current point (the viewport center
  # when it has never been shown).
  shot <- withr::local_tempfile(fileext = ".png")
  staged |> pz_screenshot(shot)
  ink <- cursor_png_ink(page, shot, band = c(280, 430))
  expect_gt(ink$count, 50)

  # The overlay that capture leaves drawn is page-global DOM; a still
  # from the unstaged page resolves cursor = NULL (auto, not recording)
  # and hides it at capture.
  page |> pz_screenshot(shot)
  expect_equal(cursor_png_ink(page, shot, band = c(280, 430))$count, 0)
})

test_that("staging never leaks cursor ink into pipelines from the page", {
  page <- local_page(cursor_fixture_file(), width = 1000, height = 700)
  shot <- withr::local_tempfile(fileext = ".png")

  # An unassigned stage touches no DOM: pipelines from `page` resolve
  # the defaults, so a still shows no cursor ink.
  page |> pz_stage(cursor = TRUE)
  page |> pz_screenshot(shot)
  expect_equal(cursor_png_ink(page, shot, band = c(280, 430))$count, 0)

  # Assignment carries cursor = TRUE into the staged pipeline: its
  # still resolves the overlay at capture time and draws the cursor.
  staged <- page |> pz_stage(cursor = TRUE)
  staged |> pz_screenshot(shot)
  expect_gt(cursor_png_ink(page, shot, band = c(280, 430))$count, 50)

  # A still from the unstaged page hides the overlay the staged capture
  # left drawn: visibility resolves per capture from the context, so
  # one chain's staging never reaches another's captures.
  page |> pz_screenshot(shot)
  expect_equal(cursor_png_ink(page, shot, band = c(280, 430))$count, 0)

  # cursor = FALSE resolves the same way: hiding at capture, not
  # leaving a stale overlay for any chain that captures next.
  hidden <- page |> pz_stage(cursor = FALSE)
  hidden |> pz_screenshot(shot)
  expect_equal(cursor_png_ink(page, shot, band = c(280, 430))$count, 0)
})

test_that("staged settings reach only pipelines from the staged context", {
  page <- local_cursor_page()

  # An unassigned stage reaches nothing: pipelines from the page
  # variable resolve the built-in defaults (the overlay scale stays
  # 1.75 because the unassigned cursor_scale never reached this
  # pipeline's show).
  page |> pz_stage(cursor_scale = 2)
  page |> pz_cursor_show("#btn")
  expect_equal(cursor_overlay_scale(page), 1.75)

  # Assignment carries the setting into every pipeline from `staged`.
  staged <- page |> pz_stage(cursor_scale = 2)
  staged |> pz_cursor_show("#none")
  expect_equal(cursor_overlay_scale(page), 2)
})

test_that("pz_find contexts inherit staged settings", {
  page <- local_cursor_page()
  staged <- page |> pz_stage(cursor_scale = 3)

  scoped <- pz_find(staged, "#btn")
  expect_equal(ctx_stage(scoped)$cursor_scale, 3)

  # The inherited setting resolves in the scoped pipeline's calls
  # (cursor_show() with no target uses the scope)
  scoped |> pz_cursor_show()
  expect_equal(cursor_overlay_scale(page), 3)

  # Unwinding the scope keeps the staging
  root <- pz_find_reset(scoped)
  expect_equal(ctx_stage(root)$cursor_scale, 3)

  # A scope derived from the unassigned page sees the defaults
  plain <- pz_find(page, "#btn")
  expect_equal(ctx_stage(plain)$cursor_scale, 1.75)
})

test_that("pz_stage merges settings onto the defaults and validates", {
  page <- local_cursor_page()

  expect_identical(ctx_stage(page), STAGE_DEFAULTS)
  expect_equal(ctx_stage(page)$cursor_speed, 500)
  expect_equal(ctx_stage(page)$cursor_scale, 1.75)
  expect_true(ctx_stage(page)$camera_follow)

  staged <- page |>
    pz_stage(
      cursor_speed = 800,
      cursor_scale = 2,
      typing_speed = 30,
      pause = 0.5
    )
  stage <- ctx_stage(staged)
  expect_equal(stage$cursor_speed, 800)
  expect_equal(stage$cursor_scale, 2)
  expect_equal(stage$typing_speed, 30)
  expect_equal(stage$pause, 0.5)

  # Only supplied arguments change.
  expect_null(stage$cursor)
  expect_null(stage$enter)
  expect_identical(stage$typing, "natural")

  staged <- staged |>
    pz_stage(enter = "left", typing = "instant", cursor = TRUE)
  stage <- ctx_stage(staged)
  expect_identical(stage$enter, "left")
  expect_identical(stage$typing, "instant")
  expect_true(stage$cursor)
  expect_equal(stage$cursor_speed, 800)
  expect_equal(stage$cursor_scale, 2)

  # An explicit NULL removes the override (back to the default);
  # only omitted arguments leave a setting alone.
  staged <- staged |>
    pz_stage(
      cursor = NULL,
      cursor_speed = NULL,
      cursor_scale = NULL,
      enter = NULL,
      typing = NULL,
      typing_speed = NULL,
      pause = NULL
    )
  expect_identical(ctx_stage(staged), STAGE_DEFAULTS)

  staged <- staged |> pz_stage(camera_follow = FALSE)
  expect_false(ctx_stage(staged)$camera_follow)
  staged <- staged |> pz_stage(camera_follow = NULL)
  expect_true(ctx_stage(staged)$camera_follow)

  expect_error(pz_stage(page, camera_follow = "yes"), class = "rlang_error")
  expect_error(pz_stage(page, cursor = "yes"), class = "rlang_error")
  expect_error(pz_stage(page, cursor_speed = 0), class = "rlang_error")
  expect_error(pz_stage(page, cursor_scale = 0), class = "rlang_error")
  expect_error(pz_stage(page, cursor_scale = 5.1), class = "rlang_error")
  expect_error(pz_stage(page, cursor_scale = Inf), class = "rlang_error")
  expect_error(pz_stage(page, cursor_scale = "large"), class = "rlang_error")

  staged <- staged |> pz_stage(cursor_scale = 5)
  expect_equal(ctx_stage(staged)$cursor_scale, 5)

  expect_error(pz_stage(page, enter = "up"), class = "paparazzi_error_input")
  expect_error(pz_stage(page, typing = "slow"), class = "rlang_error")
  expect_error(pz_stage(page, typing_speed = -1), class = "rlang_error")
  expect_error(pz_stage(page, pause = -1), class = "rlang_error")
  expect_error(pz_stage(page, bogus = 1), class = "rlang_error")
  expect_identical(ctx_stage(page), STAGE_DEFAULTS)
})

test_that("omitted staging settings leave all overrides alone", {
  page <- local_cursor_page()
  staged <- page |>
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
  before <- ctx_stage(staged)

  staged <- staged |> pz_stage()

  expect_identical(ctx_stage(staged), before)
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
  expect_error(
    pz_stage_annotate(page, caption_side = "left"),
    class = "rlang_error"
  )
  expect_error(pz_stage_annotate(page, bogus = 1), class = "rlang_error")
  expect_identical(ctx_stage(page), STAGE_DEFAULTS)
})

test_that("pz_stage_annotate sets defaults without changing other staging", {
  page <- local_cursor_page()
  staged <- page |> pz_stage(cursor_speed = 800)

  result <- withVisible(pz_stage_annotate(
    staged,
    color = "green",
    font_family = "monospace",
    font_size = 20
  ))

  # pz_stage_annotate() derives a new context; it returns invisibly
  # outside a recording.
  expect_false(result$visible)
  expect_s3_class(result$value, "PaparazziContext")
  expect_identical(result$value$page, page)
  expect_identical(
    annotate_style(result$value, NULL, NULL, NULL),
    list(color = "green", font_family = "monospace", font_size = 20)
  )
  expect_equal(ctx_stage(result$value)$cursor_speed, 800)
})

test_that("omitted annotation defaults stay set", {
  page <- local_cursor_page()
  staged <- page |>
    pz_stage_annotate(
      color = "green",
      font_family = "monospace",
      font_size = 20
    )

  staged <- staged |> pz_stage_annotate()

  expect_identical(
    annotate_style(staged, NULL, NULL, NULL),
    list(color = "green", font_family = "monospace", font_size = 20)
  )
})

test_that("NULL resets only supplied annotation defaults", {
  page <- local_cursor_page()
  staged <- page |>
    pz_stage_annotate(
      color = "green",
      font_family = "monospace",
      font_size = 20
    )

  staged <- staged |> pz_stage_annotate(color = NULL)

  expect_identical(
    annotate_style(staged, NULL, NULL, NULL),
    list(color = "#e11d48", font_family = "monospace", font_size = 20)
  )
})

test_that("NULL restores all annotation defaults without resetting other staging", {
  page <- local_cursor_page()
  staged <- page |>
    pz_stage(cursor_speed = 800) |>
    pz_stage_annotate(
      color = "green",
      font_family = "monospace",
      font_size = 20
    )

  staged <- staged |>
    pz_stage_annotate(color = NULL, font_family = NULL, font_size = NULL)

  expect_identical(
    annotate_style(staged, NULL, NULL, NULL),
    list(color = "#e11d48", font_family = "sans-serif", font_size = 14)
  )
  expect_equal(ctx_stage(staged)$cursor_speed, 800)
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
  expect_identical(ctx_stage(page), STAGE_DEFAULTS)
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

  expect_equal(
    pz_evaluate(page, "document.getElementById('name').value"),
    "otters"
  )
  expect_equal(pz_evaluate(page, "document.getElementById('bio').value"), "abc")
  expect_equal(
    pz_evaluate(page, "document.getElementById('edit').textContent"),
    "xy"
  )
  expect_equal(pz_evaluate(page, "window.__log.inputs.name"), 6)
  expect_equal(pz_evaluate(page, "window.__log.inputs.bio"), 3)
  expect_equal(pz_evaluate(page, "window.__log.inputs.edit"), 2)

  # typing = "instant" is one insertion even while recording.
  page2 <- local_cursor_page()
  page2 <- page2 |> pz_stage(typing = "instant")
  page2 |>
    pz_record_start(
      withr::local_tempfile(fileext = ".mp4"),
      fps = 10,
      hold = c(0, 0)
    )
  page2 |> pz_act_type("otters", target = "#name")
  page2 |> pz_record_stop()

  expect_equal(pz_evaluate(page2, "window.__log.inputs.name"), 1)
  expect_equal(
    pz_evaluate(page2, "document.getElementById('name').value"),
    "otters"
  )

  # Not recording: instant whatever the setting.
  page3 <- local_cursor_page()
  page3 |> pz_stage()
  page3 |> pz_act_type("otters", target = "#name")
  expect_equal(pz_evaluate(page3, "window.__log.inputs.name"), 1)
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

  # pz_act_scroll() returns once the scroll position has settled, and
  # per-event wheel rounding is corrected to the target, so the page ends
  # on target within the correction threshold.
  page |> pz_act_scroll(by = c(0, 600), duration = 0.1)
  expect_true(abs(pz_evaluate(page, "window.scrollY") - 600) <= 2)
  expect_true(pz_evaluate(page, "window.__log.wheels") > 0)
  expect_true(pz_evaluate(page, "window.__log.wheelsTrusted"))

  page |> pz_act_scroll(to = "bottom", duration = 0.1)
  bottom <- pz_evaluate(
    page,
    "document.scrollingElement.scrollHeight - document.documentElement.clientHeight"
  )
  expect_true(abs(pz_evaluate(page, "window.scrollY") - bottom) <= 2)

  # A scoped scroll wheels the scope's container, not the page.
  wheels <- pz_evaluate(page, "window.__log.wheels")
  page |>
    pz_find("#scroller") |>
    pz_act_scroll(to = "bottom", duration = 0.1)
  expect_true(
    abs(
      pz_evaluate(page, "document.getElementById('scroller').scrollTop") - 650
    ) <=
      2
  )
  expect_true(pz_evaluate(page, "window.__log.wheels") > wheels)

  page |> pz_record_stop()
})

test_that("wheel_position_settled returns the position once it holds still", {
  loop <- later::create_loop()
  withr::defer(later::destroy_loop(loop))
  ctx <- list(page = list(child_loop = loop))

  reads <- 0L
  settled <- wheel_position_settled(ctx, function() {
    reads <<- reads + 1L
    # Mid-flight for the first few reads, then parked at the target.
    list(left = 0, top = min(reads, 4L))
  })
  expect_gt(reads, 4L)
  expect_identical(settled$top, 4L)
})

test_that("wheel_position_settled falls back to the latest read when never still", {
  loop <- later::create_loop()
  withr::defer(later::destroy_loop(loop))
  ctx <- list(page = list(child_loop = loop))

  reads <- 0L
  start <- Sys.time()
  settled <- wheel_position_settled(ctx, function() {
    reads <<- reads + 1L
    list(left = 0, top = reads)
  })
  elapsed <- as.numeric(difftime(Sys.time(), start, units = "secs"))
  expect_identical(settled$top, reads)
  expect_gte(elapsed, wheel_settle_timeout_secs * 0.9)
})

test_that("staged root offsets and directions correct incomplete wheels", {
  page <- local_cursor_page()
  pz_evaluate(
    page,
    "document.head.insertAdjacentHTML('beforeend', '<style>::-webkit-scrollbar { width:15px; height:15px }</style>');
     document.getElementById('spacer').style.width = '2000px'"
  )
  local_mocked_bindings(stage_wheel = function(...) invisible(TRUE))

  scroll_staged(page, NULL, by = c(120, 300), to = NULL, duration = 0.01)
  expect_equal(
    unlist(pz_evaluate(page, "[window.scrollX, window.scrollY]")),
    c(120, 300)
  )

  scroll_staged(page, NULL, by = c(-40, -100), to = NULL, duration = 0.01)
  expect_equal(
    unlist(pz_evaluate(page, "[window.scrollX, window.scrollY]")),
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
    unlist(pz_evaluate(page, "[window.scrollX, window.scrollY]")),
    unlist(pz_evaluate(
      page,
      "[document.scrollingElement.scrollWidth - document.documentElement.clientWidth, document.scrollingElement.scrollHeight - document.documentElement.clientHeight]"
    ))
  )

  scroll_staged(page, NULL, by = NULL, to = c("left", "top"), duration = 0.01)
  expect_equal(
    unlist(pz_evaluate(page, "[window.scrollX, window.scrollY]")),
    c(0, 0)
  )
})

test_that("staged scoped fallback uses offsets and directions without root serialization", {
  page <- local_cursor_page()
  pz_evaluate(
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
    unlist(pz_evaluate(
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
    unlist(pz_evaluate(
      page,
      "(() => { const s = document.getElementById('scroller'); return [Math.round((s.scrollWidth - s.clientWidth) / 2), Math.round((s.scrollHeight - s.clientHeight) / 2)]; })()"
    ))
  )

  scroll_staged(ctx, scoped, by = NULL, to = c("left", "top"), duration = 0.01)
  expect_equal(position(), c(0, 0))
})

test_that("a nested scroller obstructs a scoped wheel and stays untouched", {
  page <- local_cursor_page()
  pz_evaluate(
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
    pz_evaluate(page, "document.getElementById('scroller').scrollTop"),
    200
  )
  expect_equal(
    pz_evaluate(page, "document.getElementById('inner-scroller').scrollTop"),
    0
  )
  expect_equal(pz_evaluate(page, "window.__log.wheels"), 0)
  expect_equal(pz_evaluate(page, "window.scrollY"), 0)
})

test_that("pz_act_scroll forwards duration to staged wheels for by, to, and target", {
  skip_if_no_av()
  page <- local_cursor_page()
  page <- page |> pz_stage(cursor_speed = 500)
  page |>
    pz_record_start(
      withr::local_tempfile(fileext = ".mp4"),
      fps = 10,
      hold = c(0, 0)
    )

  # Native wheel delivery is covered separately; isolate duration forwarding.
  wheel_durations <- numeric()
  testthat::local_mocked_bindings(
    stage_wheel = function(ctx, point, dx, dy, duration, call = caller_env()) {
      wheel_durations <<- c(wheel_durations, duration)
      invisible(TRUE)
    }
  )

  page |> pz_act_scroll(by = c(0, 300), duration = 0.05)
  expect_equal(pz_evaluate(page, "window.scrollY"), 300)
  expect_true(length(wheel_durations) > 0)
  expect_true(all(wheel_durations == 0.05))
  wheel_durations <- numeric()

  page |> pz_act_scroll(to = "bottom", duration = 0.05)
  expect_equal(
    pz_evaluate(page, "window.scrollY"),
    pz_evaluate(
      page,
      "document.scrollingElement.scrollHeight - document.documentElement.clientHeight"
    )
  )
  expect_true(length(wheel_durations) > 0)
  expect_true(all(wheel_durations == 0.05))
  wheel_durations <- numeric()

  page |> pz_act_scroll(target = "#plain", duration = 0.05)
  expect_true(pz_evaluate(
    page,
    "document.getElementById('plain').getBoundingClientRect().y >= 0"
  ))
  expect_true(length(wheel_durations) > 0)
  expect_true(all(wheel_durations == 0.05))

  before <- pz_evaluate(page, "window.scrollY")
  page |> pz_act_scroll(by = c(0, 0), duration = 0)
  expect_equal(pz_evaluate(page, "window.scrollY"), before)

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
  expect_equal(pz_evaluate(page, "window.scrollY"), 300)

  page |> pz_act_scroll(to = "bottom", duration = 0)
  expect_equal(
    pz_evaluate(page, "window.scrollY"),
    pz_evaluate(
      page,
      "document.scrollingElement.scrollHeight - document.documentElement.clientHeight"
    )
  )

  page |> pz_act_scroll(target = "#plain", duration = 0)
  expect_true(pz_evaluate(
    page,
    "document.getElementById('plain').getBoundingClientRect().y >= 0"
  ))

  expect_equal(pz_evaluate(page, "window.__log.wheels"), 0)

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

  expect_equal(pz_evaluate(page, "window.__log.belowClicks"), 1)
  expect_true(pz_evaluate(page, "window.__log.wheels") > 0)
  expect_true(pz_evaluate(page, "window.scrollY") > 500)
})

test_that("a target visible in a below-the-fold container is wheeled into view", {
  skip_if_no_av()
  page <- local_cursor_page()
  # A scrollable container beyond the fold whose target sits inside its
  # clip: the target is visible to the container yet off-screen, so the
  # auto-scroll must reach past the nearest scrollable ancestor to the
  # document.
  pz_evaluate(
    page,
    r"[
(() => {
  const container = document.createElement('div');
  container.id = 'deep';
  container.style.cssText = 'position:absolute;left:100px;top:calc(100vh + 300px);width:300px;height:250px;overflow:auto;border:1px solid #ccc;';
  const button = document.createElement('button');
  button.id = 'deep-btn';
  button.textContent = 'deep';
  button.style.cssText = 'margin-top:20px;width:120px;height:40px;';
  const tall = document.createElement('div');
  tall.style.cssText = 'height:900px;background:#f8f8f8;';
  container.appendChild(button);
  container.appendChild(tall);
  document.body.appendChild(container);
  button.addEventListener('click', () => window.__log.deepClicks = (window.__log.deepClicks || 0) + 1);
})()
]"
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

  expect_equal(pz_evaluate(page, "window.__log.deepClicks"), 1)
  # Only the document needed scrolling: the container was already
  # showing the target.
  expect_equal(
    pz_evaluate(page, "document.getElementById('deep').scrollTop"),
    0
  )
  expect_true(pz_evaluate(page, "window.scrollY") > 0)
  expect_true(pz_evaluate(page, "window.__log.wheels") > 0)
})

test_that("cursor = FALSE then cursor = NULL restores the auto behavior", {
  skip_if_no_av()
  page <- local_cursor_page()
  page <- page |> pz_stage(cursor = FALSE)
  page |>
    pz_record_start(
      withr::local_tempfile(fileext = ".mp4"),
      fps = 10,
      hold = c(0, 0)
    )

  page |> pz_act_click("#btn")
  # cursor = FALSE never draws, even while recording.
  expect_null(cursor_overlay_state(page))

  page <- page |> pz_stage(cursor = NULL)
  page |> pz_act_click("#btn")
  # The NULL restored the default: auto draws while recording.
  st <- cursor_overlay_state(page)
  expect_equal(st[[1]], 1)
  expect_equal(st[2:3], c(660, 322))

  page |> pz_record_stop()

  expect_equal(pz_evaluate(page, "window.__log.clicks"), 2)
})

test_that("recording reconciles overlay visibility from the recording context", {
  skip_if_no_av()
  page <- local_cursor_page()
  # An explicit show leaves the overlay drawn; cursor = FALSE staged on
  # the recording chain means it must not appear in the video either.
  page |> pz_cursor_show("#btn")
  staged <- page |> pz_stage(cursor = FALSE)

  staged |>
    pz_record_start(
      withr::local_tempfile(fileext = ".mp4"),
      fps = 10,
      hold = c(0, 0)
    ) |>
    pz_act_click("#btn")
  expect_equal(cursor_overlay_state(page)[[1]], 0)

  page |> pz_record_stop()
})

test_that("a nested scroller over the viewport center never eats root wheels", {
  skip_if_no_av()
  # A FIXED scroller over the viewport center stays over it at every
  # scroll position and would consume every wheel aimed at the
  # document; with no point that reaches the container, the instant
  # application must run before any wheel fires, so recorded and
  # unrecorded chains end in the identical state.
  cover_center <- function(page) {
    pz_evaluate(
      page,
      r"[
(() => {
  const container = document.createElement('div');
  container.id = 'center-scroller';
  container.style.cssText = 'position:fixed;left:calc(50% - 150px);top:calc(50% - 100px);width:300px;height:200px;overflow:auto;';
  const tall = document.createElement('div');
  tall.style.cssText = 'height:2000px;background:#f8f8f8;';
  container.appendChild(tall);
  document.body.appendChild(container);
})()
]"
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
  expect_equal(pz_evaluate(page, "window.scrollY"), 400)

  # Not one wheel fired: the scroll was applied instantly, and the
  # covering scroller is untouched.
  expect_equal(pz_evaluate(page, "window.__log.wheels"), 0)
  expect_equal(
    pz_evaluate(page, "document.getElementById('center-scroller').scrollTop"),
    0
  )

  # The auto-scroll before an action hits the same fallback: the fixed
  # scroller still covers every root wheel point.
  page |> pz_act_click("#below")
  expect_equal(pz_evaluate(page, "window.__log.belowClicks"), 1)
  expect_equal(pz_evaluate(page, "window.__log.wheels"), 0)
  expect_equal(
    pz_evaluate(page, "document.getElementById('center-scroller').scrollTop"),
    0
  )

  page |> pz_record_stop()
  recorded <- c(
    scrollY = pz_evaluate(page, "window.scrollY"),
    scoped = pz_evaluate(
      page,
      "document.getElementById('center-scroller').scrollTop"
    )
  )

  page2 <- local_cursor_page()
  cover_center(page2)
  page2 |> pz_act_scroll(by = c(0, 400))
  page2 |> pz_act_click("#below")
  unrecorded <- c(
    scrollY = pz_evaluate(page2, "window.scrollY"),
    scoped = pz_evaluate(
      page2,
      "document.getElementById('center-scroller').scrollTop"
    )
  )

  expect_equal(recorded, unrecorded)
})

test_that("an off-screen scope is brought into view with staged wheels too", {
  skip_if_no_av()
  page <- local_cursor_page()
  pz_evaluate(
    page,
    r"[
(() => {
  const container = document.createElement('div');
  container.id = 'deep-scope';
  container.style.cssText = 'position:absolute;left:100px;top:calc(100vh + 300px);width:300px;height:250px;overflow:auto;border:1px solid #ccc;';
  const tall = document.createElement('div');
  tall.style.cssText = 'height:900px;background:#f8f8f8;';
  container.appendChild(tall);
  document.body.appendChild(container);
})()
]"
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

  expect_true(pz_evaluate(page, "window.__log.wheels") > 0)
  expect_equal(
    pz_evaluate(page, "document.getElementById('deep-scope').scrollTop"),
    0
  )
  expect_true(pz_evaluate(page, "window.scrollY") > 0)
})

test_that("the stage pause holds after each action only while recording", {
  skip_if_no_av()
  page <- local_cursor_page()
  page <- page |> pz_stage(pause = 0.5)
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
  page2 <- page2 |> pz_stage(pause = 0.5)
  page2 |> pz_act_click("#btn")
  expect_equal(pz_evaluate(page2, "window.__log.clicks"), 1)
})

test_that("the stage pause holds after focus and root or scoped blur", {
  skip_if_no_av()
  page <- local_cursor_page()
  # Distinctive pause value: identifiable among the actions' other pumps.
  page <- page |> pz_stage(pause = 0.37)
  page |>
    pz_record_start(
      withr::local_tempfile(fileext = ".mp4"),
      fps = 10,
      hold = c(0, 0)
    )

  field <- pz_find(page, "#name")
  # record_stop() is safe under the mock: its drain polls run on
  # later::run_now(), not pump_loop, and there are no camera keyframes.
  pauses <- numeric()
  local_mocked_bindings(
    pump_loop = function(loop, duration, ...) {
      pauses <<- c(pauses, duration)
    }
  )

  page |> pz_act_focus("#name")
  expect_true(pz_evaluate(page, "document.activeElement.id === 'name'"))
  expect_equal(tail(pauses, 1), 0.37)

  pauses <- numeric()
  page |> pz_act_blur()
  expect_false(pz_evaluate(page, "document.activeElement.id === 'name'"))
  expect_equal(tail(pauses, 1), 0.37)

  pauses <- numeric()
  field |> pz_act_focus()
  expect_equal(tail(pauses, 1), 0.37)

  pauses <- numeric()
  field |> pz_act_blur()
  expect_equal(tail(pauses, 1), 0.37)

  page |> pz_record_stop()

  # Not recording: no pause pumps at all (the mock above still stands).
  pauses <- numeric()
  page |> pz_act_focus("#name")
  page |> pz_act_blur()
  field |> pz_act_focus()
  field |> pz_act_blur()
  expect_length(pauses, 0)
})

test_that("the stage pause holds after root typing without a target", {
  skip_if_no_av()
  page <- local_cursor_page()
  page <- page |>
    pz_stage(pause = 0.5, typing = "instant", camera_follow = FALSE)
  page |> pz_act_focus("#name")
  page |>
    pz_record_start(
      withr::local_tempfile(fileext = ".mp4"),
      fps = 10,
      hold = c(0, 0)
    )

  pauses <- numeric()
  with_mocked_bindings(
    pump_loop = function(loop, duration, ...) {
      pauses <<- c(pauses, duration)
    },
    page |> pz_act_type("a")
  )
  page |> pz_record_stop()

  expect_equal(pz_get_value(page, target = "#name"), "a")
  expect_equal(tail(pauses, 1), 0.5)

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
  page <- page |> pz_stage(pause = pause)
  page |>
    pz_record_start(
      withr::local_tempfile(fileext = ".mp4"),
      fps = 10,
      hold = c(0, 0)
    )

  defer_record_stop(page)
  page |> pz_act_click("#name")
  holds <- numeric()
  local_mocked_bindings(
    pump_loop = function(loop, duration, ...) {
      holds <<- c(holds, duration)
    }
  )

  page |> pz_act_press("a")
  expect_equal(tail(holds, 1), pause)
  expect_equal(pz_get_value(page, target = "#name"), "a")

  holds <- numeric()
  page |> pz_act_select_text("Go", target = "#btn")
  expect_equal(tail(holds, 1), pause)
  expect_equal(pz_evaluate(page, "window.getSelection().toString()"), "Go")

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

  # The recorder's first capture is its slowest (cold renderer on a
  # fresh page); warm the pipeline before the actions begin.
  rec <- page_recorder(page)
  pz_poll(
    function() length(rec$files) >= 1L,
    timeout = 5,
    loop = page$page$child_loop,
    what = "a baseline frame before the entrance glide"
  )

  page |> pz_act_click("#btn")

  # The click leaves the cursor drawn at the button until the next
  # action, so wait until a retained frame carries its ink there.
  # (Typing would glide the cursor to #name and hide it while the
  # characters land.) The glide's schedule and off-frame start are
  # pinned by the overlay-level entrance tests in test-cursor.R;
  # sampling ink mid-glide would race the capture pump against the
  # animation's wall clock, and a failure would implicate the test's
  # own timing rather than the product.
  scanned <- 0L
  pz_poll(
    function() {
      if (length(rec$files) <= scanned) {
        return(FALSE)
      }
      fresh <- rec$files[seq.int(scanned + 1L, length(rec$files))]
      scanned <<- length(rec$files)
      any(vapply(
        fresh,
        function(f) {
          ink <- cursor_png_ink(
            page,
            f,
            band = c(300, 344),
            x_range = c(635, 700)
          )
          ink$count > 20 && abs(ink$x - 660) < 25 && abs(ink$y - 322) < 20
        },
        logical(1)
      ))
    },
    timeout = 5,
    loop = page$page$child_loop,
    what = "cursor ink at the button in a retained frame"
  )

  page |>
    pz_act_type("otters", target = "#name") |>
    pz_act_click("#below") |>
    pz_record_stop()

  expect_equal(pz_evaluate(page, "window.__log.clicks"), 1)
  expect_equal(pz_evaluate(page, "window.__log.belowClicks"), 1)
  expect_equal(
    pz_evaluate(page, "document.getElementById('name').value"),
    "otters"
  )
  expect_equal(pz_evaluate(page, "window.__log.inputs.name"), 6)
  expect_true(pz_evaluate(page, "window.__log.wheels") > 0)

  # The auto cursor belonged to the recording and left with it.
  expect_equal(cursor_overlay_state(page)[[1]], 0)

  info <- recorded_video_info(out)
  expect_true(info$duration >= 1.5)

  frames_dir <- paste0(tools::file_path_sans_ext(out), "_frames")
  on.exit(unlink(frames_dir, recursive = TRUE), add = TRUE)
  frames <- list.files(frames_dir, full.names = TRUE)
  expect_true(length(frames) >= 10)

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

  page |>
    pz_stage(enter = "left") |>
    pz_act_click("#btn") |>
    pz_act_type("otters", target = "#name") |>
    pz_act_click("#below")

  expect_equal(pz_evaluate(page, "window.__log.clicks"), 1)
  expect_equal(pz_evaluate(page, "window.__log.belowClicks"), 1)
  expect_equal(
    pz_evaluate(page, "document.getElementById('name').value"),
    "otters"
  )

  # No staging happened: one insertion, no wheels, no cursor layer.
  expect_equal(pz_evaluate(page, "window.__log.inputs.name"), 1)
  expect_equal(pz_evaluate(page, "window.__log.wheels"), 0)
  expect_null(cursor_overlay_state(page))
})

test_that("click_effect and click_effect_color stage, validate, and reset", {
  page <- local_cursor_page()
  staged <- page

  expect_identical(ctx_stage(staged)$click_effect, "press")
  expect_identical(ctx_stage(staged)$click_effect_color, "#e11d48")

  for (effect in c("ring", "none", "press")) {
    staged <- pz_stage(staged, click_effect = effect)
    expect_identical(ctx_stage(staged)$click_effect, effect)
  }

  expect_error(pz_stage(page, click_effect = "slide"), class = "rlang_error")

  staged <- pz_stage(staged, click_effect_color = "#2563eb")
  expect_identical(ctx_stage(staged)$click_effect_color, "#2563eb")
  expect_error(
    pz_stage(page, click_effect_color = ""),
    "click_effect_color.*empty string"
  )
  expect_error(pz_stage(page, click_effect_color = 7), class = "rlang_error")

  staged <- pz_stage(staged, click_effect = NULL, click_effect_color = NULL)
  expect_identical(ctx_stage(staged)$click_effect, "press")
  expect_identical(ctx_stage(staged)$click_effect_color, "#e11d48")
})

test_that("show_keys defaults to none and restores its staged default", {
  page <- local_record_page()
  staged <- page

  expect_identical(ctx_stage(staged)$show_keys, "none")

  for (style in c("words", "mac", "both")) {
    staged <- pz_stage(staged, show_keys = style)
    expect_identical(ctx_stage(staged)$show_keys, style)
  }

  expect_error(pz_stage(page, show_keys = "nope"), "nope")
  staged <- pz_stage(staged, show_keys = NULL)
  expect_identical(ctx_stage(staged)$show_keys, "none")
})

test_that("pz_stage_annotate stages fill, text color, stroke width and distance", {
  page <- local_cursor_page()

  expect_null(ctx_stage(page)$annotate_fill)
  expect_null(ctx_stage(page)$annotate_text_color)
  expect_error(pz_stage_annotate(page, fill = ""), "fill.*empty string")
  expect_error(
    pz_stage_annotate(page, text_color = ""),
    "text_color.*empty string"
  )
  expect_error(pz_stage_annotate(page, stroke_width = 0), "stroke_width")
  expect_error(pz_stage_annotate(page, stroke_width = -1), "stroke_width")
  expect_error(pz_stage_annotate(page, distance = -1), "distance")
  expect_identical(ctx_stage(page), STAGE_DEFAULTS)

  staged <- page |>
    pz_stage_annotate(
      fill = "red",
      text_color = "black",
      stroke_width = 5,
      distance = 30
    )
  expect_identical(ctx_stage(staged)$annotate_fill, "red")
  expect_identical(ctx_stage(staged)$annotate_text_color, "black")
  expect_identical(ctx_stage(staged)$annotate_stroke_width, 5)
  expect_identical(ctx_stage(staged)$annotate_distance, 30)

  staged <- staged |> pz_stage_annotate()
  expect_identical(ctx_stage(staged)$annotate_fill, "red")
  expect_identical(ctx_stage(staged)$annotate_distance, 30)

  staged <- staged |>
    pz_stage_annotate(
      fill = NULL,
      text_color = NULL,
      stroke_width = NULL,
      distance = NULL
    )
  expect_identical(
    ctx_stage(staged)$annotate_fill,
    STAGE_DEFAULTS$annotate_fill
  )
  expect_identical(
    ctx_stage(staged)$annotate_text_color,
    STAGE_DEFAULTS$annotate_text_color
  )
  expect_identical(
    ctx_stage(staged)$annotate_stroke_width,
    STAGE_DEFAULTS$annotate_stroke_width
  )
  expect_identical(
    ctx_stage(staged)$annotate_distance,
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

test_that("pz_inspect returns its context invisibly and drops into chains", {
  page <- local_inspect_page()
  got <- inspect_capture(function() pz_inspect(page))
  expect_identical(got$value, page)
  expect_false(got$visible)

  # Mid-chain: the context flows through untouched.
  capture.output(ctx <- page |> pz_find("#insp-list") |> pz_inspect())
  expect_s3_class(ctx, "PaparazziContext")
  expect_identical(length(ctx$scope), 1L)
  expect_identical(pz_get_count(ctx, target = ".insp-item"), 12L)
})

test_that("the console summary matches the spec format", {
  page <- local_inspect_page()
  withr::local_options(cli.width = 400)
  got <- inspect_capture(function() pz_inspect(page))

  expect_length(got$out, 5L)
  expect_match(got$out[[1]], "^── paparazzi page ─+$")
  expect_match(got$out[[2]], "^URL        file:")
  inner <- unlist(pz_js(page, "[window.innerWidth, window.innerHeight, window.devicePixelRatio]"))
  dpr <- inner[[3]]
  scale <- if (dpr == round(dpr)) sprintf("%gx", as.integer(dpr)) else paste0(dpr, "x")
  expect_identical(
    got$out[[3]],
    sprintf("%-11s%s × %s @%s · light", "Device", inner[[1]], inner[[2]], scale)
  )
  expect_identical(got$out[[4]], "Scope      root")
  expect_identical(got$out[[5]], "Recording  off · cursor hidden")
  # No target, no warnings, no visuals by default (tests aren't interactive).
  expect_length(got$msgs, 0L)
})

test_that("the scope stack renders with live match counts", {
  page <- local_inspect_page()
  ctx <- page |> pz_find("#insp-list") |> pz_find(".insp-item")
  got <- inspect_capture(function() pz_inspect(ctx))

  expect_identical(
    got$out[[4]],
    "Scope      root › `#insp-list` (1) › `.insp-item` (12)"
  )
  # A narrowed scope compacts its which-qualifier for display.
  narrow <- pz_find_nth(ctx, 2)
  got <- inspect_capture(function() pz_inspect(narrow))
  expect_identical(
    got$out[[4]],
    "Scope      root › `#insp-list` (1) › `.insp-item` (12) › `.insp-item` #2 (1)"
  )
})

test_that("stale pinned elements warn without aborting", {
  page <- local_inspect_page()
  withr::local_options(cli.width = 400)
  ctx <- pz_find(page, "#insp-btn")

  # Detached, but the pinned set still resolves: (live of pinned) + warning.
  pz_js(page, "document.getElementById('insp-btn').remove()")
  got <- inspect_capture(function() pz_inspect(ctx))
  expect_identical(got$out[[4]], "Scope      root › `#insp-btn` (0 of 1)")
  expect_identical(got$value, ctx)
  expect_length(got$msgs, 1L)
  expect_match(got$msgs[[1]], "no longer in the page")

  # Released object group (e.g. a context that outlived a navigation):
  # the whole scope reads as gone. (#insp-btn was removed above, so pin a
  # scope that still exists and release its objects manually.)
  ctx <- pz_find(page, "#insp-list")
  page$release_object_group()
  got <- inspect_capture(function() pz_inspect(ctx))
  expect_identical(got$out[[4]], "Scope      root › `#insp-list` (gone)")
  expect_length(got$msgs, 1L)
  expect_match(got$msgs[[1]], "no longer resolves")
})

test_that("target matches resolve once, without auto-waiting", {
  page <- local_inspect_page()
  # .insp-late arrives after 5s; auto-waiting would hold the call for it.
  got <- inspect_capture(function() pz_inspect(page, ".insp-late"))
  expect_identical(got$out[[5]], "Target     `.insp-late` → no matches")
  expect_length(got$out, 6L)
  expect_identical(got$value, page)
})

test_that("targets resolve relative to the current scope", {
  page <- local_inspect_page()
  ctx <- pz_find(page, "#insp-list")
  got <- inspect_capture(function() pz_inspect(ctx, ".insp-item"))
  expect_identical(got$out[[5]], "Target     `.insp-item` → 12 matches")

  # The buttons are outside the scope: no match, no wait.
  got <- inspect_capture(function() pz_inspect(ctx, "button"))
  expect_identical(got$out[[5]], "Target     `button` → no matches")
})

test_that("each match shows a short tag and its state", {
  page <- local_inspect_page()
  got <- inspect_capture(function() pz_inspect(page, "#insp-btn"))
  expect_identical(got$out[[5]], "Target     `#insp-btn` → 1 match")
  expect_identical(
    got$out[[6]],
    '  1  <button id="insp-btn" class="insp-btn" aria-label="Actions">'
  )
  expect_identical(got$out[[7]], "     visible · enabled · at 300,300 · 80 × 30")

  got <- inspect_capture(function() pz_inspect(page, "#insp-hidden"))
  expect_identical(got$out[[6]], '  1  <div id="insp-hidden" class="insp-hidden">')
  expect_identical(got$out[[7]], "     hidden · enabled · at 0,0 · 0 × 0")

  got <- inspect_capture(function() pz_inspect(page, "#insp-disabled"))
  expect_match(got$out[[7]], "^     visible · disabled ·")
})

test_that("long match lists are truncated", {
  page <- local_inspect_page()
  got <- inspect_capture(function() pz_inspect(page, ".insp-item"))
  expect_identical(got$out[[5]], "Target     `.insp-item` → 12 matches")
  rows <- grep("^  [0-9]+  ", got$out)
  expect_length(rows, 10L)
  expect_true(any(grepl("^  10  ", got$out)))
  expect_false(any(grepl("^  11  ", got$out)))
  expect_true(any(got$out == "     … and 2 more"))
  # The recording line still closes the block after the truncation.
  expect_identical(got$out[[length(got$out)]], "Recording  off · cursor hidden")
})

test_that("show = screenshot annotates, captures, and cleans up", {
  page <- local_inspect_page()
  withr::local_options(cli.width = 1000)
  path <- withr::local_tempfile(fileext = ".png")
  ctx <- pz_find(page, "#insp-list")
  got <- inspect_capture(function() {
    pz_inspect(ctx, target = ".insp-item", show = "screenshot", path = path)
  })

  expect_true(file.exists(path))
  expect_length(got$msgs, 1L)
  expect_match(got$msgs[[1]], "Annotated screenshot")

  # Dashed scope outlines AND solid numbered target outlines are in the
  # annotated capture.
  counts <- inspect_png_colors(
    page,
    path,
    list(inspect_color_scope, inspect_color_target)
  )
  expect_gt(counts[[1]], 0)
  expect_gt(counts[[2]], 0)

  # The outline layer is removed after the capture: the page is clean.
  expect_identical(inspect_overlay_count(page), 0L)
  # And a plain screenshot of the same region has no outline pixels.
  plain <- withr::local_tempfile(fileext = ".png")
  pz_screenshot(ctx, plain, target = ".insp-item")

  counts <- inspect_png_colors(
    page,
    plain,
    list(inspect_color_scope, inspect_color_target)
  )
  expect_equal(counts, c(0, 0))
})

test_that("show = screenshot writes a temp file and prints its path", {
  page <- local_inspect_page()
  withr::local_options(cli.width = 1000)
  got <- inspect_capture(function() pz_inspect(page, show = "screenshot"))
  m <- regmatches(
    got$msgs[[1]],
    regexpr("Annotated screenshot: '([^']+)'", got$msgs[[1]])
  )
  expect_length(m, 1L)
  path <- sub(".*'([^']+)'.*", "\\1", m)
  expect_true(file.exists(path))
  expect_match(path, "\\.png$")
})

test_that("outlines drawn into the page never appear in pz_screenshot", {
  page <- local_inspect_page()
  # Draw outlines over #insp-plain and leave them, as show = "browser" does.
  rects <- tibble::tibble(x = 0, y = 0, width = 200, height = 200)
  overlay_draw(page, rects, rects)
  expect_gt(inspect_overlay_count(page), 0L)

  path <- withr::local_tempfile(fileext = ".png")
  pz_screenshot(page, path, target = "#insp-plain")
  counts <- inspect_png_colors(
    page,
    path,
    list(inspect_color_scope, inspect_color_target)
  )
  expect_equal(counts, c(0, 0))

  # The guard restores the host: the outlines are still live in the page.
  expect_false(identical(inspect_overlay_display(page), "none"))
  expect_gt(inspect_overlay_count(page), 0L)
})

test_that("the overlay host is invisible to resolution and drawing replaces it", {
  page <- local_inspect_page()
  before <- pz_get_count(page, target = "div")

  rects <- tibble::tibble(x = 0, y = 0, width = 100, height = 100)
  overlay_draw(page, rects, rects)
  expect_identical(pz_get_count(page, target = "div"), before)
  # The resolver excludes everything under the overlay host, including
  # the host itself.
  expect_identical(pz_get_count(page, target = "#paparazzi-overlay-root"), 0L)

  # Drawing again replaces the layer rather than stacking (one scope
  # box, one target box, one numbered badge).
  overlay_draw(page, rects, rects)
  expect_identical(inspect_overlay_count(page), 3L)

  overlay_clear(page)
  expect_identical(inspect_overlay_count(page), 0L)
})

test_that("print() shows the summary without the target section or visuals", {
  page <- local_inspect_page()
  got <- inspect_capture(function() print(page))
  expect_length(got$out, 5L)
  expect_match(got$out[[1]], "^── paparazzi page ─+$")
  expect_match(got$out[[2]], "^URL        file:")
  expect_match(got$out[[3]], "^Device     ")
  expect_identical(got$out[[4]], "Scope      root")
  expect_identical(got$out[[5]], "Recording  off · cursor hidden")
  expect_false(any(grepl("Target", got$out)))

  ctx <- page |> pz_find("#insp-list") |> pz_find(".insp-item")
  got <- inspect_capture(function() print(ctx))
  expect_identical(
    got$out[[4]],
    "Scope      root › `#insp-list` (1) › `.insp-item` (12)"
  )
  expect_false(any(grepl("Target", got$out)))

  # A closed page stays a one-liner.
  pz_close(page)
  got <- inspect_capture(function() print(page))
  expect_identical(got$out, "<PaparazziPage: closed>")
})

test_that("pz_inspect validates its input", {
  page <- local_inspect_page()
  expect_error(pz_inspect(page, show = "poster"), class = "rlang_error")
  expect_error(pz_inspect(1), class = "paparazzi_error_context")
  expect_error(
    pz_inspect(page, path = "x.png"),
    class = "paparazzi_error_input"
  )
  expect_error(
    pz_inspect(page, show = "screenshot", path = 1),
    class = "rlang_error"
  )
  expect_error(pz_inspect(page, "oops" = 1), class = "rlang_error")
})

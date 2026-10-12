test_that("the retained-pixel instrument distinguishes the task marker color", {
  skip_if_no_av()
  page <- local_task_page(width = 800, height = 900)
  drag_preview_task_marker(page)
  out <- withr::local_tempfile(fileext = '.mp4')
  frames <- paste0(tools::file_path_sans_ext(out), '_frames')
  withr::defer(unlink(frames, recursive = TRUE))
  pz_record_start(page, out, fps = 30, hold = c(0, 0), keep_frames = TRUE)
  defer_record_stop(page)
  path <- drag_preview_retained_checkpoint(
    page,
    verify = drag_preview_marker_present(page)
  )
  marker <- pz_js(
    page,
    "(() => { const r = document.querySelector('#preview-marker').getBoundingClientRect(); return {x:r.x,y:r.y,width:r.width,height:r.height}; })()"
  )
  green <- drag_preview_marker_box(page, path)
  expect_false(is.null(green))
  expect_lt(
    max(abs(unlist(green[c('x', 'y', 'width', 'height')]) - unlist(marker))),
    1.5
  )
  # Deliberately incorrect color is a passing negative control: a broken or
  # non-discriminating instrument cannot pass both of these assertions.
  expect_null(drag_preview_marker_box(page, path, color = c(220, 20, 180)))
  pz_js(
    page,
    "document.querySelector('#preview-marker').style.background = 'rgb(220,20,180)'"
  )
  changed <- drag_preview_retained_checkpoint(
    page,
    verify = drag_preview_marker_present(page, color = c(220, 20, 180))
  )
  expect_null(drag_preview_marker_box(page, changed))
  expect_false(is.null(drag_preview_marker_box(
    page,
    changed,
    color = c(220, 20, 180)
  )))
  pz_record_stop(page)
  expect_true(file.exists(path))
})

test_that('disabled previews retain the original marker but never carry it', {
  skip_if_no_av()
  page <- local_task_page(width = 800, height = 900)
  pz_stage(page, pause = 0)
  drag_preview_task_marker(page)
  out <- withr::local_tempfile(fileext = '.mp4')
  frames <- paste0(tools::file_path_sans_ext(out), '_frames')
  withr::defer(unlink(frames, recursive = TRUE))
  pz_record_start(page, out, fps = 30, hold = c(0, 0), keep_frames = TRUE)
  defer_record_stop(page)
  original <- drag_preview_retained_checkpoint(
    page,
    verify = drag_preview_marker_present(page)
  )
  expect_false(is.null(drag_preview_marker_box(page, original)))
  carried <- NULL
  local_mocked_bindings(
    drag_preview_boot_js = function() {
      stop('disabled preview loaded its library')
    },
    stage_drag_carry = function(ctx, from, to, step) {
      point <- (from + to) / 2 + c(x = 80, y = 0)
      cursor_apply(ctx, point, pressed = TRUE)
      step(point)
      carried <<- drag_preview_retained_checkpoint(
        ctx,
        verify = drag_preview_marker_absent(ctx)
      )
    }
  )
  expect_no_warning(pz_act_drag(
    page,
    '#preview-source .task-drag-handle',
    '#preview-target .task-drag-handle',
    preview = FALSE
  ))
  expect_null(drag_preview_marker_box(page, carried))
  expect_true(drag_preview_absent(page))
  expect_true(pz_js(
    page,
    "document.querySelectorAll('.task')[1] === window.__previewSource"
  ))
  pz_record_stop(page)
  expect_true(file.exists(carried))
})

test_that('retained carry and settle pixels follow the same task row for to and by', {
  skip_if_no_av()
  # These cover both cursor entry positions and both HTML5 destination routes.
  # The third repeats the pixel proof with all geometry modifiers together.
  cases <- list(
    list(parked = TRUE, by = FALSE, geometry = FALSE),
    list(parked = FALSE, by = TRUE, geometry = FALSE),
    list(parked = TRUE, by = FALSE, geometry = TRUE)
  )
  capture <- function(case) {
    page <- local_task_page(
      width = 1000,
      height = 1100,
      scale = if (case$geometry) 2 else 1
    )
    pz_stage(page, pause = 0, cursor_speed = 120)
    drag_preview_task_marker(page)
    if (case$geometry) {
      pz_js(
        page,
        "document.documentElement.style.zoom = '1.1'; document.body.style.paddingTop = '220px'; document.body.style.minHeight = '2000px'; window.scrollTo(0,150)"
      )
      expect_equal(page_dpr(page), 2)
      expect_gt(pz_js(page, 'window.scrollY'), 0)
    }
    source <- '#preview-source .task-drag-handle'
    out <- withr::local_tempfile(fileext = '.mp4')
    frames <- paste0(tools::file_path_sans_ext(out), '_frames')
    withr::defer(unlink(frames, recursive = TRUE))
    frame <- if (case$geometry) {
      pz_frame('.task-list-frame', pad = 16, when = 'start')
    } else {
      NULL
    }
    geometry_frame <- if (case$geometry) {
      pz_js(
        page,
        "(() => { const r = document.querySelector('.task-list-frame').getBoundingClientRect(); return {x:r.x-16,y:r.y-16,width:r.width+32,height:r.height+32}; })()"
      )
    } else {
      NULL
    }
    pz_record_start(
      page,
      out,
      fps = 30,
      hold = c(0, 0),
      frame = frame,
      keep_frames = TRUE
    )
    defer_record_stop(page)
    if (case$parked) {
      pz_cursor_move(page, source, duration = 0)
    } else {
      pz_cursor_move(page, '#task-title', duration = 0)
    }
    initial <- pz_js(
      page,
      "(() => {
      const r = window.__previewSource.getBoundingClientRect();
      const m = document.querySelector('#preview-marker').getBoundingClientRect();
      return {x:r.x,y:r.y,width:r.width,height:r.height,dx:m.x-r.x,dy:m.y-r.y,mw:m.width,mh:m.height};
    })()"
    )
    original <- drag_preview_retained_checkpoint(
      page,
      verify = drag_preview_marker_present(page)
    )
    expect_false(is.null(drag_preview_marker_box(page, original)))
    carried <- mid <- endpoint <- NULL
    carry_expected <- settle_expected <- settle_start <- final <- target <- NULL
    pointer <- NULL
    original_boot <- drag_preview_boot_js
    original_settle <- drag_preview_settle
    original_pause <- stage_action_pause
    original_carry <- stage_drag_carry
    paused_clean <- FALSE
    local_mocked_bindings(
      stage_action_pause = function(ctx) {
        expect_true(drag_preview_absent(ctx))
        paused_clean <<- TRUE
        original_pause(ctx)
      },
      drag_preview_boot_js = function() {
        drag_preview_counted_boot(original_boot)
      },
      stage_drag_carry = function(ctx, from, to, step) {
        sampled <- FALSE
        pointer <<- to
        original_carry(ctx, from, to, function(point) {
          step(point)
          fraction <- (point[['y']] - from[['y']]) / (to[['y']] - from[['y']])
          if (!sampled && fraction > 0.55) {
            sampled <<- TRUE
            carry_expected <<- c(
              x = initial$x + point[['x']] - from[['x']] + initial$dx,
              y = initial$y + point[['y']] - from[['y']] + initial$dy
            )
            carried <<- drag_preview_retained_checkpoint(
              ctx,
              verify = drag_preview_marker_at(ctx, carry_expected)
            )
          }
        })
        expect_true(sampled)
      },
      drag_preview_settle = function(state) {
        start_box <- pz_js(
          page,
          paste0(
            '(() => {const r = ',
            DRAG_PREVIEW_CONTROLLER_JS,
            '.image.getBoundingClientRect();return {x:r.x,y:r.y};})()'
          )
        )
        settle_start <<- unlist(start_box) + c(x = initial$dx, y = initial$dy)
        duration <- original_settle(state)
        expect_gt(duration, 0)
        sample <- pz_js(
          page,
          paste0(
            "(() => { const p = ",
            DRAG_PREVIEW_CONTROLLER_JS,
            ";
          const a = p.image.getAnimations()[0]; a.pause(); a.currentTime = 90;
          const r = p.source.getBoundingClientRect();
          const t = document.querySelector('#preview-target').getBoundingClientRect();
          return {source:{x:r.x,y:r.y},target:{x:t.x,y:t.y}, same:p.source === window.__previewSource,
            attached:p.source.isConnected, cssWidth:parseFloat(p.image.style.width), cssHeight:parseFloat(p.image.style.height)};
        })()"
          )
        )
        expect_true(sample$same)
        expect_true(sample$attached)
        expect_lt(abs(sample$cssWidth - initial$width), 0.01)
        expect_lt(abs(sample$cssHeight - initial$height), 0.01)
        final <<- unlist(sample$source)
        target <<- unlist(sample$target)
        expect_gt(abs(final[['y']] - target[['y']]), initial$height / 2)
        # Flush the paused WAAPI sample, then measure and retain actual pixels.
        pump_loop(page$child_loop, 0.04)
        box <- pz_js(
          page,
          paste0(
            "(() => {const r = ",
            DRAG_PREVIEW_CONTROLLER_JS,
            ".image.getBoundingClientRect();return {x:r.x,y:r.y};})()"
          )
        )
        settle_expected <<- unlist(box) + c(x = initial$dx, y = initial$dy)
        mid <<- drag_preview_retained_checkpoint(
          page,
          verify = drag_preview_marker_at(page, settle_expected)
        )
        pz_js(
          page,
          paste0(
            '(() => { const p = ',
            DRAG_PREVIEW_CONTROLLER_JS,
            '; p.image.getAnimations()[0].currentTime = 180; })()'
          )
        )
        endpoint <<- drag_preview_retained_checkpoint(
          page,
          verify = drag_preview_marker_at(
            page,
            final + c(x = initial$dx, y = initial$dy)
          )
        )
        pz_js(
          page,
          paste0(DRAG_PREVIEW_CONTROLLER_JS, '.image.getAnimations()[0].play()')
        )
        duration
      }
    )
    if (case$by) {
      from <- setNames(element_center(page, source), c('x', 'y'))
      to <- setNames(
        element_center(page, '#preview-target .task-drag-handle'),
        c('x', 'y')
      )
      expect_no_warning(pz_act_drag(page, source, by = unname(to - from)))
    } else {
      expect_no_warning(pz_act_drag(
        page,
        source,
        '#preview-target .task-drag-handle'
      ))
    }
    expect_true(paused_clean)
    carried_box <- drag_preview_marker_box(page, carried)
    image_box <- drag_preview_marker_box(page, carried, color = c(80, 40, 230))
    expect_false(is.null(image_box))
    expect_lt(
      abs(image_box$x - carry_expected[['x']] - 30 * initial$mw / 20),
      1.5
    )
    expect_lt(abs(image_box$y - carry_expected[['y']]), 1.5)
    mid_box <- drag_preview_marker_box(page, mid)
    end_box <- drag_preview_marker_box(page, endpoint)
    for (box in list(carried_box, mid_box, end_box)) {
      expect_false(is.null(box))
      expect_lt(
        max(abs(unlist(box[c('width', 'height')]) - c(initial$mw, initial$mh))),
        2
      )
    }
    expect_lt(max(abs(unlist(carried_box[c('x', 'y')]) - carry_expected)), 1.5)
    expect_lt(max(abs(unlist(mid_box[c('x', 'y')]) - settle_expected)), 1.5)
    resting_marker <- final + c(x = initial$dx, y = initial$dy)
    expect_lt(max(abs(unlist(end_box[c('x', 'y')]) - resting_marker)), 1.5)
    # A midpoint is neither the carried start nor a snap to the drop target.
    expect_gt(sum((settle_expected - resting_marker)^2), 1)
    expect_lt(
      sum((settle_expected - resting_marker)^2),
      sum((settle_start - resting_marker)^2)
    )
    expect_true(drag_preview_absent(page))
    expect_false(page_cursor(page)$pressed)
    expect_equal(c(x = page_cursor(page)$x, y = page_cursor(page)$y), pointer)
    expect_true(pz_js(
      page,
      "document.querySelectorAll('.task')[1] === window.__previewSource"
    ))
    expect_equal(
      unlist(pz_js(
        page,
        "Array.from(document.querySelectorAll('.task-title')).slice(0,3).map(n => n.textContent.trim())"
      )),
      c('File tax return', 'Renew passport', 'Book dentist appointment')
    )
    expect_equal(pz_js(page, 'window.__previewCaptures'), 1)
    events <- pz_js(page, 'window.__previewEvents')
    drop <- events[vapply(
      events,
      function(e) identical(e$type, 'drop'),
      logical(1)
    )]
    expect_length(drop, 1)
    expect_true(drop[[1]]$trusted)
    expect_identical(
      drop[[1]]$payload,
      pz_js(page, 'window.__previewSource.dataset.id')
    )
    cleaned <- drag_preview_retained_checkpoint(
      page,
      verify = drag_preview_marker_absent(page)
    )
    expect_null(drag_preview_marker_box(page, cleaned))
    rec <- page_recorder(page)
    pz_record_stop(page)
    expect_true(all(file.exists(c(carried, mid, endpoint, cleaned))))
    if (case$geometry) {
      # Decode the actual encoded output as well as its full retained PNGs.
      decoded <- tempfile('preview-decoded-')
      withr::defer(unlink(decoded, recursive = TRUE))
      invisible(utils::capture.output(
        invisible(av::av_video_images(
          out,
          destdir = decoded,
          format = 'png',
          fps = 30
        )),
        type = 'message'
      ))
      files <- list.files(decoded, pattern = '[.]png$', full.names = TRUE)
      expect_gt(length(files), 0)
      expect_lt(
        max(abs(
          unlist(rec$crop[c('x', 'y', 'width', 'height')]) -
            unlist(geometry_frame)
        )),
        2.5
      )
      crop <- record_output_spec(rec, png_read_size(carried))$crop
      expect_gt(crop$x, 0)
      expect_gt(crop$y, 0)
      expect_equal(
        png_dimensions(files[[1]]),
        as.integer(c(crop$width, crop$height))
      )
      boxes <- lapply(files, function(path) {
        drag_preview_marker_box(page, path, tolerance = 18)
      })
      boxes <- Filter(Negate(is.null), boxes)
      positions <- do.call(
        rbind,
        lapply(boxes, function(box) unlist(box[c('x', 'y')]))
      )
      expect_gt(nrow(positions), 2)
      crop_offset <- c(x = crop$x, y = crop$y) / page_dpr(page)
      for (point in list(carry_expected, settle_expected, resting_marker)) {
        errors <- apply(
          abs(sweep(positions, 2, point - crop_offset, '-')),
          1,
          max
        )
        expect_lt(min(errors), 2)
      }
    }
  }
  for (case in cases) {
    capture(case)
  }
})

test_that('the unpaused production path records carry and a one-row-up settle', {
  skip_if_no_av()
  page <- local_task_page(width = 800, height = 900)
  # Slow carry (glide clamps at 2s): the mid-flight assertion needs screencast
  # frames during the carry even when a starved runner delivers them late.
  pz_stage(page, pause = 0, cursor_speed = 40)
  drag_preview_task_marker(page)
  out <- withr::local_tempfile(fileext = '.mp4')
  frames <- paste0(tools::file_path_sans_ext(out), '_frames')
  withr::defer(unlink(frames, recursive = TRUE))
  pz_record_start(page, out, fps = 60, hold = c(0, 0), keep_frames = TRUE)
  defer_record_stop(page)
  pz_cursor_move(page, '#preview-source .task-drag-handle', duration = 0)
  initial <- pz_js(
    page,
    "(() => { const r = window.__previewSource.getBoundingClientRect(); const m = document.querySelector('#preview-marker').getBoundingClientRect(); return {x:r.x,y:r.y,height:r.height,dx:m.x-r.x,dy:m.y-r.y}; })()"
  )
  original_settle <- drag_preview_settle
  first_settle_frame <- NULL
  resting <- target <- NULL
  local_mocked_bindings(drag_preview_settle = function(state) {
    first_settle_frame <<- length(page_recorder(page)$files) + 1L
    boxes <- pz_js(
      page,
      "(() => { const s = window.__previewSource.getBoundingClientRect(); const t = document.querySelector('#preview-target').getBoundingClientRect(); return {source:{x:s.x,y:s.y},target:{x:t.x,y:t.y}}; })()"
    )
    resting <<- unlist(boxes$source) + c(x = initial$dx, y = initial$dy)
    target <<- unlist(boxes$target) + c(x = initial$dx, y = initial$dy)
    # Observe the boundary only: no substituted carry, extra pump, paused WAAPI,
    # altered animation time or copied production implementation in this test.
    original_settle(state)
  })
  expect_no_warning(pz_act_drag(
    page,
    '#preview-source .task-drag-handle',
    '#preview-target .task-drag-handle'
  ))
  rec <- page_recorder(page)
  action_files <- rec$files
  boxes <- lapply(action_files, function(path) {
    drag_preview_marker_box(page, path)
  })
  carry <- boxes[seq_len(first_settle_frame - 1L)]
  carry <- Filter(Negate(is.null), carry)
  # A passing frame must be genuinely mid-flight: strictly between the
  # source row and the resting spot one row up. Bounding by the resting
  # y (not the target's) excludes end-of-carry frames already parked at
  # the resting row.
  expect_true(any(vapply(
    carry,
    function(box) {
      box$y > initial$y + initial$dy + 10 && box$y < resting[['y']] - 5
    },
    logical(1)
  )))
  # Capture density during the settle is bounded by the screencast ack
  # round-trip, so a short settle can yield a single mid-flight frame and the
  # preview is disposed before any frame shows the rest position. The settle's
  # execution and geometry are asserted via the boundary mock instead.
  expect_gt(target[['y']] - resting[['y']], initial$height / 2)
  expect_equal(
    unlist(pz_js(
      page,
      "Array.from(document.querySelectorAll('.task-title')).slice(0,3).map(n => n.textContent.trim())"
    )),
    c('File tax return', 'Renew passport', 'Book dentist appointment')
  )
  expect_true(drag_preview_absent(page))
  cleaned <- drag_preview_retained_checkpoint(
    page,
    verify = drag_preview_marker_absent(page)
  )
  expect_null(drag_preview_marker_box(page, cleaned))
  pz_record_stop(page)
  expect_true(file.exists(out))
})

test_that('a loaded local font and image survive the production drag carry', {
  skip_if_no_av()
  page <- local_task_page(width = 800, height = 900, timeout = 5)
  pz_stage(page, pause = 0, cursor_speed = 120)
  drag_preview_task_marker(page)
  font <- pz_font_file(
    'PreviewTest',
    test_path('fixtures', 'fonts', 'silkscreen-400.woff2')
  )
  pz_stage_fonts(page, font)
  # The staged FontFace is programmatic; also exercise readable grouped CSS.
  pz_js(
    page,
    sprintf(
      "(() => {
        const style = document.createElement('style');
        const dataURL = 'data:font/woff2;base64,%s';
        style.textContent = '@media all { @font-face { font-family: PreviewTest; font-weight: 400; src: url(\"' + dataURL + '\") format(\"woff2\"); } }' +
          '@media not all { @font-face { font-family: InactiveMediaPreviewFont; src: url(\"' + dataURL + '\"); } }' +
          '@supports (display: paparazzi-invalid-display) { @font-face { font-family: InactiveSupportsPreviewFont; src: url(\"' + dataURL + '\"); } }';
        document.head.appendChild(style);
        const glyph = document.createElement('span');
        glyph.textContent = 'HI';
        glyph.style.cssText = 'position:absolute;left:120px;top:8px;font:400 16px/24px PreviewTest;color:rgb(250,90,20);pointer-events:none;';
        window.__previewSource.appendChild(glyph);
        return true;
      })()",
      gsub('[[:space:]]', '', font$data)
    )
  )
  expect_true(pz_js(
    page,
    "(async () => {
      const title = window.__previewSource.querySelector('.task-title');
      title.style.fontFamily = 'PreviewTest';
      await document.fonts.load('400 16px PreviewTest');
      await document.fonts.ready;
      return getComputedStyle(title).fontFamily === 'PreviewTest' &&
        document.fonts.check('400 16px PreviewTest') &&
        [...document.fonts].some(f => f.family === 'PreviewTest' && f.status === 'loaded');
    })()"
  ))
  pz_wait_for_js(
    page,
    'window.__previewSource.querySelector("img").complete && window.__previewSource.querySelector("img").naturalWidth === 12'
  )
  out <- withr::local_tempfile(fileext = '.mp4')
  frames <- paste0(tools::file_path_sans_ext(out), '_frames')
  withr::defer(unlink(frames, recursive = TRUE))
  pz_record_start(page, out, fps = 30, hold = c(0, 0), keep_frames = TRUE)
  defer_record_stop(page)
  drag_preview_stylesheet_guard(page)
  before <- pz_js(page, 'window.__previewStyleSnapshot()')
  original_boot <- drag_preview_boot_js
  original_carry <- stage_drag_carry
  carried <- NULL
  local_mocked_bindings(
    drag_preview_boot_js = function() {
      drag_preview_counted_boot(
        original_boot,
        'return original(...args).then(png => { window.__previewPNG = png; return png; });'
      )
    },
    stage_drag_carry = function(ctx, from, to, step) {
      original_carry(ctx, from, to, function(point) {
        step(point)
        if (
          is.null(carried) &&
            point[['y']] > from[['y']] + 25 &&
            point[['y']] < to[['y']] - 25
        ) {
          carried <<- drag_preview_retained_checkpoint(
            ctx,
            verify = drag_preview_marker_present(ctx)
          )
        }
      })
    }
  )
  expect_no_warning(pz_act_drag(
    page,
    '#preview-source .task-drag-handle',
    '#preview-target .task-drag-handle'
  ))
  expect_false(is.null(carried))
  green <- drag_preview_marker_box(page, carried)
  blue <- drag_preview_marker_box(page, carried, color = c(80, 40, 230))
  expect_false(is.null(green))
  expect_false(is.null(blue))
  expect_lt(max(abs(c(blue$width, blue$height) - c(12, 12))), 1.5)
  expect_lt(
    max(abs(c(blue$x - green$x, blue$y - green$y) - c(30, 0))),
    1.5
  )
  expect_equal(pz_js(page, 'window.__previewCaptures'), 1)
  expect_true(pz_js(
    page,
    'window.__previewFontEmbedCSS.includes("@font-face") && window.__previewFontEmbedCSS.includes("data:font/woff2;base64,")'
  ))
  expect_equal(pz_js(page, 'window.__previewInsertions'), 0)
  expect_equal(pz_js(page, 'window.__previewStyleSnapshot()'), before)
  expect_true(pz_js(
    page,
    '!matchMedia("not all").matches && !CSS.supports("display: paparazzi-invalid-display") && !window.__previewFontEmbedCSS.includes("InactiveMediaPreviewFont") && !window.__previewFontEmbedCSS.includes("InactiveSupportsPreviewFont")'
  ))
  # Font-specific glyph dimensions in the raster, not just a loaded page face.
  glyph <- pz_js(
    page,
    "(async () => {
      const image = new Image(); image.src = window.__previewPNG; await image.decode();
      const canvas = document.createElement('canvas');
      canvas.width = image.naturalWidth; canvas.height = image.naturalHeight;
      const ctx = canvas.getContext('2d'); ctx.drawImage(image, 0, 0);
      const data = ctx.getImageData(0, 0, canvas.width, canvas.height).data;
      let left = canvas.width, top = canvas.height, right = -1, bottom = -1;
      for (let y = 0; y < canvas.height; y++) for (let x = 0; x < canvas.width; x++) {
        const i = (y * canvas.width + x) * 4;
        if (Math.abs(data[i] - 250) < 3 && Math.abs(data[i+1] - 90) < 3 && Math.abs(data[i+2] - 20) < 3) {
          left = Math.min(left, x); right = Math.max(right, x);
          top = Math.min(top, y); bottom = Math.max(bottom, y);
        }
      }
      ctx.font = '400 16px PreviewTest';
      const embedded = ctx.measureText('HI');
      ctx.font = '400 16px monospace';
      const fallback = ctx.measureText('HI');
      return {width:(right-left+1)/devicePixelRatio, height:(bottom-top+1)/devicePixelRatio,
        expectedWidth:embedded.actualBoundingBoxLeft + embedded.actualBoundingBoxRight,
        expectedHeight:embedded.actualBoundingBoxAscent + embedded.actualBoundingBoxDescent,
        fallbackWidth:fallback.actualBoundingBoxLeft + fallback.actualBoundingBoxRight};
    })()"
  )
  expect_gt(glyph$width, 0)
  # Windows glyph hinting rasters the embedded font a few pixels wider than
  # canvas measureText reports; the fallback check below still discriminates.
  expect_lt(abs(glyph$width - glyph$expectedWidth), 5)
  expect_lt(abs(glyph$height - glyph$expectedHeight), 1.5)
  expect_gt(abs(glyph$width - glyph$fallbackWidth), 3)
  expect_true(pz_js(
    page,
    'document.querySelectorAll(".task")[1] === window.__previewSource'
  ))
  expect_equal(
    unlist(pz_js(
      page,
      "Array.from(document.querySelectorAll('.task-title')).slice(0,3).map(n => n.textContent.trim())"
    )),
    c('File tax return', 'Renew passport', 'Book dentist appointment')
  )
  expect_true(drag_preview_absent(page))
  pz_record_stop(page)
  expect_true(file.exists(carried))
})

test_that('content-box captures preserve the measured border box and far-edge pixels', {
  skip_if_no_av()
  page <- local_page(width = 800, height = 600)
  pz_stage(page, pause = 0)
  expect_true(pz_js(
    page,
    "(() => {
      document.body.insertAdjacentHTML('beforeend', `
        <div id='preview-source' draggable='true' style='position:absolute;left:40px;top:140px;box-sizing:content-box;width:100px;height:40px;padding:10px;border:2px solid rgb(210,30,60);background:white'>
          <span style='position:absolute;right:0;bottom:0;width:8px;height:8px;background:rgb(8,200,80);pointer-events:none'></span>
        </div>
        <div id='preview-target' style='position:absolute;left:40px;top:340px;width:124px;height:64px'>Drop here</div>`);
      const source = document.querySelector('#preview-source');
      const target = document.querySelector('#preview-target');
      source.addEventListener('dragstart', e => {
        e.dataTransfer.setData('text/plain', 'border-box');
        source.style.borderColor = 'rgb(20,20,20)';
        source.firstElementChild.style.background = 'rgb(220,20,180)';
      });
      target.addEventListener('dragover', e => e.preventDefault());
      target.addEventListener('drop', e => {
        e.preventDefault();
        target.dataset.payload = e.dataTransfer.getData('text/plain');
      });
      window.htmlToImage = {sentinel: 'page-owned'};
      source.pageLibrary = window.htmlToImage;
      return getComputedStyle(source).boxSizing === 'content-box';
    })()"
  ))
  measured <- pz_js(
    page,
    "(() => { const r = document.querySelector('#preview-source').getBoundingClientRect(); return {width:r.width,height:r.height}; })()"
  )
  expect_equal(unlist(measured), c(width = 124, height = 64))
  out <- withr::local_tempfile(fileext = '.mp4')
  frames <- paste0(tools::file_path_sans_ext(out), '_frames')
  withr::defer(unlink(frames, recursive = TRUE))
  pz_record_start(page, out, fps = 30, hold = c(0, 0), keep_frames = TRUE)
  defer_record_stop(page)
  original_boot <- drag_preview_boot_js
  original_carry <- stage_drag_carry
  carried <- capture <- NULL
  local_mocked_bindings(
    drag_preview_boot_js = function() drag_preview_counted_boot(original_boot),
    stage_drag_carry = function(ctx, from, to, step) {
      original_carry(ctx, from, to, function(point) {
        step(point)
        if (
          is.null(carried) &&
            point[['y']] > from[['y']] + 90 &&
            point[['y']] < to[['y']] - 25
        ) {
          capture <<- pz_js(
            ctx,
            "(() => {
              const controller = document.getElementById('paparazzi-overlay-root').shadowRoot.querySelector('.pz-drag-preview').pz;
              const image = controller.image;
              const r = image.getBoundingClientRect();
              const c = document.createElement('canvas').getContext('2d');
              c.canvas.width = image.naturalWidth;
              c.canvas.height = image.naturalHeight;
              c.drawImage(image, 0, 0);
              const dpr = window.devicePixelRatio;
              const pixel = (x, y) => Array.from(c.getImageData(Math.floor(x*dpr), Math.floor(y*dpr), 1, 1).data);
              return {x:r.x,y:r.y,width:r.width,height:r.height,
                rasterWidth:image.naturalWidth/dpr,rasterHeight:image.naturalHeight/dpr,
                right:pixel(123,32),bottom:pixel(62,63),marker:pixel(118,58),
                sentinel:window.htmlToImage === controller.source.pageLibrary};
            })()"
          )
          carried <<- drag_preview_retained_checkpoint(
            ctx,
            verify = drag_preview_marker_present(ctx)
          )
        }
      })
    }
  )
  expect_no_warning(pz_act_drag(page, '#preview-source', '#preview-target'))
  expect_false(is.null(capture))
  expect_equal(
    unlist(capture[c('width', 'height')]),
    c(width = 124, height = 64),
    tolerance = 0.001
  )
  expect_equal(
    unlist(capture[c('rasterWidth', 'rasterHeight')]),
    c(rasterWidth = 124, rasterHeight = 64)
  )
  for (edge in c('right', 'bottom')) {
    expect_lt(max(abs(unlist(capture[[edge]]) - c(210, 30, 60, 255))), 3)
  }
  expect_lt(max(abs(unlist(capture$marker) - c(8, 200, 80, 255))), 3)
  expect_true(capture$sentinel)
  border <- drag_preview_marker_box(page, carried, color = c(210, 30, 60))
  marker <- drag_preview_marker_box(page, carried)
  expect_false(is.null(border))
  expect_false(is.null(marker))
  # The retained frame lands while the preview is still gliding, so its
  # absolute position lags the capture-time rect by the screencast ack
  # window; assert layout (size, marker offset inside the border box)
  # instead of position.
  expect_lt(
    max(abs(
      unlist(border[c('width', 'height')]) -
        unlist(capture[c('width', 'height')])
    )),
    1.5
  )
  expect_lt(
    max(abs(
      unlist(marker[c('x', 'y', 'width', 'height')]) -
        c(border$x + 114, border$y + 54, 8, 8)
    )),
    1.5
  )
  expect_equal(pz_js(page, 'window.__previewCaptures'), 1)
  expect_true(pz_js(
    page,
    "window.htmlToImage === document.querySelector('#preview-source').pageLibrary"
  ))
  expect_equal(
    pz_js(page, "document.querySelector('#preview-target').dataset.payload"),
    'border-box'
  )
  expect_true(drag_preview_absent(page))
  pz_record_stop(page)
})

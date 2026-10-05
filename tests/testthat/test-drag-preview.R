# Keep the application fixture: changing the marker at dragstart makes a pure
# green carried marker evidence of a pre-dragstart capture, not the live row.
drag_preview_task_marker <- function(page) {
  pz_js(
    page,
    "(() => {
    const source = document.querySelectorAll('.task')[0];
    source.id = 'preview-source';
    document.querySelectorAll('.task')[2].id = 'preview-target';
    const marker = document.createElement('span');
    marker.id = 'preview-marker';
    marker.style.cssText = 'position:absolute;left:60px;top:12px;width:20px;height:20px;background:rgb(8,200,80);pointer-events:none;';
    source.appendChild(marker);
    // Local styled text and an embedded image travel with the same source.
    source.querySelector('.task-title').style.fontFamily = 'monospace';
    const image = document.createElement('img');
    image.alt = '';
    image.style.cssText = 'position:absolute;left:90px;top:12px;width:12px;height:12px;pointer-events:none;';
    image.src = 'data:image/svg+xml,' + encodeURIComponent('<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"12\" height=\"12\"><path fill=\"rgb(80,40,230)\" d=\"M0 0h12v12H0z\"/></svg>');
    source.appendChild(image);
    window.__previewSource = source;
    window.__previewEvents = [];
    document.addEventListener('dragstart', e => {
      if (e.target === source) marker.style.background = 'rgb(220,20,180)';
    });
    for (const type of ['dragstart', 'drop', 'dragend']) {
      document.addEventListener(type, e => {
        window.__previewEvents.push({type, trusted:e.isTrusted,
          payload:e.dataTransfer?.getData('text/plain')});
      });
    }
    return true;
  })()"
  )
}

# Decode in the browser's canvas, never by viewing an image. NULL means the
# requested color is absent. The same scan works on retained and decoded video
# PNGs; scale converts their actual pixels back to viewport CSS coordinates.
drag_preview_marker_box <- function(
  page,
  path,
  color = c(8, 200, 80),
  scale = page_dpr(page),
  tolerance = 2
) {
  png_canvas_eval(
    page,
    path,
    sprintf(
      "const data = c.getImageData(0, 0, img.width, img.height).data;
     let left = img.width, top = img.height, right = -1, bottom = -1, count = 0;
     for (let y = 0; y < img.height; y++) for (let x = 0; x < img.width; x++) {
       const i = (y * img.width + x) * 4;
       if (Math.abs(data[i] - %g) <= %g && Math.abs(data[i+1] - %g) <= %g && Math.abs(data[i+2] - %g) <= %g) {
         left = Math.min(left, x); top = Math.min(top, y);
         right = Math.max(right, x); bottom = Math.max(bottom, y); count++;
       }
     }
     return count ? {x:left/%g, y:top/%g, width:(right-left+1)/%g, height:(bottom-top+1)/%g, count} : null;",
      color[1],
      tolerance,
      color[2],
      tolerance,
      color[3],
      tolerance,
      scale,
      scale,
      scale,
      scale
    )
  )
}

# Verifiers for drag_preview_retained_checkpoint(): does a retained frame show
# the marker in `color` at `point`, anywhere, or nowhere at all?
drag_preview_marker_at <- function(
  page,
  point,
  color = c(8, 200, 80),
  tolerance = 2
) {
  point <- unlist(point)
  function(path) {
    box <- drag_preview_marker_box(page, path, color = color)
    !is.null(box) &&
      max(abs(unlist(box[c('x', 'y')]) - point[c('x', 'y')])) <= tolerance
  }
}

drag_preview_marker_present <- function(page, color = c(8, 200, 80)) {
  function(path) !is.null(drag_preview_marker_box(page, path, color = color))
}

drag_preview_marker_absent <- function(page, color = c(8, 200, 80)) {
  function(path) is.null(drag_preview_marker_box(page, path, color = color))
}

# Capture a retained frame that is fresh, not merely new: pump the child loop
# until the recorder writes a frame beyond `before` and, when `verify` is set,
# until that frame's content matches, so a slow runner cannot hand back a
# frame captured before the DOM state the caller just created.
drag_preview_retained_checkpoint <- function(page, verify = NULL, timeout = 3) {
  before <- length(page_recorder(page)$files)
  fresh <- function() {
    files <- page_recorder(page)$files
    if (length(files) <= before) {
      return(list(pass = FALSE))
    }
    path <- tail(files, 1)
    list(pass = is.null(verify) || isTRUE(verify(path)), path = path)
  }
  result <- expect_retry(
    fresh,
    timeout = timeout,
    loop = page$child_loop,
    interval = 0.02
  )
  expect_gt(length(page_recorder(page)$files), before)
  if (!result$pass) {
    if (length(page_recorder(page)$files) > before) {
      testthat::fail('the retained frame never matched the expected content')
    } else {
      # No frame arrived and expect_gt above records it; NA keeps downstream
      # calls (file.exists, readBin) failing instead of passing vacuously.
      return(NA_character_)
    }
  }
  result$path
}

# Pump until a retained frame from `from` onward shows the marker at `point`.
# DOM state is not enough: the preview image detaches as soon as the settle
# finishes, and the screencast frames queued behind that moment only drain
# while the child loop is pumped.
drag_preview_wait_retained_at <- function(
  page,
  point,
  from = 1L,
  tolerance = 1.5,
  timeout = 3
) {
  scanned <- from - 1L
  at_rest <- drag_preview_marker_at(page, point, tolerance = tolerance)
  result <- expect_retry(
    function() {
      files <- page_recorder(page)$files
      start <- max(scanned + 1L, from)
      new_files <- if (start <= length(files)) {
        files[start:length(files)]
      } else {
        character(0)
      }
      scanned <<- length(files)
      list(
        pass = any(vapply(
          new_files,
          function(path) at_rest(path),
          logical(1)
        ))
      )
    },
    timeout = timeout,
    loop = page$child_loop,
    interval = 0.02
  )
  if (!result$pass) {
    testthat::fail('no retained frame showed the marker at the rest position')
  }
  invisible(TRUE)
}

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

# Count the real library call, not just controller creation. In unsafe cases the
# wrapper must remain uncalled: failing after capture is a privacy failure.
drag_preview_counted_boot <- function(boot, replacement = NULL) {
  js <- boot()
  needle <- '\nreturn ('
  matches <- gregexpr(needle, js, fixed = TRUE)[[1]]
  stopifnot(length(matches) == 1L, matches[[1]] > 0)
  replacement <- replacement %||% 'return original(...args);'
  sub(
    needle,
    paste0(
      '\nconst original = exports.toPng; exports.toPng = (...args) => {',
      'window.__previewCaptures = (window.__previewCaptures || 0) + 1;',
      'window.__previewFontEmbedCSS = args[1]?.fontEmbedCSS;',
      replacement,
      '};\nreturn ('
    ),
    js,
    fixed = TRUE
  )
}

# Measure with the native getter even when a sheet's public getter is unreadable.
# Throwing on insertion also catches mutations hidden by upstream error handling.
drag_preview_stylesheet_guard <- function(page) {
  pz_js(
    page,
    "(() => {
      const nativeRules = Object.getOwnPropertyDescriptor(CSSStyleSheet.prototype, 'cssRules').get;
      window.__previewStyleSnapshot = () => ({
        sheets: Array.from(document.styleSheets, sheet =>
          Array.from(nativeRules.call(sheet), rule => rule.cssText)),
        source: ['color', 'backgroundColor', 'fontFamily', 'fontSize', 'opacity', 'transform', 'filter']
          .map(key => getComputedStyle(window.__previewSource)[key]),
        title: getComputedStyle(window.__previewSource.querySelector('.task-title')).color
      });
      window.__previewInsertions = 0;
      CSSStyleSheet.prototype.insertRule = () => {
        window.__previewInsertions++;
        throw new Error('Live stylesheet insertion during preview');
      };
      return true;
    })()"
  )
}

drag_preview_absent <- function(page) {
  pz_js(
    page,
    "!document.getElementById('paparazzi-overlay-root')?.shadowRoot?.querySelector('.pz-drag-preview')"
  )
}

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

test_that('preview is named-only and validates a single nonmissing boolean', {
  page <- local_task_page()
  for (value in list(NULL, NA, 1, 'yes', logical(), c(TRUE, FALSE))) {
    expect_error(pz_act_drag(
      page,
      '.task:nth-child(5)',
      '.task:first-child',
      preview = value
    ))
  }
  expect_error(
    pz_act_drag(page, '.task:nth-child(5)', '.task:first-child', FALSE),
    'unused|empty|must be empty'
  )
})

test_that('ineligible drags do not boot the preview or call the library', {
  skip_if_no_av()
  check_gate <- function(gate) {
    page <- if (gate == 'mouse') {
      local_advanced_page()
    } else {
      local_task_page()
    }
    pz_stage(page, pause = 0)
    if (gate != 'mouse') {
      drag_preview_task_marker(page)
    }
    if (gate != 'unrecorded') {
      pz_record_start(
        page,
        withr::local_tempfile(fileext = '.mp4'),
        hold = c(0, 0)
      )
      defer_record_stop(page)
      if (gate == 'paused') {
        pz_record_pause(page)
      }
      if (gate == 'hidden') pz_cursor_hide(page)
    }
    boots <- 0L
    local_mocked_bindings(drag_preview_boot_js = function() {
      boots <<- boots + 1L
      stop('ineligible drag booted the raster library')
    })
    if (gate == 'mouse') {
      expect_no_warning(pz_act_drag(page, '#dragbox', '#dropzone'))
      expect_true('mouseup' %in% adv_log_types(adv_log(page)))
    } else {
      expect_no_warning(pz_act_drag(
        page,
        '#preview-source .task-drag-handle',
        '#preview-target .task-drag-handle',
        preview = gate != 'disabled'
      ))
      expect_true(pz_js(
        page,
        'document.querySelectorAll(".task")[1] === window.__previewSource'
      ))
    }
    expect_identical(boots, 0L)
    expect_true(drag_preview_absent(page))
    rec <- page_recorder(page)
    if (!is.null(rec)) pz_record_stop(page)
  }
  for (gate in c('unrecorded', 'paused', 'hidden', 'mouse', 'disabled')) {
    check_gate(gate)
  }
})

test_that('redaction rejects unsafe capture before the library while preserving the drop', {
  skip_if_no_av()
  check_redaction <- function(case) {
    page <- local_task_page(width = 800, height = 900)
    pz_stage(page, pause = 0)
    drag_preview_task_marker(page)
    if (
      case %in% c('unrelated-fill', 'unrelated-blur', 'unavailable', 'invalid')
    ) {
      pz_annotate_redact(
        page,
        '#task-title',
        method = if (case == 'unrelated-blur') 'blur' else 'fill'
      )
    } else if (case == 'ancestor') {
      pz_annotate_redact(page, '.task-list')
    } else if (case == 'hidden-descendant') {
      pz_annotate_redact(page, '#preview-marker')
      pz_js(
        page,
        'document.querySelector("#preview-marker").style.display = "none"'
      )
    } else if (case == 'padded-overlap') {
      pz_annotate_redact(page, '.task:nth-child(2)', pad = 20)
    } else {
      pz_annotate_redact(
        page,
        '#preview-source',
        method = if (case == 'source-blur') 'blur' else 'fill'
      )
    }
    if (case == 'unavailable') {
      pz_js(
        page,
        'document.querySelector("#paparazzi-overlay-root").shadowRoot.querySelector(".pz-annotations").remove()'
      )
    }
    if (case == 'invalid') {
      pz_js(
        page,
        'document.querySelector("#paparazzi-overlay-root").shadowRoot.querySelector(".pz-annotations").pz.dragPreviewSafety = () => ({safe:"unknown"})'
      )
    }
    pz_record_start(
      page,
      withr::local_tempfile(fileext = '.mp4'),
      fps = 15,
      hold = c(0, 0)
    )
    defer_record_stop(page)
    original_boot <- drag_preview_boot_js
    local_mocked_bindings(drag_preview_boot_js = function() {
      drag_preview_counted_boot(original_boot)
    })
    warnings <- list()
    withCallingHandlers(
      pz_act_drag(
        page,
        '#preview-source .task-drag-handle',
        '#preview-target .task-drag-handle'
      ),
      warning = function(w) {
        warnings <<- c(warnings, list(w))
        invokeRestart('muffleWarning')
      }
    )
    safe <- startsWith(case, 'unrelated')
    expect_length(warnings, if (safe) 0 else 1)
    if (!safe) {
      expect_s3_class(warnings[[1]], 'paparazzi_warning_drag_preview')
    }
    expect_equal(
      pz_js(page, 'window.__previewCaptures || 0'),
      if (safe) 1 else 0
    )
    expect_true(pz_js(
      page,
      'document.querySelectorAll(".task")[1] === window.__previewSource'
    ))
    expect_true(drag_preview_absent(page))
    pz_record_stop(page)
  }
  for (case in c(
    'unrelated-fill',
    'unrelated-blur',
    'source-fill',
    'source-blur',
    'ancestor',
    'hidden-descendant',
    'padded-overlap',
    'unavailable',
    'invalid'
  )) {
    check_redaction(case)
  }
})

test_that('optional capture, decode, show, move and settle failures warn once and keep the drop', {
  skip_if_no_av()
  check_failure <- function(method) {
    page <- local_task_page(width = 800, height = 900)
    pz_stage(page, pause = 0)
    drag_preview_task_marker(page)
    pz_record_start(
      page,
      withr::local_tempfile(fileext = '.mp4'),
      fps = 15,
      hold = c(0, 0)
    )
    defer_record_stop(page)
    original_boot <- drag_preview_boot_js
    original_prepare <- drag_preview_prepare
    if (method == 'decode') {
      pz_js(
        page,
        "window.__realDecode = Image.prototype.decode"
      )
      withr::defer(pz_js(page, 'Image.prototype.decode = window.__realDecode'))
    }
    local_mocked_bindings(
      drag_preview_boot_js = function() {
        drag_preview_counted_boot(
          original_boot,
          if (method == 'capture') {
            "throw new Error('injected capture failure');"
          } else if (method == 'decode') {
            "return original(...args).then(png => { Image.prototype.decode = () => Promise.reject(new Error('injected decode failure')); return png; });"
          } else {
            NULL
          }
        )
      },
      drag_preview_prepare = function(state, els, from) {
        original_prepare(state, els, from)
        if (method %in% c('show', 'move', 'settle')) {
          pz_js(
            page,
            paste0(
              '(() => { const p = ',
              DRAG_PREVIEW_CONTROLLER_JS,
              '; window.__previewController = p; p.',
              method,
              ' = () => {throw new Error("injected ',
              method,
              ' failure")}; })()'
            )
          )
        }
      }
    )
    warnings <- list()
    withCallingHandlers(
      pz_act_drag(
        page,
        '#preview-source .task-drag-handle',
        '#preview-target .task-drag-handle'
      ),
      warning = function(w) {
        warnings <<- c(warnings, list(w))
        invokeRestart('muffleWarning')
      }
    )
    expect_length(warnings, 1)
    expect_s3_class(warnings[[1]], 'paparazzi_warning_drag_preview')
    expect_match(
      conditionMessage(warnings[[1]]),
      paste('injected', method, 'failure')
    )
    expect_equal(pz_js(page, 'window.__previewCaptures'), 1)
    expect_true(pz_js(
      page,
      'document.querySelectorAll(".task")[1] === window.__previewSource'
    ))
    expect_true(drag_preview_absent(page))
    if (method %in% c('show', 'move', 'settle')) {
      expect_true(pz_js(
        page,
        'window.__previewController.source === null && window.__previewController.image === null'
      ))
    }
    expect_false(page_cursor(page)$pressed)
    pz_record_stop(page)
  }
  for (method in c('capture', 'decode', 'show', 'move', 'settle')) {
    check_failure(method)
  }
})

test_that('real carry errors and interrupts propagate unchanged despite failing cleanup', {
  skip_if_no_av()
  check_unwind <- function(interrupted) {
    page <- local_task_page(width = 800, height = 900)
    pz_stage(page, pause = 0)
    drag_preview_task_marker(page)
    pz_record_start(
      page,
      withr::local_tempfile(fileext = '.mp4'),
      hold = c(0, 0)
    )
    defer_record_stop(page)
    original_prepare <- drag_preview_prepare
    failure <- if (interrupted) {
      structure(
        list(message = 'injected interrupt', call = NULL),
        class = c('interrupt', 'condition')
      )
    } else {
      rlang::error_cnd('paparazzi_error_input', message = 'genuine carry error')
    }
    local_mocked_bindings(
      drag_preview_prepare = function(state, els, from) {
        original_prepare(state, els, from)
        pz_js(
          page,
          paste0(
            '(() => { const p = ',
            DRAG_PREVIEW_CONTROLLER_JS,
            '; window.__previewController = p; const dispose = p.dispose.bind(p);',
            'p.dispose = () => {dispose(); throw new Error("cleanup failed")}; })()'
          )
        )
      },
      stage_drag_carry = function(ctx, from, to, step) stop(failure)
    )
    warnings <- list()
    caught <- withCallingHandlers(
      tryCatch(
        pz_act_drag(
          page,
          '#preview-source .task-drag-handle',
          '#preview-target .task-drag-handle'
        ),
        error = identity,
        interrupt = identity
      ),
      warning = function(w) {
        warnings <<- c(warnings, list(w))
        invokeRestart('muffleWarning')
      }
    )
    expect_identical(caught, failure)
    expect_length(warnings, 0)
    expect_true(drag_preview_absent(page))
    expect_true(pz_js(
      page,
      'window.__previewController.source === null && window.__previewController.image === null'
    ))
    expect_false(page_cursor(page)$pressed)
    pz_record_stop(page)
  }
  check_unwind(FALSE)
  check_unwind(TRUE)
})

test_that('failed interception disposes the prepared image without displaying it', {
  skip_if_no_av()
  page <- local_task_page(width = 800, height = 900)
  pz_stage(page, pause = 0)
  drag_preview_task_marker(page)
  pz_record_start(page, withr::local_tempfile(fileext = '.mp4'), hold = c(0, 0))
  defer_record_stop(page)
  original_prepare <- drag_preview_prepare
  original_poll <- pz_poll
  local_mocked_bindings(
    drag_preview_prepare = function(state, els, from) {
      original_prepare(state, els, from)
      pz_js(
        page,
        paste0(
          '(() => { const p = ',
          DRAG_PREVIEW_CONTROLLER_JS,
          '; window.__previewController = p; window.__previewShows = 0;',
          'const show = p.show.bind(p); p.show = point => {window.__previewShows++; return show(point)}; })()'
        )
      )
    },
    pz_poll = function(fn, ..., what = NULL) {
      if (!is.null(what) && grepl('the drag from', what, fixed = TRUE)) {
        cli::cli_abort(
          'injected interception failure',
          class = 'paparazzi_error_input'
        )
      }
      original_poll(fn, ..., what = what)
    }
  )
  expect_error(
    pz_act_drag(
      page,
      '#preview-source .task-drag-handle',
      '#preview-target .task-drag-handle'
    ),
    'injected interception failure'
  )
  expect_equal(pz_js(page, 'window.__previewShows'), 0)
  expect_true(drag_preview_absent(page))
  expect_true(pz_js(
    page,
    'window.__previewController.source === null && window.__previewController.image === null'
  ))
  expect_false(page_cursor(page)$pressed)
  pz_record_stop(page)
})

test_that('a timed-out capture cannot display or retain the source after late completion', {
  skip_if_no_av()
  page <- local_task_page(width = 800, height = 900)
  pz_stage(page, pause = 0)
  drag_preview_task_marker(page)
  pz_record_start(page, withr::local_tempfile(fileext = '.mp4'), hold = c(0, 0))
  defer_record_stop(page)
  original_boot <- drag_preview_boot_js
  original_timeout <- page$default_timeout
  original_prepare <- drag_preview_prepare
  prepared <- NULL
  local_mocked_bindings(
    drag_preview_prepare = function(state, els, from) {
      prepared <<- state
      page$default_timeout <- 0.1
      on.exit(page$default_timeout <- original_timeout)
      original_prepare(state, els, from)
    },
    drag_preview_boot_js = function() {
      drag_preview_counted_boot(
        original_boot,
        paste0(
          'window.__previewController = ',
          DRAG_PREVIEW_CONTROLLER_JS,
          ';',
          'return new Promise(resolve => {window.__releasePreviewCapture = () => resolve("data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jB1sAAAAASUVORK5CYII=")});'
        )
      )
    }
  )
  warnings <- list()
  withCallingHandlers(
    pz_act_drag(
      page,
      '#preview-source .task-drag-handle',
      '#preview-target .task-drag-handle'
    ),
    warning = function(w) {
      warnings <<- c(warnings, list(w))
      invokeRestart('muffleWarning')
    }
  )
  expect_null(prepared$owner)
  expect_length(warnings, 1)
  expect_s3_class(warnings[[1]], 'paparazzi_warning_drag_preview')
  expect_match(conditionMessage(warnings[[1]]), 'Timed out|timed out')
  expect_true(pz_js(
    page,
    'document.querySelectorAll(".task")[1] === window.__previewSource'
  ))
  expect_true(drag_preview_absent(page))
  expect_true(pz_js(
    page,
    'window.__previewController.source === null && window.__previewController.image === null'
  ))
  pz_js(page, 'window.__releasePreviewCapture()')
  pump_loop(page$child_loop, 0.15)
  expect_true(drag_preview_absent(page))
  expect_true(pz_js(
    page,
    'window.__previewController.source === null && window.__previewController.image === null'
  ))
  expect_equal(pz_js(page, 'window.__previewCaptures'), 1)
  pz_record_stop(page)
})

test_that('settling never guesses a replacement row or an unrendered source box', {
  skip_if_no_av()
  check_skip <- function(mutation) {
    page <- local_task_page(width = 800, height = 900)
    pz_stage(page, pause = 0)
    drag_preview_task_marker(page)
    pz_js(
      page,
      paste0(
        "document.addEventListener('drop', () => { const source = window.__previewSource; ",
        switch(
          mutation,
          removed = 'source.remove();',
          replaced = 'source.replaceWith(source.cloneNode(true));',
          hidden = 'source.style.setProperty("display", "none", "important");',
          resized = 'source.style.height = "100px"; source.style.flexShrink = "0";'
        ),
        '});'
      )
    )
    pz_record_start(
      page,
      withr::local_tempfile(fileext = '.mp4'),
      hold = c(0, 0)
    )
    defer_record_stop(page)
    original_settle <- drag_preview_settle
    settled <- FALSE
    local_mocked_bindings(drag_preview_settle = function(state) {
      duration <- original_settle(state)
      expect_equal(duration, 0)
      settled <<- TRUE
      expect_true(drag_preview_absent(page))
      duration
    })
    expect_no_warning(pz_act_drag(
      page,
      '#preview-source .task-drag-handle',
      '#preview-target .task-drag-handle'
    ))
    expect_true(settled)
    expect_true(drag_preview_absent(page))
    expect_false(page_cursor(page)$pressed)
    pz_record_stop(page)
  }
  for (mutation in c('removed', 'replaced', 'hidden', 'resized')) {
    check_skip(mutation)
  }
})

test_that('the unpaused production path records carry and a one-row-up settle', {
  skip_if_no_av()
  page <- local_task_page(width = 800, height = 900)
  pz_stage(page, pause = 0, cursor_speed = 120)
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
  # Frames delivered after the action must include the settled position;
  # polling retained frames here also drains the screencast events queued
  # behind the settle.
  drag_preview_wait_retained_at(page, resting, from = first_settle_frame)
  rec <- page_recorder(page)
  action_files <- rec$files
  boxes <- lapply(action_files, function(path) {
    drag_preview_marker_box(page, path)
  })
  carry <- boxes[seq_len(first_settle_frame - 1L)]
  carry <- Filter(Negate(is.null), carry)
  expect_true(any(vapply(
    carry,
    function(box) {
      box$y > initial$y + initial$dy + 10 && box$y < target[['y']] - 5
    },
    logical(1)
  )))
  settle <- boxes[seq.int(first_settle_frame, length(boxes))]
  settle <- Filter(Negate(is.null), settle)
  expect_gte(length(settle), 2)
  ys <- vapply(settle, function(box) box$y, numeric(1))
  expect_true(any(ys > resting[['y']] + 4 & ys < target[['y']] - 4))
  expect_true(any(diff(ys) < -2))
  expect_lt(min(abs(ys - resting[['y']])), 2)
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

test_that('unsafe font stylesheets skip capture without mutations or changing the native drop', {
  skip_if_no_av()
  check_sheet <- function(case) {
    page <- local_task_page(width = 800, height = 900)
    pz_stage(page, pause = 0, cursor_speed = 120)
    drag_preview_task_marker(page)
    font <- pz_font_file(
      'OpaquePreviewFont',
      test_path('fixtures', 'fonts', 'silkscreen-400.woff2')
    )
    expect_true(pz_js(
      page,
      sprintf(
        "(() => {
          const style = document.createElement('style');
          const caseName = %s;
          const css = '.task { color: rgb(12,34,56); }';
          if (caseName === 'import') {
            style.textContent = '@import url(\"data:text/css,' + encodeURIComponent(css) + '\");';
            return new Promise((resolve, reject) => {
              style.onload = () => resolve(style.sheet.cssRules[0].type === CSSRule.IMPORT_RULE);
              style.onerror = () => reject(new Error('Import fixture failed'));
              document.head.appendChild(style);
            });
          }
          style.textContent = css + (caseName === 'font-url' ?
            '@media all { @font-face { font-family: UnusedPreviewFont; src: url(\"missing-preview-font.woff2\") format(\"woff2\"); } }' : '');
          document.head.appendChild(style);
          if (caseName === 'unreadable') {
            Object.defineProperty(style.sheet, 'href', {value: 'data:text/css,' + encodeURIComponent('.task {color: rgb(210,30,60)}')});
            Object.defineProperty(style.sheet, 'cssRules', {get() {
              throw new DOMException('Unreadable fixture stylesheet', 'SecurityError');
            }});
          }
          if (caseName === 'opaque-font') {
            const face = new FontFace('OpaquePreviewFont', 'url(data:font/woff2;base64,' + %s + ')');
            document.fonts.add(face);
            window.__previewSource.querySelector('.task-title').style.fontFamily = 'OpaquePreviewFont';
            return face.load().then(() => true);
          }
          return true;
        })()",
        jsonlite::toJSON(case, auto_unbox = TRUE),
        jsonlite::toJSON(gsub('[[:space:]]', '', font$data), auto_unbox = TRUE)
      )
    ))
    drag_preview_stylesheet_guard(page)
    before <- pz_js(page, 'window.__previewStyleSnapshot()')
    expect_equal(before$source[[1]], 'rgb(12, 34, 56)')
    pz_record_start(
      page,
      withr::local_tempfile(fileext = '.mp4'),
      hold = c(0, 0)
    )
    defer_record_stop(page)
    original_boot <- drag_preview_boot_js
    local_mocked_bindings(drag_preview_boot_js = function() {
      drag_preview_counted_boot(original_boot)
    })
    warnings <- list()
    withCallingHandlers(
      pz_act_drag(
        page,
        '#preview-source .task-drag-handle',
        '#preview-target .task-drag-handle'
      ),
      warning = function(w) {
        warnings <<- c(warnings, list(w))
        invokeRestart('muffleWarning')
      }
    )
    expect_length(warnings, 1)
    expect_s3_class(warnings[[1]], 'paparazzi_warning_drag_preview')
    expect_equal(pz_js(page, 'window.__previewCaptures || 0'), 0)
    expect_equal(pz_js(page, 'window.__previewInsertions'), 0)
    expect_equal(pz_js(page, 'window.__previewStyleSnapshot()'), before)
    expect_true(pz_js(
      page,
      'document.querySelectorAll(".task")[1] === window.__previewSource'
    ))
    expect_equal(
      unlist(pz_js(page, 'window.__previewEvents.map(e => e.type)')),
      c('dragstart', 'drop', 'dragend')
    )
    expect_true(pz_js(
      page,
      'window.__previewEvents.every(e => e.trusted) && window.__previewEvents.find(e => e.type === "drop").payload === window.__previewSource.dataset.id'
    ))
    expect_true(drag_preview_absent(page))
    expect_false(page_cursor(page)$pressed)
    pz_record_stop(page)
  }
  for (case in c('unreadable', 'import', 'font-url', 'opaque-font')) {
    check_sheet(case)
  }
})

test_that('dragstart transforms and filters deliberately disable the captured preview, not the drop', {
  skip_if_no_av()
  check_footprint <- function(property) {
    page <- local_task_page(width = 800, height = 900)
    pz_stage(page, pause = 0, cursor_speed = 120)
    drag_preview_task_marker(page)
    pz_js(
      page,
      sprintf(
        "document.addEventListener('dragstart', e => {
          if (e.target === window.__previewSource) e.target.style.%s = '%s';
        })",
        property,
        if (property == 'transform') 'translateX(1px)' else 'brightness(0.9)'
      )
    )
    pz_record_start(
      page,
      withr::local_tempfile(fileext = '.mp4'),
      hold = c(0, 0)
    )
    defer_record_stop(page)
    original_boot <- drag_preview_boot_js
    original_prepare <- drag_preview_prepare
    local_mocked_bindings(
      drag_preview_boot_js = function() {
        drag_preview_counted_boot(original_boot)
      },
      drag_preview_prepare = function(state, els, from) {
        original_prepare(state, els, from)
        pz_js(
          page,
          paste0('window.__previewController = ', DRAG_PREVIEW_CONTROLLER_JS)
        )
      }
    )
    warnings <- list()
    withCallingHandlers(
      pz_act_drag(
        page,
        '#preview-source .task-drag-handle',
        '#preview-target .task-drag-handle'
      ),
      warning = function(w) {
        warnings <<- c(warnings, list(w))
        invokeRestart('muffleWarning')
      }
    )
    expect_length(warnings, 1)
    expect_s3_class(warnings[[1]], 'paparazzi_warning_drag_preview')
    expect_match(
      conditionMessage(warnings[[1]]),
      'Unsupported drag preview footprint'
    )
    expect_equal(pz_js(page, 'window.__previewCaptures'), 1)
    expect_identical(pz_js(page, 'window.__previewFontEmbedCSS'), '')
    expect_true(pz_js(
      page,
      'window.__previewController.source === null && window.__previewController.image === null'
    ))
    expect_true(pz_js(
      page,
      'document.querySelectorAll(".task")[1] === window.__previewSource'
    ))
    expect_equal(
      unlist(pz_js(page, 'window.__previewEvents.map(e => e.type)')),
      c('dragstart', 'drop', 'dragend')
    )
    expect_true(pz_js(
      page,
      'window.__previewEvents.every(e => e.trusted) && window.__previewEvents.find(e => e.type === "drop").payload === window.__previewSource.dataset.id'
    ))
    expect_true(drag_preview_absent(page))
    expect_false(page_cursor(page)$pressed)
    pz_record_stop(page)
  }
  for (property in c('transform', 'filter')) {
    check_footprint(property)
  }
})

test_that('a real missing local image disables capture without blocking the drag', {
  skip_if_no_av()
  page <- local_task_page(width = 800, height = 900, timeout = 5)
  pz_stage(page, pause = 0, cursor_speed = 120)
  drag_preview_task_marker(page)
  expect_true(pz_js(
    page,
    "new Promise(resolve => {
      const image = document.createElement('img');
      image.id = 'preview-missing-image';
      image.alt = '';
      image.width = 12;
      image.height = 12;
      image.style.cssText = 'position:absolute;left:110px;top:12px;pointer-events:none;';
      window.__previewImageError = false;
      image.onerror = () => { window.__previewImageError = true; resolve(true); };
      image.onload = () => resolve(false);
      window.__previewSource.appendChild(image);
      image.src = 'missing-drag-preview.png';
    })"
  ))
  expect_true(pz_js(
    page,
    "(() => {
      const image = document.querySelector('#preview-missing-image');
      return window.__previewImageError && image.complete && image.naturalWidth === 0 &&
        image.width === 12 && image.height === 12;
    })()"
  ))
  pz_record_start(page, withr::local_tempfile(fileext = '.mp4'), hold = c(0, 0))
  defer_record_stop(page)
  original_boot <- drag_preview_boot_js
  original_prepare <- drag_preview_prepare
  original_carry <- stage_drag_carry
  original_timeout <- page$default_timeout
  carried <- FALSE
  local_mocked_bindings(
    drag_preview_boot_js = function() drag_preview_counted_boot(original_boot),
    drag_preview_prepare = function(state, els, from) {
      # Bound the real capture if missing-image handling ever stops settling.
      page$default_timeout <- 2
      on.exit(page$default_timeout <- original_timeout)
      original_prepare(state, els, from)
    },
    stage_drag_carry = function(ctx, from, to, step) {
      original_carry(ctx, from, to, function(point) {
        step(point)
        if (!carried) {
          expect_true(drag_preview_absent(ctx))
          carried <<- TRUE
        }
      })
    }
  )
  warnings <- list()
  withCallingHandlers(
    pz_act_drag(
      page,
      '#preview-source .task-drag-handle',
      '#preview-target .task-drag-handle'
    ),
    warning = function(w) {
      warnings <<- c(warnings, list(w))
      invokeRestart('muffleWarning')
    }
  )
  expect_length(warnings, 1)
  expect_s3_class(warnings[[1]], 'paparazzi_warning_drag_preview')
  expect_match(
    conditionMessage(warnings[[1]]),
    'JavaScript error preparing the drag preview: Event',
    fixed = TRUE
  )
  expect_true(carried)
  expect_equal(pz_js(page, 'window.__previewCaptures'), 1)
  expect_true(drag_preview_absent(page))
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
  expect_false(page_cursor(page)$pressed)
  pz_record_stop(page)
})

test_that('SVG use and iframe skip capture before copying outside the source subtree', {
  skip_if_no_av()
  check_use <- function(redacted, iframe = FALSE) {
    page <- local_page(width = 800, height = 600)
    pz_stage(page, pause = 0)
    pz_js(
      page,
      "(() => {
        document.body.insertAdjacentHTML('beforeend', `
          <div id='preview-definitions' style='position:absolute;left:400px;top:140px;width:100px;height:40px'>
            <svg width='100' height='40'><defs><g id='secret'><rect width='20' height='20' fill='rgb(8,200,80)'/></g></defs></svg>
          </div>
          <div id='preview-source' draggable='true' style='position:absolute;left:40px;top:140px;width:124px;height:64px'>
            <svg xmlns:xlink='http://www.w3.org/1999/xlink' width='100' height='40'><use xlink:href='#secret'/></svg>
          </div>
          <div id='preview-target' style='position:absolute;left:40px;top:340px;width:124px;height:64px'>Drop here</div>`);
        const source = document.querySelector('#preview-source');
        const target = document.querySelector('#preview-target');
        source.addEventListener('dragstart', e => e.dataTransfer.setData('text/plain', 'svg-use'));
        target.addEventListener('dragover', e => e.preventDefault());
        target.addEventListener('drop', e => {
          e.preventDefault();
          target.dataset.payload = e.dataTransfer.getData('text/plain');
          target.dataset.drops = String(Number(target.dataset.drops || 0) + 1);
        });
        return source.querySelector('use') instanceof SVGUseElement &&
          !source.contains(document.querySelector('#secret'));
      })()"
    )
    if (iframe) {
      expect_true(pz_js(
        page,
        "new Promise(resolve => {
          const frame = document.createElement('iframe');
          frame.style.cssText = 'width:100px;height:40px;border:0;pointer-events:none';
          frame.srcdoc = '<body><div id=frame-secret style=display:none>PRIVATE FRAME CONTENT</div></body>';
          frame.onload = () => resolve(
            frame.contentDocument.querySelector('#frame-secret').textContent === 'PRIVATE FRAME CONTENT' &&
            !document.querySelector('#preview-source').contains(frame.contentDocument.body)
          );
          document.querySelector('#preview-source').replaceChildren(frame);
        })"
      ))
    }
    if (redacted) {
      # Install while rendered; hidden external definitions still participate
      # in html-to-image's ensureSVGSymbols, outside source containment checks.
      pz_annotate_redact(page, '#preview-definitions')
    }
    pz_js(
      page,
      "document.querySelector('#preview-definitions').style.display = 'none'"
    )
    pz_record_start(
      page,
      withr::local_tempfile(fileext = '.mp4'),
      hold = c(0, 0)
    )
    defer_record_stop(page)
    original_boot <- drag_preview_boot_js
    local_mocked_bindings(drag_preview_boot_js = function() {
      drag_preview_counted_boot(original_boot)
    })
    warnings <- list()
    withCallingHandlers(
      pz_act_drag(page, '#preview-source', '#preview-target'),
      warning = function(w) {
        warnings <<- c(warnings, list(w))
        invokeRestart('muffleWarning')
      }
    )
    expect_length(warnings, 1)
    expect_s3_class(warnings[[1]], 'paparazzi_warning_drag_preview')
    expect_match(
      conditionMessage(warnings[[1]]),
      'Unsupported drag preview footprint'
    )
    expect_equal(pz_js(page, 'window.__previewCaptures || 0'), 0)
    expect_equal(
      pz_js(page, "document.querySelector('#preview-target').dataset.drops"),
      '1'
    )
    expect_equal(
      pz_js(page, "document.querySelector('#preview-target').dataset.payload"),
      'svg-use'
    )
    expect_true(drag_preview_absent(page))
    expect_false(page_cursor(page)$pressed)
    pz_record_stop(page)
  }
  check_use(TRUE)
  # Even without redaction, all use references are conservatively unsupported.
  check_use(FALSE)
  # iframe contentDocument.body also lies outside the source-document subtree.
  check_use(FALSE, iframe = TRUE)
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
  expect_lt(
    max(abs(
      unlist(border[c('x', 'y', 'width', 'height')]) -
        unlist(capture[c('x', 'y', 'width', 'height')])
    )),
    1.5
  )
  expect_lt(
    max(abs(
      unlist(marker[c('x', 'y', 'width', 'height')]) -
        c(capture$x + 114, capture$y + 54, 8, 8)
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

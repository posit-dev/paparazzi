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
        fps = 2,
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

test_that('file pages explain unreadable stylesheets and link to drag preview help', {
  skip_if_no_av()
  page <- local_page(
    paste0('file://', pz_example('tasks')),
    width = 800,
    height = 900
  )
  pz_stage(page, pause = 0)
  drag_preview_task_marker(page)
  pz_record_start(
    page,
    withr::local_tempfile(fileext = '.mp4'),
    fps = 2,
    hold = c(0, 0)
  )
  defer_record_stop(page)
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
  message <- conditionMessage(warnings[[1]])
  expect_true(all(vapply(
    c(
      "cannot read the page's stylesheets",
      'HTTP',
      'httpuv',
      'pz_open',
      'pz_serve_static',
      'preview = FALSE'
    ),
    grepl,
    logical(1),
    x = message,
    fixed = TRUE
  )))
  expect_match(message, 'Drag preview section')
  expect_match(message, 'pz_act_drag')
  expect_false(grepl('<anonymous>|cssRules|SecurityError', message))
  expect_true(drag_preview_absent(page))
  expect_true(pz_js(
    page,
    'document.querySelectorAll(".task")[1] === window.__previewSource'
  ))
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
      fps = 2,
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
  pz_record_start(
    page,
    withr::local_tempfile(fileext = '.mp4'),
    fps = 2,
    hold = c(0, 0)
  )
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
  pz_record_start(
    page,
    withr::local_tempfile(fileext = '.mp4'),
    fps = 2,
    hold = c(0, 0)
  )
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
      fps = 2,
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

test_that('a source that gains an iframe after the drop loses its preview silently', {
  skip_if_no_av()
  page <- local_task_page(width = 800, height = 900)
  pz_stage(page, pause = 0)
  drag_preview_task_marker(page)
  pz_record_start(
    page,
    withr::local_tempfile(fileext = '.mp4'),
    fps = 2,
    hold = c(0, 0)
  )
  defer_record_stop(page)
  # The iframe arrives in the drop handler, after the preview is prepared
  # and before the post-drop settle re-checks the source.
  pz_js(
    page,
    paste0(
      "document.addEventListener('drop', () => {",
      "document.querySelector('#preview-source')",
      ".insertAdjacentHTML('beforeend',",
      "'<iframe srcdoc=\"<body></body>\" style=\"width:10px;height:10px;border:0\"></iframe>');",
      "})"
    )
  )
  original_settle <- drag_preview_settle
  settled <- FALSE
  local_mocked_bindings(drag_preview_settle = function(state) {
    expect_false(is.null(state))
    expect_false(drag_preview_absent(page))
    duration <- original_settle(state)
    settled <<- TRUE
    expect_equal(duration, 0)
    expect_true(drag_preview_absent(page))
    expect_true(pz_js(
      page,
      "document.querySelector('#preview-source iframe') instanceof HTMLIFrameElement"
    ))
    duration
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
  expect_true(settled)
  expect_length(warnings, 0)
})

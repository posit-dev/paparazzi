test_that('redaction rejects unsafe capture before the library while preserving the drop', {
  skip_if_no_av()
  check_redaction <- function(case) {
    page <- local_task_page(width = 800, height = 900)
    page <- pz_stage(page, pause = 0)
    drag_preview_task_marker(page)
    if (
      case %in% c('unrelated-fill', 'unrelated-blur', 'unavailable', 'invalid')
    ) {
      pz_annotate_redact(
        page,
        '#task_title',
        method = if (case == 'unrelated-blur') 'blur' else 'fill'
      )
    } else if (case == 'ancestor') {
      pz_annotate_redact(page, '.task-list')
    } else if (case == 'hidden-descendant') {
      pz_annotate_redact(page, '#preview-marker')
      pz_evaluate(
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
      pz_evaluate(
        page,
        'document.querySelector("#paparazzi-overlay-root").shadowRoot.querySelector(".pz-annotations").remove()'
      )
    }
    if (case == 'invalid') {
      pz_evaluate(
        page,
        'document.querySelector("#paparazzi-overlay-root").shadowRoot.querySelector(".pz-annotations").pz.dragPreviewSafety = () => ({safe:"unknown"})'
      )
    }
    pz_record_start(
      page,
      withr::local_tempfile(fileext = '.mp4'),
      fps = 2,
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
      expect_match(conditionMessage(warnings[[1]]), 'redaction')
      expect_match(conditionMessage(warnings[[1]]), 'Keep redactions separate')
      expect_match(conditionMessage(warnings[[1]]), 'Drag preview section')
    }
    expect_equal(
      pz_evaluate(page, 'window.__previewCaptures || 0'),
      if (safe) 1 else 0
    )
    expect_true(pz_evaluate(
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
    page <- pz_stage(page, pause = 0)
    drag_preview_task_marker(page)
    pz_record_start(
      page,
      withr::local_tempfile(fileext = '.mp4'),
      fps = 2,
      hold = c(0, 0)
    )
    defer_record_stop(page)
    original_boot <- drag_preview_boot_js
    original_prepare <- drag_preview_prepare
    if (method == 'decode') {
      pz_evaluate(
        page,
        "window.__realDecode = Image.prototype.decode"
      )
      withr::defer(pz_evaluate(
        page,
        'Image.prototype.decode = window.__realDecode'
      ))
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
          pz_evaluate(
            page,
            sprintf(
              r"[
(() => {
  const preview = %s;
  window.__previewController = preview;
  preview.%s = () => { throw new Error("injected %s failure") };
})()
]",
              DRAG_PREVIEW_CONTROLLER_JS,
              method,
              method
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
    expect_match(
      conditionMessage(warnings[[1]]),
      'The optional drag preview was disabled; the drag will continue.',
      fixed = TRUE
    )
    expect_match(conditionMessage(warnings[[1]]), 'Drag preview section')
    expect_match(conditionMessage(warnings[[1]]), 'pz_act_drag')
    expect_false(grepl(
      '<anonymous>|\\n\\s+at ',
      conditionMessage(warnings[[1]])
    ))
    expect_equal(pz_evaluate(page, 'window.__previewCaptures'), 1)
    expect_true(pz_evaluate(
      page,
      'document.querySelectorAll(".task")[1] === window.__previewSource'
    ))
    expect_true(drag_preview_absent(page))
    if (method %in% c('show', 'move', 'settle')) {
      expect_true(pz_evaluate(
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

test_that('unsafe font stylesheets skip capture without mutations or changing the native drop', {
  skip_if_no_av()
  check_sheet <- function(case) {
    page <- local_task_page(width = 800, height = 900)
    page <- pz_stage(page, pause = 0)
    drag_preview_task_marker(page)
    font <- pz_font_file(
      'OpaquePreviewFont',
      test_path('fixtures', 'fonts', 'silkscreen-400.woff2')
    )
    expect_true(pz_evaluate(
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
          style.textContent = css + (caseName === 'group' ? '@layer preview { ' + css + ' }' : caseName === 'font-url' ?
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
    before <- pz_evaluate(page, 'window.__previewStyleSnapshot()')
    expect_equal(before$source[[1]], 'rgb(12, 34, 56)')
    pz_record_start(
      page,
      withr::local_tempfile(fileext = '.mp4'),
      fps = 2,
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
    message <- conditionMessage(warnings[[1]])
    expect_match(
      message,
      if (case == 'unreadable') {
        'cannot read the page.*stylesheets'
      } else {
        'unsupported CSS rule groups, imported stylesheets'
      }
    )
    expect_match(
      message,
      if (case == 'unreadable') 'HTTP' else 'data URLs in @font-face rules'
    )
    expect_match(message, 'Drag preview section')
    expect_equal(pz_evaluate(page, 'window.__previewCaptures || 0'), 0)
    expect_equal(pz_evaluate(page, 'window.__previewInsertions'), 0)
    expect_equal(pz_evaluate(page, 'window.__previewStyleSnapshot()'), before)
    expect_true(pz_evaluate(
      page,
      'document.querySelectorAll(".task")[1] === window.__previewSource'
    ))
    expect_equal(
      unlist(pz_evaluate(page, 'window.__previewEvents.map(e => e.type)')),
      c('dragstart', 'drop', 'dragend')
    )
    expect_true(pz_evaluate(
      page,
      'window.__previewEvents.every(e => e.trusted) && window.__previewEvents.find(e => e.type === "drop").payload === window.__previewSource.dataset.id'
    ))
    expect_true(drag_preview_absent(page))
    expect_false(page_cursor(page)$pressed)
    pz_record_stop(page)
  }

  for (case in c('unreadable', 'import', 'font-url', 'opaque-font', 'group')) {
    check_sheet(case)
  }
})

test_that('dragstart transforms and filters deliberately disable the captured preview, not the drop', {
  skip_if_no_av()
  check_footprint <- function(property) {
    page <- local_task_page(width = 800, height = 900)
    page <- pz_stage(page, pause = 0)
    drag_preview_task_marker(page)
    pz_evaluate(
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
      fps = 2,
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
        pz_evaluate(
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
      'source geometry or content cannot be captured safely'
    )
    expect_match(
      conditionMessage(warnings[[1]]),
      'Use a source without transforms'
    )
    expect_match(conditionMessage(warnings[[1]]), 'Drag preview section')
    expect_equal(pz_evaluate(page, 'window.__previewCaptures'), 1)
    expect_identical(pz_evaluate(page, 'window.__previewFontEmbedCSS'), '')
    expect_true(pz_evaluate(
      page,
      'window.__previewController.source === null && window.__previewController.image === null'
    ))
    expect_true(pz_evaluate(
      page,
      'document.querySelectorAll(".task")[1] === window.__previewSource'
    ))
    expect_equal(
      unlist(pz_evaluate(page, 'window.__previewEvents.map(e => e.type)')),
      c('dragstart', 'drop', 'dragend')
    )
    expect_true(pz_evaluate(
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
  page <- pz_stage(page, pause = 0)
  drag_preview_task_marker(page)

  expect_true(pz_evaluate(
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

  expect_true(pz_evaluate(
    page,
    "(() => {
      const image = document.querySelector('#preview-missing-image');
      return window.__previewImageError && image.complete && image.naturalWidth === 0 &&
        image.width === 12 && image.height === 12;
    })()"
  ))

  pz_record_start(
    page,
    withr::local_tempfile(fileext = '.mp4'),
    fps = 2,
    hold = c(0, 0)
  )
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
    'Failed to load the img needed for the preview (error)',
    fixed = TRUE
  )

  expect_true(carried)
  expect_equal(pz_evaluate(page, 'window.__previewCaptures'), 1)
  expect_true(drag_preview_absent(page))
  expect_true(pz_evaluate(
    page,
    'document.querySelectorAll(".task")[1] === window.__previewSource'
  ))
  expect_equal(
    unlist(pz_evaluate(
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
    page <- pz_stage(page, pause = 0)
    pz_evaluate(
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
      expect_true(pz_evaluate(
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
    pz_evaluate(
      page,
      "document.querySelector('#preview-definitions').style.display = 'none'"
    )
    pz_record_start(
      page,
      withr::local_tempfile(fileext = '.mp4'),
      fps = 2,
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
      'source contains an iframe or SVG <use> reference'
    )
    expect_match(
      conditionMessage(warnings[[1]]),
      'Use a source without these references'
    )
    expect_match(conditionMessage(warnings[[1]]), 'Drag preview section')
    expect_equal(pz_evaluate(page, 'window.__previewCaptures || 0'), 0)
    expect_equal(
      pz_evaluate(
        page,
        "document.querySelector('#preview-target').dataset.drops"
      ),
      '1'
    )
    expect_equal(
      pz_evaluate(
        page,
        "document.querySelector('#preview-target').dataset.payload"
      ),
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

test_that('unknown preview failures preserve literal messages and omit multiline stacks', {
  message <- 'unfamiliar {value} at the source\n    at prepare (<anonymous>:1:2)\n    at run (<anonymous>:3:4)'
  expect_identical(
    drag_preview_error_message(message),
    'unfamiliar {value} at the source'
  )

  state <- new.env(parent = emptyenv())
  state$owner <- TRUE
  state$warned <- FALSE
  local_mocked_bindings(drag_preview_dispose = function(state) {
    state$owner <- NULL
  })
  warnings <- list()
  withCallingHandlers(
    drag_preview_optional(state, function(ctx) {
      drag_preview_result(list(
        failure = list(
          reason = 'future-reason',
          message = 'unfamiliar {value} at the source'
        )
      ))
    }),
    warning = function(w) {
      warnings <<- c(warnings, list(w))
      invokeRestart('muffleWarning')
    }
  )

  expect_length(warnings, 1)
  expect_s3_class(warnings[[1]], 'paparazzi_warning_drag_preview')
  expect_match(
    conditionMessage(warnings[[1]]),
    'unfamiliar {value} at the source',
    fixed = TRUE
  )
  expect_match(conditionMessage(warnings[[1]]), 'Drag preview section')

  expect_no_warning(drag_preview_optional(state, function(ctx) {
    stop('a disabled preview must not run again')
  }))
})

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
# Verify tighter than the pixel assertions (1.5px) so a verified frame
# can't fail them on the margin.
drag_preview_marker_at <- function(
  page,
  point,
  color = c(8, 200, 80),
  tolerance = 1
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
# The 10s budget covers starved runners: each verify is a canvas-decode
# round-trip (~1s under contention) and stale-but-late frames consume polls.
drag_preview_retained_checkpoint <- function(
  page,
  verify = NULL,
  timeout = 10
) {
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
    sprintf(
      r"(
        const original = exports.toPng; exports.toPng = (...args) => {
        window.__previewCaptures = (window.__previewCaptures || 0) + 1;
        window.__previewFontEmbedCSS = args[1]?.fontEmbedCSS;
        %s
        };
        return (
      )",
      replacement
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

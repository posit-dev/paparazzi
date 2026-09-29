#' Mark page elements
#'
#' Draws an annotation for each element matched by `target`. Annotations
#' follow their elements as the page scrolls or changes layout, and appear
#' in screenshots and recordings until cleared with [pz_annotate_clear()].
#' Annotations belong to the current document; navigating away removes them.
#'
#' @inheritParams pz_click
#' @param target A selector, [pz_loc()] spec, or list of targets.
#'   `NULL` uses the current scope, or `document.body` at the root.
#' @param ... Checked empty; reserved for future use.
#' @param type `"box"` (outline), `"circle"` (ellipse), `"underline"` (bottom
#'   stroke), or `"highlight"` (translucent fill blended over the page).
#' @param label Optional badge. `TRUE` numbers the matches 1, 2, ...;
#'   one string or number repeats on each match.
#' @param pad Extra CSS pixels around each element: one number or
#'   `c(top, right, bottom, left)`. `NULL` uses zero.
#' @param reveal `"fade"`, `"draw"`, `"pop"`, `"slide"`, `"wipe"`, or
#'   `"none"`. `NULL` uses fade for boxes and draw for the other types.
#'   Reveals animate only during an active, unpaused recording; clearing
#'   reverses the reveal. Wipe sweeps clockwise from 12 o'clock.
#' @param id Optional nonempty id. Reusing it replaces its annotations;
#'   `"spotlight"` and `"caption"` are reserved for other types.
#' @param color CSS color for the outline and badge, or `NULL` for the
#'   page default from [pz_stage()].
#' @param font_family CSS font family for the badge, or `NULL` for the
#'   page default.
#' @param font_size Badge font size in CSS pixels, or `NULL` for the page
#'   default.
#'
#' @return `ctx`, invisibly.
#' @seealso [pz_annotate_clear()], [pz_stage()]
#' @export
pz_annotate <- function(
  ctx,
  target = NULL,
  ...,
  type = "box",
  label = NULL,
  pad = NULL,
  reveal = NULL,
  id = NULL,
  color = NULL,
  font_family = NULL,
  font_size = NULL
) {
  check_context(ctx)
  check_dots_empty()
  if (
    !is.character(type) ||
      length(type) != 1L ||
      is.na(type) ||
      !type %in% c("box", "circle", "underline", "highlight")
  ) {
    cli::cli_abort(
      "{.arg type} must be {.val box}, {.val circle}, {.val underline}, or {.val highlight}."
    )
  }
  reveal <- reveal %||% if (identical(type, "box")) "fade" else "draw"
  if (
    !is.character(reveal) ||
      length(reveal) != 1L ||
      is.na(reveal) ||
      !reveal %in% c("fade", "draw", "pop", "slide", "wipe", "none")
  ) {
    cli::cli_abort(
      "{.arg reveal} must be {.val fade}, {.val draw}, {.val pop}, {.val slide}, {.val wipe}, or {.val none}."
    )
  }
  check_annotation_id(id)
  if (!is.null(label)) {
    if (isTRUE(label)) {
      label <- TRUE
    } else if (
      (is.character(label) || is.numeric(label)) &&
        length(label) == 1L &&
        !is.na(label)
    ) {
      label <- as.character(label)
    } else {
      cli::cli_abort("{.arg label} must be `TRUE`, one string or one number.")
    }
  }
  pad <- check_pad(pad %||% 0, arg = "pad")
  stage <- page_stage(ctx$page)
  color <- color %||% stage$annotate_color
  font_family <- font_family %||% stage$annotate_font_family
  font_size <- font_size %||% stage$annotate_font_size
  check_string(color)
  check_string(font_family)
  check_number_decimal(font_size, min = 0, allow_infinite = FALSE)
  if (font_size == 0) {
    cli::cli_abort("{.arg font_size} must be greater than 0.")
  }
  els <- annotate_elements(ctx, target)
  annotate_register_init(ctx)
  recording <- annotate_recording(ctx$page)
  options <- list(
    id = id,
    type = type,
    pad = unname(pad),
    label = label,
    color = color,
    fontFamily = font_family,
    fontSize = font_size,
    reveal = reveal,
    animate = recording
  )
  duration <- annotate_call(ctx, els, "draw", options, "drawing the annotation")
  if (recording && duration > 0) {
    pump_loop(ctx$page$child_loop, duration / 1000 + 0.05)
  }
  ctx_return(ctx)
}

#' Redact page elements
#'
#' Covers every element matched by `target` with an instant opaque fill or
#' backdrop blur in screenshots and recordings. Fill is the safe choice for
#' secrets: blur can leave text partly legible. Redactions follow elements
#' as they move; if an element disconnects or stops rendering, its last box
#' remains until cleared. They belong to the current document and are lost
#' on navigation. Redaction covers each element's border box plus `pad`, not
#' overflowing descendants; target the overflowing element or add padding. Later
#' top-layer UI (modal dialogs and popovers) paints above redactions, so
#' targets inside an open modal or popover are rejected.
#'
#' @inheritParams pz_annotate
#' @param method `"fill"` (default) or `"blur"` (32 CSS px backdrop blur).
#' @param pad Extra CSS pixels around each element; `NULL` uses zero.
#' @param id Optional nonempty id; reusing it replaces the old annotation.
#'   `"spotlight"` and `"caption"` are reserved.
#' @param color CSS color for fill; `NULL` uses near-black (`#171717`), not
#'   the staged mark color. A near-black opaque base stays underneath even
#'   when a custom color is translucent or invalid. Cannot be set for blur.
#' @return `ctx`, invisibly.
#' @seealso [pz_annotate()], [pz_annotate_clear()]
#' @export
pz_annotate_redact <- function(
  ctx,
  target = NULL,
  ...,
  method = c("fill", "blur"),
  pad = NULL,
  id = NULL,
  color = NULL
) {
  check_context(ctx)
  check_dots_empty()
  method <- rlang::arg_match(method)
  check_annotation_id(id)
  if (!is.null(color)) {
    check_string(color)
    if (method == "blur") {
      cli::cli_abort(
        "{.arg color} is only supported with {.code method = 'fill'}."
      )
    }
  }
  pad <- check_pad(pad %||% 0, arg = "pad")
  els <- annotate_elements(ctx, target)
  annotate_register_init(ctx)
  options <- list(id = id, method = method, pad = unname(pad), color = color)
  annotate_call(ctx, els, "redact", options, "redacting the elements")
  ctx_return(ctx)
}

#' Clear page annotations
#'
#' Remove an annotation by id, or remove every annotation when `id` is
#' `NULL`. During an active recording, marks play their reveal in reverse
#' before removal; paused recordings and stills clear instantly.
#'
#' @inheritParams pz_annotate
#' @param id Id to clear; `NULL` clears all. Reserved ids are allowed.
#' @return `ctx`, invisibly.
#' @export
pz_annotate_clear <- function(ctx, id = NULL, ...) {
  check_context(ctx)
  check_dots_empty()
  if (!is.null(id)) {
    check_string(id)
    if (!nzchar(id)) {
      cli::cli_abort("{.arg id} must be nonempty.")
    }
  }
  recording <- annotate_recording(ctx$page)
  data <- jsonlite::toJSON(
    list(id = id, animate = recording),
    auto_unbox = TRUE,
    null = "null"
  )
  duration <- pz_js(
    ctx,
    paste0(
      "(() => { const h = document.getElementById('paparazzi-overlay-root'); ",
      "return h?.shadowRoot?.querySelector('.pz-annotations')?.pz?.clear(",
      data,
      ") || false; })()"
    )
  )
  # Log the caption clear at the call's video time, not after mark fades.
  if (is.null(id) || identical(id, "caption")) {
    caption_clear(ctx$page)
  }
  if (recording && duration > 0) {
    pump_loop(ctx$page$child_loop, duration / 1000 + 0.05)
    pz_js(
      ctx,
      "document.getElementById('paparazzi-overlay-root')?.shadowRoot?.querySelector('.pz-annotations')?.pz?.finishClear()"
    )
  }
  ctx_return(ctx)
}

annotate_elements <- function(ctx, target, frame = caller_env()) {
  scoped <- if (is.null(target)) scope_root(ctx, call = frame)
  if (!is.null(scoped)) {
    return(scoped)
  }
  els <- loc_resolve(ctx, target, multiple = "all", call = frame)
  withr::defer(release_elements(els), envir = frame)
  els
}

check_annotation_id <- function(id, call = caller_env()) {
  if (is.null(id)) {
    return(invisible(NULL))
  }
  check_string(id, call = call)
  if (!nzchar(id) || id %in% c("spotlight", "caption")) {
    cli::cli_abort(
      "{.arg id} must be nonempty and cannot be {.val spotlight} or {.val caption}.",
      call = call
    )
  }
  invisible(NULL)
}

# Calls a layer entry point with the resolved elements as `this`, booting
# the layer first if this document doesn't have one yet.
annotate_call <- function(ctx, els, fn, options, what) {
  json <- jsonlite::toJSON(options, auto_unbox = TRUE, null = "null")
  timeout <- ctx$page$default_timeout
  res <- cdp_call(
    ctx$page$session$Runtime$callFunctionOn(
      paste0(
        "function() { return (",
        annotate_boot_js,
        ")().pz.",
        fn,
        "(this, ",
        json,
        "); }"
      ),
      objectId = els$object_id,
      returnByValue = TRUE,
      timeout_ = timeout
    ),
    timeout,
    what
  )
  cdp_check_exception(res, what)
  res$result$value
}

annotate_recording <- function(page) {
  stage_recording(page) && !isTRUE(page_recorder(page)$paused)
}

annotate_register_init <- function(ctx) {
  page <- ctx$page
  if (!is.null(page$.__enclos_env__$private$staging_$annotate_init_id)) {
    return(invisible(NULL))
  }
  session <- page$session
  timeout <- page$default_timeout
  session$Page$enable(timeout_ = timeout)
  source <- paste0(
    "(() => { const boot = () => (",
    annotate_boot_js,
    ")(); ",
    "if (document.documentElement) boot(); ",
    "else document.addEventListener('DOMContentLoaded', boot, {once:true}); })();"
  )
  res <- session$Page$addScriptToEvaluateOnNewDocument(
    source = source,
    timeout_ = timeout
  )
  page$.__enclos_env__$private$staging_$annotate_init_id <- res$identifier
  invisible(NULL)
}

# A document-bound runtime: the layer owns the only Map of annotations.
annotate_boot_js <- r"(function() {
  let host = document.getElementById('paparazzi-overlay-root');
  if (!host) {
    host = document.createElement('div');
    host.id = 'paparazzi-overlay-root';
    host.style.cssText = 'position:absolute;top:0;left:0;width:0;height:0;z-index:2147483647;pointer-events:none;';
    document.documentElement.appendChild(host);
  }
  if (!host.shadowRoot) host.attachShadow({mode:'open'});
  const root = host.shadowRoot;
  let layer = root.querySelector('.pz-annotations');
  if (layer) return layer;
  layer = document.createElement('div');
  layer.className = 'pz-annotations';
  layer.setAttribute('aria-hidden', 'true');
  layer.style.cssText = 'position:fixed;left:0;top:0;pointer-events:none;z-index:0;';
  root.appendChild(layer);
  const entries = new Map();
  let frame = null;
  let next = 0;
  const durations = {none:0, fade:250, draw:350, pop:250, slide:300, wipe:400};
  const svgNS = 'http://www.w3.org/2000/svg';
  const keys = (reveal, path) => {
    switch (reveal) {
      case 'fade': return [{opacity:0},{opacity:1}];
      case 'draw': return path ? [{strokeDashoffset:1},{strokeDashoffset:0}] :
        [{transform:'scaleX(0)'},{transform:'scaleX(1)'}];
      case 'pop': return [{opacity:0,transform:'scale(.85)'},
                          {opacity:1,transform:'scale(1)'}];
      case 'slide': return [{opacity:0,transform:'translateY(12px)'},
                            {opacity:1,transform:'translateY(0)'}];
      case 'wipe': return Array.from({length:73}, (_, i) => ({
        maskImage:`conic-gradient(#000 ${i * 5}deg, transparent 0)`,
        offset:i / 72
      }));
    }
    return [];
  };
  const start = (node, reveal, entering, shape) => {
    const target = reveal === 'draw' ? (shape.tagName === 'svg' ? shape.firstChild : shape) :
      reveal === 'wipe' ? shape : node;
    const anim = target.animate(keys(reveal, target instanceof SVGGeometryElement), {
      duration:durations[reveal], fill:'forwards',
      direction:entering ? 'normal' : 'reverse', easing:'linear'
    });
    if (entering) anim.onfinish = () => {
      if (reveal === 'wipe') target.style.maskImage = 'none';
      anim.cancel();
    };
    else anim.onfinish = () => node.remove();
  };
  const stroke = kind => {
    const svg = document.createElementNS(svgNS, 'svg');
    svg.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;overflow:visible;';
    const path = document.createElementNS(svgNS, kind);
    path.setAttribute('pathLength', '1');
    path.style.cssText = 'fill:none;stroke:currentColor;stroke-width:3;vector-effect:non-scaling-stroke;stroke-dasharray:1;';
    svg.appendChild(path);
    return svg;
  };
  const clamp = (x, lo, hi) => Math.min(Math.max(x, lo), hi);
  const positionCallout = (entry, i, r) => {
    const box = entry.nodes[i];
    const {width:w, height:h, side} = entry.places[i];
    const gap = 8;
    const x = side.includes('left') ? r.left - w - gap :
      side.includes('right') ? r.right + gap : r.left + (r.width - w) / 2;
    const y = side.includes('top') ? r.top - h - gap :
      side.includes('bottom') ? r.bottom + gap : r.top + (r.height - h) / 2;
    const insetX = Math.min(gap, innerWidth / 2);
    const insetY = Math.min(gap, innerHeight / 2);
    const left = clamp(x, insetX, Math.max(insetX, innerWidth - insetX - w));
    const top = clamp(y, insetY, Math.max(insetY, innerHeight - insetY - h));
    box.style.left = left + 'px';
    box.style.top = top + 'px';
    if (!entry.arrow) return;
    const svg = box.querySelector('svg');
    if (left < r.right && left + w > r.left && top < r.bottom && top + h > r.top) {
      svg.style.display = 'none';
      return;
    }
    svg.style.display = '';
    const nearest = (a, b, c, d) => {
      if (b < c) return [b, c];
      if (d < a) return [a, d];
      const middle = (Math.max(a, c) + Math.min(b, d)) / 2;
      return [middle, middle];
    };
    const [bx, tx] = nearest(left, left + w, r.left, r.right);
    const [by, ty] = nearest(top, top + h, r.top, r.bottom);
    const dx = tx - bx, dy = ty - by;
    const length = Math.hypot(dx, dy) || 1;
    const ux = dx / length, uy = dy / length;
    const headLength = Math.min(9, length * 0.7);
    const headWidth = Math.min(4, length * 0.3);
    const line = svg.firstChild;
    line.setAttribute('x1', bx - left);
    line.setAttribute('y1', by - top);
    line.setAttribute('x2', tx - left);
    line.setAttribute('y2', ty - top);
    svg.lastChild.setAttribute('points', [
      [tx - left, ty - top],
      [tx - left - ux * headLength - uy * headWidth,
       ty - top - uy * headLength + ux * headWidth],
      [tx - left - ux * headLength + uy * headWidth,
       ty - top - uy * headLength - ux * headWidth]
    ].map(p => p.join(',')).join(' '));
  };
  const sync = () => {
    if (!entries.size) return;
    const zoom = parseFloat(getComputedStyle(document.documentElement).zoom) || 1;
    layer.style.zoom = String(1 / zoom);
    for (const entry of entries.values()) {
      if (entry.spotlight) {
        const svg = entry.nodes[0];
        const mask = svg.querySelector('mask');
        const vw = window.innerWidth, vh = window.innerHeight;
        const docW = Math.max(document.documentElement.scrollWidth, document.body.scrollWidth);
        const docH = Math.max(document.documentElement.scrollHeight, document.body.scrollHeight);
        const docLeft = getComputedStyle(document.documentElement).direction === 'rtl' &&
          docW > vw ? -(docW - vw) : 0;
        const left = Math.min(0, docLeft - window.scrollX);
        const top = Math.min(0, -window.scrollY);
        const width = Math.max(vw, docLeft - window.scrollX + docW) - left;
        const height = Math.max(vh, -window.scrollY + docH) - top;
        svg.style.left = left + 'px';
        svg.style.top = top + 'px';
        svg.setAttribute('width', width);
        svg.setAttribute('height', height);
        mask.setAttribute('x', 0);
        mask.setAttribute('y', 0);
        mask.setAttribute('width', width);
        mask.setAttribute('height', height);
        mask.firstChild.setAttribute('width', width);
        mask.firstChild.setAttribute('height', height);
        svg.lastChild.setAttribute('width', width);
        svg.lastChild.setAttribute('height', height);
        entry.elements.forEach((el, i) => {
          const hole = entry.holes[i];
          if (!el.isConnected || !el.getClientRects().length) {
            hole.style.display = 'none';
            return;
          }
          const r = el.getBoundingClientRect(), p = entry.pad;
          const w = r.width + p[1] + p[3], h = r.height + p[0] + p[2];
          if (getComputedStyle(el).visibility !== 'visible' || r.width <= 0 ||
              r.height <= 0 || w <= 0 || h <= 0) {
            hole.style.display = 'none';
            return;
          }
          hole.style.display = '';
          hole.setAttribute('x', r.left - left - p[3]);
          hole.setAttribute('y', r.top - top - p[0]);
          hole.setAttribute('width', w);
          hole.setAttribute('height', h);
        });
        continue;
      }
      entry.elements.forEach((el, i) => {
        const box = entry.nodes[i];
        if (!el.isConnected || !el.getClientRects().length) {
          if (!entry.redact) box.style.display = 'none';
          return;
        }
        const r = el.getBoundingClientRect();
        box.style.display = '';
        if (entry.callout) {
          positionCallout(entry, i, r);
          return;
        }
        const p = entry.pad;
        box.style.left = (r.left - p[3]) + 'px';
        box.style.top = (r.top - p[0]) + 'px';
        box.style.width = Math.max(0, r.width + p[1] + p[3]) + 'px';
        const w = Math.max(0, r.width + p[1] + p[3]);
        const h = Math.max(0, r.height + p[0] + p[2]);
        box.style.height = h + 'px';
        if (entry.type === 'circle' || (entry.type === 'box' && entry.reveal === 'draw')) {
          const svg = box.querySelector('svg');
          const path = svg.firstChild;
          svg.setAttribute('viewBox', `0 0 ${Math.max(w, 1)} ${Math.max(h, 1)}`);
          if (entry.type === 'circle') {
            path.setAttribute('cx', w / 2);
            path.setAttribute('cy', h / 2);
            path.setAttribute('rx', Math.max(0, (w - 3) / 2));
            path.setAttribute('ry', Math.max(0, (h - 3) / 2));
          } else {
            path.setAttribute('x', 1.5);
            path.setAttribute('y', 1.5);
            path.setAttribute('rx', 3.5);
            path.setAttribute('ry', 3.5);
            path.setAttribute('width', Math.max(0, w - 3));
            path.setAttribute('height', Math.max(0, h - 3));
          }
        }
      });
    }
  };
  const tick = () => {
    frame = null;
    sync();
    if (entries.size) frame = requestAnimationFrame(tick);
  };
  const finishClear = () => {
    layer.querySelectorAll('.pz-exiting').forEach(node => node.remove());
  };
  const remove = (id, animate) => {
    const entry = entries.get(id);
    if (!entry) return false;
    entries.delete(id);
    if (!entries.size && frame !== null) { cancelAnimationFrame(frame); frame = null; }
    for (const node of entry.nodes) {
      node.getAnimations({subtree:true}).forEach(anim => anim.cancel());
      if (animate && durations[entry.reveal]) {
        node.classList.add('pz-exiting');
        if (entry.reveal === 'draw' || entry.reveal === 'wipe') node.querySelector('span')?.remove();
        start(node, entry.reveal, false, node.querySelector('.pz-shape'));
      } else node.remove();
    }
    return animate ? durations[entry.reveal] : 0;
  };
  layer.pz = {
    sync,
    paintedRects(elements) {
      sync();
      let union = null;
      const include = (r, stroke = 0) => {
        if (!Number.isFinite(r.left) || !Number.isFinite(r.top) ||
            r.width < 0 || r.height < 0) return;
        const box = [r.left - stroke, r.top - stroke,
                     r.right + stroke, r.bottom + stroke];
        union = union === null ? box : [
          Math.min(union[0], box[0]), Math.min(union[1], box[1]),
          Math.max(union[2], box[2]), Math.max(union[3], box[3])
        ];
      };
      for (const entry of entries.values()) {
        if (entry.redact) continue;
        entry.elements.forEach((el, i) => {
          if (!el.isConnected || !el.getClientRects().length ||
              !elements.some(target => target === el || target.contains(el))) return;
          if (entry.spotlight) {
            const hole = entry.holes[i];
            if (hole.style.display === 'none') return;
            const svg = entry.nodes[0];
            const origin = svg.getBoundingClientRect();
            const scaleX = origin.width / Number(svg.getAttribute('width'));
            const scaleY = origin.height / Number(svg.getAttribute('height'));
            const x = origin.left + Number(hole.getAttribute('x')) * scaleX;
            const y = origin.top + Number(hole.getAttribute('y')) * scaleY;
            const w = Number(hole.getAttribute('width')) * scaleX;
            const h = Number(hole.getAttribute('height')) * scaleY;
            include({left:x, top:y, right:x + w, bottom:y + h,
                     width:w, height:h});
            return;
          }
          const node = entry.nodes[i];
          if (node.style.display === 'none' || getComputedStyle(node).visibility !== 'visible') return;
          if (entry.callout) {
            include(node.querySelector('.pz-bubble').getBoundingClientRect());
            const svg = node.querySelector('svg');
            if (svg && svg.style.display !== 'none') {
              const line = svg.firstChild;
              include(line.getBoundingClientRect(), 1);
              include(svg.lastChild.getBoundingClientRect());
            }
          } else {
            const shape = node.querySelector('.pz-shape');
            const svg = shape.tagName.toLowerCase() === 'svg';
            include((svg ? shape.firstChild : shape).getBoundingClientRect(), svg ? 1.5 : 0);
          }
          const badge = node.querySelector('span');
          if (badge) include(badge.getBoundingClientRect());
        });
      }
      return union;
    },
    finishClear,
    spotlight: (elements, opts) => {
      remove('spotlight', false);
      const svg = document.createElementNS(svgNS, 'svg');
      svg.classList.add('pz-spotlight');
      svg.style.cssText = 'position:fixed;left:0;top:0;pointer-events:none;z-index:-1;overflow:visible;';
      const mask = document.createElementNS(svgNS, 'mask');
      const maskId = 'pz-spotlight-mask-' + (++next);
      mask.id = maskId;
      mask.setAttribute('maskUnits', 'userSpaceOnUse');
      mask.setAttribute('maskContentUnits', 'userSpaceOnUse');
      mask.style.maskType = 'luminance';
      const backdrop = document.createElementNS(svgNS, 'rect');
      backdrop.setAttribute('fill', 'white');
      mask.appendChild(backdrop);
      const holes = elements.map(() => {
        const hole = document.createElementNS(svgNS, 'rect');
        hole.setAttribute('fill', 'black');
        hole.setAttribute('rx', 6);
        hole.setAttribute('ry', 6);
        mask.appendChild(hole);
        return hole;
      });
      const defs = document.createElementNS(svgNS, 'defs');
      defs.appendChild(mask);
      svg.appendChild(defs);
      const cover = document.createElementNS(svgNS, 'rect');
      cover.setAttribute('fill', 'black');
      cover.setAttribute('fill-opacity', opts.dim);
      cover.setAttribute('mask', `url(#${maskId})`);
      svg.appendChild(cover);
      layer.appendChild(svg);
      entries.set('spotlight', {elements:[...elements], nodes:[svg], holes,
                               pad:opts.pad, reveal:opts.reveal, spotlight:true});
      sync();
      if (opts.animate && durations[opts.reveal]) start(svg, opts.reveal, true, null);
      if (frame === null) frame = requestAnimationFrame(tick);
      return opts.animate ? durations[opts.reveal] : 0;
    },
    clear: ({id, animate}) => {
      let duration = 0;
      for (const key of id === null ? [...entries.keys()] : [id]) {
        duration = Math.max(duration, remove(key, animate));
      }
      return duration;
    },
    draw: (elements, opts) => {
      let id = opts.id;
      if (id === null) {
        do { id = '__pz_auto_' + (++next); } while (entries.has(id));
      }
      remove(id, false);
      const nodes = elements.map((el, i) => {
        const box = document.createElement('div');
        box.className = 'pz-annotation';
        box.style.cssText = 'position:fixed;box-sizing:border-box;pointer-events:none;';
        box.style.color = opts.color;
        box.style.borderColor = opts.color;
        let shape = box;
        if (opts.type === 'box') {
          if (opts.reveal === 'draw') {
            shape = stroke('rect');
            shape.classList.add('pz-shape');
            box.appendChild(shape);
          } else {
            shape = document.createElement('div');
            shape.className = 'pz-shape';
            shape.style.cssText = 'position:absolute;inset:0;box-sizing:border-box;border:3px solid;border-radius:5px;';
            shape.style.borderColor = opts.color;
            box.appendChild(shape);
          }
        } else if (opts.type === 'circle') {
          shape = stroke('ellipse');
          shape.classList.add('pz-shape');
          box.appendChild(shape);
        } else {
          shape = document.createElement('div');
          shape.className = 'pz-shape';
          shape.style.cssText = 'position:absolute;left:0;width:100%;transform-origin:left center;';
          if (opts.type === 'underline') {
            shape.style.cssText += 'height:3px;bottom:2px;background:currentColor;';
          } else {
            shape.style.cssText += 'top:0;height:100%;background:currentColor;opacity:.35;mix-blend-mode:multiply;';
          }
          box.appendChild(shape);
        }
        if (opts.label !== null) {
          const badge = document.createElement('span');
          badge.textContent = opts.label === true ? String(i + 1) : String(opts.label);
          badge.style.cssText = 'position:absolute;left:0;top:0;transform:translateY(-100%);padding:2px 5px;color:white;border-radius:3px;line-height:1.2;';
          badge.style.backgroundColor = opts.color;
          badge.style.fontFamily = opts.fontFamily;
          badge.style.fontSize = opts.fontSize + 'px';
          box.appendChild(badge);
        }
        layer.appendChild(box);
        return box;
      });
      entries.set(id, {elements:[...elements], nodes, pad:opts.pad,
                       reveal:opts.reveal, type:opts.type});
      sync();
      if (opts.animate && durations[opts.reveal]) {
        nodes.forEach(node => start(node, opts.reveal, true,
          node.querySelector('.pz-shape')));
      }
      if (frame === null) frame = requestAnimationFrame(tick);
      return opts.animate ? durations[opts.reveal] : 0;
    },
    callout: (elements, opts) => {
      let id = opts.id;
      if (id === null) {
        do { id = '__pz_auto_' + (++next); } while (entries.has(id));
      }
      remove(id, false);
      const nodes = elements.map((el, i) => {
        const box = document.createElement('div');
        box.className = 'pz-callout';
        box.style.cssText = 'position:fixed;box-sizing:border-box;pointer-events:none;';
        const shape = document.createElement('div');
        shape.className = 'pz-shape';
        shape.style.cssText = 'position:relative;width:100%;height:100%;';
        const bubble = document.createElement('div');
        bubble.className = 'pz-bubble';
        bubble.textContent = opts.text;
        bubble.style.cssText = 'box-sizing:border-box;width:max-content;white-space:normal;overflow-wrap:anywhere;overflow:hidden;background:#171717;color:white;border:2px solid;border-radius:8px;line-height:1.35;padding:8px 12px;';
        bubble.style.borderColor = opts.color;
        bubble.style.fontFamily = opts.fontFamily;
        bubble.style.fontSize = opts.fontSize + 'px';
        bubble.style.maxWidth = Math.max(1, Math.min(320, innerWidth - 16)) + 'px';
        bubble.style.maxHeight = Math.max(1, innerHeight - 16) + 'px';
        if (opts.label !== null) bubble.style.paddingTop = (opts.fontSize * 1.2 + 14) + 'px';
        shape.appendChild(bubble);
        if (opts.arrow) {
          const svg = document.createElementNS(svgNS, 'svg');
          svg.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;overflow:visible;color:inherit;';
          const line = document.createElementNS(svgNS, 'line');
          line.style.cssText = 'stroke:currentColor;stroke-width:2;';
          const head = document.createElementNS(svgNS, 'polygon');
          head.style.cssText = 'fill:currentColor;';
          svg.style.color = opts.color;
          svg.append(line, head);
          shape.appendChild(svg);
        }
        box.appendChild(shape);
        if (opts.label !== null) {
          const badge = document.createElement('span');
          badge.textContent = opts.label === true ? String(i + 1) : String(opts.label);
          badge.style.cssText = 'position:absolute;top:5px;left:6px;box-sizing:border-box;max-width:calc(100% - 8px);overflow:hidden;text-overflow:ellipsis;white-space:nowrap;padding:1px 5px;background:#171717;color:white;border:1px solid;border-radius:4px;line-height:1.2;';
          badge.style.borderColor = opts.color;
          badge.style.fontFamily = opts.fontFamily;
          badge.style.fontSize = opts.fontSize + 'px';
          box.appendChild(badge);
        }
        layer.appendChild(box);
        return box;
      });
      // Width constraints are fixed at draw; resizing the viewport does not rewrap text.
      const places = nodes.map((node, i) => {
        const bubble = node.querySelector('.pz-bubble');
        const width = bubble.offsetWidth, height = bubble.offsetHeight;
        node.style.width = width + 'px';
        node.style.height = height + 'px';
        let side = opts.side;
        if (side === null) {
          const r = elements[i].getBoundingClientRect();
          const room = [r.top, innerWidth - r.right, innerHeight - r.bottom, r.left];
          const need = [height, width, height, width];
          const fits = room.map((n, j) => n >= need[j] + 8);
          const indices = fits.some(Boolean) ? [0, 1, 2, 3].filter(j => fits[j]) : [0, 1, 2, 3];
          const best = indices.reduce((a, b) => room[b] > room[a] ? b : a);
          side = [['top'], ['right'], ['bottom'], ['left']][best];
        }
        return {width, height, side};
      });
      entries.set(id, {elements:[...elements], nodes, places, callout:true,
                       arrow:opts.arrow, reveal:opts.reveal});
      sync();
      if (opts.animate && durations[opts.reveal]) {
        nodes.forEach(node => start(node, opts.reveal, true,
          node.querySelector('.pz-shape')));
      }
      if (frame === null) frame = requestAnimationFrame(tick);
      return opts.animate ? durations[opts.reveal] : 0;
    },
    redact: (elements, opts) => {
      for (const el of elements) {
        if (el.closest(':modal, :popover-open')) {
          throw new Error('Cannot redact content in a modal dialog or popover.');
        }
        if (!el.isConnected || !el.getClientRects().length) {
          throw new Error('Cannot redact an element without a rendered box.');
        }
        const r = el.getBoundingClientRect();
        if (r.width + opts.pad[1] + opts.pad[3] <= 0 ||
            r.height + opts.pad[0] + opts.pad[2] <= 0) {
          throw new Error('Redaction needs a box with nonzero width and height.');
        }
      }
      let id = opts.id;
      if (id === null) {
        do { id = '__pz_auto_' + (++next); } while (entries.has(id));
      }
      remove(id, false);
      const nodes = elements.map(() => {
        const box = document.createElement('div');
        box.className = 'pz-redaction';
        box.style.cssText = 'position:fixed;box-sizing:border-box;pointer-events:none;z-index:1;';
        if (opts.method === 'blur') {
          box.style.backdropFilter = 'blur(32px)';
        } else {
          box.style.backgroundColor = '#171717';
          if (opts.color !== null) {
            const tint = document.createElement('div');
            tint.style.cssText = 'position:absolute;inset:0;';
            tint.style.backgroundColor = opts.color;
            box.appendChild(tint);
          }
        }
        layer.appendChild(box);
        return box;
      });
      entries.set(id, {elements:[...elements], nodes, pad:opts.pad, reveal:'none', redact:true});
      sync();
      if (frame === null) frame = requestAnimationFrame(tick);
      return id;
    }
  };
  return layer;
})"

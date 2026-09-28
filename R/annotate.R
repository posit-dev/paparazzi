#' Draw a box around page elements
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
#' @param type Currently only `"box"` is supported.
#' @param label Optional badge. `TRUE` numbers the matches 1, 2, ...;
#'   one string or number repeats on each match.
#' @param pad Extra CSS pixels around each element: one number or
#'   `c(top, right, bottom, left)`. `NULL` uses zero.
#' @param reveal `"fade"` (the default) or `"none"`. Reveals animate only
#'   during an active, unpaused recording.
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
  if (!identical(type, "box")) {
    cli::cli_abort("Only {.val box} is supported for {.arg type}.")
  }
  reveal <- reveal %||% "fade"
  if (
    !is.character(reveal) ||
      length(reveal) != 1L ||
      is.na(reveal) ||
      !reveal %in% c("fade", "none")
  ) {
    cli::cli_abort("{.arg reveal} must be {.val fade} or {.val none}.")
  }
  if (!is.null(id)) {
    check_string(id)
    if (!nzchar(id) || id %in% c("spotlight", "caption")) {
      cli::cli_abort(
        "{.arg id} must be nonempty and cannot be {.val spotlight} or {.val caption}."
      )
    }
  }
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
  els <- loc_resolve(ctx, target, multiple = "all")
  withr::defer(release_elements(els))
  annotate_register_init(ctx)
  recording <- annotate_recording(ctx$page)
  options <- list(
    id = id,
    pad = unname(pad),
    label = label,
    color = color,
    fontFamily = font_family,
    fontSize = font_size,
    reveal = reveal,
    animate = recording
  )
  json <- jsonlite::toJSON(options, auto_unbox = TRUE, null = "null")
  timeout <- ctx$page$default_timeout
  res <- cdp_call(
    ctx$page$session$Runtime$callFunctionOn(
      paste0(
        "function() { return (",
        annotate_boot_js,
        ")().pz.draw(this, ",
        json,
        "); }"
      ),
      objectId = els$object_id,
      returnByValue = TRUE,
      timeout_ = timeout
    ),
    timeout,
    "drawing the annotation"
  )
  cdp_check_exception(res, "drawing the annotation")
  if (recording && identical(reveal, "fade")) {
    pump_loop(ctx$page$child_loop, 0.3)
  }
  invisible(ctx)
}

#' Redact page elements
#'
#' Covers every element matched by `target` with an instant opaque fill or
#' backdrop blur in screenshots and recordings. Fill is the safe choice for
#' secrets: blur can leave text partly legible. Redactions follow elements
#' as they move; if an element disconnects or stops rendering, its last box
#' remains until cleared. They belong to the current document and are lost
#' on navigation.
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
  if (!is.null(id)) {
    check_string(id)
    if (!nzchar(id) || id %in% c("spotlight", "caption")) {
      cli::cli_abort(
        "{.arg id} must be nonempty and cannot be {.val spotlight} or {.val caption}."
      )
    }
  }
  if (!is.null(color)) {
    check_string(color)
    if (method == "blur") {
      cli::cli_abort(
        "{.arg color} is only supported with {.code method = 'fill'}."
      )
    }
  }
  pad <- check_pad(pad %||% 0, arg = "pad")
  els <- loc_resolve(ctx, target, multiple = "all")
  withr::defer(release_elements(els))
  annotate_register_init(ctx)
  options <- list(id = id, method = method, pad = unname(pad), color = color)
  json <- jsonlite::toJSON(options, auto_unbox = TRUE, null = "null")
  timeout <- ctx$page$default_timeout
  res <- cdp_call(
    ctx$page$session$Runtime$callFunctionOn(
      paste0(
        "function() { return (",
        annotate_boot_js,
        ")().pz.redact(this, ",
        json,
        "); }"
      ),
      objectId = els$object_id,
      returnByValue = TRUE,
      timeout_ = timeout
    ),
    timeout,
    "redacting the elements"
  )
  cdp_check_exception(res, "redacting the elements")
  invisible(ctx)
}

#' Clear page annotations
#'
#' Remove an annotation by id, or remove every annotation when `id` is
#' `NULL`. During a recording, fading boxes fade out before removal.
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
  fades <- pz_js(
    ctx,
    paste0(
      "(() => { const h = document.getElementById('paparazzi-overlay-root'); ",
      "return h?.shadowRoot?.querySelector('.pz-annotations')?.pz?.clear(",
      data,
      ") || false; })()"
    )
  )
  if (recording && isTRUE(fades)) {
    pump_loop(ctx$page$child_loop, 0.3)
    pz_js(
      ctx,
      "document.getElementById('paparazzi-overlay-root')?.shadowRoot?.querySelector('.pz-annotations')?.pz?.finishClear()"
    )
  }
  invisible(ctx)
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
  const sync = () => {
    if (!entries.size) return;
    const zoom = parseFloat(getComputedStyle(document.documentElement).zoom) || 1;
    layer.style.zoom = String(1 / zoom);
    for (const entry of entries.values()) {
      entry.elements.forEach((el, i) => {
        const box = entry.nodes[i];
        if (!el.isConnected || !el.getClientRects().length) {
          if (!entry.redact) box.style.display = 'none';
          return;
        }
        const r = el.getBoundingClientRect();
        const p = entry.pad;
        box.style.display = '';
        box.style.left = (r.left - p[3]) + 'px';
        box.style.top = (r.top - p[0]) + 'px';
        box.style.width = Math.max(0, r.width + p[1] + p[3]) + 'px';
        box.style.height = Math.max(0, r.height + p[0] + p[2]) + 'px';
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
      node.getAnimations().forEach(anim => anim.cancel());
      if (animate && entry.reveal === 'fade') {
        node.classList.add('pz-exiting');
        const anim = node.animate([{opacity:1},{opacity:0}], {duration:250,fill:'forwards'});
        anim.onfinish = () => node.remove();
      } else node.remove();
    }
    return animate && entry.reveal === 'fade';
  };
  layer.pz = {
    sync,
    finishClear,
    clear: ({id, animate}) => {
      let fading = false;
      for (const key of id === null ? [...entries.keys()] : [id]) {
        fading = remove(key, animate) || fading;
      }
      return fading;
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
        box.style.cssText = 'position:fixed;box-sizing:border-box;pointer-events:none;border:3px solid;border-radius:5px;';
        box.style.borderColor = opts.color;
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
        if (opts.animate && opts.reveal === 'fade') {
          const anim = box.animate([{opacity:0},{opacity:1}], {duration:250,fill:'forwards'});
          anim.onfinish = () => { box.style.opacity = '1'; anim.cancel(); };
        }
        return box;
      });
      entries.set(id, {elements:[...elements], nodes, pad:opts.pad, reveal:opts.reveal});
      sync();
      if (frame === null) frame = requestAnimationFrame(tick);
      return id;
    },
    redact: (elements, opts) => {
      if (elements.some(el => !el.isConnected || !el.getClientRects().length)) {
        throw new Error('Cannot redact an element without a rendered box.');
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

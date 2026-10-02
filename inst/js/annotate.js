function(root) {
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
  // Draw reveal for a callout with a leader: the bubble fades in while the
  // shaft draws via dashoffset, then the decorations appear. Clearing
  // reverses: decorations hide at once, the shaft undraws, the node leaves.
  const startLeaderDraw = (node, entering) => {
    const svg = node.querySelector('svg');
    const shaft = svg.querySelector('.pz-shaft');
    const decos = svg.querySelectorAll('.pz-deco-start, .pz-deco-end');
    const bubble = node.querySelector('.pz-bubble');
    decos.forEach(d => d.style.visibility = 'hidden');
    const fade = bubble.animate(
      entering ? [{opacity:0},{opacity:1}] : [{opacity:1},{opacity:0}],
      {duration:durations.fade, fill:'forwards', easing:'linear'}
    );
    const draw = shaft.animate(
      entering ? [{strokeDashoffset:1},{strokeDashoffset:0}] :
        [{strokeDashoffset:0},{strokeDashoffset:1}],
      {duration:durations.draw, fill:'forwards', easing:'linear'}
    );
    if (entering) draw.onfinish = () => {
      decos.forEach(d => d.style.visibility = '');
      fade.cancel();
      draw.cancel();
    };
    else draw.onfinish = () => node.remove();
  };
  const start = (node, reveal, entering, shape) => {
    if (reveal === 'draw' && node.classList.contains('pz-callout') &&
        node.querySelector('svg')) {
      return startLeaderDraw(node, entering);
    }
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
  const stroke = (kind, sw) => {
    const svg = document.createElementNS(svgNS, 'svg');
    svg.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;overflow:visible;';
    const path = document.createElementNS(svgNS, kind);
    path.setAttribute('pathLength', '1');
    path.style.cssText = `fill:none;stroke:currentColor;stroke-width:${sw};vector-effect:non-scaling-stroke;stroke-dasharray:1;`;
    svg.appendChild(path);
    return svg;
  };
  const clamp = (x, lo, hi) => Math.min(Math.max(x, lo), hi);
  // Lays out one leader decoration at anchor (px,py), pointing along the
  // unit vector (dx,dy) from the shaft toward the anchor, and returns how
  // much shaft length it consumes (the shaft stops at the decoration's
  // base). avail caps the decoration's size on short leaders.
  const layoutDecoration = (el, kind, px, py, dx, dy, sw, avail) => {
    if (kind === 'arrow') {
      const length = Math.min(5 * sw, avail);
      const halfWidth = length / 2;
      el.setAttribute('points', [
        [px, py],
        [px - dx * length - dy * halfWidth,
         py - dy * length + dx * halfWidth],
        [px - dx * length + dy * halfWidth,
         py - dy * length - dx * halfWidth]
      ].map(p => p.join(',')).join(' '));
      return length;
    }
    if (kind === 'dot') {
      const r = Math.min(1.5 * sw, avail);
      el.setAttribute('cx', px);
      el.setAttribute('cy', py);
      el.setAttribute('r', r);
      return r;
    }
    // bar: a perpendicular tick centered on the anchor
    const halfLength = Math.min(2.5 * sw, avail);
    el.setAttribute('x1', px - dy * halfLength);
    el.setAttribute('y1', py + dx * halfLength);
    el.setAttribute('x2', px + dy * halfLength);
    el.setAttribute('y2', py - dx * halfLength);
    return Math.min(sw / 2, avail);
  };
  const positionCallout = (entry, i, r) => {
    const box = entry.nodes[i];
    const {width:w, height:h, side} = entry.places[i];
    const gap = entry.distance;
    const x = side.includes('left') ? r.left - w - gap :
      side.includes('right') ? r.right + gap : r.left + (r.width - w) / 2;
    const y = side.includes('top') ? r.top - h - gap :
      side.includes('bottom') ? r.bottom + gap : r.top + (r.height - h) / 2;
    // The viewport clamp keeps its fixed 8px inset, independent of distance.
    const insetX = Math.min(8, innerWidth / 2);
    const insetY = Math.min(8, innerHeight / 2);
    const left = clamp(x, insetX, Math.max(insetX, innerWidth - insetX - w));
    const top = clamp(y, insetY, Math.max(insetY, innerHeight - insetY - h));
    box.style.left = left + 'px';
    box.style.top = top + 'px';
    if (entry.leader === false) return;
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
    const sw = entry.strokeWidth;
    const both = entry.leader.start !== 'none' && entry.leader.end !== 'none';
    const avail = length * (both ? 0.45 : 0.9);
    const shaft = svg.children[0];
    let consumedStart = 0, consumedEnd = 0, k = 1;
    if (entry.leader.start !== 'none') {
      consumedStart = layoutDecoration(svg.children[k++], entry.leader.start,
        bx - left, by - top, -ux, -uy, sw, avail);
    }
    if (entry.leader.end !== 'none') {
      consumedEnd = layoutDecoration(svg.children[k], entry.leader.end,
        tx - left, ty - top, ux, uy, sw, avail);
    }
    shaft.setAttribute('x1', bx - left + ux * consumedStart);
    shaft.setAttribute('y1', by - top + uy * consumedStart);
    shaft.setAttribute('x2', tx - left - ux * consumedEnd);
    shaft.setAttribute('y2', ty - top - uy * consumedEnd);
  };
  // The intersection of the padding boxes of el's axis-aligned overflow
  // ancestors, in viewport coordinates; a side no ancestor clips stays
  // infinite. Null when el has no rendered box or is visibility:hidden with
  // no visible descendants. Custom overflow-clip-margin is not honored.
  const clipRegion = (el) => {
    if (!el.isConnected || !el.getClientRects().length) return null;
    if (getComputedStyle(el).visibility !== 'visible' &&
        ![...el.querySelectorAll('*')].some(child =>
          child.getClientRects().length &&
          getComputedStyle(child).visibility === 'visible')) {
      return null;
    }
    const region = {left:-Infinity, top:-Infinity, right:Infinity, bottom:Infinity};
    let node = el;
    let ancestor = el.parentElement || el.getRootNode().host;
    let position = getComputedStyle(el).position;
    let escaping = false, containingBlock = null;
    while (ancestor && ancestor !== document.documentElement) {
      if (position === 'absolute' || position === 'fixed') {
        containingBlock = node.offsetParent;
        escaping = true;
      }
      if (ancestor === containingBlock) escaping = false;
      const style = getComputedStyle(ancestor);
      const x = style.overflowX !== 'visible';
      const y = style.overflowY !== 'visible';
      if (!escaping && ancestor !== document.body &&
          style.display !== 'inline' && style.display !== 'contents' && (x || y)) {
        const a = ancestor.getBoundingClientRect();
        const bl = parseFloat(style.borderLeftWidth), br = parseFloat(style.borderRightWidth);
        const bt = parseFloat(style.borderTopWidth), bb = parseFloat(style.borderBottomWidth);
        const px = parseFloat(style.paddingLeft) + parseFloat(style.paddingRight);
        const py = parseFloat(style.paddingTop) + parseFloat(style.paddingBottom);
        const borderBox = style.boxSizing === 'border-box';
        const baseWidth = parseFloat(style.width) + (borderBox ? 0 : px + bl + br);
        const baseHeight = parseFloat(style.height) + (borderBox ? 0 : py + bt + bb);
        const scrollbarX = Math.max(0, borderBox ?
          Math.round(baseWidth - bl - br) - ancestor.clientWidth :
          ancestor.offsetWidth - Math.round(baseWidth));
        const scrollbarY = Math.max(0, borderBox ?
          Math.round(baseHeight - bt - bb) - ancestor.clientHeight :
          ancestor.offsetHeight - Math.round(baseHeight));
        // Resolved content-box sizes exclude scrollbars. Only the scrollbar
        // measurement needs the integer CSSOM dimensions, not the scale.
        const width = baseWidth + (borderBox ? 0 : scrollbarX);
        const height = baseHeight + (borderBox ? 0 : scrollbarY);
        const scaleX = a.width / (width || 1);
        const scaleY = a.height / (height || 1);
        if (x) {
          const scrollbarLeft = Math.max(0, ancestor.clientLeft - Math.round(bl));
          region.left = Math.max(region.left, a.left + (bl + scrollbarLeft) * scaleX);
          region.right = Math.min(region.right, a.right - (br + scrollbarX - scrollbarLeft) * scaleX);
        }
        if (y) {
          const scrollbarTop = Math.max(0, ancestor.clientTop - Math.round(bt));
          region.top = Math.max(region.top, a.top + (bt + scrollbarTop) * scaleY);
          region.bottom = Math.min(region.bottom, a.bottom - (bb + scrollbarY - scrollbarTop) * scaleY);
        }
      }
      node = ancestor;
      position = style.position;
      ancestor = ancestor.parentElement || ancestor.getRootNode().host;
    }
    return region;
  };
  const sync = () => {
    if (!entries.size) return;
    const zoom = parseFloat(getComputedStyle(document.documentElement).zoom) || 1;
    layer.style.zoom = String(1 / zoom);
    for (const entry of entries.values()) {
      if (entry.kind === 'spotlight') {
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
          const clip = clipRegion(el);
          if (clip === null) {
            hole.style.display = 'none';
            return;
          }
          const r = el.getBoundingClientRect(), p = entry.pad;
          // Zero-size targets leave no hole, padded or not.
          if (r.width <= 0 || r.height <= 0) {
            hole.style.display = 'none';
            return;
          }
          const hx = Math.max(r.left - p[3], clip.left);
          const hy = Math.max(r.top - p[0], clip.top);
          const hw = Math.min(r.right + p[1], clip.right) - hx;
          const hh = Math.min(r.bottom + p[2], clip.bottom) - hy;
          if (hw <= 0 || hh <= 0) {
            hole.style.display = 'none';
            return;
          }
          hole.style.display = '';
          hole.setAttribute('x', hx - left);
          hole.setAttribute('y', hy - top);
          hole.setAttribute('width', hw);
          hole.setAttribute('height', hh);
        });
        continue;
      }
      entry.elements.forEach((el, i) => {
        const box = entry.nodes[i];
        const clip = clipRegion(el);
        if (clip === null) {
          box.style.display = 'none';
          return;
        }
        const r = el.getBoundingClientRect();
        box.style.display = '';
        if (entry.kind === 'callout') {
          const left = Math.max(r.left, clip.left), top = Math.max(r.top, clip.top);
          const right = Math.min(r.right, clip.right), bottom = Math.min(r.bottom, clip.bottom);
          if (right <= left || bottom <= top) {
            box.style.display = 'none';
            return;
          }
          // The leader anchors to the visible part of a partly clipped
          // target; the bubble itself is never clipped.
          positionCallout(entry, i, {left, top, right, bottom,
            width:right - left, height:bottom - top});
          return;
        }
        const p = entry.pad;
        const left = r.left - p[3], top = r.top - p[0];
        box.style.left = left + 'px';
        box.style.top = top + 'px';
        const w = Math.max(0, r.width + p[1] + p[3]);
        box.style.width = w + 'px';
        const h = Math.max(0, r.height + p[0] + p[2]);
        box.style.height = h + 'px';
        if (entry.kind !== 'redact') {
          // CSSOM lengths are serialized and transformed rects use float
          // precision. Ignore numeric roundoff, not subpixel clipping.
          const precision = 1e-6 * Math.max(1, Math.abs(r.left), Math.abs(r.top),
            Math.abs(r.right), Math.abs(r.bottom));
          if (r.right <= clip.left + precision || r.left >= clip.right - precision ||
              r.bottom <= clip.top + precision || r.top >= clip.bottom - precision) {
            box.style.display = 'none';
            return;
          }
          // Preserve padding on uncut target sides without letting padding
          // bring an entirely clipped target's mark back into view.
          if (r.left >= clip.left - precision) clip.left = Math.min(clip.left, left);
          if (r.top >= clip.top - precision) clip.top = Math.min(clip.top, top);
          if (r.right <= clip.right + precision) clip.right = Math.max(clip.right, left + w);
          if (r.bottom <= clip.bottom + precision) clip.bottom = Math.max(clip.bottom, top + h);
        }
        if (Math.max(left, clip.left) >= Math.min(left + w, clip.right) ||
            Math.max(top, clip.top) >= Math.min(top + h, clip.bottom)) {
          box.style.display = 'none';
          return;
        }
        // Negative insets let badges overhang the mark within the clip region.
        const inset = v => Math.max(v, -1e5) + 'px';
        box.style.clipPath = `inset(${inset(clip.top - top)} ${inset(left + w - clip.right)} ${inset(top + h - clip.bottom)} ${inset(clip.left - left)})`;
        if (entry.kind === 'circle' || (entry.kind === 'box' && entry.reveal === 'draw')) {
          const svg = box.querySelector('svg');
          const path = svg.firstChild;
          const sw = entry.strokeWidth;
          svg.setAttribute('viewBox', `0 0 ${Math.max(w, 1)} ${Math.max(h, 1)}`);
          if (entry.kind === 'circle') {
            path.setAttribute('cx', w / 2);
            path.setAttribute('cy', h / 2);
            path.setAttribute('rx', Math.max(0, (w - sw) / 2));
            path.setAttribute('ry', Math.max(0, (h - sw) / 2));
          } else {
            path.setAttribute('x', sw / 2);
            path.setAttribute('y', sw / 2);
            path.setAttribute('rx', 3.5);
            path.setAttribute('ry', 3.5);
            path.setAttribute('width', Math.max(0, w - sw));
            path.setAttribute('height', Math.max(0, h - sw));
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
  const remove = (id, animate) => {
    const entry = entries.get(id);
    if (!entry) return false;
    entries.delete(id);
    if (!entries.size && frame !== null) { cancelAnimationFrame(frame); frame = null; }
    for (const node of entry.nodes) {
      node.getAnimations({subtree:true}).forEach(anim => anim.cancel());
      if (animate && durations[entry.reveal]) {
        if (entry.reveal === 'draw' || entry.reveal === 'wipe') node.querySelector('span')?.remove();
        start(node, entry.reveal, false, node.querySelector('.pz-shape'));
      } else node.remove();
    }
    return animate ? durations[entry.reveal] : 0;
  };
  const register = (id, entry, nodes, opts) => {
    if (id === null) {
      do { id = '__pz_auto_' + (++next); } while (entries.has(id));
    }
    remove(id, false);
    nodes.forEach(node => layer.appendChild(node));
    entry.nodes = nodes;
    if (entry.kind === 'callout') measureCallout(entry, opts);
    entries.set(id, entry);
    sync();
    if (opts.animate && durations[entry.reveal]) {
      nodes.forEach(node => start(node, entry.reveal, true,
        node.querySelector('.pz-shape')));
    }
    if (frame === null) frame = requestAnimationFrame(tick);
    return {id, duration:opts.animate ? durations[entry.reveal] : 0};
  };
  const measureCallout = (entry, opts) => {
    // Width constraints are fixed at draw; resizing the viewport does not rewrap text.
    entry.places = entry.nodes.map((node, i) => {
      const bubble = node.querySelector('.pz-bubble');
      const width = bubble.offsetWidth, height = bubble.offsetHeight;
      node.style.width = width + 'px';
      node.style.height = height + 'px';
      let side = opts.side;
      if (side === null) {
        const r = entry.elements[i].getBoundingClientRect();
        const room = [r.top, innerWidth - r.right, innerHeight - r.bottom, r.left];
        const need = [height, width, height, width];
        const fits = room.map((n, j) => n >= need[j] + opts.distance);
        const indices = fits.some(Boolean) ? [0, 1, 2, 3].filter(j => fits[j]) : [0, 1, 2, 3];
        const best = indices.reduce((a, b) => room[b] > room[a] ? b : a);
        side = [['top'], ['right'], ['bottom'], ['left']][best];
      }
      return {width, height, side};
    });
  };
  layer.pz = {
    sync,
    dragPreviewSafety(source, footprint) {
      const unsafe = reason => ({safe:false, reason});
      const validBox = r => r &&
        ['left', 'top', 'right', 'bottom', 'width', 'height'].every(key =>
          Number.isFinite(r[key])) && r.width > 0 && r.height > 0 &&
        r.right > r.left && r.bottom > r.top;
      if (!validBox(footprint)) return unsafe('invalid-footprint');
      if (!(source instanceof Element) || !source.isConnected ||
          source.getRootNode() !== document) return unsafe('unknown-source');
      if (!layer.isConnected) return unsafe('unknown-state');
      try {
        let count = 0;
        for (const entry of entries.values()) {
          if (entry.kind !== 'redact') continue;
          if (!['fill', 'blur'].includes(entry.method) ||
              !Array.isArray(entry.pad) || entry.pad.length !== 4 ||
              !entry.pad.every(Number.isFinite) ||
              !Array.isArray(entry.elements) || !entry.elements.length ||
              !Array.isArray(entry.nodes) || entry.nodes.length !== entry.elements.length) {
            return unsafe('unknown-state');
          }
          count += entry.nodes.length;
          for (let i = 0; i < entry.elements.length; i++) {
            const el = entry.elements[i], node = entry.nodes[i];
            if (!(el instanceof Element) || !el.isConnected ||
                el.getRootNode() !== document || !node?.isConnected ||
                node.parentNode !== layer || !node.classList.contains('pz-redaction')) {
              return unsafe('unknown-state');
            }
          }
        }
        if (layer.querySelectorAll('.pz-redaction').length !== count) {
          return unsafe('unknown-state');
        }
        sync();
        for (const entry of entries.values()) {
          if (entry.kind !== 'redact') continue;
          for (let i = 0; i < entry.elements.length; i++) {
            const el = entry.elements[i];
            if (source === el || source.contains(el) || el.contains(source)) {
              return unsafe('related-redaction');
            }
            const clip = clipRegion(el);
            if (clip === null) continue;
            const node = entry.nodes[i];
            if (node.style.display === 'none') continue;
            const r = node.getBoundingClientRect();
            if (!validBox(r)) return unsafe('unknown-state');
            const left = Math.max(r.left, clip.left), top = Math.max(r.top, clip.top);
            const right = Math.min(r.right, clip.right), bottom = Math.min(r.bottom, clip.bottom);
            if (left < footprint.right && right > footprint.left &&
                top < footprint.bottom && bottom > footprint.top) {
              return unsafe('overlapping-redaction');
            }
          }
        }
        return {safe:true, reason:'safe'};
      } catch (_) {
        return unsafe('unknown-state');
      }
    },
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
        if (entry.kind === 'redact') continue;
        entry.elements.forEach((el, i) => {
          if (!el.isConnected || !el.getClientRects().length ||
              !elements.some(target => target === el || target.contains(el))) return;
          if (entry.kind === 'spotlight') {
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
          if (entry.kind === 'callout') {
            include(node.querySelector('.pz-bubble').getBoundingClientRect());
            const svg = node.querySelector('svg');
            if (svg && svg.style.display !== 'none') {
              for (const child of svg.children) {
                include(child.getBoundingClientRect(), entry.strokeWidth / 2);
              }
            }
          } else {
            const shape = node.querySelector('.pz-shape');
            const svg = shape.tagName.toLowerCase() === 'svg';
            include((svg ? shape.firstChild : shape).getBoundingClientRect(),
              svg ? entry.strokeWidth / 2 : 0);
          }
          const badge = node.querySelector('span');
          if (badge) include(badge.getBoundingClientRect());
        });
      }
      return union;
    },
    spotlight: (elements, opts) => {
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
      return register('spotlight', {elements:[...elements], holes,
        pad:opts.pad, reveal:opts.reveal, kind:'spotlight'}, [svg], opts).duration;
    },
    clear: ({id, animate}) => {
      let duration = 0;
      for (const key of id === null ? [...entries.keys()] : [id]) {
        duration = Math.max(duration, remove(key, animate));
      }
      return duration;
    },
    draw: (elements, opts) => {
      const nodes = elements.map((el, i) => {
        const box = document.createElement('div');
        box.className = 'pz-annotation';
        box.style.cssText = 'position:fixed;box-sizing:border-box;pointer-events:none;';
        box.style.color = opts.color;
        box.style.borderColor = opts.color;
        let shape = box;
        if (opts.type === 'box') {
          if (opts.reveal === 'draw') {
            shape = stroke('rect', opts.strokeWidth);
            shape.classList.add('pz-shape');
            box.appendChild(shape);
          } else {
            shape = document.createElement('div');
            shape.className = 'pz-shape';
            shape.style.cssText = `position:absolute;inset:0;box-sizing:border-box;border:${opts.strokeWidth}px solid;border-radius:5px;`;
            shape.style.borderColor = opts.color;
            box.appendChild(shape);
          }
        } else if (opts.type === 'circle') {
          shape = stroke('ellipse', opts.strokeWidth);
          shape.classList.add('pz-shape');
          box.appendChild(shape);
        } else {
          shape = document.createElement('div');
          shape.className = 'pz-shape';
          shape.style.cssText = 'position:absolute;left:0;width:100%;transform-origin:left center;';
          if (opts.type === 'underline') {
            shape.style.cssText += `height:${opts.strokeWidth}px;bottom:2px;background:currentColor;`;
          } else {
            shape.style.cssText += 'top:0;height:100%;background:currentColor;opacity:.35;mix-blend-mode:multiply;';
          }
          box.appendChild(shape);
        }
        if (opts.label !== null) {
          const badge = document.createElement('span');
          badge.textContent = opts.label === true ? String(i + 1) : String(opts.label);
          badge.style.cssText = 'position:absolute;left:0;top:0;transform:translateY(-100%);padding:2px 5px;border-radius:3px;line-height:1.2;';
          badge.style.backgroundColor = opts.labelFill;
          badge.style.color = opts.labelTextColor;
          badge.style.fontFamily = opts.fontFamily;
          badge.style.fontSize = opts.fontSize + 'px';
          box.appendChild(badge);
        }
        return box;
      });
      return register(opts.id, {elements:[...elements], pad:opts.pad,
        reveal:opts.reveal, kind:opts.type, strokeWidth:opts.strokeWidth},
        nodes, opts).duration;
    },
    callout: (elements, opts) => {
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
        bubble.style.cssText = 'box-sizing:border-box;width:max-content;white-space:normal;overflow-wrap:anywhere;overflow:hidden;border:2px solid;border-radius:8px;line-height:1.35;padding:8px 12px;';
        bubble.style.backgroundColor = opts.fill;
        bubble.style.color = opts.textColor;
        bubble.style.borderColor = opts.color;
        bubble.style.fontFamily = opts.fontFamily;
        bubble.style.fontSize = opts.fontSize + 'px';
        bubble.style.maxWidth = Math.max(1, Math.min(320, innerWidth - 16)) + 'px';
        bubble.style.maxHeight = Math.max(1, innerHeight - 16) + 'px';
        if (opts.label !== null) bubble.style.paddingTop = (opts.fontSize * 1.2 + 14) + 'px';
        shape.appendChild(bubble);
        if (opts.leader !== false) {
          const svg = document.createElementNS(svgNS, 'svg');
          svg.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;overflow:visible;color:inherit;';
          svg.style.color = opts.color;
          const shaft = document.createElementNS(svgNS, 'line');
          shaft.classList.add('pz-shaft');
          shaft.setAttribute('pathLength', '1');
          shaft.style.cssText = `stroke:currentColor;stroke-width:${opts.strokeWidth};stroke-linecap:butt;stroke-dasharray:1;`;
          svg.appendChild(shaft);
          for (const end of ['start', 'end']) {
            const kind = opts.leader[end];
            if (kind === 'none') continue;
            const deco = document.createElementNS(svgNS,
              kind === 'arrow' ? 'polygon' : kind === 'dot' ? 'circle' : 'line');
            deco.classList.add('pz-deco-' + end);
            deco.style.cssText = kind === 'bar' ?
              `stroke:currentColor;stroke-width:${opts.strokeWidth};fill:none;` :
              'fill:currentColor;';
            svg.appendChild(deco);
          }
          shape.appendChild(svg);
        }
        box.appendChild(shape);
        if (opts.label !== null) {
          const badge = document.createElement('span');
          badge.textContent = opts.label === true ? String(i + 1) : String(opts.label);
          badge.style.cssText = 'position:absolute;top:5px;left:6px;box-sizing:border-box;max-width:calc(100% - 8px);overflow:hidden;text-overflow:ellipsis;white-space:nowrap;padding:1px 5px;border:1px solid;border-radius:4px;line-height:1.2;';
          badge.style.backgroundColor = opts.fill;
          badge.style.color = opts.textColor;
          badge.style.borderColor = opts.color;
          badge.style.fontFamily = opts.fontFamily;
          badge.style.fontSize = opts.fontSize + 'px';
          box.appendChild(badge);
        }
        return box;
      });
      return register(opts.id, {elements:[...elements], kind:'callout',
        leader:opts.leader, strokeWidth:opts.strokeWidth, distance:opts.distance,
        reveal:opts.reveal}, nodes, opts).duration;
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
        return box;
      });
      return register(opts.id, {elements:[...elements], pad:opts.pad,
        reveal:'none', kind:'redact', method:opts.method}, nodes, opts).id;
    }
  };
  return layer;
}

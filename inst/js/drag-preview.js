function(root, htmlToImage, element, point, annotationsAbsent) {
  root.querySelector('.pz-drag-preview')?.pz.dispose();
  const layer = document.createElement('div');
  layer.className = 'pz-drag-preview';
  layer.setAttribute('aria-hidden', 'true');
  layer.style.cssText = 'position:fixed;left:0;top:0;pointer-events:none;z-index:-2;';
  root.appendChild(layer);
  const own = element.getAttribute('draggable');
  let inherited = element.closest('[draggable]');
  const finiteRect = r => r && [r.left, r.top, r.width, r.height].every(Number.isFinite) &&
    r.width > 0 && r.height > 0;
  const inside = (r, box) => r.left >= box.left - 0.5 && r.top >= box.top - 0.5 &&
    r.right <= box.right + 0.5 && r.bottom <= box.bottom + 0.5;
  // The raster viewport is the untransformed border box. Decline content
  // whose painted footprint cannot be established without reconstructing CSS.
  const bounds = el => {
    if (!el?.isConnected || el.getRootNode() !== document || !el.getClientRects().length) return null;
    const rect = el.getBoundingClientRect();
    if (!finiteRect(rect)) return null;
    let zoom = 1;
    for (let node = el; node; node = node.parentElement) {
      const css = getComputedStyle(node);
      if (css.transform !== 'none' || css.translate !== 'none' ||
          css.rotate !== 'none' || css.scale !== 'none' || css.perspective !== 'none') return null;
      zoom *= parseFloat(css.zoom) || 1;
      if (node !== el) {
        const box = node.getBoundingClientRect();
        if (css.overflowX !== 'visible' && (rect.left < box.left - 0.5 || rect.right > box.right + 0.5)) return null;
        if (css.overflowY !== 'visible' && (rect.top < box.top - 0.5 || rect.bottom > box.bottom + 0.5)) return null;
      }
    }
    if (!Number.isFinite(zoom) || zoom <= 0) return null;
    // SVG references and iframes can copy nodes outside this document subtree.
    for (const node of [el, ...el.querySelectorAll('*')]) {
      const css = getComputedStyle(node);
      if (node.shadowRoot || node instanceof SVGUseElement || node instanceof HTMLIFrameElement ||
          css.transform !== 'none' || css.translate !== 'none' ||
          css.rotate !== 'none' || css.scale !== 'none' || css.filter !== 'none') return null;
      if (node !== el && (css.position === 'fixed' || css.position === 'sticky' ||
          (css.position === 'absolute' && getComputedStyle(el).position === 'static'))) return null;
      for (const pseudo of ['::before', '::after']) {
        const content = getComputedStyle(node, pseudo).content;
        if (content !== 'none' && content !== 'normal' && content !== '""') return null;
      }
      if (node.getClientRects().length && !inside(node.getBoundingClientRect(), rect)) return null;
      for (const child of node.childNodes) {
        if (child.nodeType !== Node.TEXT_NODE || !child.textContent.trim()) continue;
        const range = document.createRange();
        range.selectNodeContents(child);
        for (const r of range.getClientRects()) if (!inside(r, rect)) return null;
      }
    }
    return {left:rect.left, top:rect.top, right:rect.right, bottom:rect.bottom,
      width:rect.width, height:rect.height, zoom};
  };
  const live = () => controller.source !== null && layer.isConnected &&
    root.querySelector('.pz-drag-preview')?.pz === controller;
  const safety = footprint => {
    const annotations = root.querySelector('.pz-annotations');
    if (!annotations) {
      if (annotationsAbsent) return;
      throw new Error('Annotation safety is unavailable');
    }
    const verdict = annotations.pz?.dragPreviewSafety?.(controller.source, footprint);
    if (verdict?.safe !== true) throw new Error(verdict?.reason || 'Annotation safety is unknown');
  };
  const current = () => {
    const box = bounds(controller.source);
    if (!box) throw new Error('Unsupported drag preview footprint');
    safety(box);
    return box;
  };
  let captured = null;
  let grab = null;
  let position = null;
  const place = p => {
    position = {x:p.x - grab.x, y:p.y - grab.y};
    controller.image.style.transform = `translate(${position.x}px, ${position.y}px)`;
  };
  const controller = {
    source:own !== null && own !== '' ? element : (inherited || element),
    image:null,
    async prepare() {
      captured = current();
      grab = {x:point.x - captured.left, y:point.y - captured.top};
      const png = await htmlToImage.toPng(controller.source, {
        width:captured.width / captured.zoom, height:captured.height / captured.zoom,
        pixelRatio:(window.devicePixelRatio || 1) * captured.zoom,
        style:{zoom:'1', transform:'none', boxSizing:'border-box', margin:'0', position:'relative',
          left:'0', top:'0', right:'auto', bottom:'auto'}
      });
      if (!live()) return;
      const image = new Image();
      image.src = png;
      await image.decode();
      if (!live()) return;
      current();
      image.style.cssText = `position:absolute;left:0;top:0;width:${captured.width}px;height:${captured.height}px;max-width:none;max-height:none;pointer-events:none;`;
      image.draggable = false;
      image.alt = '';
      controller.image = image;
    },
    show(p) {
      if (!live() || !controller.image) throw new Error('Drag preview is unavailable');
      current();
      const zoom = parseFloat(getComputedStyle(document.documentElement).zoom) || 1;
      layer.style.zoom = String(1 / zoom);
      place(p);
      layer.appendChild(controller.image);
    },
    move(p) {
      if (!live() || !controller.image) throw new Error('Drag preview is unavailable');
      current();
      place(p);
    },
    settle() {
      if (!live() || !controller.image?.isConnected) return 0;
      const box = bounds(controller.source);
      if (!box) { controller.dispose(); return 0; }
      safety(box);
      if (Math.abs(box.width - captured.width) > 0.5 || Math.abs(box.height - captured.height) > 0.5) {
        controller.dispose();
        return 0;
      }
      if (Math.abs(box.left - position.x) < 0.5 && Math.abs(box.top - position.y) < 0.5) return 0;
      const end = `translate(${box.left}px, ${box.top}px)`;
      controller.image.animate([
        {transform:controller.image.style.transform}, {transform:end}
      ], {duration:180, easing:'ease-out', fill:'forwards'});
      return 180;
    },
    dispose() {
      const image = controller.image;
      controller.source = null;
      controller.image = null;
      captured = grab = position = null;
      delete layer.pz;
      layer.remove();
      if (image) {
        for (const animation of image.getAnimations()) animation.cancel();
        image.remove();
      }
    }
  };
  element = inherited = null;
  layer.pz = controller;
  return controller;
}

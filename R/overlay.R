OVERLAY_HOST_ID <- "paparazzi-overlay-root"

OVERLAY_HOST_JS <- paste0(
  "let host = document.getElementById('",
  OVERLAY_HOST_ID,
  "');",
  "if (!host) { host = document.createElement('div');",
  "host.id = '",
  OVERLAY_HOST_ID,
  "';",
  "host.style.cssText = 'position:absolute;top:0;left:0;width:0;height:0;z-index:2147483647;pointer-events:none;';",
  "document.documentElement.appendChild(host); }",
  "if (!host.shadowRoot) host.attachShadow({mode:'open'});",
  "const root = host.shadowRoot;"
)

ANNOTATION_LAYER_JS <- paste0(
  "document.getElementById('",
  OVERLAY_HOST_ID,
  "')?.shadowRoot?.querySelector('.pz-annotations')?.pz"
)

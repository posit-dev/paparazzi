el_rects <- function(els, call = caller_env()) {
  if (!inherits(els, "paparazzi_elements")) {
    stop_input_type(els, "a <paparazzi_elements> object", call = call)
  }
  if (els$count == 0L) {
    return(tibble::tibble(
      x = numeric(),
      y = numeric(),
      width = numeric(),
      height = numeric()
    ))
  }
  m <- matrix(
    els_values_flat(
      els,
      "function() {
        return this.flatMap((el) => {
          const r = el.getBoundingClientRect();
          return [r.x, r.y, r.width, r.height];
        });
      }",
      call = call
    ),
    ncol = 4,
    byrow = TRUE
  )
  tibble::tibble(
    x = as.double(m[, 1]),
    y = as.double(m[, 2]),
    width = as.double(m[, 3]),
    height = as.double(m[, 4])
  )
}

el_scroll_into_view <- function(els, call = caller_env()) {
  if (!inherits(els, "paparazzi_elements")) {
    stop_input_type(els, "a <paparazzi_elements> object", call = call)
  }
  if (els$count == 0L || is.null(els$object_id)) {
    return(invisible(els))
  }
  # The scroll is instant: CSS scroll-behavior: smooth would animate it,
  # and a geometry read right after would observe a mid-scroll position.
  els_values_flat(
    els,
    "function() { if (this.length) this[0].scrollIntoView({ block: 'nearest', inline: 'nearest', behavior: 'instant' }); }",
    call = call
  )
  invisible(els)
}

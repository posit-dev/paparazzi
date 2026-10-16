# Read the textContent of every element in a resolved set (trimmed), so
# tests can assert *which* elements matched, not just how many.
elements_text <- function(els) {
  unlist(
    els$page$session$Runtime$callFunctionOn(
      "function() { return this.map((el) => el.textContent.trim()); }",
      objectId = els$object_id,
      returnByValue = TRUE
    )$result$value
  )
}

# Viewport center of the first element matching `selector`, as c(x, y).
element_center <- function(page, selector) {
  unlist(pz_evaluate(
    page,
    sprintf(
      r"[
(() => {
  const rect = document.querySelector('%s').getBoundingClientRect();
  return [rect.x + rect.width / 2, rect.y + rect.height / 2];
})()
]",
      selector
    )
  ))
}

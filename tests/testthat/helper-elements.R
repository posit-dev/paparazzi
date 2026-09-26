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

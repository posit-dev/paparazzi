skill_r_blocks <- function(path) {
  lines <- readLines(path)
  starts <- which(trimws(lines) == "```r")
  lapply(starts, function(start) {
    end <- start + match("```", trimws(lines[-seq_len(start)]))
    paste(lines[start + seq_len(end - start - 1L)], collapse = "\n")
  })
}

test_that("skill R examples parse and use exported functions and arguments", {
  files <- list.files(
    system.file("skills/paparazzi", package = "paparazzi"),
    pattern = "\\.md$",
    recursive = TRUE,
    full.names = TRUE
  )
  expect_gt(length(files), 0L)
  exports <- getNamespaceExports("paparazzi")
  forwarded <- list(
    pz_open = "pz_device",
    pz_with_page = c("pz_open", "pz_device"),
    pz_local_page = c("pz_open", "pz_device"),
    pz_record = "pz_record_start"
  )

  check_calls <- function(node, label) {
    if (is.call(node)) {
      fn <- node[[1]]
      if (
        is.call(fn) &&
          length(fn) == 3L &&
          as.character(fn[[1]]) %in% c("::", ":::") &&
          identical(fn[[2]], as.name("paparazzi"))
      ) {
        fn <- fn[[3]]
      }
      if (is.symbol(fn) && startsWith(as.character(fn), "pz_")) {
        name <- as.character(fn)
        expect_true(name %in% exports, info = paste(label, name))
        if (name %in% exports) {
          functions <- c(name, forwarded[[name]])
          allowed <- unlist(lapply(functions, function(fn) {
            names(formals(getExportedValue("paparazzi", fn)))
          }))
          named <- names(as.list(node))[-1L]
          unknown <- setdiff(named[nzchar(named)], setdiff(allowed, "..."))
          expect_true(
            length(unknown) == 0L,
            info = paste(label, name, paste(unknown, collapse = ", "))
          )
        }
      }
    }
    if (is.call(node) || is.expression(node) || is.pairlist(node)) {
      for (child in as.list(node)) {
        if (!rlang::is_missing(child)) {
          check_calls(child, label)
        }
      }
    }
  }

  for (file in files) {
    blocks <- skill_r_blocks(file)
    for (i in seq_along(blocks)) {
      label <- paste(basename(file), "R block", i)
      parsed <- tryCatch(parse(text = blocks[[i]]), error = identity)
      expect_false(inherits(parsed, "error"), info = label)
      if (!inherits(parsed, "error")) {
        check_calls(parsed, label)
      }
    }
  }
})

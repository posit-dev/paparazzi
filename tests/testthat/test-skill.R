skill_markdown_files <- function() {
  skill_dir <- system.file("skills/paparazzi", package = "paparazzi")
  if (!dir.exists(skill_dir)) {
    return(character())
  }

  list.files(skill_dir, pattern = "\\.md$", recursive = TRUE, full.names = TRUE)
}

skill_r_code_blocks <- function(path) {
  lines <- readLines(path, warn = FALSE)
  blocks <- list()
  in_block <- FALSE
  fence_length <- 0L
  code <- character()

  for (line in lines) {
    if (!in_block) {
      opening <- regexec(
        "^ {0,3}(`{3,})[[:space:]]*r([[:space:]].*)?$",
        line,
        perl = TRUE
      )
      match <- regmatches(line, opening)[[1]]
      if (length(match)) {
        in_block <- TRUE
        fence_length <- nchar(match[[2]])
        code <- character()
      }
      next
    }

    closing <- regexec("^ {0,3}(`{3,})[[:space:]]*$", line, perl = TRUE)
    match <- regmatches(line, closing)[[1]]
    if (length(match) && nchar(match[[2]]) >= fence_length) {
      blocks[[length(blocks) + 1L]] <- paste(code, collapse = "\n")
      in_block <- FALSE
      fence_length <- 0L
      code <- character()
    } else {
      code <- c(code, line)
    }
  }

  if (in_block) {
    blocks[[length(blocks) + 1L]] <- paste(code, collapse = "\n")
  }
  blocks
}

skill_call_name <- function(call) {
  fn <- call[[1L]]
  if (is.symbol(fn)) {
    name <- as.character(fn)
    if (startsWith(name, "pz_")) {
      return(name)
    }
  }

  if (
    is.call(fn) &&
      length(fn) == 3L &&
      as.character(fn[[1L]]) %in% c("::", ":::") &&
      identical(as.character(fn[[2L]]), "paparazzi") &&
      is.symbol(fn[[3L]])
  ) {
    name <- as.character(fn[[3L]])
    if (startsWith(name, "pz_")) {
      return(name)
    }
  }

  NULL
}

skill_call_issues <- function(
  expr,
  exports,
  formal_lookup,
  forwarded = list()
) {
  issues <- character()

  allowed_args <- function(name) {
    if (!(name %in% exports)) {
      return(character())
    }

    fn_formals <- names(formal_lookup(name))
    args <- setdiff(fn_formals, "...")
    target <- forwarded[[name]]
    if ("..." %in% fn_formals && !is.null(target)) {
      args <- union(args, allowed_args(target))
    }
    args
  }

  walk <- function(node) {
    if (is.call(node)) {
      name <- skill_call_name(node)
      if (!is.null(name)) {
        if (!(name %in% exports)) {
          issues <<- c(issues, paste0(name, " is not exported"))
        } else {
          arg_names <- names(as.list(node))[-1L]
          arg_names <- unique(arg_names[!is.na(arg_names) & nzchar(arg_names)])
          bad_args <- setdiff(arg_names, allowed_args(name))
          if (length(bad_args)) {
            issues <<- c(
              issues,
              paste0(
                name,
                " has unknown named argument(s): ",
                paste(bad_args, collapse = ", ")
              )
            )
          }
        }
      }
      for (part in as.list(node)) {
        if (!rlang::is_missing(part)) {
          walk(part)
        }
      }
    } else if (is.expression(node) || is.pairlist(node) || is.list(node)) {
      for (part in node) {
        if (!rlang::is_missing(part)) {
          walk(part)
        }
      }
    }
  }

  walk(expr)
  issues
}

skill_package_exports <- function() {
  getNamespaceExports("paparazzi")
}

skill_package_formals <- function(name) {
  get(name, envir = asNamespace("paparazzi"), inherits = FALSE) |>
    formals()
}

skill_forwarded_args <- list(
  pz_open = "pz_device",
  pz_with_page = "pz_open",
  pz_local_page = "pz_open",
  pz_record = "pz_record_start"
)


test_that("skill R block extraction handles fence lengths and language tags", {
  path <- withr::local_tempfile(fileext = ".md")
  writeLines(
    c(
      "```text",
      "not_r()",
      "```",
      "```r",
      "pz_first()",
      "````",
      "````r extra-option",
      "pz_second()",
      "````"
    ),
    path
  )

  expect_identical(
    skill_r_code_blocks(path),
    list("pz_first()", "pz_second()")
  )
})

test_that("skill call walker finds nested and namespaced calls", {
  expr <- parse(
    text = paste(
      "pz_outer(pz_inner(value = pz_leaf()),",
      "paparazzi::pz_namespaced(target = pz_nested()))",
      "function(page) { pz_inner(value = page) }",
      "pz_outer(x = c(1, 2)[, ])",
      "paparazzi:::pz_nested()",
      sep = "\n"
    )
  )
  exports <- c(
    "pz_outer",
    "pz_inner",
    "pz_leaf",
    "pz_namespaced",
    "pz_nested"
  )
  formal_lookup <- function(name) {
    switch(
      name,
      pz_outer = formals(function(x) NULL),
      pz_inner = formals(function(value) NULL),
      pz_leaf = formals(function() NULL),
      pz_namespaced = formals(function(target) NULL),
      pz_nested = formals(function() NULL),
      stop("unexpected function")
    )
  }

  expect_length(
    skill_call_issues(expr, exports, formal_lookup),
    0L
  )
})

test_that("skill call checks reject unexported functions and invalid arguments", {
  formal_lookup <- function(name) {
    switch(
      name,
      pz_known = formals(function(x) NULL),
      pz_forwarder = formals(function(...) NULL),
      pz_target = formals(function(value) NULL),
      stop("unexpected function")
    )
  }
  expr <- parse(
    text = paste(
      "pz_known(x = 1, misspelled = 2)",
      "pz_forwarder(value = pz_missing())",
      sep = "\n"
    )
  )

  expect_identical(
    skill_call_issues(
      expr,
      c("pz_known", "pz_forwarder", "pz_target"),
      formal_lookup,
      forwarded = list(pz_forwarder = "pz_target")
    ),
    c(
      "pz_known has unknown named argument(s): misspelled",
      "pz_missing is not exported"
    )
  )
  expect_identical(
    skill_call_issues(
      parse(text = "pz_forwarder(typo = 1)"),
      c("pz_forwarder", "pz_target"),
      formal_lookup,
      forwarded = list(pz_forwarder = "pz_target")
    ),
    "pz_forwarder has unknown named argument(s): typo"
  )
  expect_identical(
    skill_call_issues(
      parse(text = "pz_forwarder(value = 1)"),
      "pz_forwarder",
      formal_lookup
    ),
    "pz_forwarder has unknown named argument(s): value"
  )
})

test_that("all R examples in paparazzi skill markdown parse and use the API", {
  files <- skill_markdown_files()
  expect_true(
    length(files) > 0L,
    info = "No paparazzi skill markdown files found"
  )

  for (file in files) {
    blocks <- skill_r_code_blocks(file)
    for (i in seq_along(blocks)) {
      label <- paste(basename(file), "R block", i, sep = ":")
      expr <- tryCatch(
        parse(text = blocks[[i]], keep.source = FALSE),
        error = identity
      )
      expect_false(inherits(expr, "error"), info = label)
      if (inherits(expr, "error")) {
        next
      }

      issues <- skill_call_issues(
        expr,
        skill_package_exports(),
        skill_package_formals,
        forwarded = skill_forwarded_args
      )
      expect_identical(
        issues,
        character(),
        info = paste(label, paste(issues, collapse = "; "))
      )
    }
  }
})

test_that("pz_loc builds a spec with the given fields", {
  loc <- pz_loc("#chat .ProseMirror")
  expect_s3_class(loc, "paparazzi_loc")
  expect_identical(loc$css, "#chat .ProseMirror")
  expect_null(loc$has_text)
  expect_null(loc$which)
  expect_null(loc$within)
})

test_that("pz_loc validates css and has_text", {
  expect_error(pz_loc(1), class = "rlang_error")
  expect_error(pz_loc(".btn", has_text = 1), class = "rlang_error")
  expect_error(pz_loc(".btn", has_text = c("a", "b")), class = "rlang_error")
})

test_that("pz_loc validates which", {
  expect_error(pz_loc(".btn", which = "third"), "first")
  expect_error(pz_loc(".btn", which = 0), class = "rlang_error")
  expect_error(pz_loc(".btn", which = 1.5), class = "rlang_error")
  expect_s3_class(pz_loc(".btn", which = "first"), "paparazzi_loc")
  expect_s3_class(pz_loc(".btn", which = "last"), "paparazzi_loc")
  expect_s3_class(pz_loc(".btn", which = 2), "paparazzi_loc")
})

test_that("pz_loc promotes a bare string within", {
  loc <- pz_loc(".btn", within = "#panel")
  expect_s3_class(loc$within, "paparazzi_loc")
  expect_identical(loc$within, pz_loc("#panel"))
})

test_that("pz_loc accepts a fully qualified within spec", {
  within <- pz_loc(".panel", has_text = "Delete", which = "first")
  loc <- pz_loc(".btn", within = within)
  expect_identical(loc$within, within)
})

test_that("pz_loc rejects a non-spec within", {
  # The error names `within`, not as_loc()'s internal `target` formal.
  expect_error(pz_loc(".btn", within = 1), "`within`")
  expect_error(pz_loc(".btn", within = 1), "CSS selector")
})

test_that("pz_loc checks dots empty", {
  expect_error(pz_loc(".btn", extra = 1), "empty")
})

test_that("as_loc promotes strings and passes specs through", {
  loc <- pz_loc(".btn")
  expect_identical(as_loc(".btn"), loc)
  expect_identical(as_loc(loc), loc)
  expect_error(as_loc(1), "CSS selector")
  expect_error(as_loc(NULL), "CSS selector")
})

test_that("as_loc_list builds a union from specs, strings, and mixed lists", {
  a <- pz_loc(".a")
  expect_identical(as_loc_list(".b"), list(pz_loc(".b")))
  expect_identical(as_loc_list(a), list(a))
  expect_identical(as_loc_list(list(".b", a)), list(pz_loc(".b"), a))
  # Names are dropped: the union must serialize as a JSON array.
  named <- as_loc_list(list(x = ".b", y = a))
  expect_null(names(named))
  expect_error(as_loc_list(list(".b", 1)), "CSS selector")
})

test_that("format_loc renders css and qualifiers in fixed order", {
  expect_identical(format_loc(pz_loc(".btn")), "`.btn`")
  expect_identical(
    format_loc(
      pz_loc(".shiny-tool-request", has_text = "get_weather", which = "last", within = ".chat")
    ),
    '`.shiny-tool-request` (has_text: "get_weather", which: last, within: `.chat`)'
  )
  expect_identical(format_loc(pz_loc(".btn", which = 3)), "`.btn` (which: 3)")
  expect_identical(
    format_loc(pz_loc(".btn", within = pz_loc(".panel", has_text = "Delete"))),
    '`.btn` (within: `.panel` (has_text: "Delete"))'
  )
})

test_that("format_loc describes a union target", {
  expect_identical(
    format_loc(as_loc_list(list(".a", pz_loc(".b", which = "first")))),
    "`.a` | `.b` (which: first)"
  )
})

test_that("print.paparazzi_loc shows the target description", {
  loc <- pz_loc(".btn", which = "last")
  out <- paste(capture.output(print(loc)), collapse = "\n")
  expect_identical(out, "<paparazzi_loc> `.btn` (which: last)")
})

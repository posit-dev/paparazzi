test_that("pz_example() lists the shipped examples", {
  expect_identical(pz_example(), c("tasks", "tasks-app"))
})

test_that("pz_example() returns paths without needing the extension", {
  tasks <- pz_example("tasks")
  expect_true(file.exists(tasks))
  expect_identical(basename(tasks), "tasks.html")

  app <- pz_example("tasks-app")
  expect_true(dir.exists(app))
  expect_true(file.exists(file.path(app, "app.R")))
})

test_that("pz_example() errors on unknown names", {
  expect_snapshot(error = TRUE, {
    pz_example("nope")
    pz_example(c("tasks", "tasks-app"))
  })
})


test_that("walkthrough keeps both high-priority task titles in view", {
  page <- local_page(pz_example("tasks"), width = 800, height = 900)
  page |>
    pz_type("Prepare release notes", target = "#task-title") |>
    pz_click("#add-task") |>
    pz_expect_text(
      "Prepare release notes",
      target = pz_loc(".task-title", which = "first")
    ) |>
    pz_find(pz_loc(".task", has_text = "Prepare release notes")) |>
    pz_click(".task-done") |>
    pz_find_reset() |>
    pz_click(".filters a[href='#done']") |>
    pz_click(".filters a[href='#all']") |>
    pz_expect_visible(pz_loc(".task", has_text = "File tax return")) |>
    pz_scroll("#toggle-help") |>
    pz_annotate_redact("[data-priority='high'] .task-title")
  rows <- pz_js(
    page,
    "(() => { const list = document.querySelector('.task-list'); const clip = list.getBoundingClientRect(); return [...list.querySelectorAll('[data-priority=high] .task-title')].map(el => { const r = el.getBoundingClientRect(); return {title:el.textContent, visible:r.top >= clip.top + list.clientTop && r.bottom <= clip.top + list.clientTop + list.clientHeight}; }); })()"
  )
  expect_identical(
    vapply(rows, `[[`, "", "title"),
    c("Renew passport", "File tax return")
  )
  expect_true(all(vapply(rows, `[[`, logical(1), "visible")))
  redactions <- pz_js(
    page,
    paste0(
      "(() => { const titles = document.querySelectorAll('[data-priority=high] .task-title');",
      "const boxes = document.querySelector('#paparazzi-overlay-root')",
      ".shadowRoot.querySelectorAll('.pz-redaction');",
      "return {count: boxes.length, aligned: [...titles].map((el, i) => {",
      "const r = el.getBoundingClientRect(), b = boxes[i]?.getBoundingClientRect();",
      "return b && boxes[i].style.display !== 'none' &&",
      "['left', 'top', 'width', 'height'].every(key => Math.abs(b[key] - r[key]) < 1);",
      "})}; })()"
    )
  )
  expect_equal(redactions$count, 2)
  expect_true(all(unlist(redactions$aligned)))
})

# Every help page's examples run here with the interactive guard forced on,
# so an example that rots fails the suite instead of only a pkgdown build.
example_rd_db <- function() {
  root <- test_path("..", "..")
  if (dir.exists(file.path(root, "man"))) {
    tools::Rd_db(dir = root)
  } else {
    tools::Rd_db("paparazzi")
  }
}

rd_db <- example_rd_db()

has_examples <- vapply(
  rd_db,
  function(rd) "\\examples" %in% vapply(rd, attr, "", "Rd_tag"),
  logical(1)
)

for (rd_name in names(rd_db)[has_examples]) {
  test_that(paste("examples run:", rd_name), {
    script <- withr::local_tempfile(fileext = ".R")
    tools::Rd2ex(rd_db[[rd_name]], script, commentDontrun = TRUE)
    skip_if_no_chrome()
    withr::local_options(rlang_interactive = TRUE)
    withr::local_dir(withr::local_tempdir())
    # Examples may intentionally print caught expectation errors, and
    # pz_inspect() reports where it wrote an annotated screenshot. Capture
    # that message stream and assert the documented output instead of letting
    # it leak into the test reporter.
    messages <- capture.output(
      expect_no_error(utils::capture.output(
        source(script, local = new.env(parent = globalenv()))
      )),
      type = "message"
    )
    expected <- switch(
      rd_name,
      "pz_expect_exists.Rd" = c(
        "Error : Expected an element to match",
        "Target: `.error-message`",
        "Last seen: 0 matches",
        "Waited <elapsed>s."
      ),
      "pz_expect_text.Rd" = c(
        "Error : Expected text to contain \"otters\"",
        "Target: `h1`",
        "Last seen: \"Tasks\"",
        "Waited <elapsed>s."
      ),
      "pz_inspect.Rd" = "Annotated screenshot: <path>",
      character()
    )
    if (rd_name %in% c("pz_expect_exists.Rd", "pz_expect_text.Rd")) {
      expect_match(tail(messages, 1), "^Waited [0-9]+(\\.[0-9]+)?s\\.$")
      messages[[length(messages)]] <- "Waited <elapsed>s."
    }
    if (identical(rd_name, "pz_inspect.Rd")) {
      expect_length(messages, 1L)
      expect_match(messages[[1]], "^Annotated screenshot: '.+\\.png'$")
      messages <- "Annotated screenshot: <path>"
    }
    expect_identical(messages, expected)
  })
}

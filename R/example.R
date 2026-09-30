#' Paths to example pages and apps
#'
#' paparazzi ships a few small pages and apps for its examples and
#' articles. `pz_example()` returns the path to one of them, ready to pass to
#' [pz_open()] or [pz_serve_shiny()]. The examples are:
#'
#' * `"tasks"`: a static task tracker page (an HTML file) with a form, a
#'   scrollable list of draggable tasks, filter links that change the URL
#'   fragment, inline title editing, an attachment input for new tasks, a
#'   help panel that starts hidden, and a "Start over" link that loads the
#'   page again. Adding a task shows "Saving..." for 400ms before the task
#'   appears.
#' * `"tasks-app"`: a Shiny app directory with a text input, a selectize
#'   priority input, an Add button, and a task list whose output takes half
#'   a second to render. Running it requires the shiny package.
#'
#' @param name The name of an example, without a file extension. `NULL`
#'   returns the names of all examples.
#'
#' @return The absolute path to the example's file or directory, or a
#'   character vector of example names when `name` is `NULL`.
#'
#' @examples
#' pz_example()
#' pz_example("tasks")
#'
#' @examplesIf paparazzi:::examples_run(site = TRUE)
#' page <- pz_open(pz_example("tasks"))
#' pz_get_title(page)
#' pz_close(page)
#'
#' @export
pz_example <- function(name = NULL) {
  check_string(name, allow_null = TRUE)
  dir <- system.file("examples", package = "paparazzi", mustWork = TRUE)
  files <- list.files(dir)
  # Examples are pages (.html) or app directories; other files are assets.
  files <- files[
    tools::file_ext(files) == "html" | dir.exists(file.path(dir, files))
  ]
  names <- tools::file_path_sans_ext(files)
  if (is.null(name)) {
    return(sort(names))
  }
  if (!name %in% names) {
    cli::cli_abort(c(
      "{.val {name}} is not a paparazzi example.",
      "i" = "Available examples: {.val {sort(names)}}."
    ))
  }
  file.path(dir, files[match(name, names)])
}

# Paths to example pages and apps

paparazzi ships a few small pages and apps for its examples and
articles. `pz_example()` returns the path to one of them, ready to pass
to
[`pz_open()`](https://posit-dev.github.io/paparazzi/reference/pz_open.md)
or
[`pz_serve_shiny()`](https://posit-dev.github.io/paparazzi/reference/pz_serve_shiny.md).
The examples are:

## Usage

``` r
pz_example(name = NULL)
```

## Arguments

- name:

  The name of an example, without a file extension. `NULL` returns the
  names of all examples.

## Value

The absolute path to the example's file or directory, or a character
vector of example names when `name` is `NULL`.

## Details

- `"tasks"`: a static task tracker page (an HTML file) with a form, a
  scrollable list of draggable tasks, filter links that change the URL
  fragment, inline title editing, an attachment input for new tasks, a
  help panel that starts hidden, and a "Start over" link that loads the
  page again. Adding a task shows "Saving..." for 400ms before the task
  appears.

- `"tasks-app"`: a Shiny app directory with a text input, a selectize
  priority input, an Add button, and a task list whose output takes half
  a second to render. Running it requires the shiny package.

## Examples

``` r
pz_example()
#> [1] "tasks"     "tasks-app"
pz_example("tasks")
#> [1] "/home/runner/work/_temp/Library/paparazzi/examples/tasks.html"

page <- pz_open(pz_example("tasks"))
pz_get_title(page)
#> [1] "Tasks"
pz_close(page)
```

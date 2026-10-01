# Agent guide: Locators and scopes

This reference covers picking the right elements and carrying a scope
through a chain. A **locator**
([`pz_loc()`](https://posit-dev.github.io/paparazzi/reference/pz_loc.md))
describes what to find; a **scoped context** (from
[`pz_find()`](https://posit-dev.github.io/paparazzi/reference/pz_find.md))
pins what was found. The examples share one page and run in order.

## Start from the page root

The root page is the starting point for independent chains. A CSS string
is shorthand for `pz_loc(css)`. Target IDs for single controls, and
classes or data attributes for collections.

``` r

library(paparazzi)
page <- pz_open(pz_example("tasks"), width = 1000, height = 720)
page |> pz_expect_count(7, target = ".task")
pz_get_elements(page, target = "#new-task input")
```

[`pz_get_elements()`](https://posit-dev.github.io/paparazzi/reference/pz_get_elements.md)
describes the matches;
[`pz_get_text()`](https://posit-dev.github.io/paparazzi/reference/pz_get_text.md),
[`pz_get_value()`](https://posit-dev.github.io/paparazzi/reference/pz_get_value.md),
[`pz_get_attr()`](https://posit-dev.github.io/paparazzi/reference/pz_get_attr.md)
and
[`pz_get_style()`](https://posit-dev.github.io/paparazzi/reference/pz_get_style.md)
read one property. Getters return values and end the chain, so after an
action that updates the page asynchronously, expect the update before
reading.

## Describe a reusable target

A
[`pz_loc()`](https://posit-dev.github.io/paparazzi/reference/pz_loc.md)
spec isn’t tied to a page and is resolved each time an action,
expectation or getter uses it. The same spec works across DOM updates,
pages and sessions, and in a test, a screenshot and a recording alike.

``` r

passport <- pz_loc(".task", has_text = "passport")
passport_title <- pz_loc(".task-title", within = passport)
page |> pz_expect_count(1, target = passport)
pz_get_text(page, target = passport_title)
```

`has_text` is a case-sensitive substring match on the element’s text,
with whitespace collapsed on both sides. Pick text that identifies the
row, then target a control inside it. `within` takes a string or another
spec and keeps only matches inside it.

``` r

passport_button <- pz_loc(".task-done", within = passport)
page |>
  pz_act_click(passport_button) |>
  pz_expect_class("done", target = passport)
```

## Choose one match by position

`which` applies after the CSS and text filters, and takes `"first"`,
`"last"` or a 1-based position. Use it when order is part of the
interface, like a newest-first task list.

``` r

first_title <- pz_loc(".task-title", which = "first")
last_title <- pz_loc(".task-title", which = "last")
second_task <- pz_loc(".task", which = 2)
pz_get_text(page, target = first_title)
pz_get_text(page, target = last_title)
pz_get_text(page, target = pz_loc(".task-title", within = second_task))
```

Because positions count the filtered matches, `which` and `has_text`
combine naturally. A position past the end matches nothing, and an
expectation will wait for it to appear.

## Combine targets as a union

A list of strings and specs matches every element any of them matches.
Use it to check or frame several separate regions at once.

``` r

high_titles <- pz_loc(".task-title", within = ".task[data-priority='high']")
pz_get_text(page, target = high_titles)
pz_get_count(page, target = list(".task.done", high_titles))
```

Clicking and typing need a single element. Narrow a collection with a
more specific locator, or with
[`pz_find_first()`](https://posit-dev.github.io/paparazzi/reference/pz_find_first.md),
[`pz_find_last()`](https://posit-dev.github.io/paparazzi/reference/pz_find_last.md)
or
[`pz_find_nth()`](https://posit-dev.github.io/paparazzi/reference/pz_find_nth.md).
Most expectations require every match to pass, so scope them to what you
mean to check.

## Assign the context `pz_find()` returns

[`pz_find()`](https://posit-dev.github.io/paparazzi/reference/pz_find.md)
resolves its target right away, waits for at least one match, pins the
matched elements and returns a **new context**. The context you passed
in is unchanged, so assign the result to use the scope more than once.

``` r

task_list <- pz_find(page, ".task-list")
passport_row <- pz_find(task_list, passport)
passport_row |> pz_expect_class("done")
pz_get_text(passport_row, target = ".task-title")
pz_get_count(page, target = ".task")
```

Now `page` is still the root, `task_list` is scoped to the list, and
`passport_row` to one row. An explicit `target` is looked up inside the
current scope, and `target = NULL` means the scope itself. At the root,
getters and expectations default to the page body, but pointer actions
need a target.

A scope can itself be the thing you click:

``` r

help_button <- pz_find(page, "#toggle-help")
help_button |> pz_act_click()
page |> pz_expect_visible(target = "#help")
```

## Narrow a pinned set

Finding a collection pins all of it. Without a target, the positional
find helpers pick from that pinned set. With a target, they find matches
in the current scope and pin the chosen one.

``` r

all_tasks <- pz_find(page, ".task")
first_row <- pz_find_first(all_tasks)
last_row <- pz_find_last(all_tasks)
second_row <- pz_find_nth(all_tasks, 2)
pz_get_text(first_row, target = ".task-title")
pz_get_text(last_row, target = ".task-title")
pz_get_text(second_row, target = ".task-title")
```

When a positional find has a target, put the position in the helper and
leave `which` out of the spec, so the rule lives in one place.

``` r

page |>
  pz_find_first(".task[data-priority='high']") |>
  pz_expect_exists(target = ".task-title")
```

## Return to a broader scope

[`pz_find_pop()`](https://posit-dev.github.io/paparazzi/reference/pz_find_pop.md)
returns the context one scope up, and
[`pz_find_reset()`](https://posit-dev.github.io/paparazzi/reference/pz_find_reset.md)
returns the root; neither changes the context you pass.
`from_root = TRUE` finds from the page root but pushes onto the current
scope stack, so a pop returns to where you were.

``` r

passport_row |>
  pz_find_pop() |>
  pz_expect_count(7, target = ".task")

passport_row |>
  pz_find_reset() |>
  pz_expect_visible(target = "#new-task")

task_list |>
  pz_find("#new-task", from_root = TRUE) |>
  pz_expect_exists(target = "#task-title") |>
  pz_find_pop() |>
  pz_expect_count(7, target = ".task")
```

## Refind scopes after the page changes

A scope pins specific DOM elements. It keeps working while they stay in
the page, even if their children change. When an element is replaced, as
with Shiny outputs or navigation, keep the spec, expect the new content,
then find it again. Navigation also releases every pinned scope.

``` r

page |>
  pz_nav_reload() |>
  pz_expect_visible(target = passport)
fresh_row <- pz_find(page, passport)
fresh_row |> pz_expect_exists(target = ".task-done")
pz_close(page)
```

Shiny covers re-rendered outputs, Testing covers choosing expectations,
and Pages and serving covers navigation and page ownership.

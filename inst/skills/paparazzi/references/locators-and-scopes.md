# Locators and scopes

Use this reference to select the intended elements and carry scope through a
chain. A locator describes what to find; a scoped context pins what was found.
The examples below share one page and run in order.

## Start from the page root

Keep the root page as the stable starting point for independent chains.
CSS strings are shorthand for `pz_loc(css)`. Use stable IDs for individual
controls and meaningful classes or data attributes for collections.

```r
library(paparazzi)
page <- pz_open(pz_example("tasks"), width = 1000, height = 720)
page |> pz_expect_count(7, target = ".task")
pz_get_elements(page, target = "#new-task input")
```

`pz_get_elements()` describes matched elements for inspection;
`pz_get_text()`, `pz_get_value()`, `pz_get_attr()` and `pz_get_style()` read
specific properties. Getters return values and end the context chain.
Read after an expectation when an action has started an asynchronous update.

## Describe a reusable target

`pz_loc()` is page-independent and lazy: resolution happens when an action,
expectation or getter uses it. Keep the spec across sessions and DOM updates.
The same description can be used by a test, screenshot and recording.

```r
passport <- pz_loc(".task", has_text = "passport")
passport_title <- pz_loc(".task-title", within = passport)
page |> pz_expect_count(1, target = passport)
pz_get_text(page, target = passport_title)
```

`has_text` is a case-sensitive substring match on the element's text content.
Whitespace is collapsed on both sides. Choose text that identifies the
intended row, then target a control within it. `within` accepts a string or
another fully qualified spec and restricts matches to descendants of the
matching ancestors.

```r
passport_button <- pz_loc(".task-done", within = passport)
page |>
  pz_act_click(passport_button) |>
  pz_expect_class("done", target = passport)
```

## Choose one match by position

`which` is applied after CSS and text filtering. It accepts `"first"`,
`"last"` or a positive 1-based integer. Use ordering when order is part of
the interface's contract, such as newest-first tasks.

```r
first_title <- pz_loc(".task-title", which = "first")
last_title <- pz_loc(".task-title", which = "last")
second_task <- pz_loc(".task", which = 2)
pz_get_text(page, target = first_title)
pz_get_text(page, target = last_title)
pz_get_text(page, target = pz_loc(".task-title", within = second_task))
```

A locator with an out-of-range position matches no element. Expectations
provide retrying readiness checks for newly inserted matches. Match positions
refer to the filtered set, so a position and `has_text` can be combined when
that is the intended selection rule.

## Combine targets as a union

A list of strings and specs matches the union of their elements. Use it to
check or frame a collection of independent regions. A single CSS selector
with multiple matches also describes a collection.

```r
high_titles <- pz_loc(".task-title", within = ".task[data-priority='high']")
pz_get_text(page, target = high_titles)
pz_get_count(page, target = list(".task.done", high_titles))
```

Actions such as click and type need one actionable element. Narrow a
collection to a specific locator or use `pz_find_first()`, `pz_find_last()`
or `pz_find_nth()` when one position is the intended target. Expectations
usually require every match to satisfy the condition; scope accordingly.

## Assign the context returned by find

`pz_find()` eagerly resolves a target, waits for at least one match, pins the
matched set and visibly returns a **new context**. It leaves its input context
unchanged. Retain that returned context to run more than one scoped chain.

```r
task_list <- pz_find(page, ".task-list")
passport_row <- pz_find(task_list, passport)
passport_row |> pz_expect_class("done")
pz_get_text(passport_row, target = ".task-title")
pz_get_count(page, target = ".task")
```

Here `page` remains at the root, `task_list` is scoped to the list, and
`passport_row` is scoped to its row. A later explicit `target` is looked up
among descendants of the current scope. For calls that accept it,
`target = NULL` refers to the scope itself. At the root, getters and
expectations generally use the page body, while pointer actions need an
explicit target.

Use this to click a control already selected as a scope:

```r
help_button <- pz_find(page, "#toggle-help")
help_button |> pz_act_click()
page |> pz_expect_visible(target = "#help")
```

## Narrow a pinned set

Finding a collection pins the whole matched set. The positional find helpers
without a target slice that set immediately. With a target, they resolve the
matching set in the current scope and pin the selected match.

```r
all_tasks <- pz_find(page, ".task")
first_row <- pz_find_first(all_tasks)
last_row <- pz_find_last(all_tasks)
second_row <- pz_find_nth(all_tasks, 2)
pz_get_text(first_row, target = ".task-title")
pz_get_text(last_row, target = ".task-title")
pz_get_text(second_row, target = ".task-title")
```

For a positional find with a target, give position to the helper and use a
spec without `which`. This keeps the selection rule in one place.

```r
page |>
  pz_find_first(".task[data-priority='high']") |>
  pz_expect_exists(target = ".task-title")
```

## Return to a broader scope

`pz_find_pop()` returns a context one scope level up. `pz_find_reset()` returns
a root context. Both leave the context passed to them unchanged.
`from_root = TRUE` resolves a new find from the page root while pushing it
onto the current stack; popping then returns to the previous scope.

```r
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

## Reacquire scopes after replacement

Pinned scopes represent particular DOM elements. They stay useful while those
elements remain attached, even when descendants change. For reactive output
replacement or navigation, keep a lazy spec and acquire a new scope after
asserting readiness. Navigation returns a root context and releases the prior
pinned scopes.

```r
page |>
  pz_nav_reload() |>
  pz_expect_visible(target = passport)
fresh_row <- pz_find(page, passport)
fresh_row |> pz_expect_exists(target = ".task-done")
pz_close(page)
```

For re-rendered Shiny outputs, see Shiny. For choosing an expectation before
reading a property, see Testing. For HTTP history and page ownership, see
Pages and serving.

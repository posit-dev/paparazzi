# Locate elements by CSS, with text, position, and scope qualifiers

`pz_loc()` builds a page-independent element spec: a CSS selector,
optionally narrowed by required text content (`has_text`), a match
position (`which`), and an ancestor scope (`within`). Specs are lazy –
they resolve at use time, so they follow DOM changes between uses – and
can be defined once and reused across sessions.

Wherever a spec is accepted, a bare string is promoted to
`pz_loc(string)`, and a list of specs and strings is a union that
matches the elements of any member.

## Usage

``` r
pz_loc(css, ..., has_text = NULL, which = NULL, within = NULL)
```

## Arguments

- css:

  A CSS selector string.

- ...:

  Checked empty; reserved for future use.

- has_text:

  Substring the element's text content must contain. `NULL` omits text
  filtering. Case-sensitive; whitespace collapses on both sides, so
  `has_text = "Save now"` matches text reading "Save now".

- which:

  Pick one match by position: `"first"`, `"last"`, or a 1-based positive
  integer. Applied after `css` and `has_text` filtering; an out-of-range
  position means *no* match, not an error. `NULL` keeps all matches.

- within:

  Only match descendants of elements matching this spec (a string or
  `pz_loc()`, itself fully qualified). If `within` matches nothing, the
  whole spec matches nothing. `NULL` omits the ancestor qualifier.

## Value

An S3 object of class `paparazzi_loc`.

## Examples

``` r
# A spec describes elements; nothing is looked up until you use it
pz_loc(".task")
#> <paparazzi_loc> `.task`
pz_loc(".task", has_text = "passport")
#> <paparazzi_loc> `.task` (has_text: "passport")
pz_loc(".task", which = "last")
#> <paparazzi_loc> `.task` (which: last)
pz_loc(".task-done", within = pz_loc(".task", has_text = "dentist"))
#> <paparazzi_loc> `.task-done` (within: `.task` (has_text: "dentist"))

page <- pz_open(pz_example("tasks"))

# Specs resolve each time they're used, so define them once and reuse them
high <- pz_loc(".task-title", within = ".task[data-priority='high']")
pz_get_text(page, target = high)
#> [1] "Renew passport"  "File tax return"

# A list of specs and strings matches the elements of any member
pz_get_count(page, target = list(".task.done", high))
#> [1] 3
pz_close(page)
```

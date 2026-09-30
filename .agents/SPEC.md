# paparazzi

A "Playwright-lite" R package over chromote: smooth, pipeable browser driving, plus screenshots and screen recordings.

Status: implemented. The API index below records the shipped signatures; task-specific mechanism decisions are recorded in kata comments.

## Background

The shinychat blog post (`open-source-website/content/blog/shinychat-r-0.5.0-python-0.7.1/apps/`) automated every screenshot and recording with ~45 helpers in `_common.R`. Those helpers are the seed for this package:

- **Driving:** `js`, `wait_for*`, `click_selector`, key presses, `rect_of`/`rect_of_text`, `select_edit_text`, `set_viewport`, `set_zoom`.
- **Stills:** `save_png`, `viewport_png`, `element_png`, `union_png`.
- **Recording:** `movie_start` (`snap`/`beat`/`loop`/`loop_until`), `movie_save` (ffmpeg concat), `movie_clip_fit`.
- **Staging:** a fake SVG cursor moved in lockstep with real CDP mouse events, eased glides, click animation, natural typing.
- **App lifecycle:** `start_app`/`stop_app`/`free_port` (overlaps webshot2's `R/process.R` and `R/wait.R`).

Known bugs to fix while porting:

- `wait_for()` treats its ms timeout as seconds.
- The bounding-box union JS updates `x` before computing the width.
- `movie_save()` assigns each frame the duration of the gap *before* it.
- `start_app()` never drains its stdout/stderr pipes.

## Decisions

### Package

- New package, independent of webshot2 for now. webshot2 may later be rebuilt on top of paparazzi.
- Implementation lives in R6 methods; a functional `pz_*()` layer is the primary, documented interface.
- Automatic waiting before actions is on by default, with a timeout configurable per session and per call.

### Chaining

- Actions take a **context** as their first argument and normally return it invisibly, so whole scripts can be one `|>` chain. Knitted media captures are terminal exceptions: pathless screenshots and completed recordings return printable results. Knitr includes a result when it is the visible last call of a top-level chunk expression. An interactive pathless screenshot also returns a printable preview. Explicit-path screenshots and recordings outside knitting still return the context invisibly. Recording chains are the other exception (see Recording lifecycle): the context `pz_record_start()` returns, and contexts derived from it, come back visibly while that recording runs, and printing one stops the recording.
- The exception is the `pz_find*()` family (`pz_find()`, `pz_find_first()`, `pz_find_last()`, `pz_find_nth()`, `pz_find_pop()`, `pz_find_reset()`), which returns its context visibly. Scope lives only in the returned context, so a scoped context that is neither assigned nor piped onward prints at the console instead of disappearing silently.
- A context is either the page (root) or a scoped context created by `pz_find*()`.
- Page-level functions (`pz_press()`, recording, cursor, navigation) work from any context. Recording start remains chainable; during knitting, recording stop and the completed block form return media rather than a context.

### Argument order

- The first argument after `ctx` is the operation's main input.
  - When that input is the element (click, hover, find), it is `target`.
  - For `pz_find_nth()`, getters, and expectations, `target` follows any main input and precedes `...`, so it can be passed positionally or by name. Other actions keep an optional, named `target` after `...`.
- `...` separates positional inputs from named-only options where it is checked empty. In `pz_expect_attr()` and `pz_expect_style()`, it instead carries named attribute/style pairs; dot-prefixed control arguments (`.target`, `.match`, `.not`, `.timeout`, `.normalize`) avoid collisions with pair names. `pz_open()` forwards its dots to `pz_device()`. All other dots are checked empty with `rlang::check_dots_empty()`.
- `target = NULL` means **the current context**:

  | Context | click / hover | type / press | screenshot |
  |---|---|---|---|
  | Scoped | the scope element | the scope element | the scope's box |
  | Root | error: needs a target | the focused element | viewport |

```r
pz_click(ctx, target = NULL, ...)
pz_type(ctx, text, ..., target = NULL)
pz_screenshot(ctx, path, ..., target = NULL, frame = NULL)
# path may be omitted while knitting (numbered PNG in the chunk's figure directory)
# or at an interactive console (temporary PNG preview); otherwise it is required.
pz_set_files(ctx, files, ..., target = NULL)
pz_select_text(ctx, text, ..., target = NULL)
pz_press(ctx, key, ...)
pz_expect_text(ctx, text, target = NULL, ..., match = "contains", not = FALSE, timeout = NULL)
pz_get_attr(ctx, name, target = NULL, ...)
pz_expect_attr(ctx, .target = NULL, ..., .match = c("exact", "contains", "regex"), .not = FALSE, .timeout = NULL)
```

### Actions

Pointer and keyboard:

- `pz_click()`, `pz_hover()`, `pz_type()` as above.
- `pz_press(ctx, key, ...)`: Playwright-style key syntax, e.g. `"Enter"`, `"Control+A"`, `"Meta+Enter"`, `"Shift+Tab"`. A vector presses keys in sequence: `pz_press(c("ArrowDown", "Enter"))`. Discussed: a `Mod` modifier and a `show_keys` option (see Camera, annotations, and captions).
- `pz_focus(ctx, target = NULL, ...)` / `pz_blur(ctx, ...)`: e.g. focus to show an input's enabled look, blur to remove focus rings before a screenshot.
- `pz_scroll(ctx, target = NULL, ..., by = NULL, to = NULL, duration = NULL)`: with a target, scroll it into view; with `by = c(x, y)` or `to = "bottom"` (direction vocabulary), scroll the current scope's container. While recording, scrolling is smooth, using real `mouseWheel` events with the cursor over the container; positive `duration` overrides the staged time per wheel scroll, while `duration = 0` uses the existing instant path (no queued wheels). Auto-scroll before other actions is animated the same way.
- `pz_drag(ctx, target, to, ..., by = NULL)`: `to` is a target, or use an offset `by = c(x, y)`. Real mouse press/move/release; the cursor glides while holding when recording. HTML5 drag and drop (`dragstart`/`drop`) needs `Input.setInterceptDrags` + `Input.dispatchDragEvent`, chosen when the source is `draggable`.
- `pz_select_text(ctx, text, ..., target = NULL)`: highlights an exact substring inside an element, as if dragging across it (TreeWalker over text nodes, DOM `Range`, window selection; works across inline tags). Typing afterwards replaces the selection. While recording, it's staged as a real mouse drag from the start of the text to the end.

Setting values:

- `pz_set_value(ctx, value, ..., target = NULL)`: generic DOM setter, like Playwright's `fill()`. Sets the value and dispatches `input` and `change`. Covers text inputs, textareas, native `<select>` (by value), checkboxes/radios (`TRUE`/`FALSE`), range and date inputs. Uses the native prototype setter so framework-controlled inputs notice. Contenteditable/ProseMirror falls back to select-all + `Input.insertText`. Instant even while recording; use `pz_type()` or clicks for the animated version. Clearing is `pz_set_value("")`, so there's no `pz_clear()`; replacing text on camera is `pz_set_value("") |> pz_type("new text")`.
- `pz_set_shiny_input(ctx, id, value, ..., wait = TRUE)`: sets a Shiny input through its input binding (as shinytest2's `set_inputs()` does), so the UI updates visibly and the server sees a real change. Handles selectize, sliders, date ranges, and any widget with a binding. Resolves `id` within the current scope (modules). `wait = TRUE` waits for Shiny idle. A missing binding is a clear error. It's the only Shiny-specific action.
- `pz_set_files(ctx, files, ..., target = NULL)`: file inputs, via `DOM.setFileInputFiles`.

Skipped in favor of primitives: select option (`pz_set_value()` for native selects, `pz_set_shiny_input()` for selectize), check/uncheck (`pz_set_value(TRUE)` or `pz_click()`), and clear (`pz_set_value("")`).

Navigation triggered by actions (clicking a link, submitting a form, JS redirects) isn't detected automatically. Call `pz_wait_for_navigation()` explicitly, which makes expected navigations obvious in the code and marks where scope resets to root.

### Element specs

- `pz_loc(css, ..., has_text, which, within)` builds a page-independent spec, which can be defined once and reused across sessions.
- Bare strings are promoted to `pz_loc(css)` wherever a spec is accepted.
- Lists of specs/strings are accepted where a union makes sense (e.g. screenshots).
- `which`, `within` and `has_text` live on the spec only, not on actions.

```r
chat <- list(
  input = pz_loc("#chat_user_input .ProseMirror"),
  send = pz_loc(".shiny-chat-btn-send"),
  last_reply = pz_loc(".shiny-chat-assistant-message", which = "last")
)
```

### Scoping

Scope is part of the chain's context, managed as a stack:

- `pz_find(ctx, target, ..., from_root = FALSE)`: push a scope. With `from_root = TRUE` the target is resolved from the root, but the new scope is still pushed on top of the stack, so `pz_find_pop()` returns to the previous scope.
- `pz_find_first()`, `pz_find_last()`, `pz_find_nth(n, target = NULL, ...)`: same as `pz_find()` with `which`. `target` is optional; without it they narrow the current scope. Each call pushes one level.
- `pz_find_pop()`: pop one level.
- `pz_find_reset()`: clear all scope, back to root.

`pz_find()` returns a new context; it never mutates the page object. The browser is shared: actions change the tab, and every context of a page sees those changes. Scope belongs to the chain: it's a view held on the R side, so it never carries over implicitly into the next chain, a helper's caller, or another test that shares the page. A later chain inherits a scope only when it starts from a context that holds one.

Resolution: specs are lazy, `pz_find*()` is eager.

| | Resolved | On DOM change |
|---|---|---|
| `pz_loc()` / strings | at use, every time (lazy) | follows the DOM |
| `pz_find*()` scopes | at call time, after auto-waiting for ≥ 1 match (eager) | error if detached |
| `element` column in getter tibbles | at get time (eager) | error if detached |

- `pz_find*()` actually finds and pins the matched set. Users operating on found elements don't want that set to change underneath them; a lazy, reusable description is what `pz_loc()` is for.
- Targets passed to actions (strings, `pz_loc()`) are still resolved and auto-waited lazily **inside** the pinned scope at action time, so re-renders within a scope are fine.
- Before each use, pinned elements are checked with `isConnected`. A detached scope raises a clear error and is never silently re-queried:

  ```
  ✖ Scope element is no longer in the page (it was probably re-rendered).
    Scope: `.shiny-tool-request` (has_text: "get_weather")
  ℹ Call `pz_find()` again after the update, or target it with `pz_loc()`.
  ```

- Multi-match scopes pin the whole set found at that moment.
- Implementation: pinned elements are CDP remote objects (object IDs in a per-page object group), acted on with `Runtime.callFunctionOn`. A small internal wrapper class owns their lifecycle (connection checks, release). Navigation and `pz_close()` release the object group.
- A `lazy = TRUE` option could be added later without breaking changes.

### Multiple matches

- Each action decides whether it can operate on several elements; there is no `strict` argument.
- **Accept multiple:** screenshot (union of boxes), expectations (see below), getters (one value per match).
- **Error on multiple:** click, type, set_files, hover, select_text, cursor moves, drag.

### Expectations

Shared behavior:

- Signature: `pz_expect_x(ctx, <main input>, target = NULL, ..., not = FALSE, timeout = NULL)`. The pair-taking `pz_expect_attr()` and `pz_expect_style()` instead use dot-prefixed controls (see below).
- Retry until pass or timeout. `timeout = NULL` uses the session default; `timeout = 0` checks once.
- On success, return `ctx` invisibly.
- On failure, throw a classed error (e.g. `paparazzi_expectation_failure`) showing the expectation, the last observed value, the full target including scope, and the time waited:

  ```
  ✖ Expected text to contain "otters"
    Target: `.shiny-chat-assistant-message` (which: last)
      within `.shiny-chat-container`
    Last seen: "Here's a summary of the penguins data..."
    Waited 5s.
  ```

Catalog:

| Group | Function | Main input |
|---|---|---|
| Presence | `pz_expect_exists()` | – |
| | `pz_expect_count()` | `n`, or `min`/`max` |
| State | `pz_expect_visible()` | – |
| | `pz_expect_hidden()` | – |
| | `pz_expect_enabled()` | – |
| | `pz_expect_focused()` | – |
| | `pz_expect_checked()` | – |
| | `pz_expect_in_viewport()` | – |
| Content | `pz_expect_text()` | `text` |
| | `pz_expect_value()` | `value` |
| | `pz_expect_attr()` | attribute/value pairs in the dots |
| | `pz_expect_class()` | `class` |
| | `pz_expect_style()` | `...` property/value pairs (see Styles) |
| Escape hatch | `pz_expect_js()` | JS predicate receiving the element, e.g. `"el => el.scrollTop > 0"` |
| Page | `pz_expect_url()` | `url` |
| | `pz_expect_title()` | `title` |

Negation:

- Every expectation takes `not = FALSE` (`pz_expect_attr()` and `pz_expect_style()` use `.not`); no `pz_expect_not_*()` variants.
- Aliases only when the negated state is a common concept in its own right. For now that's just `pz_expect_hidden()`, which is exactly `pz_expect_visible(not = TRUE)`.

Multiple matches:

- The default is **all**: every match must satisfy the expectation. To express "some element", narrow the scope, e.g. `pz_find_last()` or `pz_loc(has_text =)`.
- The exception is `pz_expect_exists()`, which is about existence: it passes with at least one match (visible or not), and with `not = TRUE` it passes with zero matches.
- State and single-value content checks need at least one match. With `not = TRUE`, they pass when no match satisfies the condition, including zero matches. The pair-taking attribute/style checks instead negate the combined all-matches/all-pairs condition.
- Text vectors: length 1 applies to every match. Length `n` compares pairwise in order and requires exactly `n` matches. The same applies to attribute values in `pz_expect_attr()`.
- In `pz_expect_attr()`, the dots hold named attribute/value pairs. Multiple pairs combine with AND across every element; `.not = TRUE` negates the combined check (it passes when any pair fails on any element, or when there are no matches). Vector values stay pairwise per attribute for the match count.

| Check | Passes when | `not = TRUE` passes when |
|---|---|---|
| `pz_expect_exists()` | ≥ 1 match in the DOM | 0 matches |
| `pz_expect_visible()` | ≥ 1 match, all visible | no match visible (including 0) |
| `pz_expect_hidden()` | no match visible (including 0) | same as `pz_expect_visible()` |
| `pz_expect_count(n)` | exactly `n` matches (or `min`/`max`) | anything other than `n` |

Text matching:

- `match = c("contains", "exact", "regex")`, defaulting to `"contains"`. Also used by `pz_expect_value()`, `pz_expect_attr()` (as `.match`, defaulting to `"exact"`), `pz_expect_url()` and `pz_expect_title()`.
- Whitespace is collapsed before comparing.

Waits vs. expectations:

- `pz_expect_*()`: conditions on elements and the page that have a clear expected value.
- `pz_wait_for*()`: synchronization points that don't assert a value: `pz_wait_for_stable()` (text or layout stops changing), `pz_wait_for_js()`, `pz_wait_for_shiny_idle()`, `pz_wait_for_navigation()` (explicit wait after an action that navigates; resets scope to root), and `pz_wait(seconds)` for deliberate pauses.
- There's no element-state `pz_wait_for(target, state =)`; use `pz_expect_visible()`, `pz_expect_hidden()` or `pz_expect_exists(not = TRUE)`.

testthat:

- When testthat is running, a passing expectation counts as a testthat expectation and a failure is reported as a test failure, via `testthat::expect()` (testthat in Suggests).
- Outside tests, expectations behave as described above.
- Later: soft assertions, and `pz_expect_screenshot()` for visual regression on top of `expect_snapshot_file()`.

### Getters

Getters return values, so they end the chain. They're named `pz_get_*()`, parallel to `pz_expect_*()`.

| Getter | Returns | Matching expectation |
|---|---|---|
| `pz_get_count()` | integer | `pz_expect_count()` |
| `pz_get_text()` | character, one per match | `pz_expect_text()` |
| `pz_get_value()` | character, one per match | `pz_expect_value()` |
| `pz_get_attr(name)` | character, one per match, `NA` if missing | `pz_expect_attr()` |
| `pz_get_style(props)` | tibble, one row per match | `pz_expect_style()` |
| `pz_get_rect()` | tibble: `x`, `y`, `width`, `height`, one row per match | – |
| `pz_get_elements()` | tibble: `tag`, `id`, `class`, `text`, one row per match | – |
| `pz_get_html()` | character, outer HTML, one per match | – |
| `pz_get_url()` / `pz_get_title()` | character | `pz_expect_url()` / `pz_expect_title()` |
| `pz_js()` | the JS value | `pz_expect_js()` |

- Same argument rule as everything else: `pz_get_text(ctx, target = NULL, ...)`, `pz_get_attr(ctx, name, target = NULL, ...)`. `target = NULL` means the current scope.
- Getters auto-wait for at least one match, then return all matches, and error after the timeout. `pz_get_count()` returns immediately, since 0 is a valid answer.
- `pz_get_text()` collapses whitespace like `pz_expect_text()`; `raw = TRUE` turns that off.
- Tibble getters include an `element` list-column. Each entry is a context scoped to that one match, pinned at get time (see Scoping), so you can continue from it: `rects$element[[2]] |> pz_hover() |> pz_screenshot("second.png")`. The column gets a short pillar type label (e.g. `<pz_ctx>`) and a compact print format. tibble is in Imports.
- No peek/tee helper. To grab a value mid-chain, split the chain by assigning the scoped context:

  ```r
  item <- page |>
    pz_find(".history-drawer") |>
    pz_find_last(".history-item")

  title <- pz_get_text(item, ".history-title")

  item |>
    pz_hover() |>
    pz_click(".actions-btn")
  ```

### Styles

`pz_get_style()` / `pz_expect_style()` read and check **computed** styles. "style" rather than "css" because it's the applied style (as in `getComputedStyle()`), and because "CSS" already means selectors in this package. Docs should mention Playwright's `toHaveCSS()` and jQuery's `.css()` for discoverability.

```r
pz_get_style(ctx, props = NULL, target = NULL, ...)
pz_expect_style(ctx, .target = NULL, ..., .not = FALSE, .timeout = NULL, .normalize = TRUE)

page |> pz_expect_style(display = "none", .target = ".tool-body")
page |> pz_expect_style(font_size = "1rem", color = "#0d6efd", .target = ".btn-primary")
```

- In `pz_expect_style()`, `...` holds the property/value pairs (dynamic dots, so `!!!styles` works). `.target` precedes the dots; the remaining controls (`.not`, `.timeout`, `.normalize`) follow them. All controls are dot-prefixed to avoid collisions with property names.
- snake_case names are converted to kebab-case (`font_size` → `font-size`). Custom properties (`` `--bs-primary` ``) pass through unchanged.
- Every match must satisfy every pair. `.not = TRUE` passes when at least one pair doesn't match.
- `pz_get_style()` returns a tibble with one row per match, one character column per property, and the `element` column. `props = NULL` returns all computed properties.

Normalization: the browser returns computed values (`rgb(...)`, px lengths, numeric font weights), which rarely match what users write. Expected values are normalized in the browser too:

- A probe element lives in a paparazzi-owned container inside a shadow root at the document root, never in the app's DOM. This leaves positional selectors (`:first-child`, `:nth-child()`, `:has()`, sibling combinators), `:empty`, and the app's MutationObservers untouched.
- The expected value is set inline on the probe, and only the context needed to resolve it is copied from the target:

  | Expected value uses | Context copied onto the probe container |
  |---|---|
  | `em`, `ex`, `ch` | target's computed `font-size` / `font-family` |
  | `%` | target's parent width and height |
  | `currentColor` | target's computed `color` |
  | `rem`, `vw`/`vh`, color names, hex, keywords | none (global) |

- Reading the target and normalizing through the probe happen in one synchronous JS call, so nothing appears in screenshots or recordings.
- Numeric px comparisons use a small tolerance (~0.5px) for subpixel noise.
- A value the browser rejects (probe style stays empty) errors immediately as invalid CSS, without retrying.
- Shorthands (`margin`, `border`, `background`) are unreliable in computed styles; errors suggest longhands.
- `normalize = FALSE` compares raw computed strings, for contexts the probe can't reproduce (unusual `%` cases, container query units).
- State-dependent styles (`:hover`) work by acting first, then expecting, since the target's current computed style is read. Pseudo-elements could get a `pseudo =` argument later.

### Formatting

air and styler flatten pipe indentation, so scope depth can't be shown with indentation. This is handled with style guidance, not API:

- Flat chains are fine; `pz_find*()`, `pz_find_pop()` and `pz_find_reset()` mark scope changes.
- Short comments between pipe steps work as section headers (formatters keep them).
- For longer scoped stretches, assign the scoped context to a well-named variable and start a new chain from it.
- No block form for scoping.

### Recording

Lifecycle:

- Recorder state lives on the page, so recording happens inside a single chain.
- `pz_record_start(ctx, path, ..., format = c("auto", "mp4", "webm", "gif"))`: `path` is the main input. If omitted while knitting, a numbered path in the chunk's figure directory is used; if omitted interactively, a temp file, previewed in the viewer at stop. Otherwise `path` is required. `format` applies only without a path (an error alongside one): `"auto"` is MP4, or GIF when knitting to non-HTML output, where video can only be linked.
- **Recording chains:** start returns, invisibly, a new context carrying its recorder; `ctx_derive()` keeps it through `pz_find*()` and navigation resets. Chainable functions return through `ctx_return()`, which is visible only while that context's recorder is the page's active one. Printing such a context (`print()` or `knit_print()`) calls `pz_record_stop()` and shows the media: knitr media while knitting, a viewer preview interactively (video previews get an HTML wrapper page in a temp dir). So `page |> pz_record_start() |> ... ` needs no stop at the end of an expression; assign it or call `pz_record_stop()` to span statements. Chains not from start (`page |> pz_click()`) never stop a recording. Considered and rejected: making every chain visible, which would print page summaries after every action in knitted docs and consoles and cost CDP round trips per print.
- `pz_record_stop(ctx)`: encodes and writes the file. During knitting, the completed recording is returned as printable media, including when the path was explicit; outside knitting it returns the context.
- `pz_record_pause()` / `pz_record_resume()`: cut stretches out of the recording. There's no cancel.
- `pz_record_hold(ctx, seconds)`: hold the frame while recording; no-op otherwise. Unlike `pz_wait()`, which always waits, debugging runs without recording don't pay for video-only pauses.
- Block form, with an embraced expression rather than a function. It stops and encodes on exit (including on error). It returns what `pz_record_stop()` returns, never the block's value: `ctx` invisibly with a path outside knitting, media while knitting, a preview when pathless and interactive. With no path, supply the expression by name as `pz_record(code = { ... })` (the `(ctx, path, code, ...)` argument order is unchanged):

  ```r
  page |>
    pz_record("demo.mp4", {
      page |>
        pz_type("Show me penguins", target = chat$input) |>
        pz_click(chat$send) |>
        pz_wait_for_stable(target = chat$last_reply)
    }) |>
    pz_screenshot("after.png")
  ```

Capture:

- During knitting, a visible, top-level GIF result uses knitr's image-figure handling (including figure options). MP4/WebM recordings use an HTML video element for HTML output and a link for other outputs; they are not images. An intermediate result inside a pipe is not automatically included. Quarto uses the same knitr capture path; no Quarto-specific API is needed.
- Two methods: timer-driven polling (default) and `Page.startScreencast` (frames must be acked).
- Both capture the **full viewport**; cropping happens at encode time. The frame can therefore be measured against the final layout, which replaces the blog's two-pass trick. The cost is lower polling fps; a `clip_at = "start"` option could clip during capture.

```r
pz_record_start(
  ctx, path, ...,
  method = c("poll", "screencast"),
  frame = NULL,             # NULL = page default or viewport; a pz_frame(); FALSE
  fps = 15,
  scale = NULL,             # output width or scale factor
  hold = c(0.5, 1),         # seconds to hold first/last frame
  keep_frames = FALSE
)
```

Framing is shared with screenshots; see Framing.

Timer and event loop:

- chromote's synchronous calls block by running `run_now()` on its private child loop (`synchronize.R`). The polling timer is scheduled on that child loop (`session$get_child_loop()`), so it fires during every synchronous chromote call.
- `pz_wait()` and expectation polling run `later::run_now(loop = child_loop)` instead of `Sys.sleep()`, so frames keep coming during waits.
- Timer captures use async chromote calls (`wait_ = FALSE`) to avoid nesting `synchronize()` inside a callback. If a capture is still in flight when the timer fires, the tick is skipped.
- Long-running plain R code between steps freezes the recording; document this.

Encoding:

- Format from the extension: `.mp4` (h264, yuv420p, dimensions rounded to multiples of 4), `.webm`, `.gif`.
- `av` encodes `.mp4` and `.webm`; every `.gif` uses `gifski`. Framed GIFs additionally use `png` to crop captured PNGs before gifski encodes them. All three packages are in Suggests; `pz_record_start()` checks up front that the packages needed for the requested format are installed.
- Frames are resampled to `fps` in R (latest frame at each output tick). This removes the blog's frame-duration off-by-one.

### Framing

`pz_frame()` is a lazy spec for the capture region, used by both `pz_screenshot(frame =)` and `pz_record_start(frame =)`. It generalizes the blog's `union_png()` and `movie_clip_fit()` (with the union bug fixed).

```r
pz_frame(
  target = NULL,        # NULL = use the calling function's target
  ...,
  ratio = NULL,         # e.g. 4/3, 16/9; NULL = tight to content
  pad = 0,              # number, or c(top, right, bottom, left)
  offset = c(0, 0),     # nudge in px
  anchor = "center",    # direction vocabulary
  bounds = NULL,        # target to clamp within
  when = c("stop", "start")   # recordings only
)
```

Computation:

1. Union the targets' bounding boxes.
2. Add `pad`, then shift by `offset`.
3. If `ratio` is set, grow the shorter side to reach it, placing content by `anchor`.
4. Clamp to `bounds` and to the capture surface: the rendered document for stills (`captureBeyondViewport` renders below-fold content, so a below-fold frame stays capturable) and the visible viewport for recordings.
5. Round to even pixels for video, whole pixels for stills.

`pz_screenshot()` has no `pad` argument; padding lives in the frame.

```r
page |> pz_screenshot("card.png", target = card, frame = pz_frame(pad = 32))
page |> pz_screenshot("card.png", target = card, frame = pz_frame(ratio = 16/9, pad = 24, anchor = "top"))
page |> pz_record_start("demo.mp4", frame = pz_frame(".shiny-chat-container", ratio = 4/3))
```

Default framing is page state set with `pz_stage_frame()`:

```r
pz_stage_frame(ctx, ..., ratio = NULL, pad = NULL, offset = NULL, anchor = NULL, bounds = NULL)

page |>
  pz_stage_frame(ratio = 4/3, pad = 32, offset = c(0, 14)) |>
  pz_screenshot("tool-collapsed.png", target = card) |>    # framed by default
  pz_screenshot("full.png", frame = FALSE) |>              # opt out: plain viewport
  pz_record_start("demo.mp4", frame = pz_frame(".shiny-chat-container"))  # explicit wins
```

- An explicit `frame =` replaces the default entirely (no field merging). `frame = FALSE` disables framing for one call. `pz_stage_frame(NULL)` clears the default.
- `pz_stage_frame()`, `pz_stage()` and `pz_stage_annotate()` set persistent page defaults. Framing and annotation styles apply to screenshots as well as recordings; `pz_stage()` primarily controls recording animation, with cursor visibility and scale also applying to stills.

### Cursor and staging

Staging settings live on the page, set with `pz_stage()` at any point in a chain, and persist across recordings. `pz_record_start()` does not repeat them. In `pz_stage()` and `pz_stage_annotate()`, every setting has `= NULL` in the signature: omitted arguments leave settings alone, explicit `NULL` restores the default, and a value sets an override.

```r
pz_stage(
  ctx, ...,
  cursor = NULL,          # NULL = visible only while recording; TRUE = always (stills too); FALSE = never
  cursor_speed = NULL,    # px per second during glides and staged scrolls; default 500
  cursor_scale = NULL,    # overlay cursor size multiplier; default 1.75
  enter = NULL,           # where a hidden cursor first appears: NULL (at target) or a side
  typing = NULL,          # "natural" (default) / "instant"
  typing_speed = NULL,    # characters per second; default 16
  pause = NULL,           # seconds to hold after each action; default 0
  camera_follow = NULL,  # follow targets while zoomed; default TRUE
  show_keys = NULL       # keystroke callouts; default "none"
)
```

Staging only animates while recording, so commenting out the recording runs the chain straight to its final state. The exception is cursor visibility: `cursor = TRUE` shows a static cursor in screenshots too.

| Setting / call | Recording | Not recording |
|---|---|---|
| Cursor glide, press animation | animated | skipped; the real CDP pointer still moves, so hover works. With `cursor = TRUE`, the cursor jumps to the pointer |
| `typing` / `typing_speed` | natural | instant |
| `pause` | held after each action | skipped |
| `pz_cursor_leave()` | glides out of frame | hides immediately |
| `pz_cursor_show()` / `pz_cursor_hide()` | shown / hidden | shown / hidden (static cursor for stills) |
| `pz_wait(seconds)` | waits | waits |

Cursor functions:

```r
pz_cursor_show(ctx, target = NULL, ..., from = NULL, icon = NULL)
pz_cursor_hide(ctx, ...)
pz_cursor_move(ctx, target, ..., duration = NULL, icon = NULL, offset = NULL)
pz_cursor_leave(ctx, side = "right", icon = NULL)
pz_scroll(ctx, target = NULL, ..., by = NULL, to = NULL, duration = NULL)
```

Pointer actions while recording:

1. Cursor visible: glide from its position to the target, pause briefly, act.
2. Cursor never shown: fade in on the target with a slightly longer pause (default), or with `enter = <side>` start off-frame on that side and glide in.
3. After `pz_cursor_leave()` the cursor is still visible but off-frame; the next action glides back in from there.
4. After a recorded `pz_type()` with a target, the cursor **rests**: it fades out in place so it doesn't cover the typed text, but it isn't hidden the way `pz_cursor_hide()` hides it. The next move glides from the resting point and fades in as it starts. Only a move ends a rest; presses and staging redraws leave it undrawn, and a navigation re-injects it undrawn. `pz_inspect()` reports `cursor resting`.

Movement and look:

- Glide duration scales with distance (roughly `clamp(0.25 + distance / cursor_speed, 0.5, 2)` seconds), cubic ease-in-out, short pauses before (~0.15s) and after (~0.2s) clicks. The 500 px/s default is deliberately slower than natural pointing so viewers can follow it; 400-600 px/s is a useful range. Staged scrolling uses the same duration bounds; `pz_scroll(duration > 0)` overrides the per-wheel-scroll duration and `duration = 0` scrolls instantly.
- Press animation scales the 1.75x default cursor down relative to its base size; `cursor_scale = 1` restores the original 20px artwork.
- The cursor icon follows the element under its landing point. `icon` names cover the CSS cursor keywords with bundled, per-keyword artwork (`auto` explicitly shows the default arrow; `none` draws no glyph while retaining overlay position). A computed `cursor: url(...)` with a supported fallback keyword uses the fallback; URL image contents are not drawn, and a bare URL falls back to `default`. An explicit `icon` on a cursor call overrides inference for that call only: it holds through the call's landing and does not persist, and the next automatic move starts with the icon left visible. A first off-frame entrance uses `default` unless the call sets `icon`. While recording, an automatic glide keeps the icon visible at its start and switches it once, when the eased glide enters the intended destination; elements merely crossed on the path are ignored. `pz_cursor_move(offset = c(x, y))` shifts the landing point in viewport CSS pixels (positive right and down, scalar recycled, per-call) and moves only the drawn overlay — no pointer events are dispatched. Landings may fall outside the viewport without clamping; the resting icon is inferred at the actual landing point, flipping a second time at landing when an offset leaves the target for a differently-cursored element. Ripple comes later.
- CSS zoom and device pixel ratio are handled internally.

Typing: one `Input.insertText` per character with randomized delays around `typing_speed`. Works for `<input>`, `<textarea>` and contenteditable/ProseMirror. No typo simulation.

Robustness:

- The overlay is re-injected after navigation via `Page.addScriptToEvaluateOnNewDocument`, keeping its last position.
- The overlay is excluded from `pz_find()`, bounding boxes and union screenshots, and uses `pointer-events: none`.

### Camera, annotations, and captions

Video-editor features for recordings and annotated stills. Design discussion, rationale and probe notes are on kata `1a3m`; the full idea backlog is on `54b1`. Implemented; per-feature mechanism decisions are in kata comments on `40bm`, `7sq5`, `gdjm`, `m6kv`, `mkns`, `b0y7`, `3t7j`, `0rdt`, `aq35`, and `51my`.

There are two families, split by where the effect shows up, paired with persistent page defaults in `pz_stage()` or `pz_stage_annotate()` (like `pz_cursor_*()` with `pz_stage(cursor_*)`):

- `pz_camera*()`: moves the view. Recording-only.
- `pz_annotate*()`: marks up the page. Appears in recordings and stills.

Keystroke callouts are a `pz_press()` option, not functions of their own.

There are three layers:

| Layer | What lives there | Mechanism |
|---|---|---|
| Page | marks, callouts, spotlight, redaction, cursor | DOM in the `#paparazzi-overlay-root` shadow root. Captured like page content, so it zooms with the camera. |
| Encode | camera, captions, keystroke callouts | Applied at `pz_record_stop()`: a time-varying crop and scale, plus composited screen-space PNGs. |
| Stills | annotations, current caption | Page annotations are captured as-is; the caption is composited onto the PNG. |

#### Camera

```r
pz_camera(ctx, target = NULL, ..., zoom = NULL, pad = NULL, duration = NULL, target_box = c("element", "annotated"), wait = FALSE)
pz_camera_reset(ctx, ..., wait = FALSE)
```

- The camera is an **encode-time crop**. Capture stays full-viewport. Each camera call records a keyframe (video time, shot rect in page CSS px, easing), and at stop every output frame gets an interpolated crop, scaled back to the output size. It works for both capture methods, and camera motion runs at the output fps. Sharpness is capped by the capture DPR (2 by default). The per-frame scroll position is logged so page-coordinate shots map into viewport frames.
- **Home shot:** the recording's frame (`pz_record_start(frame =)` or `pz_stage_frame()`), falling back to the full viewport. It defines the output size. Every shot grows to home's aspect ratio (centered) and is clamped inside home, so the camera never shows anything outside the recording's frame. `pz_camera_reset()` returns home, from any context.
- **Shot:** `target` takes element targets only (selector, `pz_loc()`, or a list whose union is the shot); coordinates may come later. Multiple matches are unioned. At the root, `target = NULL` is an error, as for `pz_click()`. `pad` uses `pz_frame()` semantics, but `NULL` means 24 CSS px. `zoom = NULL` fits `target` + `pad`, capped at the capture DPR (so a scale-1 page never zooms on a fit); a number is magnification relative to home. Beyond the DPR, a softness warning is given once per recording. A shot is measured when its call runs.
- **Duration:** `duration = NULL` is distance-based, `clamp(0.66 + 2 * d, 0.66, 2)` seconds, with `d = |Δcenter| / home_diagonal + 0.5 * |log2(zoom_to / zoom_from)|` (constants to be tuned against a prototype). Easing is the cursor's cubic ease-in-out. While recording, the call pumps for the move's duration so the move plays out in the video.
- **Concurrency:** `wait = FALSE` (the default) records the keyframe and returns at once, so the next step (typically a cursor glide) runs during the move; `wait = TRUE` pumps the loop for the move's duration. Manual camera calls settle first: a second `pz_camera()` waits for the previous move to land, then starts from there, so `pz_camera(x) |> ...steps... |> pz_camera(x)` moves toward `x` during the steps and then settles on it. A call whose shot is where the camera already is records a zero-length keyframe without a `duration`: it updates the target/scroll/reset anchor but adds no video time. With an explicit duration, it's a still keyframe (with `wait = TRUE`, the same as `pz_wait(duration)`). Follow moves win: they may interrupt an in-flight manual move, and since they end when their action lands, a later camera call never waits on one. `pz_record_hold()`, `pz_record_pause()` and `pz_record_stop()` let an in-flight move land first, because holds and pauses freeze video time (camera included) and stop ends it. A numeric lead delay is deferred: `pz_camera() |> pz_wait(n)` covers it.
- **Follow the action:** `pz_stage(camera_follow = TRUE)` is the default. While zoomed in, a pointer or typing action whose resolved target falls outside the shot plus a margin triggers a minimal pan at the current zoom, zooming out only as far as needed to fit the target. The move is keyframed to the cursor glide, so it lands when the cursor does; with the cursor off, it gets its own short staged pause. Expectations, getters and waits never move the camera, and it never triggers at home. With a non-waiting move in flight, follow leaves it alone when its destination frames the target (a zoom toward it, or a reset); otherwise containment is tested at the moment the action lands. Accepted tradeoff: an action that lands before such a move arrives can briefly land off-shot; `wait = TRUE` is the remedy, rather than coordinating action timing with the camera.
- **Without a recording**, camera calls are no-ops, and stills ignore the camera; to reuse a shot for a still, pass the same target to `pz_screenshot(frame =)`. The camera resets to home at every `pz_record_start()`.
- The cursor and page annotations zoom with the page. A fixed-size cursor under zoom is deferred; it would need page-side counter-scaling synced to the encode-time camera, a second clock. Revisit this after a prototype.

#### Annotations

```r
pz_annotate(ctx, target = NULL, ..., type = c("box", "circle", "underline", "highlight"),
            label = NULL, pad = NULL, reveal = NULL, id = NULL,
            color = NULL, font_family = NULL, font_size = NULL)
pz_annotate_callout(ctx, text, ..., target = NULL, side = NULL, arrow = TRUE, label = NULL,
                    reveal = NULL, id = NULL, color = NULL, font_family = NULL, font_size = NULL)
pz_annotate_spotlight(ctx, target = NULL, ..., pad = NULL, dim = NULL, reveal = NULL)
pz_annotate_redact(ctx, target = NULL, ..., method = c("fill", "blur"), pad = NULL, id = NULL, color = NULL)
pz_annotate_caption(ctx, text, ..., side = "bottom", color = NULL, font_family = NULL, font_size = NULL)
pz_annotate_clear(ctx, id = NULL, ...)
```

- **Multiple matches:** every function accepts them, so each match is annotated, and each match is redacted (anything else would leak).
- **Lifetime:** annotations persist until cleared or replaced. There is no `duration` argument; clearing is an explicit step in the chain (e.g. after `pz_wait()` or `pz_record_hold()`). Reusing an `id` replaces that annotation. `pz_annotate_clear(id = NULL)` clears everything. Spotlight and caption are single-slot (each new call replaces the last), with the reserved ids `"spotlight"` and `"caption"`. Annotations and captions are page state and persist across recordings; a caption set before `pz_record_start()` shows from the first frame. Page annotations belong to the current document: navigating to a new document removes them (a bfcache restore brings them back with the page), and the empty annotation layer is re-injected like the cursor.
- **Geometry:** each annotation keeps a reference to its element. A page-side `requestAnimationFrame` loop, running only while annotations exist, repositions the boxes in a `position: fixed` layer, which handles scrolling, inner scroll containers, fixed and sticky elements, and layout shifts. The loop only mirrors layout and orders nothing relative to R. A disconnected element hides its annotation, including redaction. Redactions also hide when their target stops rendering or is fully clipped, and follow axis-aligned overflow clipping along the target's containing-block chain (not custom `overflow-clip-margin`); they do not clip to the viewport, so below-fold framed captures stay redacted. (CSS anchor positioning can't reach page anchors from the shadow root.)
- **Reveal:** `"fade"`, `"draw"`, `"pop"`, `"slide"`, `"wipe"` (a clockwise conic sweep from 12 o'clock) or `"none"`, with a default per type. Clearing plays the reverse. Reveals animate only while recording; draw and clear calls pump through their animations, since a reveal can't play during a `pz_record_hold()` frozen frame. Without a recording, annotations draw and clear instantly. Redaction has no `reveal` and always appears instantly.
- **Options:**
  - `label`: a badge (`1`, `"A"`); `TRUE` numbers the matches 1..n, as `pz_inspect()` does.
  - `side`: the direction vocabulary. For a callout, `NULL` picks the side with the most room.
  - `arrow = FALSE`: a tooltip-style bubble next to the target.
  - `dim`: the spotlight's overlay opacity.
  - `method`: the redaction style, a solid `"fill"` (the safe choice) or `"blur"` (`backdrop-filter`, with a generous default radius). There is no pixelation: `backdrop-filter: url()` does nothing in Chrome, and filtering the element itself would restyle the page.
  - Style arguments (`color`, `font_family`, `font_size`) come after the dots and default to `NULL`, meaning the `pz_stage_annotate()` default (`color`, `font_family`, `font_size`) or the built-in fallback. On marks, the font arguments style the label badges. `font_size` is CSS px; screen-space captions scale by the output's scale factor.
- **Stills:** page annotations appear in `pz_screenshot()`; `pz_inspect()` outlines stay hidden. The current caption is composited onto stills.
- **Frames:** by default a frame measures element geometry only, which can clip an annotation's label or arrow. `pz_frame(target_box = "annotated")` makes each target contribute its box plus its own attached annotations (spotlight counts as its cutout, redaction adds nothing). This applies to stills and camera shots, but never to the recording's home frame, which is measured once while annotations come and go.

#### Captions and keystroke callouts

- **Captions:** screen-space. At encode (or still) time, a separate Chrome target renders each caption as a transparent PNG at output resolution, styled with CSS. Page webfonts don't carry over, so the font family is passed explicitly. The encoder composites it over its time window: one av filtergraph after the camera for MP4, WebM and GIF (GIF renders PNG ticks through it before gifski), and an R alpha blend for stills. The caption is a declarative page-level slot that persists across navigation and recordings. A caption still active at recording stop remains fully visible through the last frame in MP4, WebM, and GIF; an explicit clear or replacement retains its fade-out. The default look is a translucent dark pill with white text, centered, at most about 80% of the output width, wrapping. Style defaults are caption-specific: `color = NULL` is white (not the annotation `color` default), `font_size = NULL` is a caption built-in default, and `font_family = NULL` follows the `pz_stage_annotate()` font family. `pz_record_start(captions = c("burn", "vtt", "both"))` defaults to `"burn"`; `"vtt"` and `"both"` write `<name>.vtt` next to the video, which knitr can wire up as a `<track>` (kata ks7r), and are an error for GIF.
- **Keystroke callouts:** `pz_press(show_keys = NULL)`, with the page default `pz_stage(show_keys = "none")`. Values are `c("none", "words", "mac", "both")`: `"words"` shows Ctrl, Shift, Alt and Meta keycaps; `"mac"` shows ⌃ ⌥ ⇧ ⌘; `"both"` renders `Mod` as "Ctrl / ⌘". They're screen-space, shown bottom-center and stacked above any caption. A callout appears at the press, holds about 1 s after the last key, then fades over 0.25 s, all computed at encode. They're recording-only, and `pz_type()` has no `show_keys` argument.
- **`Mod` modifier:** `pz_press("Mod+K")` presses Meta when the browser reports a Mac platform, and Control otherwise.

### Sessions and apps

Opening pages:

```r
pz_open(
  x, ...,                    # ... forwarded to pz_device(), checked for typos
  wait = c("auto", "load", "shiny", "none"),
  timeout = NULL,
  shiny_options = list(),    # passed to shiny::runApp() when x is an app dir
  envvars = NULL
)
```

- `x` can be a URL, a local file (opened as `file://`), a Shiny app directory or `app.R` (run in a background process), a `pz_app()`, or an existing `ChromoteSession`.
- Shiny app objects are not supported; they error with advice to run the app in another process and pass its URL. No serialization, no process inversion.
- `wait = "auto"` uses `"shiny"` (connected and idle) for Shiny apps and `"load"` otherwise.
- Other servers (Python Shiny, `quarto preview`, …) are started by the user and opened by URL.

Apps:

```r
app <- pz_app("apps/complete-app", envvars = c(MOCK = "1"), shiny_options = list())
desktop <- pz_open(app, width = 1440)
mobile <- pz_open(app, width = 390, mobile = TRUE)
app$logs()
app$stop()
```

`pz_app()` returns a handle with `$stop()` and `$logs()` methods and a `print()` method (URL, port, status). This is the one place the API relies on methods rather than `pz_*()` functions. Cleanup works with withr: `withr::defer(app$stop())`.

- `pz_open(dir)` starts and owns an app, and closing the page stops it. `pz_app()` shares one app across pages.
- App stdout/stderr go to a temp log file (no undrained pipes), readable with `app$logs()`.
- Shutdown: interrupt, wait, kill. Runs on close, on error in block forms, and from a finalizer as a last resort.
- Ports come from a base-R picker using `serverSocket()` (R >= 4.0), not httpuv. If the app dies because the port was taken, retry with a new port.
- shiny and httpuv stay out of Imports; `rlang::check_installed("shiny")` runs only when opening an app directory.

Page lifecycle:

```r
pz_close(page)
pz_with_page(x, code, ...)     # withr-style block, closes on exit
pz_local_page(x, ..., .env)    # closes when the calling frame (e.g. a test) exits
```

`pz_with_page()` and `pz_local_page()` accept an open page or anything `pz_open()` accepts (including a `pz_app()`), and call `pz_close()` on scope exit. Given an app, they open a page on it and close only the page.

Navigation (resets scope to root; staging and recorder carry over):

```r
pz_nav_goto(ctx, url, ..., wait = "auto")
pz_nav_reload(ctx, ..., wait = "auto")
pz_nav_back(ctx, ...)
pz_nav_forward(ctx, ...)
```

Device emulation is one settings function, parallel to `pz_stage()`. Only supplied arguments change:

```r
pz_device(
  ctx, ...,
  width = NULL, height = NULL, scale = NULL, mobile = NULL,
  zoom = NULL, zoom_method = NULL,     # "viewport" (default) or "css"
  color_scheme = NULL, reduced_motion = NULL,
  locale = NULL, timezone = NULL
)
```

- Default `scale = 2` (retina).
- `zoom_method = "viewport"` shrinks the CSS viewport and raises the device scale factor, which keeps `vh` correct but can trigger media queries. `"css"` is the blog's CSS-zoom trick, which keeps the layout but can break `vh`-based layouts.
- `reduced_motion = TRUE` gives deterministic stills; opt-in because it's usually wrong for videos.

Shiny idle: `pz_wait_for_shiny_idle()` passes when `shiny:connected` has fired, `<html>` has no `shiny-busy` class and no `.recalculating` outputs remain, all held for a short stable window (~200ms).

Escape hatches:

- `pz_chromote(ctx)` returns the underlying `ChromoteSession` for raw CDP calls (not `pz_session()`, which could be confused with the page or Shiny's `session`).
- `pz_js(ctx, expr, ..., await = TRUE, timeout = NULL)` evaluates JS, awaiting promises, and returns the value (ends the chain). `timeout` bounds the evaluation; `NULL` uses the session default.

Inspecting:

```r
pz_inspect(ctx, target = NULL, ..., show = c("auto", "screenshot", "browser", "none"))
```

- Returns `ctx` invisibly, so it can be dropped anywhere in a chain.
- Prints a console summary: URL, device, scope stack with match counts (warning on stale pinned elements; scoped contexts only), recording and cursor state, and, if `target` is given, its matches resolved relative to the current scope **without** auto-waiting. Each match shows a short tag and its state (visible, enabled, box). Long lists are truncated.

  ```
  ── paparazzi scope ──────────────────────────────────────
  Scope      root › `.history-drawer` (1) › `.history-item` last (1)
  URL        http://127.0.0.1:4821/
  Device     1440 × 900 @2x · light
  Target     `.actions-btn` → 1 match
    1  <button class="actions-btn" aria-label="Actions">
       visible · enabled · at 812,344 · 24 × 24
  Recording  off · cursor hidden
  ```

- `show = "screenshot"`: an annotated screenshot (dashed outlines for scope, solid numbered outlines for target matches) shown in the IDE viewer, or its path printed.
- `show = "browser"`: draws the outlines in the live page and opens it with chromote's `$view()`.
- `show = "auto"`: `"screenshot"` in interactive sessions, `"none"` otherwise.
- Outlines live in paparazzi's shadow-root overlay and never appear in `pz_screenshot()` or recordings.
- The summary tells the root and scoped contexts apart. At the root, the header reads `paparazzi page` and there's no Scope line. A scoped context's header reads `paparazzi scope`, with the Scope line directly under it. After `pz_close()`, a root context prints `<paparazzi page> (closed)` and a scoped one prints `<paparazzi scope> (page closed)`.
- `print()` on a page or context shows the same summary without the target section or visuals.
- The page object has a `$view()` method that opens the live browser (DevTools), as chromote sessions do. There's no `pz_view()`; `pz_inspect(show = "browser")` covers the in-chain case.

Relationship to shinytest2: shinytest2 is Shiny-only, input/output-oriented, and built for regression tests. paparazzi is DOM- and interaction-oriented, works on any page, and adds staging and recording for docs and demos. Say so in the README.

### Directions

One vocabulary for `pz_cursor_leave(side =)`, `pz_stage(enter =)`, `pz_cursor_show(from =)`, `pz_frame(anchor =)` and `pz_scroll(to =)`:

- `"top"`, `"bottom"`, `"left"`, `"right"`, the four corners, and `"center"` where it makes sense.
- Input is normalized: lowercase, split on spaces or hyphens, sorted. `"top right"`, `"right top"`, `"top-right"` and `"right-top"` are equivalent.
- Invalid combinations (e.g. `"top bottom"`) error with the list of valid values.

## Example

```r
last_user <- pz_loc(".shiny-chat-user-message", which = "last")

page |>
  pz_find(last_user) |>
  pz_hover() |>
  pz_click(".shiny-chat-edit-btn") |>
  pz_find(".shiny-chat-edit-box .ProseMirror", from_root = TRUE) |>
  pz_select_text("penguins") |>
  pz_type("otters") |>
  pz_press("Enter") |>
  pz_find_reset() |>
  pz_wait_for_stable(target = pz_loc(".shiny-chat-assistant-message", which = "last")) |>
  pz_expect_text("otters", pz_loc(".shiny-chat-assistant-message", which = "last"))

page |>
  pz_find(pz_loc(".shiny-tool-request", has_text = "get_weather")) |>
  pz_click(".tool-header") |>
  pz_expect_visible(".tool-body") |>
  pz_screenshot("tool-expanded.png", frame = pz_frame(pad = 32))
```

## API index

Status of each name:

- **confirmed:** explicitly chosen or approved during design.
- **discussed:** used in proposals without objection, but not explicitly approved.
- **placeholder:** a working name that still needs review.

Every function takes `ctx` first and returns it invisibly unless noted. The `pz_find*()` family returns its context visibly (see "Chaining").

### Pages, apps, navigation

| Function | Signature | Name |
|---|---|---|
| `pz_open()` | `(x, ..., wait = c("auto", "load", "shiny", "none"), timeout = NULL, shiny_options = list(), envvars = NULL)` → page | confirmed |
| `pz_close()` | `(page)` | confirmed |
| `pz_with_page()` | `(x, code, ...)` | confirmed |
| `pz_local_page()` | `(x, ..., .env = parent.frame())` → page | confirmed |
| `pz_app()` | `(app_dir, ..., envvars = NULL, shiny_options = list(), timeout = NULL)` → app handle with `$stop()`, `$logs()` | confirmed |
| `pz_nav_goto()` | `(ctx, url, ..., wait = "auto")` | confirmed |
| `pz_nav_reload()` | `(ctx, ..., wait = "auto")` | confirmed |
| `pz_nav_back()` | `(ctx, ...)` | confirmed |
| `pz_nav_forward()` | `(ctx, ...)` | confirmed |
| `pz_device()` | `(ctx, ..., width, height, scale, mobile, zoom, zoom_method, color_scheme, reduced_motion, locale, timezone)` | confirmed |

Arguments: `shiny_options` and `wait = "auto"` are confirmed.

### Specs and scoping

| Function | Signature | Name |
|---|---|---|
| `pz_loc()` | `(css, ..., has_text = NULL, which = NULL, within = NULL)` → spec | confirmed |
| `pz_find()` | `(ctx, target, ..., from_root = FALSE)` | confirmed |
| `pz_find_first()` | `(ctx, target = NULL, ..., from_root = FALSE)` | confirmed |
| `pz_find_last()` | `(ctx, target = NULL, ..., from_root = FALSE)` | confirmed |
| `pz_find_nth()` | `(ctx, n, target = NULL, ..., from_root = FALSE)` | confirmed |
| `pz_find_pop()` | `(ctx)` | confirmed |
| `pz_find_reset()` | `(ctx)` | confirmed |

Arguments: `target` and `from_root` are confirmed. `pz_find_nth()` takes `n` as its main input, with `target` right after it, before the dots (approved revision).

### Actions

| Function | Signature | Name |
|---|---|---|
| `pz_click()` | `(ctx, target = NULL, ...)` | confirmed |
| `pz_hover()` | `(ctx, target = NULL, ...)` | confirmed |
| `pz_type()` | `(ctx, text, ..., target = NULL)` | confirmed |
| `pz_press()` | `(ctx, key, ...)` | confirmed |
| `pz_focus()` | `(ctx, target = NULL, ...)` | confirmed |
| `pz_blur()` | `(ctx, ...)` | confirmed |
| `pz_scroll()` | `(ctx, target = NULL, ..., by = NULL, to = NULL, duration = NULL)` | confirmed |
| `pz_drag()` | `(ctx, target, to, ..., by = NULL)` | confirmed |
| `pz_select_text()` | `(ctx, text, ..., target = NULL)` | confirmed |
| `pz_set_value()` | `(ctx, value, ..., target = NULL)` | confirmed |
| `pz_set_shiny_input()` | `(ctx, id, value, ..., wait = TRUE)` | confirmed |
| `pz_set_files()` | `(ctx, files, ..., target = NULL)` | confirmed |
| `pz_screenshot()` | `(ctx, path, ..., target = NULL, frame = NULL)` | confirmed |

Arguments: the `pz_press()` key syntax is confirmed. Discussed additions: a `Mod` modifier and `show_keys = NULL`.

Skipped: select option, check/uncheck, clear (covered by `pz_set_value()` / `pz_set_shiny_input()`).

### Expectations

| Function | Signature | Name |
|---|---|---|
| `pz_expect_exists()` | `(ctx, target = NULL, ..., not = FALSE, timeout = NULL)` | confirmed |
| `pz_expect_count()` | `(ctx, n = NULL, target = NULL, ..., min = NULL, max = NULL, not = FALSE, timeout = NULL)` | confirmed |
| `pz_expect_visible()` | `(ctx, target = NULL, ..., not = FALSE, timeout = NULL)` | confirmed |
| `pz_expect_hidden()` | `(ctx, target = NULL, ..., not = FALSE, timeout = NULL)` | confirmed |
| `pz_expect_enabled()` | same shape | confirmed |
| `pz_expect_focused()` | same shape | confirmed |
| `pz_expect_checked()` | same shape | confirmed |
| `pz_expect_in_viewport()` | same shape | confirmed |
| `pz_expect_text()` | `(ctx, text, target = NULL, ..., match = "contains", not = FALSE, timeout = NULL)` | confirmed |
| `pz_expect_value()` | `(ctx, value, target = NULL, ..., match = "contains", not = FALSE, timeout = NULL)` | confirmed |
| `pz_expect_attr()` | `(ctx, .target = NULL, ..., .match = c("exact", "contains", "regex"), .not = FALSE, .timeout = NULL)` | confirmed |
| `pz_expect_class()` | `(ctx, class, target = NULL, ..., not = FALSE, timeout = NULL)` | confirmed |
| `pz_expect_style()` | `(ctx, .target = NULL, ..., .not = FALSE, .timeout = NULL, .normalize = TRUE)` | confirmed |
| `pz_expect_js()` | `(ctx, expr, target = NULL, ..., not = FALSE, timeout = NULL)` | confirmed |
| `pz_expect_url()` | `(ctx, url, ..., match = "contains", not = FALSE, timeout = NULL)` | confirmed |
| `pz_expect_title()` | `(ctx, title, ..., match = "contains", not = FALSE, timeout = NULL)` | confirmed |

Arguments: the `pz_expect_` prefix, `not` and `match` are confirmed for the single-value checks. `pz_expect_attr()` and `pz_expect_style()` take their checks in the dots, so their controls are dot-prefixed (`.target`, `.match`, `.not`, `.timeout`, `.normalize` as applicable). `pz_expect_attr()` defaults to `.match = "exact"`; the other text-like expectations default to `"contains"`. In the remaining target-bearing expectations, `target` sits after the main input, before the dots.

### Waits

| Function | Signature | Name |
|---|---|---|
| `pz_wait()` | `(ctx, seconds)` | confirmed |
| `pz_wait_for_stable()` | `(ctx, ..., target = NULL, prop = "textContent", for_ms = 500, timeout = NULL)` | confirmed |
| `pz_wait_for_js()` | `(ctx, expr, ..., timeout = NULL)` | confirmed |
| `pz_wait_for_shiny_idle()` | `(ctx, ..., timeout = NULL)` | confirmed |
| `pz_wait_for_navigation()` | `(ctx, ..., wait = "auto", timeout = NULL)` | confirmed |

### Getters (end the chain)

| Function | Signature | Name |
|---|---|---|
| `pz_get_count()` | `(ctx, target = NULL, ...)` → integer | confirmed |
| `pz_get_text()` | `(ctx, target = NULL, ..., raw = FALSE)` → character | confirmed |
| `pz_get_value()` | `(ctx, target = NULL, ...)` → character | confirmed |
| `pz_get_attr()` | `(ctx, name, target = NULL, ...)` → character | confirmed |
| `pz_get_style()` | `(ctx, props = NULL, target = NULL, ...)` → tibble | confirmed |
| `pz_get_rect()` | `(ctx, target = NULL, ...)` → tibble | confirmed |
| `pz_get_elements()` | `(ctx, target = NULL, ...)` → tibble | confirmed |
| `pz_get_html()` | `(ctx, target = NULL, ...)` → character | confirmed |
| `pz_get_url()` | `(ctx)` → character | confirmed |
| `pz_get_title()` | `(ctx)` → character | confirmed |

Arguments: the `pz_get_` prefix is confirmed. `target` sits after the main input, before the dots (approved revision).

### Recording

| Function | Signature | Name |
|---|---|---|
| `pz_record_start()` | `(ctx, path, ..., method = c("poll", "screencast"), frame = NULL, fps = 15, scale = NULL, hold = c(0.5, 1), keep_frames = FALSE, captions = c("burn", "vtt", "both"), format = c("auto", "mp4", "webm", "gif"))` | confirmed |
| `pz_record_stop()` | `(ctx)` | confirmed |
| `pz_record_pause()` | `(ctx)` | confirmed |
| `pz_record_resume()` | `(ctx)` | confirmed |
| `pz_record_hold()` | `(ctx, seconds)` | confirmed |
| `pz_record()` | `(ctx, path, code, ...)` | confirmed |
| `pz_frame()` | `(target = NULL, ..., ratio = NULL, pad = 0, offset = c(0, 0), anchor = "center", bounds = NULL, when = c("stop", "start"))` → spec | confirmed |
| `pz_stage_frame()` | `(ctx, ..., ratio, pad, offset, anchor, bounds)` | confirmed |

### Cursor and staging

| Function | Signature | Name |
|---|---|---|
| `pz_stage()` | `(ctx, ..., cursor = NULL, cursor_speed = NULL, cursor_scale = NULL, enter = NULL, typing = NULL, typing_speed = NULL, pause = NULL, camera_follow = NULL, show_keys = NULL)` | confirmed |
| `pz_stage_annotate()` | `(ctx, ..., color = NULL, font_family = NULL, font_size = NULL)` | confirmed |
| `pz_cursor_show()` | `(ctx, target = NULL, ..., from = NULL, icon = NULL)` | confirmed |
| `pz_cursor_hide()` | `(ctx, ...)` | confirmed |
| `pz_cursor_move()` | `(ctx, target, ..., duration = NULL, icon = NULL, offset = NULL)` | confirmed |
| `pz_cursor_leave()` | `(ctx, side = "right", icon = NULL)` | confirmed |

Annotation style defaults are set separately with `pz_stage_annotate(ctx, ..., color = NULL, font_family = NULL, font_size = NULL)`: the defaults are `"#e11d48"`, `"sans-serif"` and 14 CSS pixels. They persist on the page and apply to new annotations in stills and recordings.

### Camera and annotations

Implemented (kata `1a3m`).

| Function | Signature | Name |
|---|---|---|
| `pz_camera()` | `(ctx, target = NULL, ..., zoom = NULL, pad = NULL, duration = NULL, target_box = c("element", "annotated"), wait = FALSE)` | confirmed |
| `pz_camera_reset()` | `(ctx, ..., wait = FALSE)` | confirmed |
| `pz_annotate()` | `(ctx, target = NULL, ..., type = c("box", "circle", "underline", "highlight"), label = NULL, pad = NULL, reveal = NULL, id = NULL, color = NULL, font_family = NULL, font_size = NULL)` | confirmed |
| `pz_annotate_callout()` | `(ctx, text, ..., target = NULL, side = NULL, arrow = TRUE, label = NULL, reveal = NULL, id = NULL, color = NULL, font_family = NULL, font_size = NULL)` | confirmed |
| `pz_annotate_spotlight()` | `(ctx, target = NULL, ..., pad = NULL, dim = NULL, reveal = NULL)` | confirmed |
| `pz_annotate_redact()` | `(ctx, target = NULL, ..., method = c("fill", "blur"), pad = NULL, id = NULL, color = NULL)` | confirmed |
| `pz_annotate_caption()` | `(ctx, text, ..., side = "bottom", color = NULL, font_family = NULL, font_size = NULL)` | confirmed |
| `pz_annotate_clear()` | `(ctx, id = NULL, ...)` | confirmed |

Arguments added to existing functions: `pz_record_start(captions = c("burn", "vtt", "both"))`, `pz_frame(target_box = c("element", "annotated"))` and `pz_stage_frame(target_box =)`, `pz_press(show_keys = NULL)`, and `pz_stage(camera_follow = NULL, show_keys = NULL)`. Annotation style defaults are set with `pz_stage_annotate()`.

### Escape hatches and debugging

| Function | Signature | Name |
|---|---|---|
| `pz_chromote()` | `(ctx)` → `ChromoteSession` | confirmed |
| `pz_js()` | `(ctx, expr, ..., await = TRUE, timeout = NULL)` → value | confirmed |
| `pz_inspect()` | `(ctx, target = NULL, ..., show = c("auto", "screenshot", "browser", "none"))` | confirmed |
| `page$view()` | method: opens the live browser | confirmed |

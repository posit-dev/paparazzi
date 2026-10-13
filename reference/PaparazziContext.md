# Paparazzi contexts and pages

A **context** is the first argument of `pz_*()` functions, enabling `|>`
chains. `pz_find*()` return contexts visibly; chainable actions return
them invisibly, except in a recording chain: the context returned by
[`pz_record_start()`](https://posit-dev.github.io/paparazzi/reference/pz_record_start.md)
(and contexts derived from it) is returned visibly while its recording
runs, and printing it stops the recording. A context is either the root
(a `PaparazziPage`) or a scoped context created by `pz_find*()`: a
context holding an immutable stack of pinned element sets. The stack is
never mutated in place – `pz_find*()` derive a new context sharing the
parent's pinned sets – and
[`pz_find_pop()`](https://posit-dev.github.io/paparazzi/reference/pz_find_pop.md)/[`pz_find_reset()`](https://posit-dev.github.io/paparazzi/reference/pz_find_reset.md)
unwind it the same way. Staged settings
([`pz_stage()`](https://posit-dev.github.io/paparazzi/reference/pz_stage.md),
[`pz_stage_annotate()`](https://posit-dev.github.io/paparazzi/reference/pz_stage_annotate.md),
[`pz_stage_frame()`](https://posit-dev.github.io/paparazzi/reference/pz_stage_frame.md))
are carried by the context and flow through derivation the same way;
assigning the staged context (`page <- page |> pz_stage(...)`) is what
makes them page-wide. Session-level state – the Chromote session, the
default timeout, the recorder, and the page's session-bound state
(staged fonts, the cursor overlay, captions) – lives on the page.

## Public fields

- `page`:

  The root `PaparazziPage` this context belongs to.

- `scope`:

  Stack of pinned element sets; empty for the root context.

- `recording`:

  The recorder a recording chain belongs to, or `NULL` (internal).

- `staging`:

  Staged settings carried by this context: a list of `overrides` (a
  named list) and `frame` (a frame spec or `NULL`); `NULL` until a
  `pz_stage*()` call derives a context (internal).

- `inspect_image`:

  Pending annotated screenshot path for knitr, or `NULL` (internal).

## Active bindings

- `session`:

  The root page's underlying `ChromoteSession` (read-only).

- `child_loop`:

  The root page's chromote child loop (read-only).

- `default_timeout`:

  The root page's default timeout in seconds.

## Methods

### Public methods

- [`PaparazziContext$new()`](#method-PaparazziContext-initialize)

- [`PaparazziContext$print()`](#method-PaparazziContext-print)

- [`PaparazziContext$close()`](#method-PaparazziContext-close)

- [`PaparazziContext$view()`](#method-PaparazziContext-view)

- [`PaparazziContext$is_closed()`](#method-PaparazziContext-is_closed)

- [`PaparazziContext$clone()`](#method-PaparazziContext-clone)

------------------------------------------------------------------------

### `PaparazziContext$new()`

Create a context attached to a page.

#### Usage

    PaparazziContext$new(page, scope = list(), recording = NULL, staging = NULL)

#### Arguments

- `page`:

  A `PaparazziPage`.

- `scope`:

  Stack of pinned element sets; defaults to empty (the root context).

- `recording`:

  The recorder of the recording chain, if any.

- `staging`:

  Staged settings for this context; defaults to none.

------------------------------------------------------------------------

### `PaparazziContext$print()`

Print the page summary (URL, device, scope stack, recording state)
without the target section or visuals; see
[`pz_inspect()`](https://posit-dev.github.io/paparazzi/reference/pz_inspect.md).
A recording chain whose recording is still running stops it instead and,
interactively, shows the video.

#### Usage

    PaparazziContext$print(...)

#### Arguments

- `...`:

  Unused; included for compatibility with the
  [`print()`](https://rdrr.io/r/base/print.html) generic.

------------------------------------------------------------------------

### `PaparazziContext$close()`

Close the root page's browser tab (its chromote session). Idempotent.
Delegates to the root page; a `PaparazziPage`'s own
[`close()`](https://rdrr.io/r/base/connections.html) runs for pages.

#### Usage

    PaparazziContext$close()

------------------------------------------------------------------------

### `PaparazziContext$view()`

Open the live browser view (DevTools) of the root page.

#### Usage

    PaparazziContext$view()

------------------------------------------------------------------------

### `PaparazziContext$is_closed()`

Has the root page been closed?

#### Usage

    PaparazziContext$is_closed()

------------------------------------------------------------------------

### `PaparazziContext$clone()`

The objects of this class are cloneable with this method.

#### Usage

    PaparazziContext$clone(deep = FALSE)

#### Arguments

- `deep`:

  Whether to make a deep clone.

## Super class

`PaparazziContext` -\> `PaparazziPage`

## Active bindings

- `session`:

  The underlying `ChromoteSession` (read-only).

- `child_loop`:

  chromote's private `later` event loop (read-only). Waits must pump
  this loop so scheduled timers keep firing.

- `default_timeout`:

  Session default timeout in seconds.

- `object_group`:

  The CDP object group holding every remote object a scope pinned
  (read-only; internal).

- `session_state`:

  Session-bound page state: the fonts registry, the cursor env,
  captions, and the annotation init id (internal).

- `recorder`:

  Current recorder state, or `NULL` (internal).

- `pre_action_loader`:

  Main-frame loader ID before the last user action, or `NULL`
  (internal).

- `app`:

  The owned or shared app handle, or `NULL` (read-only; internal).

## Methods

### Public methods

- [`PaparazziPage$new()`](#method-PaparazziPage-initialize)

- [`PaparazziPage$close()`](#method-PaparazziPage-close)

- [`PaparazziPage$release_object_group()`](#method-PaparazziPage-release_object_group)

- [`PaparazziPage$view()`](#method-PaparazziPage-view)

- [`PaparazziPage$is_closed()`](#method-PaparazziPage-is_closed)

- [`PaparazziPage$print()`](#method-PaparazziPage-print)

- [`PaparazziPage$clone()`](#method-PaparazziPage-clone)

------------------------------------------------------------------------

### `PaparazziPage$new()`

Wrap a `ChromoteSession` as a paparazzi page.

#### Usage

    PaparazziPage$new(session, timeout = 10, owned_app = NULL, shared_app = NULL)

#### Arguments

- `session`:

  A
  [`chromote::ChromoteSession`](https://rstudio.github.io/chromote/reference/ChromoteSession.html).

- `timeout`:

  Default timeout in seconds for this session.

- `owned_app`:

  App started by this page, if any.

- `shared_app`:

  Caller-owned app handle kept alive while the page lives.

------------------------------------------------------------------------

### `PaparazziPage$close()`

Close the page's browser tab (its chromote session). Idempotent.

#### Usage

    PaparazziPage$close()

------------------------------------------------------------------------

### `PaparazziPage$release_object_group()`

Release every remote object a scope pinned. Internal: runs on close and
before navigation resets scopes.

#### Usage

    PaparazziPage$release_object_group()

------------------------------------------------------------------------

### `PaparazziPage$view()`

Open the live browser view (DevTools).

#### Usage

    PaparazziPage$view()

------------------------------------------------------------------------

### `PaparazziPage$is_closed()`

Has the page been closed?

#### Usage

    PaparazziPage$is_closed()

------------------------------------------------------------------------

### `PaparazziPage$print()`

Print the page summary (URL, device, scope stack, recording state)
without the target section or visuals; see
[`pz_inspect()`](https://posit-dev.github.io/paparazzi/reference/pz_inspect.md).
A closed page prints one line.

#### Usage

    PaparazziPage$print(...)

#### Arguments

- `...`:

  Unused; included for compatibility with the
  [`print()`](https://rdrr.io/r/base/print.html) generic.

------------------------------------------------------------------------

### `PaparazziPage$clone()`

The objects of this class are cloneable with this method.

#### Usage

    PaparazziPage$clone(deep = FALSE)

#### Arguments

- `deep`:

  Whether to make a deep clone.

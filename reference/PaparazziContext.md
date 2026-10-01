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
unwind it the same way. Session-level state – the Chromote session,
default timeout, staging settings, recorder state – lives on the page.

## Public fields

- `page`:

  The root `PaparazziPage` this context belongs to.

- `scope`:

  Stack of pinned element sets; empty for the root context.

- `recording`:

  The recorder a recording chain belongs to, or `NULL` (internal).

## Methods

### Public methods

- [`PaparazziContext$new()`](#method-PaparazziContext-initialize)

- [`PaparazziContext$print()`](#method-PaparazziContext-print)

- [`PaparazziContext$clone()`](#method-PaparazziContext-clone)

------------------------------------------------------------------------

### `PaparazziContext$new()`

Create a context attached to a page.

#### Usage

    PaparazziContext$new(page, scope = list(), recording = NULL)

#### Arguments

- `page`:

  A `PaparazziPage`.

- `scope`:

  Stack of pinned element sets; defaults to empty (the root context).

- `recording`:

  The recorder of the recording chain, if any.

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

- `staging`:

  Staged page settings (internal).

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

# Phase note: pz_find*() scoping stack (kata paparazzi#whdj)

Mechanism decisions for the scoping task, resolved before code.
Durable requirements live in `.agents/SPEC.md` (sections "Scoping",
"Chaining", "Argument order", "Multiple matches"; the `element`
list-column in "Getters"; the API index "Specs and scoping"); this note
holds mechanism-level choices and session handoffs for this phase only.
Builds on the resolution engine
(`.agents/phases/element-specs-resolution.md`), the getters
(`.agents/phases/getters.md`), and the dormant scoped branches already
written into `action_elements()` (`.agents/phases/actions.md`).

## Decisions

- **The stack on the context (immutable push/pop).** `PaparazziContext`
  already reserves `scope = list()`. Extend `initialize(page, scope =
  list())` and never touch an existing object: pushing is
  `PaparazziContext$new(ctx$page, scope = c(ctx$scope, list(pinned)))`
  via an internal `push_scope(ctx, pinned)`; `pz_find_pop()` returns
  `PaparazziContext$new(ctx$page, utils::head(ctx$scope, -1))`;
  `pz_find_reset()` returns a fresh context with an empty scope (the
  page itself when already at root). The stack list shares its pinned
  elements across derived contexts; that is safe because the wrapper is
  immutable and never released by consumers. Popping does NOT release
  the popped set -- a sibling context may still hold it (immutability
  promise); cleanup is the finalizer (below) plus group release. Pop and
  reset at the root are no-ops returning `ctx`. `pz_find*()` return the
  new context invisibly (chain convention), and the `PaparazziPage`
  object is never mutated.
- **The pinned-set wrapper.** S3 `paparazzi_pinned`, a subclass of
  `paparazzi_elements` with the same fields (`page`, `object_id`,
  `count`, `description`) plus `locs` (the `as_loc_list()` list it was
  pinned from, kept for formatting narrowed scopes), class
  `c("paparazzi_pinned", "paparazzi_elements")`. Subclassing means
  `els_call()`/`els_values()`/`el_rects()`/`el_scroll_into_view()`
  accept pinned sets unchanged, and `action_elements()`'s dormant
  branch (top of stack as the element set, `pinned = TRUE`, never
  released) goes live as written. Pinnedness is detectable via
  `inherits(els, "paparazzi_pinned")`; the `list(els, pinned)` return
  shape stays. A best-effort `reg.finalizer()` releases the objectId
  when the wrapper becomes unreachable (a wrapper no context references
  can never be used again, so release is safe); it is try-silent, not
  load-bearing -- group release is authoritative.
- **Object group.** One group per page: private field `object_group_`
  on `PaparazziPage`, initialized to the constant `"paparazzi_scopes"`
  (a field, not a literal at call sites, so per-page uniqueness could
  be added without touching callers; groups are per session, so a
  constant can't collide across pages), with an active binding. Rule:
  every CDP call that CREATES a remote object meant to outlive the call
  passes `objectGroup`; transient lazy resolutions pass none and keep
  their individual `releaseObject` lifecycle, unchanged. This pins the
  find-time `Runtime$evaluate`, the narrow-slice `callFunctionOn`, and
  the per-match `callFunctionOn` calls.
- **Eager pin at find time.** Reuse the existing engine rather than a
  variant: `loc_resolve_once()` gains `object_group = NULL` (passed to
  `Runtime$evaluate`), threaded through `loc_resolve()`. `pz_find()`
  calls `loc_resolve(ctx, target, multiple = "all", object_group =
  ctx$page$object_group, from_root = from_root)` -- auto-wait for >= 1
  match and the timeout are the existing behavior (session default;
  the signatures carry no `timeout`), and the result is wrapped with
  `new_pinned()` and pushed. Multi-match scopes pin the whole set; no
  single-match error at find time.
- **Lazy resolution inside a scope: the roots-as-argument seam.**
  `loc_resolver_js` becomes one function TEXT -- `function() { const
  specs = <json>; ... }` -- whose `this` is the roots array (inside
  `resolveSpec`, `roots = spec.within ? resolveSpec(spec.within) : (this
  && this.length ? this : [document])`; `within` keeps resolving inside
  the same invocation). `target_resolver_expr()` returns
  `list(fn = <text>, description = ...)`; the `target = NULL` ->
  `[document.body]` special case stays and is only reachable at the
  root. `loc_resolve_once(ctx, fn, description, call, root = NULL)`:
  with `root = NULL` it evaluates `paste0("(", fn, ").call([document])")`
  via `Runtime$evaluate` (same behavior as today's root path, different
  expression text); with a pinned
  set it runs `Runtime$callFunctionOn(fn, objectId = root$object_id,
  returnByValue = FALSE)` so `this` is the pinned array. The count read
  after either path is unchanged. The scoped result is a transient
  handle (no objectGroup) released by its caller, exactly as today.
- **One use, one check.** New internal `scope_root(ctx, call)`: NULL at
  the root context; otherwise the pinned set at the top of the stack
  AFTER `pinned_assert_connected()` (below). It is the single seam every
  consumer reads once per `pz_*()` call -- "before each use" means per
  operation that touches the scope, not per CDP command (an action's
  scroll-rect-dispatch sequence is one use). `loc_resolve()` gains
  `from_root = FALSE`, which makes `scope_root()` return NULL so
  `pz_find(from_root = TRUE)` resolves from `document` but still pushes
  on top of the stack (pop returns to the previous scope, per the
  SPEC). `expect_impl()` resolves the root once before its retry loop
  and passes it to every per-attempt `loc_resolve_once()` -- each
  attempt re-queries lazily inside the pinned scope (re-renders within a
  scope are fine); a mid-retry detach surfaces via the probe's error
  mapping below. `action_elements()`, `get_impl()`, and `pz_get_count()`
  call `scope_root()` once.
- **target = NULL on a scoped context.** Per the SPEC table, NULL means
  the current scope: the pinned set itself, no resolution and no
  re-query (document.body is the root-only meaning; keep the existing
  provisional rule there). Single-element actions enforce it via the
  existing `check_scope_single()`; getters return one row per pinned
  match; `pz_get_count()` on a pinned scope returns its count
  immediately. Consumers use the set as-is with `pinned = TRUE`, so
  nothing releases it.
- **The detach check and its error.** `pinned_assert_connected(pinned,
  call)`: one `callFunctionOn` on the pinned array,
  `function() { return this.every((el) => el && el.isConnected); }`,
  `returnByValue = TRUE`. Any detached element invalidates the set
  (pinned sets promise their whole set). FALSE aborts with class
  `"paparazzi_error_detached"`, cli message verbatim per the SPEC:

  ```r
  cli::cli_abort(
    c(
      "Scope element is no longer in the page (it was probably re-rendered).",
      "Scope: {pinned$description}",
      i = "Call {.fn pz_find} again after the update, or target it with {.fn pz_loc}."
    ),
    class = "paparazzi_error_detached",
    call = call
  )
  ```

  Nothing anywhere silently re-queries a detached scope. The probe also
  maps a CDP "could not find object with the specified id" failure (a
  context that outlived a group release) to the same class, so
  post-navigation / post-close contexts raise the classed error rather
  than a raw chromote one. `check_context()` still fires first for a
  closed page, as today.
- **The pz_find family.** Signatures exactly per the SPEC's API index.
  `pz_find(ctx, target, ..., from_root = FALSE)`: `target` is the main
  input and required -- NULL is a classed error (there is nothing to
  find; narrowing a current scope is the `_first`/`_last`/`_nth` forms'
  job). Promote with `as_loc_list()`. `pz_find_first()/last()`:
  `(ctx, target = NULL, ..., from_root = FALSE)`. `pz_find_nth()`:
  `(ctx, n, ..., target = NULL, from_root = FALSE)` -- `n` is the main
  input so `target` moves after the dots (SPEC argument rule; the SPEC
  flags this signature as unreviewed, follow it and see flags below).
  `n` via `check_number_whole(min = 1)`; `"first"`/`"last"` are not
  accepted (use the wrappers). With `target`: apply `which` to the
  promoted loc; a spec that already carries `which` is a classed
  `paparazzi_error_input` conflict (never silently overridden). With
  `target = NULL`: NARROW -- slice the pinned set at the top eagerly,
  no re-query and no auto-wait (the set was fixed at pin time, so
  waiting is pointless): one `callFunctionOn` with `objectGroup`, e.g.
  `function() { return this.slice(0, 1); }` /
  `function() { return [this[this.length - 1]].filter((el) => el != null); }`
  / `function() { return [this[n - 1]].filter((el) => el != null); }`,
  each returning a fresh pinned array; push it. Narrowing at the root
  (nothing to narrow) and `from_root = TRUE` with `target = NULL` are
  classed errors. An out-of-range narrowing `n` is an immediate classed
  `"paparazzi_error_scope"` error -- "The current scope has {count}
  elements; there is no match {n}." -- while an out-of-range `which` on
  a target keeps lazy auto-waiting (a3vj's which semantics). Narrowed
  descriptions come from the wrapper's `locs`: a single loc gets
  `which` applied and re-formatted with `format_loc()` (matching the
  SPEC's detached-error example exactly); a union target can't take a
  `which`, so its narrowed description is the parent description plus
  ` (match: {first|last|n})`. `pz_find_pop()`/`pz_find_reset()` unwind
  without touching pinned sets (no release; see the stack decision).
  Validation: `ctx` via `check_context()`, dots empty, `from_root` via
  `check_bool()`.
- **Release: pz_close() and the navigation hook seam.**
  `PaparazziPage$close()` gains a first step: `release_object_group()`
  -- one `Runtime$releaseObjectGroup(objectGroup = ...)` (try-silent),
  then the existing `chromote$close()`. The method is public, internal
  by convention (no roxygen), and is the seam the navigation task calls
  from `pz_wait_for_navigation()` before resetting scope to root; wire
  the hook now, do not add navigation detection here. Contexts that
  survive a release hit the probe's error mapping and raise
  `paparazzi_error_detached`.
- **The `element` list-column.** Swap the stub inside
  `new_get_tibble()` (the one-function seam the getters phase left).
  While the getter's transient handle is still live (inside
  `get_impl()`'s `read`, before the on-exit release), pin one
  single-element set per match: `callFunctionOn` on the matched array
  with `objectGroup`, `function() { return [this[i - 1]]; }`, and wrap
  each result objectId as `new_pinned(page, ..., count = 1L, locs =
  <the getter's locs with which = i>)`. Each column entry is a context:
  `push_scope(ctx, pinned_i)` -- the getter context's whole stack plus
  the per-match set. That costs one extra CDP round trip per match per
  getter call; accepted (the alternative -- contexts sharing the
  getter's array handle -- breaks the uniform "one array per scope"
  wrapper contract, rejected). The transient handle is still released
  on exit, unchanged. Descriptions reuse `format_loc()` on the stored
  locs with `which = i` (single loc) or the match-suffix form (union),
  so a later detach names the row. Getter docs stop saying "reserved/
  not yet populated" (`pz_get_rect()`, `pz_get_elements()`; style
  joins when its task lands).
- **pillar machinery.** pillar is NOT in Imports (tibble is, and it
  pulls pillar transitively, so pillar is always installed -- but
  S3method registration against pillar generics needs it declared).
  Add pillar to Imports; keep vctrs out (contexts are R6 objects in a
  plain list column; no vctrs methods needed). Register
  `type_sum.PaparazziContext() -> "pz_ctx"` (pillar renders `<pz_ctx>`)
  and `pillar_shaft.PaparazziContext()` showing the TOP scope's
  description compactly (pillar truncates; root contexts show "root",
  defensively -- they never appear in the column). Whole-context
  printing is a `print` method on `PaparazziContext` (R6): a
  `<PaparazziContext>` header plus one line of space-joined stack
  descriptions; `PaparazziPage`'s existing print overrides it for
  pages, unchanged.
- **File layout.** `R/scope.R`: the six `pz_find*()` exports plus
  `scope_root()`, `push_scope()`, `new_pinned()`,
  `pinned_assert_connected()`, the slice JS, and
  `release_object_group()`. `R/context.R`: `initialize(scope)`, the
  print method, `object_group_` + active binding + the release method.
  `R/resolve.R`: the resolver-function-text shape, `root`/`object_group`
  parameters. `R/actions.R`: the dormant branches go live;
  `action_elements()` reads `scope_root()` and resolves explicit
  targets through the in-scope path; no dispatch changes elsewhere.
  `R/get.R`/`R/expect.R`: thread the root per use; the tibble factory
  swap. Tests: new `tests/testthat/test-scope.R` (stack immutability,
  pin/narrow/detach, in-scope lazy resolution, pop/reset, release on
  close), plus scoped-context cases appended to test-actions/test-get/
  test-expect where behavior shifts. New fixture
  `tests/testthat/fixtures/scopes.html` (one fixture per task; don't
  disturb elements.html/geometry.html's pinned counts) with nested
  containers for find chains, repeated classes for narrowing, and
  content the tests can drop via `pz_js()` to force detaches;
  `local_scopes_page()` appended to `helper-page.R`.

## SPEC flags

Nothing in the SPEC is unimplementable as written -- every mechanism
(`Runtime.evaluate(objectGroup =)`, `Runtime.callFunctionOn`,
`Runtime.releaseObjectGroup`, `isConnected`) exists in chromote's API.
Four things to keep visible:

- `pz_find_nth()`'s `n`-before-dots order is explicitly unreviewed in
  the SPEC; this note follows it. If it flips, only the signature
  moves -- the mechanics don't.
- The detach message says "Scope element" even for multi-element sets;
  kept verbatim per the SPEC. Any-detached invalidates the whole pinned
  set (an element can't be half-pinned).
- `pz_get_count()` is documented as returning immediately with 0 as a
  valid answer, but on a detached scope it now raises
  `paparazzi_error_detached` instead of 0. Eager pinning promises a
  live set, so the error wins; the getter's doc needs the caveat.
- Pop/reset at the root are SPEC-silent; treated as no-ops returning
  `ctx` (provisional).

## Handoff log

(newest first; three lines per session: landed / next / provisional)

- 2026-09-24 (close-out): landed the scoping task end to end on this
  branch (72d42d8..): the pz_find*() stack (context scope stack, pinned
  wrapper, object group, detach probe, eager narrowing, release seams),
  scoped expectations (expect_impl() resolves the root once before its
  retry loop and threads it into every per-attempt loc_resolve_once();
  NULL on a scope is the pinned set itself), scoped getters
  (get_impl()/pz_get_count() probe once per call; NULL on a scope
  returns one row per pinned match, the count without a re-query;
  detached scopes raise paparazzi_error_detached through the getters,
  and pz_get_count()'s doc carries the 0-vs-error caveat), the element
  list-column (one pinned single-element set per match, one context
  per match via push_scope(), row-naming narrowed descriptions, union
  match-suffix form), and the pillar machinery (pillar in Imports;
  type_sum -> "pz_ctx" via @importFrom + @export so roxygen emits
  S3method, pillar_shaft shows the top scope, "root" defensively).
  786 tests green. Next: the navigation task (pz_wait_for_navigation()
  calls release_object_group() -- the seam is wired -- then resets scope
  to root); pz_get_style() joins the element column when its task lands.
  Provisional: resolved as designed -- pop/reset at the root are
  no-ops; per-match pinning costs n extra CDP calls per tibble getter;
  the which-conflict class is paparazzi_error_input; an out-of-range
  narrowing nth errors while a target which keeps waiting;
  pz_get_count on a detached scope errors instead of returning 0.
  Carried forward, unchanged: pz_find_nth()'s n-before-dots signature
  stays SPEC-unreviewed; the detach message stays verbatim ("Scope
  element" even for multi-element sets); root target = NULL keeps the
  provisional document.body meaning (the element column describes it
  as `body` (which: 1)); pz_get_text() at the root still includes
  inline <script>/<style> text.

- 2026-09-24 (design): landed this phase note; baseline is 737592b
  (green per the prior phase close-outs). Decisions above resolved
  before code. Next (implementer): fixture scopes.html + R/scope.R +
  R/context.R/resolve.R/get.R/expect.R seams, then test-scope.R,
  roborev, close.
  Provisional: pop/reset at root are no-ops; per-match pinning costs n
  extra CDP calls per tibble getter; the `which`-conflict error class
  is `paparazzi_error_input`; narrowing an out-of-range nth errors
  while a target `which` out-of-range keeps waiting. Carried from
  getters.md, unchanged here: `pz_get_text()` at the root includes
  inline <script>/<style> text (scoping doesn't alter text reads).


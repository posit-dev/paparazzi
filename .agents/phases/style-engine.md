# Phase note: style engine (kata paparazzi#2rwr)

Mechanism decisions for the style task, resolved before code. Durable
requirements live in `.agents/SPEC.md` (section "Styles"); this note
holds mechanism-level choices and session handoffs for this phase only.
Builds on the expectation core (`expect_impl()` retry/failure format)
and the getters (`get_impl()`, `new_get_tibble()`'s `element` column).

## Decisions

- **Property names.** R side, both functions: `snake_case` ->
`kebab-case` via `_` -> `-`; names starting with `--` (custom
properties) pass through untouched. The normalized kebab name is the
canonical one and becomes the tibble column name in `pz_get_style()`
(so `props = "font_size"` yields a `` `font-size` `` column).
Duplicated names after normalization are an input error.
- **Shorthands.** R-side check on explicitly requested properties,
both functions: error listing the property and suggesting longhands
(margin -> `margin-top`, etc.). `props = NULL` in the getter returns
whatever the browser enumerates untouched: Chrome's computed-style
enumeration is longhand-only (verified: 477 properties, no
`margin`/`border`/`background`), so there is nothing to reject there.
- **Probe lifecycle.** Lazily created once per page, cached on the
`document` object (`document.__paparazzi_probe = {host, container,
probe}`), so a navigation destroys the cache naturally. The host is a
zero-size (`position:fixed; width:0; height:0; overflow:hidden`),
`visibility:hidden` div appended to `document.documentElement` with a
**closed** shadow root: `documentElement > host > shadowRoot >
container > probe`. `visibility:hidden` keeps the subtree laid out,
which percentages need (a `display:none` probe would return raw
percentages from `getComputedStyle()`); zero size + overflow hidden
means nothing ever paints, so screenshots/recordings are unaffected
either way. Being a `documentElement` child (not a body child), body
positional selectors, `:empty`, and body-rooted MutationObservers are
untouched; container and probe are reset and reused per pair, never
re-appended, so the retry loop can't accumulate nodes.
- **Single-JS-call protocol.** One `Runtime$callFunctionOn` on the
resolved element array does everything, synchronously: read each
target's computed value for every pair, classify each expected value,
copy the needed context onto the probe container, set the expected
value inline on the probe, read the probe's computed value. In: the
pairs as embedded JSON (`[{prop, value}]`) plus a `normalize` boolean.
Out: per element, per pair, `{actual, normalized, accepted}`. The JS
never persists between calls. Pairs are embedded in the function text
(the `pz_get_attr()` precedent) because chromote's `callFunctionOn`
rejects raw `arguments` (verified).
- **Normalization context classification** (in the JS, per pair,
priority order): `currentColor` (case-insensitive) -> color context
(target's computed `color`); any `%` -> size context (target's parent
computed `width`/`height`); `em`/`ex`/`ch` behind a digit or dot ->
font context (target's computed `font-size`/`font-family` copied onto
the container); everything else (rem, vw/vh, hex, color names,
keywords) -> no context. One CSS-truth adjustment to the SPEC table's
font row: when the property being normalized is `font-size` itself,
em/ex/ch resolve against the **parent's** font, so the copied context
comes from the parent (`font-size: 1.5em` on a child of a 20px parent
must normalize to 30px = its own computed size, which the target's own
30px context would never produce). For all other properties em is the
target's own font-size, per the table.
- **Invalid CSS.** Detected only with `normalize = TRUE` (only the
probe can detect it): after `probe.style.setProperty(prop, value)`,
`getPropertyValue(prop)` still empty means the browser rejected the
value or property name. The check aborts immediately with
`paparazzi_error_input` — no retry, since a rejected declaration never
becomes valid. Custom properties accept any token stream, so they are
never invalid this way. With `normalize = FALSE` an invalid value
simply never matches.
- **Comparison in R.** JS returns the strings; R compares
`style_compare(actual, expected)`: identical strings pass; otherwise
both sides matching `^-?[0-9]+(\.[0-9]+)?px$` compare numerically with
a 0.5px inclusive tolerance (subpixel noise); anything else is exact
string equality. The tolerance applies in both `normalize` modes —
it's about noise, not normalization. `not = TRUE` passes when at
least one (element, pair) comparison fails, and, like other content
checks, with zero matches (nothing matches, so it passes).
- **Observed value in failures.** `Last seen:` shows, per match, every
pair as `prop: actual` joined with `; `, matches joined with ` | `,
truncated via `expect_truncate()`. Headline: `Expected style to match
font-size: "1.5em", ...` / `Expected style not to match ...`.
- **Reuse, no new plumbing.** `pz_expect_style()` rides `expect_impl()`
(not folded into the check, per the core note); `pz_get_style()` rides
`get_impl()` and `new_get_tibble()` for the trailing `element` column,
one pinned context per match. Scoped contexts and `target = NULL`
therefore work through the existing paths with no new code.
- **File layout.** `R/style.R`, `tests/testthat/test-style.R`,
fixture `tests/testthat/fixtures/style.html`, helpers in
`tests/testthat/helper-style.R` (`local_style_page()`; the shared
`helper-page.R` untouched).

## Handoff log

(newest first; three lines per session: landed / next / provisional)

- 2026-09-24 (start): claimed 2rwr; baseline green at c8d889b (838
  tests). Probe mechanics verified in Chrome (percent/em/currentColor/
  hex all normalize; enumeration is longhand-only; `visibility:hidden`
  keeps percentage resolution alive). Decisions above resolved before
  code. Next: R/style.R + fixture + tests, document, roborev, close.
  Provisional: the font-size-em parent-context adjustment is the one
  deliberate refinement of the SPEC table's font row.

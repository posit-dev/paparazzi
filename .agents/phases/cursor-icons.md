# Phase note: cursor icon system (kata paparazzi#2vqb, df7d, k6vz, 9a2n, rny6)

Mechanism decisions for the cursor icon work under epic rvj4, built on
the cursor overlay in R/cursor.R and the decisions in
`cursor-staging.md` (overlay structure, glide math, pump driver,
navigation re-injection). Durable requirements live in `.agents/SPEC.md`
("Cursor and staging"); this note holds mechanism-level choices and
session handoffs for this phase only. zw7w (full CSS cursor
compatibility + url() research) is deferred to a later session by
garrick's decision on 2026-09-28; it stays blocked on 2vqb.

Order: rny6 (validation fix) -> df7d (pointer artwork) -> 2vqb (icon
API, the keystone) -> k6vz (glide-entry switching) -> 9a2n (landing
offset). Each lands as its own unit on main with one roborev review.

## Decisions (approved by garrick 2026-09-28 unless noted)

- **rny6:** `pz_cursor_move(duration)` rejects non-finite values via
  `check_number_decimal(..., allow_infinite = FALSE)` (classed input
  error). Scope is pz_cursor_move only; staged/scroll durations are
  clamped by construction and stay out of this fix.

- **df7d:** swap the `.pz-hand` SVG path for a conventional
  index-finger pointing hand. Internal class name and the arrow stay
  unchanged in this unit; 2vqb's restructure carries the new artwork
  forward. Hotspot stays on the fingertip; press scale-down,
  counter-zoom, and the 1.75x default are untouched.

- **2vqb, public API:** `icon` argument on `pz_cursor_show()`,
  `pz_cursor_move()`, and `pz_cursor_leave()` (not `pz_cursor_hide()`).
  Names are CSS cursor keywords. Omission/NULL = automatic for the
  call. An explicit icon holds through the call's landing and does not
  persist; the next automatic move starts with the icon left visible
  and resumes destination inference. First off-frame entry uses the
  "default" arrow unless the call sets an explicit icon.
  `pz_cursor_leave(icon =)` draws its icon for the exit and leaves it
  as the last visible icon. No `cursor_icon` setting on `pz_stage()`.
  SPEC amendments in this unit: the three signatures gain `icon`, and
  the "the cursor switches to a hand ... only extra in the first
  version" sentence is superseded by the icon inference rules.

- **2vqb, icon set (v1):** default, pointer, text, not-allowed,
  crosshair, grab, grabbing, and the resize families: ew-resize,
  ns-resize, nesw-resize, nwse-resize, row-resize, col-resize. Genuinely
  equivalent keywords share artwork (the two diagonals share one
  diagonal artwork mirrored; ew/ns/row/col share resize arrows
  rotated). The exact keyword-to-SVG map and per-icon hotspots are the
  implementer's decision, recorded here before code.

- **2vqb, overlay mechanics:** the current two-SVG display toggle
  becomes a stack of one inline SVG per icon inside `.pz-inner`, all
  positioned in the same box, selected by toggling `visibility` (NOT
  `display`) -- `visibility` is discretely animatable, which is what
  k6vz's switching rides on. Each icon declares its own hotspot
  (the artwork point that sits on the target coordinate), via a
  per-icon transform; `transform-origin` stays the press-scale anchor.
  Auto inference: walk up from `elementFromPoint()` to the first
  computed cursor other than auto; a supported keyword maps to
  artwork; a `url(...)` with a supported fallback keyword uses the
  fallback where practical; anything else falls back to "default".
  Inference happens at the actual landing point.

- **k6vz, switching mechanism (garrick-approved, no crossfade):**
  during a recorded glide the icon does NOT change at dispatch time.
  R computes the eased crossing time(s) by inverting
  cubic-bezier(0.42, 0, 0.58, 1) against the destination target's rect
  boundary along the glide line, and passes a schedule (percentages of
  the glide duration) in the state. The page builds one
  `@keyframes` rule per participating icon flipping `visibility`
  instantly (no opacity crossfade) at those percentages, with
  `animation-duration` equal to the glide duration. At most two flips:
  entering the intended destination, and -- only when a 9a2n offset
  lands outside the target -- the actual landing point. Elements
  merely crossed on the path are ignored. Not recording, or an
  explicit per-call icon: the landing icon applies immediately (no
  animation). No JS timers, no queues, no ordering flags.

- **9a2n, offset (garrick-approved):** `offset` argument on
  `pz_cursor_move()` only; `c(x, y)` viewport CSS pixels, positive
  right and down, added to the computed destination center; scalar
  recycled via the existing `check_offset()` convention; per-call, not
  persistent. The offset moves ONLY the drawn overlay -- no CDP pointer
  events are dispatched (pz_cursor_move never dispatched any; hover
  side effects stay out of the contract). Landings pushed outside the
  viewport are allowed off-frame, mirroring pz_cursor_leave positions;
  no clamping. The resting icon is inferred at the actual landing
  point per k6vz. SPEC amendment in this unit: `pz_cursor_move()`
  signature gains `offset`, with the sign convention documented.

## Handoff log

(newest first; three lines per session: landed / next / provisional)

- 2026-09-28 (rny6): landed finite-duration validation and regression coverage in `pz_cursor_move()`.
  Next: df7d pointer artwork, then 2vqb as the icon API keystone.
  Provisional: repo-wide style checks still flag unrelated existing files; the approved scope excludes them.
- 2026-09-28 (start): landed only this mechanism note; no package code
  yet. Next: rny6 + df7d in parallel worktrees, then 2vqb as the
  keystone, k6vz, 9a2n. Provisional: zw7w deferred to a later session;
  the visibility-vs-display choice in 2vqb is load-bearing for k6vz.

# Spotlight mask document-bottom cutoff (n2kc)

Signed off by orchestrator, 2026-09-29

Requirements: kata n2kc and its original repro in srcr; `.agents/SPEC.md` § Camera, annotations, and captions > Annotations. Keep implementation changes in `R/annotate.R` confined to `annotate_boot_js`; tests belong in `tests/testthat/test-annotate-spotlight.R`.

## Mechanism and decisions

- In the boot JS `sync()` spotlight branch, the SVG and its mask/backdrop/cover receive document-sized width and height. The `<mask>` uses `maskUnits="userSpaceOnUse"`, but has no `x` or `y`; SVG mask defaults are `-10%`, so its region starts above the origin and ends at 90% of its width/height. On the 816px tasks document, the mask therefore stops at y=734.4 and the scrim no longer affects pixels below it. Set the mask's `x` and `y` explicitly to `0` alongside its synchronized width/height, leaving the document/viewport geometry and cutouts unchanged.
- Audit of `annotate_boot_js`: the spotlight `<mask>` is the only SVG `<mask>`, `<clipPath>`, or `<filter>` created there. Redaction blur uses CSS `backdrop-filter: blur(32px)` on a positioned HTML box, not an SVG `<filter>` with the same default region; no other SVG region coordinates need adjustment.
- The discriminating regression test should use `pz_example("tasks")` at 720×800 with the spotlight over the upper form targets, take a raw viewport capture (as in the RTL pixel tests, rather than a target-framed screenshot), and compare an outside-cutout pixel near the viewport/document bottom against an unannotated baseline. A sample around `(20, 780)` lies below the expected 734.4px cutoff but within the visible viewport; with `dim = 0.75`, it should be approximately 25% of its baseline RGB. Before the fix this sample should remain at baseline brightness. Keep Chrome runs under `.agents/chrome-lock.sh` and record red/green FAIL/WARN counts.
- Do not edit the article. Its `spotlight` chunk (`vignettes/articles/annotations.Rmd`, chunk label `spotlight`) currently captures `target = "#new-task"` with `pz_frame(pad = 60)`, a form-area crop rather than the whole `main`. `git log -p` shows that crop was already present in the original article commit; no later article patch changed it. This is the pre-artifact workaround to widen after the fix.

## Stage 2 checks

First add and run the focused regression test red, then set mask x/y and rerun it green. Run `.agents/chrome-lock.sh btw pkg test -f 'annotate-spotlight' --reporter minimal`, plus `air format --check .`, `jarl check .`, and `git diff --check`. No documentation or article edits are in scope.

## Handoff

- Landed explicit zero `x`/`y` on the synchronized spotlight mask and a raw-viewport pixel regression for the visible document bottom.
- Next: orchestrator review and merge; the `spotlight` article chunk can be widened from `#new-task` to the full `main` crop after integration.
- Provisional decisions: none; leave the CSS `backdrop-filter` blur unchanged because boot JS defines no other SVG mask, clip path, or filter.

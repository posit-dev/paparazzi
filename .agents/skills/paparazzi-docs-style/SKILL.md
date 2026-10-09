---
name: paparazzi-docs-style
description: Writing style for paparazzi's prose documentation. Use when writing or revising README fragments (man/fragments/), pkgdown articles (vignettes/articles/), the bundled agent skill (inst/skills/paparazzi/), or explanatory roxygen prose. Covers who-does-what voice (paparazzi, you, the app's user), we vs you in walkthroughs, refine-not-reverse explanations, stating contracts, paragraph and section structure, numbered code walkthroughs, reference links, and explanatory screenshots and recordings.
---

# paparazzi docs style

How paparazzi's prose docs are written. Apply these when drafting or revising, and check a draft against them before handing it back.

## Who is doing what

1. **Every sentence has an actor.** Name who acts: paparazzi, "you" (the developer writing the script), or the person using the app being demoed. Be specific about the last one: "a person using the task tracker", not "a person".
2. **Active voice over passive.** "paparazzi calls this a spec", not "this is called a spec"; "paparazzi looks up targets", not "targets are looked up"; "paparazzi saves the video", not "the result is saved".
3. **"We" narrates, "you" acts.** In walkthrough articles, "we" narrates the worked example ("we'll build this video", "let's check"). Switch to "you" only when readers must do or have something themselves ("You'll need Chrome") or for general usage ("when you leave out the path"). README fragments describe general usage, so they use "you".
4. **Functions can be actors, but only for what they actually do.** "`pz_open()` opens the page" is fine. "`pz_loc()` finds the task" is wrong: you describe the element with `pz_loc()`, and paparazzi finds it later when a step uses it.
5. **Use concrete verbs.** "Before `pz_act_click()` clicks on an element, paparazzi waits for that element", not "before an action acts". Avoid vague placement verbs like "each video sits next to its code"; say what the reader gets ("walking through the code at each step").
6. **Tense separates what happened from how things work.** Use the present tense for how functions behave ("`pz_find()` doesn't change anything in the browser") and the past tense only for events in the example ("`pz_act_click()` changed the browser tab").

## Building an accurate mental model

7. **Refine, never reverse.** Simplifying early is fine if it builds the right model, but later text may only add detail, never contradict. Scope behavior when you first introduce it ("While paparazzi records, the cursor glides…") so a later section doesn't have to take it back.
8. **Prefer narrow, true claims over broad ones.** Check the help pages and source. Write "some functions take a per-step setting", not "a lot"; write "the one Shiny-specific function in that example", not "the only extra function".
9. **Watch for words that collide later.** For example, "visible" in "waits until visible" seemed to clash with "scrolls into view"; "not hidden" says what was meant.
10. **Frame features by what readers get.** `pz_device()` is "an easy way to set up the browser the way you want", not "make every version from one script". `pz_stage*()` is "set defaults once". Annotations "draw attention", not "point at one thing".
11. **State the contract, then the value.** When a function follows a rule readers rely on, say the rule plainly before its benefit, so readers trust how it works: "paparazzi shows one caption at a time. Each call to `pz_annotate_caption()` replaces the caption on screen…", not only "so the caption always describes what the viewer is watching".
12. **Explain the why when there's room.** Longer articles can spend a phrase on the reason behind a behavior: annotations belong to the page "because paparazzi draws them into the page itself, which is how they follow their elements and why they show up in screenshots".
13. **Show argument choices with a concrete reason.** Introduce a non-default argument where the example needs it (`side = "top"` keeps the caption off the help panel that opens at the bottom), rather than listing options.

## Paragraph and section structure

14. **Each article has a value statement.** Before writing or restructuring an article, say in one sentence what it offers that Get started doesn't, and build the outline around it. The walkthrough article's value is combining the recording tools into one longer demo, not introducing them again.
15. **Open with what we'll do.** Start an article with what we'll build. Skip contrast-setup openers ("A short clip can show one step. Showing someone… takes longer: …").
16. **Section titles name what happens.** A title should say what the section does, without reading as advice on something else: "Hide private details", not "Share it safely".
17. **Paragraph openings state the paragraph's purpose.** Readers skim first sentences. Avoid openers like "For that, …"; move a trailing sentence into the paragraph it belongs to.
18. **One idea per paragraph.** If "this" could refer to several things above it, split the paragraph and name the referent ("paparazzi calls these animations **staging**: …").
19. **Problem first, then paparazzi.** Explain why browser tests are hard (the page changes, timing is unknown) before saying paparazzi does the waiting.
20. **State the obvious in examples.** When output is wrong, say what we expected, what we got, and why ("We added a task to repot the fern, but `pz_get_text()` found the _old_ first task…").
21. **Set up before use.** Introduce selectors and reusable values (a `pz_loc()` spec in a well-named variable) before the code that uses them, and explain why they're needed. Short specs can sit at the top of the chunk that uses them. Every article's setup chunk briefly says what `pz_open()` and `pz_example()` do, so no reader gets lost.
22. **Walk through code with numbered comments.** Mark each group of steps with a `# [n] Label` comment on its own line before the group (or at the end of the line in a short setup chunk), then explain the groups after the chunk as a numbered list whose bold headings repeat the labels. Keep groups in pipeline order. Check that `air format` leaves the chunk unchanged.
23. **Land on standout features.** Give things like knitted-document output their own section; don't mention them in passing.
24. **Hammer on shared syntax.** Recording, screenshots and tests use the same functions, and Shiny adds very little to learn.
25. **Comparisons describe substance.** Skip reductive "Use it when…" lines; let the description of each tool carry the difference.
26. **Trim redundancy.** Don't restate the inverse of a claim, and don't use the same word twice in a sentence (for example, "same … same").
27. **Cut what nobody would miss.** Drop recap lists that restate earlier sections and asides about features another article demonstrates.

## Links, code and visuals

28. **pkgdown autolinks backticked functions.** When prose names a concept rather than a function, write a relative link to its reference page: `[a Shiny app](../reference/pz_serve_shiny.html)`. Link external tools (Positron, RStudio) too. In tables, link section names to their anchors and tool names to their reference pages.
29. **Explanatory screenshots can use hidden chunks** (`echo = FALSE`). Reset any staged state in the same chunk afterward, and write descriptive alt text.
30. **Let color carry meaning in annotations,** for example one color for a group of matches plus a single callout in that color. Check text contrast on light fills.
31. **Pace dense recordings.** When a recording packs in many steps, slow it with `pz_stage()` (`cursor_speed`, `typing_speed`, `pause`). Staged settings persist on the page, so restore the earlier pace afterward and say so.
32. **Render a scratch version of a visual before committing it.** Bugs in the library found while writing docs go to kata as their own issues.

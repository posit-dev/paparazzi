# 97qt: multipart task-tracker walkthrough

## Outline

Use the bundled static `tasks` page. Keep one browser page across three short, sequential MP4 recordings so the task added in part 1 is the task handled in part 2. Each clip is a top-level knitr result; `pz_record()` supplies the lifecycle and knitr copies the video into the article's figure directory. Use a modest viewport, 8 fps, and 0.6 scale. Open once and close after all clips.

1. **Add a task.** Stage cursor motion and natural typing with `pz_stage()`. Record typing a new task and clicking Add with `pz_record()`, framed to the visible `main` region with `pz_frame()` (check the crop against the final task position during rendering). Zoom to the form with `pz_camera()`, caption the action with `pz_annotate_caption()`, wait for the saved task with `pz_expect_text()`, then `pz_camera_reset()`. Show the resulting MP4 immediately.
2. **Review and finish the task.** Start on the same page. Zoom to the task list, mark the new task with a callout or box using `pz_annotate_callout()` or `pz_annotate()`, hold for reading with `pz_record_hold()`, clear it with `pz_annotate_clear()`, click Done, and show the Done filter. The filter action can demonstrate `pz_stage(camera_follow = TRUE)` while zoomed. Show the second MP4.
3. **Protect a note and open help.** Reset the filter to All and scroll the notes into view outside recording, then make a short clip around the lower page. If the note is below the frame or the crop is awkward, use a viewport home shot for this part instead. Use `pz_annotate_redact(method = "fill")` on `#notes` *before* recording so the note is covered in every frame; add a caption, click Show help, hold and clear. Show the third MP4. Do not reveal private text in narration or an uncensored frame.

Explain that recordings on the same page share app state but start at the home camera shot. Note that annotations and captions persist until cleared. Keep each clip independently playable and label the parts so the order is clear.

## Pointers, not demonstrations

Link to the function reference for spotlight and alternative mark types/reveals, `pz_press(show_keys = ...)`, `pz_record_start(captions = "both")` for optional WebVTT output, and `pz_stage_frame()` for reusable framing. Mention `pz_frame(target_box = "annotated")` only if merged and verified; do not rely on it. Point to the Shiny article for Shiny apps.

## Verification

Check every API and claim in R/ and man/. Run the article via `.agents/chrome-lock.sh` and `pkgdown::build_article()`. Inspect the HTML's real `<video>` tags and existing media paths. Extract frames from each MP4 with `av::av_video_images()` and inspect PNGs for the zoom, overlays, caption, and full note coverage. Record bugs or API friction below rather than silently hiding them.

## Findings

Pending render and media inspection.

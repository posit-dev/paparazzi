# Package index

## Pages, apps and navigation

Open a page, a Shiny app, a Quarto document or a static site to start a
chain. Set the page’s size and display settings, and move between pages.

- [`pz_open()`](https://posit-dev.github.io/paparazzi/reference/pz_open.md)
  : Open a page
- [`pz_close()`](https://posit-dev.github.io/paparazzi/reference/pz_close.md)
  : Close a page
- [`pz_example()`](https://posit-dev.github.io/paparazzi/reference/pz_example.md)
  : Paths to example pages and apps
- [`pz_with_page()`](https://posit-dev.github.io/paparazzi/reference/pz_with_page.md)
  [`pz_local_page()`](https://posit-dev.github.io/paparazzi/reference/pz_with_page.md)
  : Open a page that closes when a block or calling frame exits
- [`pz_serve_shiny()`](https://posit-dev.github.io/paparazzi/reference/pz_serve_shiny.md)
  : Run a Shiny app in a background process
- [`pz_serve_quarto()`](https://posit-dev.github.io/paparazzi/reference/pz_serve_quarto.md)
  : Serve a document or project with Quarto
- [`pz_serve_static()`](https://posit-dev.github.io/paparazzi/reference/pz_serve_static.md)
  : Serve static files over HTTP
- [`pz_device()`](https://posit-dev.github.io/paparazzi/reference/pz_device.md)
  : Set the page's size and display settings
- [`pz_nav_goto()`](https://posit-dev.github.io/paparazzi/reference/pz_nav_goto.md)
  [`pz_nav_reload()`](https://posit-dev.github.io/paparazzi/reference/pz_nav_goto.md)
  [`pz_nav_back()`](https://posit-dev.github.io/paparazzi/reference/pz_nav_goto.md)
  [`pz_nav_forward()`](https://posit-dev.github.io/paparazzi/reference/pz_nav_goto.md)
  : Navigate the page

## Screenshots and recording

Capture the page as a PNG screenshot or record it as an MP4, WebM or GIF
video.
[`pz_stage()`](https://posit-dev.github.io/paparazzi/reference/pz_stage.md)
sets how actions look while recording: the cursor, the typing speed and
the pause after each step.

- [`pz_record()`](https://posit-dev.github.io/paparazzi/reference/pz_record.md)
  : Record a block of code
- [`pz_screenshot()`](https://posit-dev.github.io/paparazzi/reference/pz_screenshot.md)
  : Take a screenshot
- [`pz_stage()`](https://posit-dev.github.io/paparazzi/reference/pz_stage.md)
  : Stage the page for recording
- [`pz_record_start()`](https://posit-dev.github.io/paparazzi/reference/pz_record_start.md)
  : Record a page interaction
- [`pz_record_stop()`](https://posit-dev.github.io/paparazzi/reference/pz_record_stop.md)
  : Stop a recording and write the video
- [`pz_record_pause()`](https://posit-dev.github.io/paparazzi/reference/pz_record_pause.md)
  [`pz_record_resume()`](https://posit-dev.github.io/paparazzi/reference/pz_record_pause.md)
  : Pause and resume a recording
- [`pz_record_hold()`](https://posit-dev.github.io/paparazzi/reference/pz_record_hold.md)
  : Hold the current frame while recording

## Actions

Use the page the way a person would: click, type, press keys, scroll and
drag. While recording, actions are staged. The `pz_set_*()` functions
set values directly instead.

- [`paparazzi-actions`](https://posit-dev.github.io/paparazzi/reference/paparazzi-actions.md)
  : How actions work
- [`pz_act_click()`](https://posit-dev.github.io/paparazzi/reference/pz_act_click.md)
  : Click an element
- [`pz_act_type()`](https://posit-dev.github.io/paparazzi/reference/pz_act_type.md)
  : Type text into an element
- [`pz_act_press()`](https://posit-dev.github.io/paparazzi/reference/pz_act_press.md)
  : Press key combinations
- [`pz_act_hover()`](https://posit-dev.github.io/paparazzi/reference/pz_act_hover.md)
  : Hover the pointer over an element
- [`pz_act_scroll()`](https://posit-dev.github.io/paparazzi/reference/pz_act_scroll.md)
  : Scroll the page or an element into view
- [`pz_act_drag()`](https://posit-dev.github.io/paparazzi/reference/pz_act_drag.md)
  : Drag an element to another element or by an offset
- [`pz_act_select_text()`](https://posit-dev.github.io/paparazzi/reference/pz_act_select_text.md)
  : Select text inside an element
- [`pz_act_focus()`](https://posit-dev.github.io/paparazzi/reference/pz_act_focus.md)
  : Focus an element
- [`pz_act_blur()`](https://posit-dev.github.io/paparazzi/reference/pz_act_blur.md)
  : Blur the focused element
- [`pz_set_value()`](https://posit-dev.github.io/paparazzi/reference/pz_set_value.md)
  : Set the value of a form control
- [`pz_set_shiny_input()`](https://posit-dev.github.io/paparazzi/reference/pz_set_shiny_input.md)
  : Set a bound Shiny input
- [`pz_set_files()`](https://posit-dev.github.io/paparazzi/reference/pz_set_files.md)
  : Attach files to a file input

## Annotations

Mark elements, point at them with callouts, spotlight or redact them,
and add captions. Annotations appear in screenshots and recordings.
[`pz_stage_annotate()`](https://posit-dev.github.io/paparazzi/reference/pz_stage_annotate.md)
sets their default styles.

- [`pz_annotate()`](https://posit-dev.github.io/paparazzi/reference/pz_annotate.md)
  : Mark page elements
- [`pz_annotate_callout()`](https://posit-dev.github.io/paparazzi/reference/pz_annotate_callout.md)
  : Add text callouts to page elements
- [`pz_annotate_spotlight()`](https://posit-dev.github.io/paparazzi/reference/pz_annotate_spotlight.md)
  : Spotlight page elements
- [`pz_annotate_redact()`](https://posit-dev.github.io/paparazzi/reference/pz_annotate_redact.md)
  : Redact page elements
- [`pz_annotate_caption()`](https://posit-dev.github.io/paparazzi/reference/pz_annotate_caption.md)
  : Add a screen-space caption
- [`pz_annotate_clear()`](https://posit-dev.github.io/paparazzi/reference/pz_annotate_clear.md)
  : Clear page annotations
- [`pz_stage_annotate()`](https://posit-dev.github.io/paparazzi/reference/pz_stage_annotate.md)
  : Set the page's annotation style defaults

## Fonts

Stage fonts from Google Fonts, Bunny Fonts or local files so that
annotations, callouts, captions and key callouts render in them.

- [`pz_stage_fonts()`](https://posit-dev.github.io/paparazzi/reference/pz_stage_fonts.md)
  : Stage fonts for annotations and captions
- [`pz_font_google()`](https://posit-dev.github.io/paparazzi/reference/pz_font_google.md)
  : Declare a font from Google Fonts
- [`pz_font_bunny()`](https://posit-dev.github.io/paparazzi/reference/pz_font_bunny.md)
  : Declare a font from Bunny Fonts
- [`pz_font_file()`](https://posit-dev.github.io/paparazzi/reference/pz_font_file.md)
  : Declare a font from a local file

## Framing and camera

Choose the part of the page that a screenshot or recording shows with
[`pz_frame()`](https://posit-dev.github.io/paparazzi/reference/pz_frame.md),
and set a default for the page with
[`pz_stage_frame()`](https://posit-dev.github.io/paparazzi/reference/pz_stage_frame.md).
During a recording, the camera zooms in on part of the frame and back
out without changing the live page.

- [`pz_frame()`](https://posit-dev.github.io/paparazzi/reference/pz_frame.md)
  : Frame a capture region
- [`pz_stage_frame()`](https://posit-dev.github.io/paparazzi/reference/pz_stage_frame.md)
  : Set or clear the page's default framing
- [`pz_camera()`](https://posit-dev.github.io/paparazzi/reference/pz_camera.md)
  : Move the recording camera
- [`pz_camera_reset()`](https://posit-dev.github.io/paparazzi/reference/pz_camera_reset.md)
  : Reset the recording camera

## Cursor

Show, move and hide the cursor drawn over the page. Its speed and size
are set with
[`pz_stage()`](https://posit-dev.github.io/paparazzi/reference/pz_stage.md).

- [`pz_cursor_show()`](https://posit-dev.github.io/paparazzi/reference/pz_cursor_show.md)
  : Show the overlay cursor
- [`pz_cursor_move()`](https://posit-dev.github.io/paparazzi/reference/pz_cursor_move.md)
  : Move the overlay cursor to an element
- [`pz_cursor_leave()`](https://posit-dev.github.io/paparazzi/reference/pz_cursor_leave.md)
  : Move the overlay cursor out of the frame
- [`pz_cursor_hide()`](https://posit-dev.github.io/paparazzi/reference/pz_cursor_hide.md)
  : Hide the overlay cursor

## Finding elements

Describe elements with reusable specs, and narrow a chain to part of the
page with scopes.

- [`pz_loc()`](https://posit-dev.github.io/paparazzi/reference/pz_loc.md)
  : Locate elements by CSS, with text, position, and scope qualifiers
- [`pz_find()`](https://posit-dev.github.io/paparazzi/reference/pz_find.md)
  : Find elements and push them as the current scope
- [`pz_find_first()`](https://posit-dev.github.io/paparazzi/reference/pz_find_first.md)
  : Find the first match and push it as the current scope
- [`pz_find_last()`](https://posit-dev.github.io/paparazzi/reference/pz_find_last.md)
  : Find the last match and push it as the current scope
- [`pz_find_nth()`](https://posit-dev.github.io/paparazzi/reference/pz_find_nth.md)
  : Find the nth match and push it as the current scope
- [`pz_find_pop()`](https://posit-dev.github.io/paparazzi/reference/pz_find_pop.md)
  : Pop the current scope
- [`pz_find_reset()`](https://posit-dev.github.io/paparazzi/reference/pz_find_reset.md)
  : Clear all scope, back to the root

## Expectations

Check the page, retrying until the check passes or times out. Inside
testthat, expectations count as test expectations.

- [`pz_expect_attr()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_attr.md)
  : Expect attributes
- [`pz_expect_checked()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_checked.md)
  : Expect elements to be checked
- [`pz_expect_class()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_class.md)
  : Expect a class
- [`pz_expect_count()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_count.md)
  : Expect a number of matching elements
- [`pz_expect_enabled()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_enabled.md)
  : Expect elements to be enabled
- [`pz_expect_exists()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_exists.md)
  : Expect at least one element to match
- [`pz_expect_focused()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_focused.md)
  : Expect elements to be focused
- [`pz_expect_in_viewport()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_in_viewport.md)
  : Expect elements to be in the viewport
- [`pz_expect_js()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_js.md)
  : Expect a JavaScript predicate to hold
- [`pz_expect_style()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_style.md)
  : Expect computed styles
- [`pz_expect_text()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_text.md)
  : Expect element text content
- [`pz_expect_title()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_title.md)
  : Expect the page title
- [`pz_expect_url()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_url.md)
  : Expect the page URL
- [`pz_expect_value()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_value.md)
  : Expect element values
- [`pz_expect_visible()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_visible.md)
  [`pz_expect_hidden()`](https://posit-dev.github.io/paparazzi/reference/pz_expect_visible.md)
  : Expect elements to be visible

## Waits

Wait for the page to settle when there’s no specific value to expect.

- [`pz_wait()`](https://posit-dev.github.io/paparazzi/reference/pz_wait.md)
  : Wait while pumping the page's event loop
- [`pz_wait_for_js()`](https://posit-dev.github.io/paparazzi/reference/pz_wait_for_js.md)
  : Wait until a JavaScript condition holds
- [`pz_wait_for_navigation()`](https://posit-dev.github.io/paparazzi/reference/pz_wait_for_navigation.md)
  : Wait for a navigation to finish
- [`pz_wait_for_shiny_idle()`](https://posit-dev.github.io/paparazzi/reference/pz_wait_for_shiny_idle.md)
  : Wait until a Shiny page is idle
- [`pz_wait_for_stable()`](https://posit-dev.github.io/paparazzi/reference/pz_wait_for_stable.md)
  : Wait until an element stops changing

## Getters

Read values from the page. Getters return values, so they end the chain.

- [`pz_get_attr()`](https://posit-dev.github.io/paparazzi/reference/pz_get_attr.md)
  : Read an attribute of matching elements
- [`pz_get_count()`](https://posit-dev.github.io/paparazzi/reference/pz_get_count.md)
  : Count matching elements
- [`pz_get_elements()`](https://posit-dev.github.io/paparazzi/reference/pz_get_elements.md)
  : Describe matching elements
- [`pz_get_html()`](https://posit-dev.github.io/paparazzi/reference/pz_get_html.md)
  : Read the HTML of matching elements
- [`pz_get_rect()`](https://posit-dev.github.io/paparazzi/reference/pz_get_rect.md)
  : Read the geometry of matching elements
- [`pz_get_style()`](https://posit-dev.github.io/paparazzi/reference/pz_get_style.md)
  : Read computed styles of matching elements
- [`pz_get_text()`](https://posit-dev.github.io/paparazzi/reference/pz_get_text.md)
  : Read the text of matching elements
- [`pz_get_title()`](https://posit-dev.github.io/paparazzi/reference/pz_get_title.md)
  : Read the page title
- [`pz_get_url()`](https://posit-dev.github.io/paparazzi/reference/pz_get_url.md)
  : Read the page URL
- [`pz_get_value()`](https://posit-dev.github.io/paparazzi/reference/pz_get_value.md)
  : Read the value of matching elements

## Escape hatches and debugging

- [`pz_inspect()`](https://posit-dev.github.io/paparazzi/reference/pz_inspect.md)
  : Inspect the current page state
- [`pz_js()`](https://posit-dev.github.io/paparazzi/reference/pz_js.md)
  : Evaluate JavaScript in the page
- [`pz_chromote()`](https://posit-dev.github.io/paparazzi/reference/pz_chromote.md)
  : Get the underlying ChromoteSession

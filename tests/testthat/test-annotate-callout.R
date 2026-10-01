callout_page <- function(.env = parent.frame()) {
  page <- local_page(.env = .env)
  pz_js(
    page,
    "document.body.innerHTML = '<div id=target style=\"position:absolute;left:220px;top:180px;width:80px;height:40px;background:#eee\"></div>';"
  )
  page
}

callout_state <- function(page) {
  pz_js(
    page,
    "(() => { const l=document.querySelector('#paparazzi-overlay-root')?.shadowRoot?.querySelector('.pz-annotations'); return [...(l?.querySelectorAll('.pz-callout') || [])].map(n => ({text:n.querySelector('.pz-bubble')?.textContent, rect:(() => { const r=n.getBoundingClientRect(); return [r.left,r.top,r.width,r.height]; })()})); })()"
  )
}

test_that("callout draws literal text into the shared layer", {
  page <- callout_page()
  expect_identical(
    pz_annotate_callout(page, "<b>Literal</b>", target = "#target", id = "tip"),
    page
  )
  expect_length(callout_state(page), 1)
  expect_identical(callout_state(page)[[1]]$text, "<b>Literal</b>")
  page |> pz_annotate_clear("tip")
  expect_length(callout_state(page), 0)
})

callout_details <- function(page) {
  pz_js(
    page,
    paste0(
      "(() => { const l=document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotations');",
      "const t=document.querySelector('#target').getBoundingClientRect();",
      "const rect=r=>[r.left,r.top,r.right,r.bottom,r.width,r.height];",
      "return {target:rect(t), nodes:[...l.querySelectorAll('.pz-callout')].map(n=>{",
      "const b=n.querySelector('.pz-bubble'),s=n.querySelector('svg');",
      "const badge=n.querySelector('span'),deco=s?s.querySelector('.pz-deco-end'):null;",
      "const bc=getComputedStyle(b),bs=badge?getComputedStyle(badge):null;",
      "const r=n.getBoundingClientRect(); return {rect:rect(r),bubble:rect(b.getBoundingClientRect()),",
      "label:badge?.textContent ?? null, text:b.textContent,",
      "color:b.style.borderColor,fill:bc.backgroundColor,textColor:bc.color,",
      "badgeFill:bs?.backgroundColor ?? null,badgeColor:bs?.color ?? null,",
      "font:b.style.fontFamily,fontSize:b.style.fontSize,",
      "leader:!!s, decos:s?[...s.children].map(c=>c.tagName):null,",
      "end:deco?.points?.length?[r.left+deco.points[0].x,r.top+deco.points[0].y]:null,",
      "head:deco?.getAttribute('points') ?? null,visible:n.style.display!=='none'}; })}; })()"
    )
  )
}

test_that("cardinal and diagonal callouts sit on their requested sides", {
  page <- callout_page()
  pz_js(
    page,
    "document.querySelector('#target').style.cssText='position:fixed;left:360px;top:300px;width:80px;height:40px;background:#eee'"
  )
  for (side in c(
    "top",
    "bottom",
    "left",
    "right",
    "top left",
    "top right",
    "bottom left",
    "bottom right"
  )) {
    page |>
      pz_annotate_callout("Tip", target = "#target", side = side, id = "tip")
    state <- callout_details(page)
    target <- unlist(state$target)
    rect <- unlist(state$nodes[[1]]$rect)
    if (grepl("top", side)) {
      expect_lte(rect[4], target[2] - 7)
    }
    if (grepl("bottom", side)) {
      expect_gte(rect[2], target[4] + 7)
    }
    if (grepl("left", side)) {
      expect_lte(rect[3], target[1] - 7)
    }
    if (grepl("right", side)) {
      expect_gte(rect[1], target[3] + 7)
    }
    endpoint <- unlist(state$nodes[[1]]$end)
    expect_true(endpoint[1] >= target[1] - 1 && endpoint[1] <= target[3] + 1)
    expect_true(endpoint[2] >= target[2] - 1 && endpoint[2] <= target[4] + 1)
    expect_true(
      any(abs(endpoint[1] - target[c(1, 3)]) < 1) ||
        any(abs(endpoint[2] - target[c(2, 4)]) < 1)
    )
    expect_true(nzchar(state$nodes[[1]]$head))
  }
  page |>
    pz_annotate_callout(
      "Tooltip",
      target = "#target",
      leader = FALSE,
      side = "right",
      id = "tip"
    )
  expect_false(callout_details(page)$nodes[[1]]$leader)
})

test_that("auto chooses roomiest cardinal once and sync follows movement", {
  page <- callout_page()
  pz_js(
    page,
    "document.querySelector('#target').style.left='20px';document.querySelector('#target').style.top=innerHeight/2+'px'"
  )
  page |>
    pz_annotate_callout(
      "Follow",
      target = "#target",
      id = "tip",
      leader = FALSE
    )
  first <- callout_details(page)
  expect_gt(first$nodes[[1]]$rect[[1]], first$target[[3]])
  pz_js(
    page,
    "document.querySelector('#target').style.left='740px';document.querySelector('#target').style.top='400px'"
  )
  pz_js(
    page,
    "document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotations').pz.sync()"
  )
  moved <- callout_details(page)
  expect_gt(moved$nodes[[1]]$rect[[1]], first$nodes[[1]]$rect[[1]])
  expect_gt(abs(moved$nodes[[1]]$rect[[2]] - first$nodes[[1]]$rect[[2]]), 50)
  pz_js(
    page,
    "document.querySelector('#target').style.left='80px';document.querySelector('#target').style.top='1200px';window.scrollTo(0,1000)"
  )
  pz_js(
    page,
    "document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotations').pz.sync()"
  )
  scrolled <- callout_details(page)
  expect_gt(scrolled$nodes[[1]]$rect[[1]], scrolled$target[[3]])
  expect_true(scrolled$nodes[[1]]$visible)
  pz_js(page, "document.querySelector('#target').remove()")
  pz_js(
    page,
    "document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotations').pz.sync()"
  )
  expect_identical(
    pz_js(
      page,
      "document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-callout').style.display"
    ),
    "none"
  )
})

test_that("multiple matches repeat text and number badges; ids share the registry", {
  page <- callout_page()
  pz_js(
    page,
    "document.body.insertAdjacentHTML('beforeend','<div class=mark style=\"position:absolute;left:120px;top:300px;width:70px;height:40px\"></div><div class=mark style=\"position:absolute;left:300px;top:300px;width:70px;height:40px\"></div>')"
  )
  page |>
    pz_stage_annotate(
      color = "rgb(255, 0, 0)",
      font_family = "monospace",
      font_size = 19
    )
  page |>
    pz_annotate_callout("Repeat", target = ".mark", label = TRUE, id = "shared")
  state <- callout_details(page)$nodes
  expect_length(state, 2)
  expect_equal(vapply(state, `[[`, "", "label"), c("1", "2"))
  expect_equal(vapply(state, `[[`, "", "text"), c("Repeat", "Repeat"))
  expect_identical(state[[1]]$color, "rgb(255, 0, 0)")
  expect_identical(state[[1]]$fontSize, "19px")
  page |>
    pz_annotate_callout("Other", target = "#target", label = "A", id = "shared")
  expect_length(callout_state(page), 1)
  expect_identical(callout_details(page)$nodes[[1]]$label, "A")
  page |> pz_annotate("#target", id = "shared", reveal = "none")
  expect_length(callout_state(page), 0)
  page |> pz_annotate_callout("New", target = "#target", id = "shared")
  page |> pz_annotate_clear("shared")
  expect_length(callout_state(page), 0)
})

test_that("callouts reject empty style strings", {
  page <- callout_page()
  expect_error(
    pz_annotate_callout(page, "x", target = "#target", color = ""),
    "color.*empty string"
  )
  expect_error(
    pz_annotate_callout(page, "x", target = "#target", font_family = ""),
    "font_family.*empty string"
  )
})

test_that("callouts validate inputs and clamp long wrapped text", {
  page <- callout_page()
  expect_error(pz_annotate_callout(page, "", target = "#target"), "text")
  expect_error(
    pz_annotate_callout(page, "x", target = "#target", side = "center"),
    "side"
  )
  expect_error(
    pz_annotate_callout(page, "x", target = "#target", leader = NA),
    "leader"
  )
  expect_error(
    pz_annotate_callout(page, "x", target = "#target", label = FALSE),
    "label"
  )
  expect_error(
    pz_annotate_callout(page, "x", target = "#target", reveal = "bad"),
    "reveal"
  )
  expect_error(
    pz_annotate_callout(
      page,
      "x",
      target = "#target",
      reveal = c("fade", "invalid")
    ),
    "reveal"
  )
  expect_error(
    pz_annotate_callout(page, "x", target = "#target", id = "spotlight"),
    "id"
  )
  page |>
    pz_annotate_callout(
      paste(rep("longword", 80), collapse = " "),
      target = "#target",
      side = "left"
    )
  state <- callout_details(page)$nodes[[1]]
  expect_lte(state$rect[[1]], 8.1)
  expect_gte(state$rect[[1]], 7.9)
  expect_lte(state$rect[[5]], 320)
  expect_gt(state$rect[[6]], 30)
  page |> pz_annotate_clear()
  page |>
    pz_annotate_callout(
      paste(rep("longword", 1200), collapse = " "),
      target = "#target",
      side = "right"
    )
  expect_true(pz_js(
    page,
    "(() => { const b=document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-bubble'); return b.scrollHeight > b.clientHeight && b.offsetHeight <= innerHeight - 16; })()"
  ))
})

test_that("callout bubble paints in still and leaves after clearing", {
  skip_if_not_installed("png")
  page <- callout_page()
  path <- withr::local_tempfile(fileext = ".png")
  page |>
    pz_annotate_callout(
      "Pixels",
      target = "#target",
      side = "right",
      id = "tip",
      reveal = "none"
    )
  state <- callout_details(page)$nodes[[1]]
  x <- round(state$rect[[1]] + 6)
  y <- round(state$rect[[2]] + 6)
  page |> pz_screenshot(path)
  dpr <- page_dpr(page)
  sample <- function() {
    as.numeric(png::readPNG(path)[y * dpr + 1, x * dpr + 1, 1:3])
  }
  expect_lt(max(sample()), 0.5)
  page |> pz_annotate_clear("tip") |> pz_screenshot(path)
  expect_equal(sample(), c(1, 1, 1), tolerance = 0.05)
})

test_that("callout pop pumps intermediate poll frames and reverse clear", {
  skip_if_not_installed("av")
  skip_if_not_installed("png")
  page <- callout_page()
  path <- withr::local_tempfile(fileext = ".mp4")
  page |> pz_record_start(path, fps = 20, hold = c(0, 0), keep_frames = TRUE)
  defer_record_stop(page)
  page |>
    pz_annotate_callout(
      "Recorded",
      target = "#target",
      side = "right",
      id = "tip"
    )
  pump_loop(page$child_loop, 0.3)
  state <- callout_details(page)$nodes[[1]]
  x <- round(state$rect[[1]] + 6) * page_dpr(page) + 1
  y <- round(state$rect[[2]] + 6) * page_dpr(page) + 1
  files <- page_recorder(page)$files
  red <- function(file) png::readPNG(file)[y, x, 1]
  entering <- vapply(files, red, 0.0)
  expect_gt(length(files), 2)
  expect_true(any(entering > 0.2 & entering < 0.9))
  expect_lt(tail(entering, 1), 0.4)
  page |> pz_annotate_clear("tip")
  leaving <- vapply(page_recorder(page)$files[-seq_along(files)], red, 0.0)
  expect_true(any(leaving > 0.2 & leaving < 0.9))
  expect_length(callout_state(page), 0)
  page |> pz_record_stop()
  expect_true(file.exists(path))
})

test_that("automatic placement chooses each roomiest cardinal side", {
  page <- callout_page()
  for (side in c("top", "right", "bottom", "left")) {
    pz_js(
      page,
      paste0(
        "(() => { const t=document.querySelector('#target');",
        "t.style.left=",
        switch(
          side,
          top = "innerWidth/2",
          bottom = "innerWidth/2",
          right = "20",
          left = "innerWidth-100"
        ),
        "+'px';",
        "t.style.top=",
        switch(
          side,
          top = "innerHeight-60",
          bottom = "20",
          right = "innerHeight/2",
          left = "innerHeight/2"
        ),
        "+'px'; })()"
      )
    )
    page |>
      pz_annotate_callout(
        "Auto",
        target = "#target",
        leader = FALSE,
        id = "tip"
      )
    state <- callout_details(page)
    target <- unlist(state$target)
    rect <- unlist(state$nodes[[1]]$rect)
    if (side == "top") {
      expect_lt(rect[4], target[2])
    }
    if (side == "right") {
      expect_gt(rect[1], target[3])
    }
    if (side == "bottom") {
      expect_gt(rect[2], target[4])
    }
    if (side == "left") expect_lt(rect[3], target[1])
  }
})

test_that("callout follows a target inside a scrolling container", {
  page <- callout_page()
  pz_js(
    page,
    paste0(
      "document.body.innerHTML='<div id=scroller style=\"position:fixed;left:150px;top:120px;width:200px;height:120px;overflow:auto\">'",
      "+'<div style=\"height:170px\"></div><div id=target style=\"width:80px;height:30px\"></div>'"
    )
  )
  page |>
    pz_annotate_callout("Inner", target = "#target", side = "right", id = "tip")
  # The target starts scrolled out of #scroller's box: the callout hides
  # until the target scrolls into view.
  expect_false(callout_details(page)$nodes[[1]]$visible)
  pz_js(
    page,
    "document.querySelector('#scroller').scrollTop=100;document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotations').pz.sync()"
  )
  first <- callout_details(page)$nodes[[1]]$rect[[2]]
  pz_js(
    page,
    "document.querySelector('#scroller').scrollTop=80;document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotations').pz.sync()"
  )
  expect_equal(
    callout_details(page)$nodes[[1]]$rect[[2]],
    first - 80,
    tolerance = 1
  )
})

test_that("callout hides for a clipped-away target and anchors to the visible rect of a partly clipped one", {
  page <- callout_page()
  pz_js(
    page,
    paste0(
      "document.body.insertAdjacentHTML('beforeend', ",
      "'<div style=\"position:absolute;left:420px;top:100px;width:200px;height:120px;overflow:auto\">' +",
      "'<div style=\"height:150px\"></div><div id=buried-call style=\"margin-left:20px;width:80px;height:60px\"></div>' +",
      "'<div style=\"height:200px\"></div></div>' +",
      "'<div style=\"position:absolute;left:420px;top:300px;width:200px;height:120px;overflow:auto\">' +",
      "'<div style=\"height:60px\"></div><div id=part-call style=\"margin-left:20px;width:80px;height:120px\"></div>' +",
      "'<div style=\"height:200px\"></div></div>')"
    )
  )
  page |>
    pz_annotate_callout(
      "gone",
      target = "#buried-call",
      reveal = "none",
      id = "gone"
    ) |>
    pz_annotate_callout(
      "partial",
      target = "#part-call",
      side = "bottom",
      reveal = "none",
      id = "partial"
    ) |>
    pz_annotate_callout(
      "partial",
      target = "#target",
      side = "bottom",
      reveal = "none",
      id = "control"
    )
  details <- callout_details(page)$nodes
  expect_length(details, 3)
  # #buried-call's box (y 250..310) sits below its container (y 100..220).
  expect_false(details[[1]]$visible)
  # #part-call's bottom (y 480) is cut by its container at y 420; the
  # leader's arrow anchors to the visible bottom edge.
  expect_true(details[[2]]$visible)
  expect_equal(details[[2]]$end[[2]], 420, tolerance = 1)
  # The bubble is never clipped.
  expect_equal(
    unlist(details[[2]]$bubble[5:6]),
    unlist(details[[3]]$bubble[5:6]),
    tolerance = 0.5
  )
})

test_that("arrow paints between bubble and target in a still", {
  skip_if_not_installed("png")
  page <- callout_page()
  path <- withr::local_tempfile(fileext = ".png")
  page |>
    pz_annotate_callout(
      "Arrow",
      target = "#target",
      side = "right",
      color = "#ff0000"
    )
  state <- callout_details(page)
  target <- unlist(state$target)
  endpoint <- unlist(state$nodes[[1]]$end)
  expect_equal(endpoint[1], target[3], tolerance = 1)
  page |> pz_screenshot(path)
  img <- png::readPNG(path)
  dpr <- page_dpr(page)
  x <- round((target[3] + state$nodes[[1]]$rect[[1]]) / 2 * dpr) + 1
  y <- round(endpoint[2] * dpr) + 1
  expect_gt(img[y, x, 1] - img[y, x, 2], 0.3)
})

test_that("idle and paused callouts do not run reveal animations", {
  skip_if_not_installed("av")
  page <- callout_page()
  page |> pz_annotate_callout("No animation", target = "#target", id = "tip")
  expect_identical(
    pz_js(
      page,
      "document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-callout').getAnimations({subtree:true}).length"
    ),
    0L
  )
  page |> pz_annotate_clear("tip")
  path <- withr::local_tempfile(fileext = ".mp4")
  page |> pz_record_start(path, fps = 15, hold = c(0, 0))
  defer_record_stop(page)
  page |> pz_record_pause()
  page |> pz_annotate_callout("Paused", target = "#target", id = "tip")
  expect_identical(
    pz_js(
      page,
      "document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-callout').getAnimations({subtree:true}).length"
    ),
    0L
  )
  page |> pz_annotate_clear("tip")
  expect_length(callout_state(page), 0)
  page |> pz_record_stop()
})

test_that("callouts use the current scope or root body without a target", {
  page <- callout_page()
  scoped <- pz_find(page, "#target")
  scoped |> pz_annotate_callout("Scope", id = "scope", side = "right")
  expect_length(callout_state(page), 1)
  details <- callout_details(page)
  target <- as.numeric(unlist(details$target))
  end <- as.numeric(unlist(details$nodes[[1]]$end))
  expect_equal(end[1], target[3], tolerance = 1)
  expect_gte(end[2], target[2])
  expect_lte(end[2], target[4])
  page |> pz_annotate_clear("scope")
  page |> pz_annotate_callout("Body", id = "body", leader = FALSE)
  expect_length(callout_state(page), 1)
  page |> pz_annotate_clear()
  expect_length(callout_state(page), 0)
})

test_that("replacing a redaction with a callout uses the same id", {
  page <- callout_page()
  page |> pz_annotate_redact("#target", id = "shared")
  page |> pz_annotate_callout("Replacement", target = "#target", id = "shared")
  expect_length(callout_state(page), 1)
  expect_identical(
    pz_js(
      page,
      "document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelectorAll('.pz-redaction').length"
    ),
    0L
  )
  page |> pz_annotate_clear("shared")
  expect_length(callout_state(page), 0)
})

test_that("clamped callouts hide overlapping arrows and reroute nonoverlapping ones", {
  page <- callout_page()
  pz_js(page, "document.querySelector('#target').style.left='0px'")
  page |>
    pz_annotate_callout(
      "Overlapping bubble",
      target = "#target",
      side = "left",
      id = "edge"
    )
  expect_identical(
    pz_js(
      page,
      "document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-callout svg').style.display"
    ),
    "none"
  )
  pz_js(
    page,
    "document.querySelector('#target').style.left='calc(100vw - 2px)'"
  )
  page |>
    pz_annotate_callout(
      "At edge",
      target = "#target",
      side = "right",
      id = "edge"
    )
  state <- callout_details(page)
  bubble <- unlist(state$nodes[[1]]$rect)
  target <- unlist(state$target)
  expect_lt(bubble[3], target[1])
  expect_false(identical(
    pz_js(
      page,
      "document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-callout svg').style.display"
    ),
    "none"
  ))
  endpoints <- pz_js(
    page,
    "(() => { const n=document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-callout'); const l=n.querySelector('.pz-shaft'); return [n.getBoundingClientRect().left+Number(l.getAttribute('x1')), n.getBoundingClientRect().left+Number(l.getAttribute('x2'))]; })()"
  )
  expect_equal(endpoints[[1]], bubble[3], tolerance = 1)
  expect_lt(endpoints[[2]], target[1])
  expect_gte(endpoints[[2]], bubble[3])
  head <- pz_js(
    page,
    "(() => { const n=document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-callout'); return n.querySelector('.pz-deco-end').getAttribute('points').split(' ').map(p=>n.getBoundingClientRect().left+Number(p.split(',')[0])); })()"
  )
  expect_equal(head[[1]], target[1], tolerance = 1)
  expect_true(all(unlist(head) >= bubble[3]))
})

test_that("long badges stay within the measured bubble and viewport", {
  page <- callout_page()
  pz_js(
    page,
    "document.querySelector('#target').style.left='calc(100vw - 80px)'"
  )
  page |>
    pz_annotate_callout(
      "Tip",
      target = "#target",
      side = "right",
      label = paste(rep("LONG", 90), collapse = "")
    )
  geometry <- pz_js(
    page,
    "(() => { const n=document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-callout'); const b=n.querySelector('.pz-bubble').getBoundingClientRect(); const a=n.querySelector('span').getBoundingClientRect(); return {bubble:[b.left,b.right],badge:[a.left,a.right],viewport:innerWidth,overflow:getComputedStyle(n.querySelector('span')).textOverflow}; })()"
  )
  expect_gte(geometry$badge[[1]], geometry$bubble[[1]])
  expect_lte(geometry$badge[[2]], geometry$bubble[[2]])
  expect_lte(geometry$badge[[2]], geometry$viewport - 8)
  expect_identical(geometry$overflow, "ellipsis")
})

test_that("callout reveal defaults to pop and rejects NULL", {
  page <- callout_page()
  expect_error(
    pz_annotate_callout(page, "Note", target = "#target", reveal = NULL),
    "reveal"
  )
  captured <- NULL
  local_mocked_bindings(annotate_call = function(ctx, els, fn, options, what) {
    captured <<- options
  })
  pz_annotate_callout(page, "Note", target = "#target")
  omitted <- captured
  pz_annotate_callout(page, "Note", target = "#target", reveal = "pop")
  expect_identical(captured, omitted)
  expect_identical(captured$reveal, "pop")
})

test_that("leader heads have stroke-scaled proportions and shafts stop at the base", {
  page <- callout_page()
  for (side in c(
    "top",
    "bottom",
    "left",
    "right",
    "top right",
    "short",
    "touching"
  )) {
    pz_js(page, "document.querySelector('#target').style.left='220px'")
    page |>
      pz_annotate_callout(
        "Arrow",
        target = "#target",
        side = if (side %in% c("short", "touching")) "right" else side,
        id = "tip",
        reveal = "draw",
        stroke_width = 2,
        distance = 8
      )
    if (side %in% c("short", "touching")) {
      gap <- if (side == "short") 3 else 0
      pz_js(
        page,
        paste0(
          "(() => { const l=document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotations');",
          "const n=l.querySelector('.pz-callout'),t=document.querySelector('#target');",
          "t.style.left=(innerWidth-8-n.offsetWidth-t.offsetWidth-",
          gap,
          ")+'px'; l.pz.sync(); })()"
        )
      )
    }
    geometry <- pz_js(
      page,
      paste0(
        "(() => { const n=document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-callout');",
        "const l=n.querySelector('.pz-shaft'),p=n.querySelector('.pz-deco-end').points;",
        "const start=[+l.getAttribute('x1'),+l.getAttribute('y1')],end=[+l.getAttribute('x2'),+l.getAttribute('y2')];",
        "const base=[(p[1].x+p[2].x)/2,(p[1].y+p[2].y)/2];",
        "return {stroke:parseFloat(getComputedStyle(l).strokeWidth),cap:getComputedStyle(l).strokeLinecap,",
        "leader:Math.hypot(p[0].x-start[0],p[0].y-start[1]),",
        "length:Math.hypot(p[0].x-base[0],p[0].y-base[1]),",
        "halfWidth:Math.hypot(p[1].x-p[2].x,p[1].y-p[2].y)/2,",
        "baseError:Math.hypot(end[0]-base[0],end[1]-base[1]),",
        "shaft:Math.hypot(end[0]-start[0],end[1]-start[1]),",
        "display:n.querySelector('svg').style.display}; })()"
      )
    )
    expected_length <- switch(
      side,
      "top right" = 10,
      short = 2.7,
      touching = 0,
      7.2
    )
    expect_equal(geometry$stroke, 2)
    expect_equal(geometry$length, expected_length, tolerance = 1e-4)
    expect_equal(geometry$halfWidth, expected_length / 2, tolerance = 1e-4)
    expect_equal(geometry$baseError, 0, tolerance = 1e-4)
    expect_equal(
      geometry$shaft + geometry$length,
      geometry$leader,
      tolerance = 1e-4
    )
    expect_identical(geometry$cap, "butt")
    expect_false(identical(geometry$display, "none"))
    if (side %in% c("top", "bottom", "left", "right")) {
      expect_gte(geometry$halfWidth, 1.8 * geometry$stroke - 1e-4)
    }
    if (side == "short") {
      expect_equal(geometry$leader, 3)
    }
    if (side == "touching") expect_equal(geometry$leader, 0)
  }
})

test_that("draw reveal draws the shaft, then shows decorations; clearing undraws", {
  page <- callout_page()
  page |>
    pz_annotate_callout("Arrow", target = "#target", side = "right", id = "tip")
  state <- pz_js(
    page,
    paste0(
      "(() => { const l=document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotations');",
      "l.pz.callout([document.querySelector('#target')], {id:'tip',text:'Arrow',side:['right'],leader:{start:'none',end:'arrow'},",
      "label:null,reveal:'draw',color:'red',fill:'#171717',textColor:'white',strokeWidth:2,distance:8,",
      "fontFamily:'sans-serif',fontSize:16,animate:true});",
      "const n=l.querySelector('.pz-callout'),anims=n.getAnimations({subtree:true});",
      "const shaft=anims.find(a=>a.effect.target.classList.contains('pz-shaft'));",
      "const bubble=anims.find(a=>a.effect.target.classList.contains('pz-bubble'));",
      "shaft.pause(); shaft.currentTime=shaft.effect.getTiming().duration/2;",
      "bubble.pause(); bubble.currentTime=bubble.effect.getTiming().duration/2;",
      "return {count:anims.length,",
      "shaftKey:[...new Set(shaft.effect.getKeyframes().flatMap(k=>Object.keys(k)))].join(','),",
      "bubbleKey:[...new Set(bubble.effect.getKeyframes().flatMap(k=>Object.keys(k)))].join(','),",
      "hidden:n.querySelector('.pz-deco-end').style.visibility,",
      "offset:parseFloat(getComputedStyle(n.querySelector('.pz-shaft')).strokeDashoffset)}; })()"
    )
  )
  expect_identical(state$count, 2L)
  expect_match(state$shaftKey, "strokeDashoffset")
  expect_match(state$bubbleKey, "opacity")
  expect_identical(state$hidden, "hidden")
  expect_gt(state$offset, 0)
  expect_lt(state$offset, 1)
  done <- pz_js(
    page,
    paste0(
      "(async () => { const l=document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotations');",
      "const n=l.querySelector('.pz-callout'),anims=n.getAnimations({subtree:true});",
      "anims.filter(a=>a.playState==='paused').forEach(a=>a.play());",
      "await Promise.all(anims.map(a=>a.finished.catch(()=>{})));",
      "await new Promise(r=>setTimeout(r,100));",
      "return {shown:n.querySelector('.pz-deco-end').style.visibility,",
      "live:n.getAnimations({subtree:true}).length}; })()"
    )
  )
  expect_identical(done$shown, "")
  expect_identical(done$live, 0L)
  leaving <- pz_js(
    page,
    paste0(
      "(() => { const l=document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotations');",
      "l.pz.clear({id:'tip',animate:true});",
      "const n=l.querySelector('.pz-callout'),anims=n.getAnimations({subtree:true});",
      "const shaft=anims.find(a=>a.effect.target.classList.contains('pz-shaft'));",
      "shaft.pause(); shaft.currentTime=shaft.effect.getTiming().duration/2;",
      "return {hidden:n.querySelector('.pz-deco-end').style.visibility,",
      "shaftKey:[...new Set(shaft.effect.getKeyframes().flatMap(k=>Object.keys(k)))].join(','),",
      "offset:parseFloat(getComputedStyle(n.querySelector('.pz-shaft')).strokeDashoffset)}; })()"
    )
  )
  expect_identical(leaving$hidden, "hidden")
  expect_match(leaving$shaftKey, "strokeDashoffset")
  expect_gt(leaving$offset, 0)
  expect_lt(leaving$offset, 1)
  removed <- pz_js(
    page,
    paste0(
      "(async () => { const l=document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotations');",
      "const n=l.querySelector('.pz-callout'),anims=n.getAnimations({subtree:true});",
      "anims.filter(a=>a.playState==='paused').forEach(a=>a.play());",
      "await Promise.all(anims.map(a=>a.finished.catch(()=>{})));",
      "await new Promise(r=>setTimeout(r,100));",
      "return {gone:!l.querySelector('.pz-callout')}; })()"
    )
  )
  expect_true(removed$gone)
})

test_that("callouts validate leader shapes and decorations", {
  page <- callout_page()
  expect_error(
    pz_annotate_callout(page, "x", target = "#target", leader = "arrow"),
    "leader",
    class = "paparazzi_error_input"
  )
  expect_error(
    pz_annotate_callout(page, "x", target = "#target", leader = 1),
    "leader",
    class = "paparazzi_error_input"
  )
  expect_error(
    pz_annotate_callout(page, "x", target = "#target", leader = c("arrow")),
    "leader",
    class = "paparazzi_error_input"
  )
  expect_error(
    pz_annotate_callout(
      page,
      "x",
      target = "#target",
      leader = c(middle = "arrow")
    ),
    "leader",
    class = "paparazzi_error_input"
  )
  expect_error(
    pz_annotate_callout(
      page,
      "x",
      target = "#target",
      leader = c(start = "dot", start = "bar")
    ),
    "leader",
    class = "paparazzi_error_input"
  )
  expect_error(
    pz_annotate_callout(
      page,
      "x",
      target = "#target",
      leader = c(end = "squiggle")
    ),
    "leader",
    class = "paparazzi_error_input"
  )
  expect_error(
    pz_annotate_callout(page, "x", target = "#target", leader = c(end = NA)),
    "leader",
    class = "paparazzi_error_input"
  )
})

test_that("leader decorations render per end and shafts stop at each base", {
  page <- callout_page()
  leader_geometry <- function() {
    pz_js(
      page,
      paste0(
        "(() => { const n=document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-callout');",
        "const s=n.querySelector('svg'),l=s.querySelector('.pz-shaft');",
        "const r=n.getBoundingClientRect(),t=document.querySelector('#target').getBoundingClientRect();",
        "const pt=el=>({x:+el.getAttribute('cx')+r.left,y:+el.getAttribute('cy')+r.top});",
        "const bar=s.querySelector('line.pz-deco-end');",
        "return {decos:[...s.children].map(c=>c.tagName+(c.classList.contains('pz-deco-start')?'-start':c.classList.contains('pz-deco-end')?'-end':'')),",
        "shaft:[+l.getAttribute('x1')+r.left,+l.getAttribute('y1')+r.top,+l.getAttribute('x2')+r.left,+l.getAttribute('y2')+r.top],",
        "dot:(c=>c?{x:+c.getAttribute('cx')+r.left,y:+c.getAttribute('cy')+r.top,r:+c.getAttribute('r')}:null)(s.querySelector('circle')),",
        "bar:bar?[+bar.getAttribute('x1')+r.left,+bar.getAttribute('y1')+r.top,+bar.getAttribute('x2')+r.left,+bar.getAttribute('y2')+r.top]:null,",
        "bubble:[r.left,r.top,r.right,r.bottom],target:[t.left,t.top,t.right,t.bottom]}; })()"
      )
    )
  }
  page |>
    pz_annotate_callout(
      "Both",
      target = "#target",
      side = "right",
      leader = c(start = "dot", end = "bar"),
      stroke_width = 2,
      distance = 40,
      id = "tip"
    )
  # side = "right" puts the bubble right of the target, so the shaft runs
  # leftward from the bubble's left edge to the target's right edge.
  g <- leader_geometry()
  expect_identical(unlist(g$decos), c("line", "circle-start", "line-end"))
  dot <- unlist(g$dot)
  expect_equal(dot[["r"]], 3, tolerance = 1e-4)
  expect_equal(dot[["x"]], g$bubble[[1]], tolerance = 1)
  expect_equal(g$shaft[[1]], dot[["x"]] - dot[["r"]], tolerance = 1e-4)
  bar <- unlist(g$bar)
  expect_equal(mean(bar[c(1, 3)]), g$target[[3]], tolerance = 1)
  expect_equal(abs(bar[[4]] - bar[[2]]) / 2, 5, tolerance = 1e-4)
  expect_equal(g$shaft[[3]], g$target[[3]] + 1, tolerance = 1e-4)
  expect_equal(g$shaft[[2]], g$shaft[[4]], tolerance = 1e-4)

  page |>
    pz_annotate_callout(
      "End only",
      target = "#target",
      side = "right",
      leader = c(end = "arrow"),
      stroke_width = 2,
      distance = 40,
      id = "tip"
    )
  g <- leader_geometry()
  expect_identical(unlist(g$decos), c("line", "polygon-end"))
  expect_equal(g$shaft[[1]], g$bubble[[1]], tolerance = 1)

  page |>
    pz_annotate_callout(
      "Plain",
      target = "#target",
      side = "right",
      leader = c(start = "none", end = "none"),
      distance = 40,
      id = "tip"
    )
  g <- leader_geometry()
  expect_identical(unlist(g$decos), "line")
  expect_equal(g$shaft[[1]], g$bubble[[1]], tolerance = 1)
  expect_equal(g$shaft[[3]], g$target[[3]], tolerance = 1)
})

test_that("short leaders clamp both decorations", {
  page <- callout_page()
  page |>
    pz_annotate_callout(
      "Short",
      target = "#target",
      side = "right",
      leader = c(start = "dot", end = "arrow"),
      stroke_width = 2,
      distance = 4,
      id = "tip"
    )
  g <- pz_js(
    page,
    paste0(
      "(() => { const n=document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-callout');",
      "const s=n.querySelector('svg'),l=s.querySelector('.pz-shaft'),c=s.querySelector('circle'),p=s.querySelector('polygon').points;",
      "const len=(a,b)=>Math.hypot(a[0]-b[0],a[1]-b[1]);",
      "const tip=[p[0].x,p[0].y],base=[(p[1].x+p[2].x)/2,(p[1].y+p[2].y)/2];",
      "return {dotR:+c.getAttribute('r'),head:len(tip,base),",
      "shaft:len([+l.getAttribute('x1'),+l.getAttribute('y1')],[+l.getAttribute('x2'),+l.getAttribute('y2')]),",
      "leader:len(tip,[+c.getAttribute('cx'),+c.getAttribute('cy')])}; })()"
    )
  )
  expect_equal(g$leader, 4, tolerance = 1)
  expect_equal(g$dotR, 4 * 0.45, tolerance = 1e-4)
  expect_equal(g$head, 4 * 0.45, tolerance = 1e-4)
  expect_gte(g$shaft, 0)
  expect_equal(g$dotR + g$shaft + g$head, g$leader, tolerance = 1)
})

test_that("fill and text_color style the bubble and badge, staged or per-call", {
  page <- callout_page()
  page |>
    pz_annotate_callout("Plain", target = "#target", label = 1, id = "tip")
  node <- callout_details(page)$nodes[[1]]
  expect_identical(node$fill, "rgb(23, 23, 23)")
  expect_identical(node$textColor, "rgb(255, 255, 255)")
  expect_identical(node$badgeFill, "rgb(23, 23, 23)")
  expect_identical(node$badgeColor, "rgb(255, 255, 255)")

  page |>
    pz_stage_annotate(fill = "#fef3c7", text_color = "#1c1917") |>
    pz_annotate_callout("Staged", target = "#target", label = 1, id = "tip")
  node <- callout_details(page)$nodes[[1]]
  expect_identical(node$fill, "rgb(254, 243, 199)")
  expect_identical(node$textColor, "rgb(28, 25, 23)")
  expect_identical(node$badgeFill, "rgb(254, 243, 199)")
  expect_identical(node$badgeColor, "rgb(28, 25, 23)")

  page |>
    pz_annotate_callout(
      "Per call",
      target = "#target",
      label = 1,
      fill = "#dbeafe",
      text_color = "#172554",
      id = "tip"
    )
  node <- callout_details(page)$nodes[[1]]
  expect_identical(node$fill, "rgb(219, 234, 254)")
  expect_identical(node$textColor, "rgb(23, 37, 84)")
  expect_identical(node$badgeFill, "rgb(219, 234, 254)")
  expect_identical(node$badgeColor, "rgb(23, 37, 84)")
  page |> pz_stage_annotate(fill = NULL, text_color = NULL)
})

test_that("callouts validate fill, text_color, stroke_width and distance", {
  page <- callout_page()
  expect_error(
    pz_annotate_callout(page, "x", target = "#target", fill = ""),
    "fill.*empty string"
  )
  expect_error(
    pz_annotate_callout(page, "x", target = "#target", text_color = ""),
    "text_color.*empty string"
  )
  expect_error(
    pz_annotate_callout(page, "x", target = "#target", stroke_width = 0),
    "stroke_width"
  )
  expect_error(
    pz_annotate_callout(page, "x", target = "#target", stroke_width = -1),
    "stroke_width"
  )
  expect_error(
    pz_annotate_callout(page, "x", target = "#target", distance = -1),
    "distance"
  )
  expect_error(
    pz_annotate_callout(page, "x", target = "#target", distance = "8"),
    "distance"
  )
})

test_that("distance sets the bubble-to-target gap and is stageable", {
  page <- callout_page()
  gap <- function() {
    state <- callout_details(page)
    target <- unlist(state$target)
    bubble <- unlist(state$nodes[[1]]$rect)
    bubble[[1]] - target[[3]]
  }
  page |>
    pz_annotate_callout("Gap", target = "#target", side = "right", id = "tip")
  default_gap <- gap()
  page |>
    pz_annotate_callout(
      "Gap",
      target = "#target",
      side = "right",
      distance = 40,
      id = "tip"
    )
  expect_equal(gap(), 40, tolerance = 1)
  page |>
    pz_stage_annotate(distance = 12) |>
    pz_annotate_callout("Gap", target = "#target", side = "right", id = "tip")
  expect_equal(gap(), 12, tolerance = 1)
  expect_gt(default_gap, 12)
  page |> pz_stage_annotate(distance = NULL)
})

test_that("an unset distance is 24 with a leader and 8 without one", {
  page <- callout_page()
  captured <- NULL
  local_mocked_bindings(annotate_call = function(ctx, els, fn, options, what) {
    captured <<- options
  })
  pz_annotate_callout(page, "x", target = "#target")
  expect_identical(captured$distance, 24)
  pz_annotate_callout(page, "x", target = "#target", leader = FALSE)
  expect_identical(captured$distance, 8)

  page |> pz_stage_annotate(distance = 30)
  pz_annotate_callout(page, "x", target = "#target", leader = FALSE)
  expect_identical(captured$distance, 30)
  page |> pz_stage_annotate(distance = NULL)
  pz_annotate_callout(page, "x", target = "#target", leader = FALSE)
  expect_identical(captured$distance, 8)
})

test_that("stroke_width scales the leader and decorations and is stageable", {
  page <- callout_page()
  leader_metrics <- function() {
    pz_js(
      page,
      paste0(
        "(() => { const n=document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-callout');",
        "const l=n.querySelector('.pz-shaft'),p=n.querySelector('.pz-deco-end').points;",
        "const base=[(p[1].x+p[2].x)/2,(p[1].y+p[2].y)/2];",
        "return {stroke:parseFloat(getComputedStyle(l).strokeWidth),",
        "head:Math.hypot(p[0].x-base[0],p[0].y-base[1])}; })()"
      )
    )
  }
  page |>
    pz_annotate_callout(
      "Wide",
      target = "#target",
      side = "right",
      stroke_width = 4,
      distance = 40,
      id = "tip"
    )
  m <- leader_metrics()
  expect_equal(m$stroke, 4)
  expect_equal(m$head, 20, tolerance = 1e-4)
  page |>
    pz_stage_annotate(stroke_width = 1) |>
    pz_annotate_callout(
      "Thin",
      target = "#target",
      side = "right",
      distance = 40,
      id = "tip"
    )
  m <- leader_metrics()
  expect_equal(m$stroke, 1)
  expect_equal(m$head, 5, tolerance = 1e-4)
  page |> pz_stage_annotate(stroke_width = NULL)
})

test_that("callout style options resolve per-call, staged, then built-in", {
  page <- callout_page()
  captured <- NULL
  local_mocked_bindings(annotate_call = function(ctx, els, fn, options, what) {
    captured <<- options
  })
  pz_annotate_callout(page, "x", target = "#target")
  defaults <- captured
  expect_identical(defaults$fill, "#171717")
  expect_identical(defaults$textColor, "white")
  expect_identical(defaults$leader, list(start = "none", end = "arrow"))
  expect_true(is.numeric(defaults$strokeWidth) && defaults$strokeWidth > 0)
  expect_true(is.numeric(defaults$distance) && defaults$distance > 0)

  page |>
    pz_stage_annotate(
      fill = "red",
      text_color = "black",
      stroke_width = 5,
      distance = 30
    )
  pz_annotate_callout(page, "x", target = "#target")
  expect_identical(captured$fill, "red")
  expect_identical(captured$textColor, "black")
  expect_identical(captured$strokeWidth, 5)
  expect_identical(captured$distance, 30)

  pz_annotate_callout(
    page,
    "x",
    target = "#target",
    fill = "blue",
    text_color = "white",
    stroke_width = 2,
    distance = 10,
    leader = FALSE
  )
  expect_identical(captured$fill, "blue")
  expect_identical(captured$textColor, "white")
  expect_identical(captured$strokeWidth, 2)
  expect_identical(captured$distance, 10)
  expect_false(captured$leader)

  pz_annotate_callout(
    page,
    "x",
    target = "#target",
    leader = c(start = "bar")
  )
  expect_identical(captured$leader, list(start = "bar", end = "none"))
})

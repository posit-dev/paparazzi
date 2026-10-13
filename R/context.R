#' @importFrom pillar type_sum
#' @export
type_sum.PaparazziContext <- function(x) {
  "pz_ctx"
}

#' @importFrom pillar pillar_shaft
#' @export
pillar_shaft.PaparazziContext <- function(x, ...) {
  scoped <- scope_top(x)
  description <- if (is.null(scoped)) "root" else scoped$description
  pillar::new_pillar_shaft_simple(description, align = "left")
}

#' Paparazzi contexts and pages
#'
#' @description
#' A **context** is the first argument of `pz_*()` functions, enabling `|>`
#' chains. `pz_find*()` return contexts visibly; chainable actions return
#' them invisibly, except in a recording chain: the context returned by
#' [pz_record_start()] (and contexts derived from it) is returned visibly
#' while its recording runs, and printing it stops the recording. A
#' context is either the root (a
#' `PaparazziPage`) or a scoped context created by `pz_find*()`: a context
#' holding an immutable stack of pinned element sets. The stack is never
#' mutated in place -- `pz_find*()` derive a new context sharing the
#' parent's pinned sets -- and [pz_find_pop()]/[pz_find_reset()] unwind it
#' the same way. Staged settings ([pz_stage()], [pz_stage_annotate()],
#' [pz_stage_frame()]) are carried by the context and flow through
#' derivation the same way; assigning the staged context
#' (`page <- page |> pz_stage(...)`) is what makes them page-wide.
#' Session-level state -- the Chromote session, the default timeout, the
#' recorder, and the page's session-bound state (staged fonts, the cursor
#' overlay, captions) -- lives on the page.
#'
#' @keywords internal
PaparazziContext <- R6::R6Class(
  "PaparazziContext",
  public = list(
    #' @field page The root `PaparazziPage` this context belongs to.
    page = NULL,

    #' @field scope Stack of pinned element sets; empty for the root context.
    scope = list(),

    #' @field recording The recorder a recording chain belongs to, or
    #'   `NULL` (internal).
    recording = NULL,

    #' @field staging Staged settings carried by this context: a list of
    #'   `overrides` (a named list) and `frame` (a frame spec or `NULL`);
    #'   `NULL` until a `pz_stage*()` call derives a context (internal).
    staging = NULL,

    #' @field inspect_image Pending annotated screenshot path for knitr, or
    #'   `NULL` (internal).
    inspect_image = NULL,

    #' @description Create a context attached to a page.
    #' @param page A `PaparazziPage`.
    #' @param scope Stack of pinned element sets; defaults to empty (the
    #'   root context).
    #' @param recording The recorder of the recording chain, if any.
    #' @param staging Staged settings for this context; defaults to none.
    initialize = function(
      page,
      scope = list(),
      recording = NULL,
      staging = NULL
    ) {
      self$page <- page
      self$scope <- scope
      self$recording <- recording
      self$staging <- staging
    },

    #' @description Print the page summary (URL, device, scope stack,
    #'   recording state) without the target section or visuals; see
    #'   [pz_inspect()]. A recording chain whose recording is still
    #'   running stops it instead and, interactively, shows the video.
    #' @param ... Unused; included for compatibility with the `print()` generic.
    print = function(...) {
      if (ctx_recording(self)) {
        return(record_print_stop(self))
      }
      inspect_summary_print(self)
      invisible(self)
    },

    #' @description Close the root page's browser tab (its chromote
    #'   session). Idempotent. Delegates to the root page; a
    #'   `PaparazziPage`'s own `close()` runs for pages.
    close = function() {
      self$page$close()
      invisible(self)
    },

    #' @description Open the live browser view (DevTools) of the root
    #'   page.
    view = function() {
      self$page$view()
      invisible(self)
    },

    #' @description Has the root page been closed?
    is_closed = function() {
      self$page$is_closed()
    }
  ),
  # Staged contexts are used exactly like pages (page <- page |>
  # pz_stage(...)), so page-level members delegate to the root page.
  # PaparazziPage overrides these with its own bindings.
  active = list(
    #' @field session The root page's underlying `ChromoteSession`
    #'   (read-only).
    session = function() {
      self$page$session
    },

    #' @field child_loop The root page's chromote child loop (read-only).
    child_loop = function() {
      self$page$child_loop
    },

    #' @field default_timeout The root page's default timeout in seconds.
    default_timeout = function(value) {
      if (missing(value)) {
        self$page$default_timeout
      } else {
        self$page$default_timeout <- value
      }
    }
  )
)

#' @rdname PaparazziContext
PaparazziPage <- R6::R6Class(
  "PaparazziPage",
  inherit = PaparazziContext,
  public = list(
    #' @description Wrap a `ChromoteSession` as a paparazzi page.
    #' @param session A `chromote::ChromoteSession`.
    #' @param timeout Default timeout in seconds for this session.
    #' @param owned_app App started by this page, if any.
    #' @param shared_app Caller-owned app handle kept alive while the page lives.
    initialize = function(
      session,
      timeout = 10,
      owned_app = NULL,
      shared_app = NULL
    ) {
      stopifnot(inherits(session, "ChromoteSession"))
      private$chromote_ <- session
      private$default_timeout_ <- timeout
      private$owned_app_ <- owned_app
      private$shared_app_ <- shared_app
      self$page <- self
    },

    #' @description Close the page's browser tab (its chromote session). Idempotent.
    close = function() {
      if (!private$closed_) {
        if (!is.null(private$owned_app_)) {
          on.exit(private$owned_app_$stop(), add = TRUE)
        }
        record_page_closed(self)
        self$release_object_group()
        private$closed_ <- TRUE
        private$chromote_$close()
      }
      invisible(self)
    },

    #' @description Release every remote object a scope pinned.
    #'   Internal: runs on close and before navigation resets scopes.
    release_object_group = function() {
      try(
        private$chromote_$Runtime$releaseObjectGroup(
          objectGroup = private$object_group_
        ),
        silent = TRUE
      )
      invisible(self)
    },

    #' @description Open the live browser view (DevTools).
    view = function() {
      private$chromote_$view()
      invisible(self)
    },

    #' @description Has the page been closed?
    is_closed = function() {
      private$closed_
    },

    #' @description Print the page summary (URL, device, scope stack,
    #'   recording state) without the target section or visuals; see
    #'   [pz_inspect()]. A closed page prints one line.
    #' @param ... Unused; included for compatibility with the `print()` generic.
    print = function(...) {
      if (private$closed_) {
        cli::cat_line("<paparazzi page> (closed)")
        return(invisible(self))
      }
      inspect_summary_print(self)
      invisible(self)
    }
  ),
  active = list(
    #' @field session The underlying `ChromoteSession` (read-only).
    session = function() {
      private$chromote_
    },

    #' @field child_loop chromote's private `later` event loop (read-only).
    #'   Waits must pump this loop so scheduled timers keep firing.
    child_loop = function() {
      private$chromote_$get_child_loop()
    },

    #' @field default_timeout Session default timeout in seconds.
    default_timeout = function(value) {
      if (missing(value)) {
        private$default_timeout_
      } else {
        check_number_decimal(value, min = 0)
        private$default_timeout_ <- value
      }
    },

    #' @field object_group The CDP object group holding every remote
    #'   object a scope pinned (read-only; internal).
    object_group = function() {
      private$object_group_
    },

    #' @field session_state Session-bound page state: the fonts registry, the cursor env, captions, and the annotation init id (internal).
    session_state = function(value) {
      if (missing(value)) {
        private$session_state_
      } else {
        private$session_state_ <- value
      }
    },

    #' @field recorder Current recorder state, or `NULL` (internal).
    recorder = function(value) {
      if (missing(value)) {
        private$recorder_
      } else {
        private$recorder_ <- value
      }
    },

    #' @field pre_action_loader Main-frame loader ID before the last user
    #'   action, or `NULL` (internal).
    pre_action_loader = function(value) {
      if (missing(value)) {
        private$pre_action_loader_
      } else {
        private$pre_action_loader_ <- value
      }
    },

    #' @field app The owned or shared app handle, or `NULL` (read-only; internal).
    app = function() {
      private$owned_app_ %||% private$shared_app_
    }
  ),
  private = list(
    chromote_ = NULL,
    owned_app_ = NULL,
    shared_app_ = NULL,
    closed_ = FALSE,
    default_timeout_ = 10,
    pre_action_loader_ = NULL,
    # A constant is safe because groups are per session, so it can't
    # collide across pages.
    object_group_ = "paparazzi_scopes",
    session_state_ = list(),
    recorder_ = NULL
  )
)

#' @exportS3Method knitr::knit_print
knit_print.PaparazziContext <- function(x, ...) {
  image <- x$inspect_image
  x$inspect_image <- NULL
  if (ctx_recording(x)) {
    # The recording media wins; the pending image would never be shown.
    if (!is.null(image)) {
      unlink(image)
    }
    return(knitr::knit_print(pz_record_stop(x), ...))
  }
  # A pending image belongs to the chunk that captured it. Anywhere else it
  # is stale (the inspect result was assigned, or a getter kept it), so drop
  # it and its unreferenced figure file.
  if (
    !is.null(image) &&
      !identical(attr(image, "chunk"), knitr::opts_current$get("label"))
  ) {
    unlink(image)
    image <- NULL
  }
  # pz_inspect() already printed the summary with its match details; only
  # print when there is no pending image to show.
  if (is.null(image)) {
    knitr::normal_print(x)
    invisible(x)
  } else {
    knitr::include_graphics(image, dpi = attr(image, "dpi"))
  }
}

ctx_derive <- function(ctx, scope, staging = ctx$staging) {
  ctx$inspect_image <- NULL
  PaparazziContext$new(
    ctx$page,
    scope = scope,
    recording = ctx$recording,
    staging = staging
  )
}

ctx_return <- function(ctx) {
  ctx$inspect_image <- NULL
  if (ctx_recording(ctx)) ctx else invisible(ctx)
}

ctx_recording <- function(ctx) {
  rec <- ctx$recording
  !is.null(rec) && rec$active && identical(rec, page_recorder(ctx$page))
}

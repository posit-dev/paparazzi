#' Run a Shiny app in a background process
#'
#' Starts a Shiny app -- a directory or an app file -- in a background R
#' process and returns a handle for its lifecycle. One app can back any
#' number of pages: pass the handle to [pz_open()] for each page. Closing
#' those pages leaves the app running.
#'
#' The handle has `$stop()` and `$logs()` methods and a `print()` method
#' showing the URL, port, and status -- the one place the paparazzi API
#' uses methods rather than `pz_*()` functions. `$stop()` interrupts,
#' waits, then kills, and is idempotent, so `withr::defer(app$stop())`
#' is a safe cleanup. A finalizer stops the app as a last resort.
#'
#' App stdout and stderr go to a temporary log file (never an undrained
#' pipe), readable mid-run with `$logs()`.
#'
#' @param app A path to a Shiny app directory or an app file
#'   (anything [shiny::runApp()] accepts as a path).
#' @param ... Reserved; must be empty.
#' @param envvars Named character vector of environment variables set in
#'   the app process, on top of the inherited environment. `NULL` adds no
#'   environment overrides.
#' @param shiny_options Additional options for [shiny::runApp()], e.g.
#'   `list(test.mode = TRUE)`. `appDir` is reserved; use `app` to select
#'   the app. `host` and `port` are managed by paparazzi: `host` defaults
#'   to `"127.0.0.1"`, and `port` (default `NULL`) picks a random free port.
#'   If startup fails because the port was taken, a new port is tried.
#' @param timeout Seconds to wait for the app to start listening;
#'   defaults to 10.
#'
#' @return A `PaparazziServe` handle with public fields `url` and `port`
#'   and methods `stop()`, `logs()`, and `is_running()`.
#'
#' @examplesIf paparazzi:::examples_run("shiny")
#' app <- pz_serve_shiny(pz_example("tasks-app"))
#' app
#'
#' # Pages opened on a handle share the app, here at two screen sizes
#' desktop <- pz_open(app, width = 1280)
#' phone <- pz_open(app, width = 390, mobile = TRUE)
#' pz_get_text(phone, target = "#summary")
#' pz_close(desktop)
#' pz_close(phone)
#'
#' # Closing the pages leaves the app running until you stop it
#' app$is_running()
#' head(app$logs())
#' app$stop()
#'
#' @export
pz_serve_shiny <- function(
  app,
  ...,
  envvars = NULL,
  shiny_options = list(),
  timeout = 10
) {
  app_dir <- app
  check_dots_empty()
  if (!is_string(app_dir)) {
    cli::cli_abort(
      "{.arg app} must be a path to a Shiny app directory or app file, not {.obj_type_friendly {app_dir}}.",
      class = "paparazzi_error_input"
    )
  }
  envvars <- check_app_envvars(envvars)
  if (!is.list(shiny_options)) {
    stop_input_type(shiny_options, "a list")
  }
  if ("appDir" %in% names(shiny_options)) {
    cli::cli_abort(
      c(
        "{.arg shiny_options} must not set {.arg appDir}.",
        i = "Use {.arg app} to select the app."
      ),
      class = "paparazzi_error_input"
    )
  }
  check_number_decimal(timeout, min = 0)
  rlang::check_installed("shiny", reason = "to run a Shiny app.")

  if (is_file_app(app_dir)) {
    app_dir <- normalizePath(app_dir, winslash = "/", mustWork = TRUE)
  } else if (dir.exists(app_dir)) {
    app_dir <- normalizePath(app_dir, winslash = "/", mustWork = TRUE)
  } else {
    cli::cli_abort(
      c(
        "{.arg app} must be a Shiny app directory or app file: {.val {app_dir}}",
        i = "No such directory, or not an {.file .R} file."
      ),
      class = "paparazzi_error_input"
    )
  }

  app_start(app_dir, envvars, shiny_options, timeout)
}

#' Serve static files over HTTP
#'
#' Serves a directory or a single HTML file on a free local port. For a
#' file, its directory is served and the handle URL points to that file.
#' Other files in that directory are also accessible over HTTP.
#'
#' @param path A path to a directory or an `.html` file.
#' @param root The directory to serve as the server root. Defaults to the
#'   file's directory for an `.html` file. Only supported when `path` is a
#'   file, which must live inside `root`; the handle URL points at `path`
#'   relative to `root`. Use it when the page references assets outside its
#'   own directory, such as `../deps/styles.css`.
#' @param ... Reserved; must be empty.
#' @return A `PaparazziServe` handle with `$url`, `$port`, `$stop()`,
#'   `$is_running()`, and `$logs()`. Static servers have no captured logs:
#'   `$logs()` returns `character()`. Pass the handle to [pz_open()] to
#'   share a server across pages. Closing those pages leaves it running.
#'   `$stop()` is idempotent; use `withr::defer(server$stop())` for cleanup.
#'   A finalizer stops the server as a last resort.
#' @examplesIf paparazzi:::examples_run("httpuv", site = TRUE)
#' # pz_open() serves HTML files over HTTP on its own; pz_serve_static()
#' # creates a handle you can share across pages instead
#' server <- pz_serve_static(pz_example("tasks"))
#' page <- pz_open(server)
#' pz_get_url(page)
#' pz_close(page)
#' server$stop()
#' @export
pz_serve_static <- function(path, ..., root = NULL) {
  check_dots_empty()
  check_string(path)
  if (
    !dir.exists(path) &&
      !(file.exists(path) && grepl("[.]html$", path, ignore.case = TRUE))
  ) {
    cli::cli_abort(
      "{.arg path} must be an existing directory or {.file .html} file.",
      class = "paparazzi_error_input"
    )
  }
  is_file <- !dir.exists(path)
  if (!is.null(root)) {
    check_string(root)
    if (!is_file) {
      cli::cli_abort(
        "{.arg root} is only supported when {.arg path} is an {.file .html} file.",
        class = "paparazzi_error_input"
      )
    }
    if (!dir.exists(root)) {
      cli::cli_abort(
        "{.arg root} must be an existing directory.",
        class = "paparazzi_error_input"
      )
    }
  }
  path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  if (!is.null(root)) {
    root <- normalizePath(root, winslash = "/", mustWork = TRUE)
    if (!startsWith(path, paste0(root, "/"))) {
      cli::cli_abort(
        "{.arg path} must be inside {.arg root}.",
        class = "paparazzi_error_input"
      )
    }
  }
  serve_static(path, root = root, call = caller_env())
}

#' Serve a document or project with Quarto
#'
#' Starts a local `quarto preview` process for a `.qmd` or `.Rmd` file,
#' or a directory containing `_quarto.yml`. Quarto renders `.Rmd` files
#' with knitr. The Quarto CLI must be on `PATH`, or its executable path
#' must be set in `QUARTO_PATH`; the quarto R package is not required.
#'
#' Input watching and automatic navigation are disabled. Quarto may
#' still reload pages after resource changes, such as CSS edits; keep
#' those resources unchanged during a capture. Interactive documents
#' (`runtime: shiny` or `server: shiny`) are not supported.
#'
#' @param path A path to a `.qmd` or `.Rmd` file, or a Quarto project directory.
#' @param ... Reserved; must be empty.
#' @param render Whether to request a full render before previewing.
#'   `FALSE` passes `--no-render`; projects use Quarto's preview preparation
#'   and cached execution results. Quarto still renders standalone documents
#'   on startup. `TRUE` passes `--render all`.
#' @return A `PaparazziServe` handle with `$url`, `$port`, `$stop()`,
#'   `$is_running()`, and `$logs()`. Each handle owns its process, so
#'   multiple previews can run at once. Standard output and errors go to
#'   a temporary log file, readable during and after the preview.
#'   Pass the handle to [pz_open()] to share it across pages; closing those
#'   pages leaves it running. `$stop()` is idempotent; use
#'   `withr::defer(server$stop())` for cleanup. A finalizer stops the
#'   preview as a last resort.
#' @export
pz_serve_quarto <- function(path, ..., render = FALSE) {
  check_dots_empty()
  check_string(path)
  check_bool(render)
  if (
    !((dir.exists(path) && file.exists(file.path(path, "_quarto.yml"))) ||
      (!dir.exists(path) &&
        file.exists(path) &&
        grepl("[.](qmd|rmd)$", path, ignore.case = TRUE)))
  ) {
    cli::cli_abort(
      "{.arg path} must be an existing {.file .qmd} or {.file .Rmd} file, or a directory containing {.file _quarto.yml}.",
      class = "paparazzi_error_input"
    )
  }
  path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  quarto_start(path, render, quarto_cli())
}

serve_open <- function(x, kind, shiny_options, envvars, timeout) {
  switch(
    kind,
    shiny = pz_serve_shiny(
      x,
      shiny_options = shiny_options,
      envvars = envvars,
      timeout = timeout
    ),
    quarto = pz_serve_quarto(x),
    static = pz_serve_static(x)
  )
}

serve_kind <- function(x) {
  if (!is_string(x) || !file.exists(x)) {
    return(NULL)
  }
  if (dir.exists(x)) {
    if (any(tolower(list.files(x)) %in% c("app.r", "server.r"))) {
      return("shiny")
    }
    if (file.exists(file.path(x, "_quarto.yml"))) {
      return("quarto")
    }
    return("static")
  }
  if (is_file_app(x) && is_shiny_app_file(basename(x))) {
    return("shiny")
  }
  if (grepl("[.](qmd|rmd)$", x, ignore.case = TRUE)) {
    return("quarto")
  }
  # pz_serve_static() only accepts .html files, so the pz_open() fallback for
  # other files stays file://. Without httpuv, HTML files fall back to file://
  # as well rather than prompting for an install.
  if (grepl("[.]html$", x, ignore.case = TRUE) && httpuv_available()) {
    return("static")
  }
  NULL
}

httpuv_available <- function() {
  requireNamespace("httpuv", quietly = TRUE)
}

serve_static <- function(x, root = NULL, call = caller_env()) {
  rlang::check_installed("httpuv", reason = "to serve static files.")
  dir <- if (!is.null(root)) {
    root
  } else if (dir.exists(x)) {
    x
  } else {
    dirname(x)
  }
  for (attempt in seq_len(5)) {
    port <- random_port()
    server <- tryCatch(
      suppressMessages(httpuv::runStaticServer(
        dir,
        host = "127.0.0.1",
        port = port,
        background = TRUE,
        browse = FALSE
      )),
      error = function(e) e
    )
    if (!inherits(server, "error")) {
      break
    }
    if (attempt == 5) {
      cli::cli_abort(
        c(
          "Couldn't start a static server for {.path {x}}.",
          x = conditionMessage(server)
        ),
        class = "paparazzi_error_app_startup",
        call = call
      )
    }
  }
  url <- paste0("http://127.0.0.1:", port, "/")
  if (!dir.exists(x)) {
    rel <- if (is.null(root)) basename(x) else substring(x, nchar(root) + 2L)
    # URLencode(reserved = TRUE) escapes "/", so encode path segments one at
    # a time and rejoin them.
    rel <- paste(
      vapply(
        strsplit(rel, "/", fixed = TRUE)[[1]],
        function(part) utils::URLencode(part, reserved = TRUE, repeated = TRUE),
        character(1)
      ),
      collapse = "/"
    )
    url <- paste0(url, rel)
  }
  PaparazziServe$new(
    process = NULL,
    log_file = NULL,
    port = port,
    url = url,
    backend = "static",
    server = server
  )
}

quarto_cli <- function() {
  path <- Sys.getenv("QUARTO_PATH", unset = "")
  if (!nzchar(path)) {
    path <- unname(Sys.which("quarto"))
  }
  if (!nzchar(path) || !file.exists(path) || dir.exists(path)) {
    cli::cli_abort(
      c(
        "The Quarto CLI could not be found.",
        i = "Install Quarto from {.url https://quarto.org/docs/get-started/}, add it to PATH, or set QUARTO_PATH to its executable path."
      ),
      class = "paparazzi_error_quarto_not_found"
    )
  }
  path
}

quarto_start <- function(path, render, cli, timeout = 60, call = caller_env()) {
  for (attempt in seq_len(5)) {
    port <- random_port()
    if (app_port_connectable(port)) {
      # Some platforms allow a second bind, but requests would reach the first
      # listener instead.
      if (attempt < 5) {
        next
      }
      app_startup_error(
        list(kind = "exited", port_taken = TRUE, log = character()),
        path,
        timeout,
        call,
        engine = "Quarto preview"
      )
    }
    preview <- new_quarto(path, render, cli, port)
    failure <- app_wait_failure(preview, timeout)
    if (is.null(failure)) {
      url <- quarto_browse_url(preview, port)
      if (length(url)) {
        preview$url <- url
      }
      return(preview)
    }
    preview$stop()
    if (failure$port_taken && attempt < 5) {
      next
    }
    app_startup_error(failure, path, timeout, call, engine = "Quarto preview")
  }
}

# Quarto can accept connections before it logs the document URL; wait
# briefly for that line before falling back to the server root.
quarto_browse_url <- function(preview, port, wait = 2) {
  deadline <- Sys.time() + wait
  repeat {
    logs <- gsub("\033\\[[0-9;]*m", "", preview$logs())
    logs <- logs[grepl("Browse at ", logs, fixed = TRUE)]
    url <- regmatches(logs, regexpr("http://[^[:space:]]+", logs))
    url <- sub("http://localhost:", "http://127.0.0.1:", url, fixed = TRUE)
    url <- url[startsWith(url, paste0("http://127.0.0.1:", port, "/"))]
    if (length(url)) {
      return(url[[1]])
    }
    if (Sys.time() >= deadline) {
      return(NULL)
    }
    Sys.sleep(0.05)
  }
}

new_quarto <- function(path, render, cli, port) {
  log_file <- tempfile(pattern = "paparazzi-quarto-", fileext = ".log")
  process <- processx::process$new(
    cli,
    args = c(
      "preview",
      path,
      "--host",
      "127.0.0.1",
      "--port",
      as.character(port),
      "--no-browser",
      "--no-watch-inputs",
      "--no-navigate",
      if (render) c("--render", "all") else "--no-render"
    ),
    stdout = log_file,
    stderr = "2>&1",
    cleanup = TRUE,
    cleanup_tree = TRUE
  )
  PaparazziServe$new(process, log_file, port, backend = "quarto")
}

# A file path is an app only if shiny::runApp() would source it.
is_file_app <- function(path) {
  grepl("[.]r$", tolower(path)) && file.exists(path) && !dir.exists(path)
}

check_app_envvars <- function(
  envvars,
  arg = caller_arg(envvars),
  call = caller_env()
) {
  if (is.null(envvars)) {
    return(NULL)
  }
  check_character(envvars, allow_null = TRUE, arg = arg, call = call)
  nms <- names(envvars)
  if (is.null(nms) || !all(nzchar(nms))) {
    cli::cli_abort(
      "{.arg {arg}} must have a name for every element.",
      class = "paparazzi_error_input",
      call = call
    )
  }
  envvars
}

app_start <- function(
  app_dir,
  envvars,
  shiny_options,
  timeout,
  call = caller_env()
) {
  max_attempts <- 5
  for (attempt in seq_len(max_attempts)) {
    port <- shiny_options$port %||% random_port()
    if (app_port_connectable(port)) {
      # Some platforms allow a second bind, but requests would reach the first
      # listener instead.
      if (attempt < max_attempts) {
        shiny_options$port <- NULL
        next
      }
      app_startup_error(
        list(kind = "exited", port_taken = TRUE, log = character()),
        app_dir,
        timeout,
        call = call
      )
    }
    config <- c(
      list(appDir = app_dir),
      shiny_options,
      list(host = "127.0.0.1", port = port, launch.browser = FALSE)
    )
    config <- config[!duplicated(names(config), fromLast = TRUE)]
    app <- new_app(config, port, envvars)
    failure <- app_wait_failure(app, timeout)
    if (is.null(failure)) {
      return(app)
    }
    app$stop()
    if (failure$port_taken && attempt < max_attempts) {
      shiny_options$port <- NULL
      next
    }
    app_startup_error(failure, app_dir, timeout, call = call)
  }
}

app_wait_failure <- function(app, timeout) {
  deadline <- Sys.time() + timeout
  repeat {
    if (!app$is_running()) {
      log <- app$logs()
      return(list(
        kind = "exited",
        port_taken = any(grepl(
          "address already in use|port .*already in use|failed to create server",
          log,
          ignore.case = TRUE
        )),
        log = log
      ))
    }
    if (app_port_connectable(app$port)) {
      return(NULL)
    }
    if (Sys.time() >= deadline) {
      return(list(kind = "timeout", port_taken = FALSE, log = app$logs()))
    }
    Sys.sleep(0.05)
  }
}

app_startup_error <- function(
  failure,
  app_dir,
  timeout,
  call,
  engine = "Shiny app"
) {
  what <- switch(
    if (failure$port_taken) "port_taken" else failure$kind,
    port_taken = "could not bind a port",
    timeout = cli::format_inline(
      "did not start within {.val {timeout}} seconds"
    ),
    exited = "exited during startup"
  )
  cli::cli_abort(
    c(
      "The {engine} at {.path {app_dir}} {what}.",
      if (length(failure$log)) {
        log <- paste(utils::tail(failure$log, 20L), collapse = "\n")
        log <- substr(log, max(1L, nchar(log) - 3999L), nchar(log))
        c(x = cli_escape(log))
      }
    ),
    class = if (identical(engine, "Shiny app")) {
      "paparazzi_error_app_startup"
    } else {
      "paparazzi_error_quarto_startup"
    },
    call = call
  )
}

# Chrome refuses to navigate to these ports in 3000:8000, so they are
# useless to paparazzi even when free (same list shiny uses).
chrome_blocked_ports <- function() {
  c(3659, 4045, 5060, 5061, 6000, 6566, 6665:6669, 6697)
}

random_port <- function(call = caller_env()) {
  candidates <- setdiff(3000:8000, chrome_blocked_ports())
  for (i in 1:100) {
    port <- sample(candidates, 1)
    probe <- tryCatch(serverSocket(port), error = function(e) NULL)
    if (!is.null(probe)) {
      close(probe)
      return(port)
    }
  }
  cli::cli_abort(
    "Could not find a free port for the server.",
    class = "paparazzi_error_app_startup",
    call = call
  )
}

app_port_connectable <- function(port, host = "127.0.0.1") {
  # A refused connection warns as well as errors; the polls below would
  # otherwise spam a warning per attempt.
  con <- suppressWarnings(tryCatch(
    socketConnection(
      host = host,
      port = port,
      open = "r+",
      blocking = TRUE,
      timeout = 1
    ),
    error = function(e) NULL
  ))
  if (is.null(con)) {
    return(FALSE)
  }
  close(con)
  TRUE
}

new_app <- function(config, port, envvars) {
  config_file <- tempfile(pattern = "paparazzi-app-", fileext = ".rds")
  saveRDS(config, config_file)
  log_file <- tempfile(pattern = "paparazzi-app-", fileext = ".log")
  process <- processx::process$new(
    file.path(R.home("bin"), "Rscript"),
    args = c(
      "-e",
      "do.call(shiny::runApp, readRDS(commandArgs(TRUE)[[1]]))",
      config_file
    ),
    # File, never a pipe: an undrained pipe blocks the app's writes.
    stdout = log_file,
    stderr = "2>&1",
    # "current" keeps the inherited environment; envvars override it.
    env = c("current", envvars),
    cleanup = TRUE,
    cleanup_tree = TRUE
  )
  PaparazziServe$new(process, log_file, port)
}

PaparazziServe <- R6::R6Class(
  "PaparazziServe",
  public = list(
    url = NULL,
    port = NULL,
    backend = "shiny",

    initialize = function(
      process,
      log_file,
      port,
      backend = "shiny",
      url = NULL,
      server = NULL
    ) {
      private$process_ <- process
      private$log_file_ <- log_file
      private$server_ <- server
      self$port <- port
      self$backend <- backend
      self$url <- url %||% sprintf("http://127.0.0.1:%d/", port)
    },

    stop = function() {
      if (!private$stopped_) {
        private$stopped_ <- TRUE
        if (identical(self$backend, "static")) {
          httpuv::stopServer(private$server_)
          return(invisible(self))
        }
        if (private$process_$is_alive()) {
          private$process_$interrupt()
          private$process_$wait(2000)
        }
        if (identical(self$backend, "quarto")) {
          private$process_$kill_tree()
          private$process_$wait(3000)
        } else if (private$process_$is_alive()) {
          private$process_$kill()
        }
      }
      invisible(self)
    },

    logs = function() {
      if (is.null(private$log_file_) || !file.exists(private$log_file_)) {
        return(character())
      }
      readLines(private$log_file_, warn = FALSE)
    },

    is_running = function() {
      if (identical(self$backend, "static")) {
        return(!private$stopped_ && private$server_$isRunning())
      }
      !private$stopped_ && private$process_$is_alive()
    },

    print = function(...) {
      status <- if (self$is_running()) {
        if (identical(self$backend, "static")) {
          "running"
        } else {
          sprintf("running (pid %d)", private$process_$get_pid())
        }
      } else if (private$stopped_ || identical(self$backend, "static")) {
        "stopped"
      } else {
        sprintf("exited (status %d)", private$process_$get_exit_status())
      }
      cli::cat_line("<paparazzi app> ", self$url, " -- ", status)
      invisible(self)
    }
  ),
  private = list(
    process_ = NULL,
    server_ = NULL,
    log_file_ = NULL,
    stopped_ = FALSE,
    finalize = function() {
      try(self$stop(), silent = TRUE)
    }
  )
)

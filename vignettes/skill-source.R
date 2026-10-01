cat_skill_source <- function(source_path) {
  vignette_dir <- dirname(knitr::current_input(dir = TRUE))
  skill_dir <- file.path(vignette_dir, "../inst/skills/paparazzi")

  if (!dir.exists(skill_dir)) {
    skill_dir <- system.file("skills/paparazzi", package = "paparazzi")
  }

  skill_source <- readLines(file.path(skill_dir, source_path))
  if (identical(skill_source[1], "---")) {
    skill_source <- skill_source[-seq_len(which(skill_source == "---")[2])]
  }
  skill_source <- skill_source[-match(TRUE, startsWith(skill_source, "# "))]
  skill_source <- gsub(
    "references/([a-z-]+)\\.md",
    "agent-\\1.html",
    skill_source
  )

  cat(skill_source, sep = "\n")
}

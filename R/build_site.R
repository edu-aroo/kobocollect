# =============================================================================
# build_site.R — build the whole website into docs/      source("R/build_site.R")
# =============================================================================
# 1. start from an empty quiz registry (each quiz() call refills it)
unlink(".quiz_registry", recursive = TRUE)

# 2. knit every .Rmd and copy assets/, data/, templates/ into docs/
rmarkdown::render_site(encoding = "UTF-8")

# 3. combine the registry into the quiz index (used to compute level scores)
files <- list.files(".quiz_registry", full.names = TRUE)
idx   <- lapply(files, function(f) jsonlite::fromJSON(f))
names(idx) <- sapply(idx, `[[`, "id")
idx   <- lapply(idx, function(x) x[c("max", "page", "level")])
json  <- jsonlite::toJSON(idx, auto_unbox = TRUE, pretty = TRUE)
for (d in c("assets", "docs/assets")) {
  writeLines(json, file.path(d, "quiz_index.json"))                      # for the Apps Script
  writeLines(paste0("window.QUIZ_INDEX = ", json, ";"), file.path(d, "quiz_index.js"))  # for course.js
}

# 4. GitHub Pages: do not run Jekyll
file.create("docs/.nojekyll")
message(length(idx), " quizzes indexed. Site built in docs/. Check docs/index.html, then commit + push.")


# ==============================================================================
# make_pdf_kit.R — PDF version of the sessions, for students with poor internet
# ------------------------------------------------------------------------------
# The PDFs stay in YOUR project (folder pdf_kit/, never published on the site).
# You decide who receives them. Quizzes are NOT in the PDF: students still answer
# them online, so their progress and scores are recorded.
#
# Needs: pagedown (install.packages("pagedown")) and Google Chrome or Chromium.
# Usage:  source("R/make_pdf_kit.R")
#         make_pdf_kit(level = "beginner", lang = "fr")
#         make_pdf_kit(level = "intermediate", lang = "en", solutions = TRUE)
# ==============================================================================

make_pdf_kit <- function(level = c("beginner", "intermediate", "advanced"),
                         lang = c("fr", "en"), solutions = FALSE,
                         author = "Aroo Falinirina") {
  level <- match.arg(level); lang <- match.arg(lang)
  stopifnot(requireNamespace("pagedown", quietly = TRUE))

  # 1. which .Rmd files belong to the level (same rule as the quiz index)
  rmd <- list.files(".", pattern = "\\.Rmd$")
  rmd <- switch(level,
    beginner     = rmd[grepl("^[0-9]", rmd)],
    intermediate = rmd[grepl("^i[0-9]", rmd)],
    advanced     = rmd[grepl("^a[0-9]", rmd)])
  rmd <- c(rmd, switch(level, beginner = "cheatsheet.Rmd",
                       intermediate = "cheatsheet-intermediate.Rmd", advanced = "cheatsheet-advanced.Rmd"))
  rmd <- rmd[file.exists(rmd)]

  # 2. a small header: hides the other language, the solutions (optional),
  #    and adds the watermark + footer on every printed page
  other <- if (lang == "fr") "en" else "fr"
  note  <- if (lang == "fr") "Quiz : répondez en ligne sur le site du cours (votre score y est enregistré)."
           else "Quiz: answer online on the course website (your score is recorded there)."
  tile  <- sprintf("<svg xmlns='http://www.w3.org/2000/svg' width='360' height='220'><text x='20' y='140' transform='rotate(-24 180 110)' font-family='Georgia,serif' font-size='20' fill='#0b3d5c' fill-opacity='0.07'>by %s</text></svg>", author)
  head  <- c(
    "<style>",
    sprintf(".%s { display: none !important; }", other),
    if (!solutions) ".solution { display: none !important; }" else
      ".solution > * { display: block !important; } .solution { border: 1px solid #dde3e6; }",
    sprintf(".pdf-watermark { background: url(\"data:image/svg+xml;utf8,%s\") !important; }",
            utils::URLencode(tile, reserved = TRUE)),   # fully encoded: no quote problems
    "</style>",
    "<script>document.addEventListener('DOMContentLoaded', function () {",
    "  var w = document.createElement('div'); w.className = 'pdf-watermark'; document.body.appendChild(w);",
    sprintf("  var f = document.createElement('div'); f.className = 'pdf-footer'; f.textContent = 'by %s'; document.body.appendChild(f);", author),
    sprintf("  document.querySelectorAll('.quiz').forEach(function (q) { q.setAttribute('data-note', '%s'); });", gsub("'", "\\\\'", note)),
    "});</script>")
  hdr <- file.path("pdf_kit", "pdf_header.html")
  writeLines(head, hdr)

  # 3. render each page to a stand-alone HTML (no login), then print it to PDF
  out_dir <- file.path("pdf_kit", level, lang)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  for (f in rmd) {
    message("-> ", f)
    html <- rmarkdown::render(
      f, output_dir = file.path("pdf_kit", "html"), quiet = TRUE, envir = new.env(),
      output_format = rmarkdown::html_document(
        theme = "flatly", highlight = "tango", self_contained = TRUE, mathjax = NULL,
        css = c("assets/course.css", "pdf_kit/pdf.css"),
        includes = rmarkdown::includes(in_header = hdr)))
    pagedown::chrome_print(html, output = file.path(out_dir, sub("\\.Rmd$", ".pdf", f)))
  }
  message("PDFs written in ", out_dir)
}

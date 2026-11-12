# =============================================================================
# course_helpers.R
# -----------------------------------------------------------------------------
# Small helper functions used INSIDE the .Rmd pages (sourced in each page's
# setup chunk). They write HTML that the JavaScript file assets/course.js
# turns into interactive elements.
#
#   fig_svg("kobo-cycle")      -> inserts assets/img/kobo-cycle.svg inline
#   quiz("k01", list(...))     -> inserts an interactive, scored quiz
#   q_num(), q_mcq(), q_text() -> build one quiz question each
#   xls(form$survey)           -> an XLSForm sheet drawn as a spreadsheet
#   ui("deploy")               -> a KoboToolbox button: French (English), from R/ui_labels.csv
#   xf(...)                    -> "XLSForm columns and functions used here" table
#   read_export(file)          -> every sheet of a KoboToolbox XLS export, as a list
#
# Nothing here is needed by the students: it is only used when YOU knit.
# =============================================================================

# ---- knitr options for every page -------------------------------------------
knitr::opts_chunk$set(
  comment   = "#>",    # prefix of printed results (easy to tell from code)
  collapse  = FALSE,   # keep code and output in separate boxes
  fig.align = "center",
  fig.width = 7, fig.height = 4.2,
  dpi       = 110,
  out.width = "85%"
)

# ---- Insert an SVG illustration -----------------------------------------------
# The SVG is pasted *inline* (not as <img>) so that the CSS can hide the
# English or French labels (class "en" / "fr") when the language changes.
fig_svg <- function(name, caption_en = NULL, caption_fr = NULL) {
  path <- file.path("assets", "img", paste0(name, ".svg"))
  svg  <- paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  svg  <- gsub("$", "&#36;", svg, fixed = TRUE)   # a "$" would be read by pandoc as the start of a math formula
  cap  <- ""
  if (!is.null(caption_en)) {
    cap <- sprintf('<figcaption><span class="en">%s</span><span class="fr">%s</span></figcaption>',
                   caption_en, caption_fr)
  }
  # asis_output() tells knitr: "this is raw HTML, do not escape it"
  # The ```{=html} fence makes pandoc copy the SVG untouched (no markdown processing of its texts:
  # spaces and straight quotes are kept).
  knitr::asis_output(sprintf('\n\n```{=html}\n<figure class="svg-fig">%s%s</figure>\n```\n\n', svg, cap))
}

# ---- Quiz questions -----------------------------------------------------------
# Each function returns a simple list. en/fr = question text in both languages.

# Numeric answer, accepted if |student - answer| <= tol
q_num <- function(en, fr, answer, tol = 0.05, hint_en = "", hint_fr = "") {
  list(type = "num", en = en, fr = fr, answer = answer, tol = tol,
       hint_en = hint_en, hint_fr = hint_fr)
}

# Multiple choice; 'correct' is the position (1, 2, 3...) of the right option
q_mcq <- function(en, fr, options_en, options_fr = options_en, correct) {
  list(type = "mcq", en = en, fr = fr,
       options_en = as.list(options_en), options_fr = as.list(options_fr),
       answer = correct - 1)            # JavaScript counts from 0, R from 1
}

# Short text answer, compared without case and spaces; several answers allowed
q_text <- function(en, fr, answers) {
  list(type = "text", en = en, fr = fr, answer = as.list(answers))
}

# ---- The quiz block -----------------------------------------------------------
# id      : unique quiz id, e.g. "s01" (used to save the score)
# title_en/title_fr : optional title shown above the questions
# qs      : list of questions built with q_num/q_mcq/q_text
# The questions are converted to JSON and then base64-encoded. Base64 is NOT
# encryption: it only stops students from reading the answers at a glance in
# the page source.
quiz <- function(id, qs, title_en = NULL, title_fr = NULL) {
  register_quiz(id, length(qs))      # remember id + number of questions (see below)
  json <- jsonlite::toJSON(qs, auto_unbox = TRUE, digits = NA)
  b64  <- jsonlite::base64_enc(charToRaw(enc2utf8(as.character(json))))
  b64  <- gsub("\n", "", b64)
  # optional title, e.g. for the exercises of the practice session
  ttl  <- if (is.null(title_en)) "" else
    sprintf(' data-title-en="%s" data-title-fr="%s"', title_en, title_fr)
  knitr::asis_output(sprintf(
    '<div class="quiz" id="quiz-%s" data-quiz-id="%s"%s data-q="%s"></div>', id, id, ttl, b64))
}

# ---- Quiz registry ------------------------------------------------------------
# Every quiz() call writes a tiny file .quiz_registry/<id>.json with its number
# of questions, its page and its level. R/build_site.R combines them into
# assets/quiz_index.json (read by the Google Apps Script) and
# assets/quiz_index.js (read by course.js) -> the site knows the maximum score of
# EVERY quiz of a level, even the pages a student has not opened yet.
# Level = first letter of the file name: "i" intermediate, "a" advanced, else beginner.
register_quiz <- function(id, n) {
  page  <- sub("\\..*$", "", basename(knitr::current_input()))
  level <- if (grepl("^i[0-9]", page)) "intermediate" else
           if (grepl("^a[0-9]", page)) "advanced" else "beginner"
  dir.create(".quiz_registry", showWarnings = FALSE)
  writeLines(jsonlite::toJSON(list(id = id, max = n, page = page, level = level), auto_unbox = TRUE),
             file.path(".quiz_registry", paste0(id, ".json")))
}

# ---- Download button for a data file -----------------------------------------
dl <- function(file, label = file, dir = "data") {
  knitr::asis_output(sprintf(
    '<a class="btn-dl" href="%s/%s" download>&#8681; %s</a>', dir, file, label))
}

# ---- Show a whole file as a code block (Advanced level) -----------------------
# `r show_file("templates/advanced/mpa_report.Rmd")` on its own line prints the file
# exactly as it is (chunks and inline code are NOT run): handy to show .Rmd/.qmd/.yml.
show_file <- function(path, lang = NULL, lines = NULL) {
  x <- readLines(path, warn = FALSE, encoding = "UTF-8")
  if (!is.null(lines)) x <- x[lines]
  if (is.null(lang)) lang <- switch(tolower(tools::file_ext(path)), rmd = "markdown", qmd = "markdown",
                                    r = "r", yml = "yaml", yaml = "yaml", bib = "bibtex", json = "json", "")
  fence <- "`````"
  knitr::asis_output(paste0("\n\n", fence, lang, "\n", paste(x, collapse = "\n"), "\n", fence, "\n\n"))
}

# ---- Illustration that can be replaced by a real screenshot ---------------------
# fig_shot("git-pane", "caption EN", "légende FR")
#   - if assets/img/screens/git-pane.png exists (your own Windows screenshot), it is shown;
#   - otherwise the drawn illustration assets/img/git-pane.svg is shown.
# The list of screenshots to take is in assets/img/screens/README.md.
fig_shot <- function(name, caption_en = NULL, caption_fr = NULL) {
  png <- file.path("assets", "img", "screens", paste0(name, ".png"))
  if (!file.exists(png)) return(fig_svg(name, caption_en, caption_fr))
  cap <- if (is.null(caption_en)) "" else
    sprintf('<figcaption><span class="en">%s</span><span class="fr">%s</span></figcaption>', caption_en, caption_fr)
  knitr::asis_output(sprintf('\n\n```{=html}\n<figure class="svg-fig"><img src="%s" alt="%s" style="max-width:100%%">%s</figure>\n```\n\n',
                             png, name, cap))
}

# fa(): "Functions and arguments" table, in English and French.
# Each row: c(code, what it does (en), what it does (fr), value expected (en), value expected (fr))
# Use "" for the value when it does not apply. The result is written as two
# Markdown tables (::: en / ::: fr) inside a box with class "fa-box".
fa <- function(..., title = TRUE) {
  rows <- list(...)
  esc <- function(x) {
    # code spans containing "|" become <code> HTML (a "|" would cut the table cell)
    m <- gregexpr("`[^`]*\\|[^`]*`", x)
    regmatches(x, m) <- lapply(regmatches(x, m), function(v) {
      v <- substr(v, 2, nchar(v) - 1)
      v <- gsub("&", "&amp;", v, fixed = TRUE); v <- gsub("<", "&lt;", v, fixed = TRUE)
      v <- gsub("|", "&#124;", v, fixed = TRUE); v <- gsub("\\", "&#92;", v, fixed = TRUE)
      paste0("<code>", v, "</code>")
    })
    gsub("|", "&#124;", x, fixed = TRUE)
  }
  tab <- function(k, head) {
    lines <- vapply(rows, function(r) {
      r <- c(r, rep("", 5 - length(r)))
      sprintf("| %s | %s | %s |", esc(r[1]), esc(r[k]), esc(r[k + 2]))
    }, "")
    paste(c(head, "|---|---|---|", lines), collapse = "\n")
  }
  en <- tab(2, "| Function / argument | What it does | Value it expects |")
  fr <- tab(3, "| Fonction / argument | Ce qu'il fait | Valeur attendue |")
  t_en <- if (title) "**Functions and arguments used here**\n\n" else ""
  t_fr <- if (title) "**Fonctions et arguments utilisés ici**\n\n" else ""
  knitr::asis_output(paste0("\n\n::: fa-box\n::: en\n", t_en, en, "\n:::\n::: fr\n", t_fr, fr, "\n:::\n:::\n\n"))
}

# =============================================================================
# Helpers added for the KoboToolbox course
# =============================================================================
source("R/kobo_helpers.R")   # the forms, the simulated data, read the exports

# ---- Show an XLSForm sheet as a spreadsheet ---------------------------------------
# xls(form$survey)                    -> the whole sheet, with Excel row numbers and column letters
# xls(form$survey, rows = 5:9)        -> only some rows (row numbers stay the real Excel ones)
# xls(form$survey, cols = c("type", "name", "label"), hl = c(7, 8))  -> highlighted rows
# xls(df, sheet = "choices")          -> the tab name shown under the table
# A data frame written by hand works too: xls(data.frame(type = ..., name = ...)).
xls <- function(d, rows = NULL, cols = NULL, hl = NULL, sheet = "survey", note = NULL) {
  d <- as.data.frame(d, stringsAsFactors = FALSE)
  d[is.na(d)] <- ""
  if (!is.null(cols)) d <- d[, intersect(cols, names(d)), drop = FALSE]
  excel_row <- seq_len(nrow(d)) + 1
  if (!is.null(rows)) { keep <- excel_row %in% rows; d <- d[keep, , drop = FALSE]; excel_row <- excel_row[keep] }
  esc <- function(x) { x <- gsub("&", "&amp;", x, fixed = TRUE); x <- gsub("<", "&lt;", x, fixed = TRUE)
                       x <- gsub("$", "&#36;", x, fixed = TRUE); gsub(">", "&gt;", x, fixed = TRUE) }
  letters_col <- function(i) { s <- ""; while (i > 0) { r <- (i - 1) %% 26; s <- paste0(LETTERS[r + 1], s); i <- (i - 1) %/% 26 }; s }
  head1 <- paste0("<tr><th class='xr'></th>", paste0("<th class='xc'>", sapply(seq_along(d), letters_col), "</th>", collapse = ""), "</tr>")
  head2 <- paste0("<tr><td class='xr'>1</td>", paste0("<td class='xh'>", esc(names(d)), "</td>", collapse = ""), "</tr>")
  body <- vapply(seq_len(nrow(d)), function(i) {
    cls <- if (excel_row[i] %in% hl) " class='xhl'" else ""
    paste0("<tr", cls, "><td class='xr'>", excel_row[i], "</td>",
           paste0("<td>", esc(as.character(unlist(d[i, ]))), "</td>", collapse = ""), "</tr>")
  }, "")
  nt <- if (is.null(note)) "" else paste0("<div class='xnote'>", note, "</div>")
  knitr::asis_output(sprintf('\n\n```{=html}\n<div class="xls-wrap"><table class="xls">%s%s%s</table><div class="xls-tab"><span>%s</span></div>%s</div>\n```\n\n',
                             head1, head2, paste(body, collapse = ""), sheet, nt))
}

# ---- Interface labels: French label first, English label in brackets -----------
# All labels of the KoboToolbox website and of KoboCollect are in R/ui_labels.csv
# (columns key, fr, en, checked, note). KoboToolbox renames buttons from time to
# time: correct the label ONCE in the CSV and rebuild, every page follows.
# checked = "yes" when you saw it in the current version, "doc" = taken from the
# official documentation (support.kobotoolbox.org), "no" = to be checked.
ui_table <- function() {
  x <- utils::read.csv(file.path("R", "ui_labels.csv"), encoding = "UTF-8",
                       stringsAsFactors = FALSE, na.strings = "", colClasses = "character")
  x[is.na(x)] <- ""
  x
}
ui <- function(key, en = TRUE) {
  x <- ui_table()
  r <- x[x$key == key, ]
  if (nrow(r) != 1) stop("ui(): label '", key, "' is not in R/ui_labels.csv")
  html_esc <- function(v) gsub("<", "&lt;", gsub("&", "&amp;", v, fixed = TRUE), fixed = TRUE)
  fr <- html_esc(r$fr); e <- html_esc(r$en)
  if (!en || fr == e) return(sprintf('<span class="ui">%s</span>', fr))
  sprintf('<span class="ui">%s <span class="ui-en">(%s)</span></span>', fr, e)
}

# ---- Read every sheet of a KoboToolbox XLS export into a list --------------------
read_export <- function(file) {
  sh <- readxl::excel_sheets(file)
  setNames(lapply(sh, function(s) as.data.frame(readxl::read_excel(file, sheet = s, guess_max = 5000))), sh)
}

# ---- "Columns used here" table: same idea as fa() in the R course ---------------
# Each row: c(column or function, what it does (en), (fr), values (en), (fr))
xf <- function(..., title = TRUE) {
  rows <- list(...)
  esc <- function(x) gsub("|", "&#124;", x, fixed = TRUE)
  tab <- function(k, head) {
    lines <- vapply(rows, function(r) {
      r <- c(r, rep("", 5 - length(r)))
      sprintf("| %s | %s | %s |", esc(r[1]), esc(r[k]), esc(r[k + 2]))
    }, "")
    paste(c(head, "|---|---|---|", lines), collapse = "\n")
  }
  en <- tab(2, "| Column / function | What it does | Values it takes |")
  fr <- tab(3, "| Colonne / fonction | Ce qu'elle fait | Valeurs possibles |")
  t_en <- if (title) "**XLSForm columns and functions used here**\n\n" else ""
  t_fr <- if (title) "**Colonnes et fonctions XLSForm utilisées ici**\n\n" else ""
  knitr::asis_output(paste0("\n\n::: fa-box\n::: en\n", t_en, en, "\n:::\n::: fr\n", t_fr, fr, "\n:::\n:::\n\n"))
}

# ---- Keyboard keys: key("Ctrl+S") -------------------------------------------------
key <- function(k) paste(sprintf("<kbd>%s</kbd>", trimws(strsplit(k, "+", fixed = TRUE)[[1]])), collapse = " + ")

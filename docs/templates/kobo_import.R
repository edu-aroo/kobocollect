# =============================================================================
# kobo_import.R — read a KoboToolbox XLS export (with groups and repeats) in R
# Course "Data collection with KoboToolbox", Advanced level (Sessions A4–A7)
# by Aroo Falinirina
# -----------------------------------------------------------------------------
# Export settings expected (DATA > Downloads):
#   - Select export type: XLS
#   - Value and header format: XML values and headers
#   - Include groups in headers: ticked (separator "/")
#   - Export Select Many questions as: Single and separate columns
# Packages: install.packages(c("readxl", "dplyr", "tidyr", "stringr"))
# =============================================================================
library(readxl)
library(dplyr)
library(tidyr)
library(stringr)

# ---- 1. Read every sheet into a named list ----------------------------------------
# read_kobo("data/exports/a03_suivi_recifs_xml.xlsx")
#   -> list(main = <first sheet>, transects = ..., poissons = ...)
read_kobo <- function(file, short_names = TRUE) {
  sheets <- excel_sheets(file)
  out <- lapply(sheets, function(s) read_excel(file, sheet = s, guess_max = 10000))
  names(out) <- c("main", sheets[-1])            # the first sheet = the main data
  if (short_names) out <- lapply(out, shorten_names)
  out
}

# ---- 2. Remove the group path from the headers ------------------------------------
# "localisation/region" -> "region" ; "plongee/observateurs/hery" -> "observateurs/hery"
# (the 0/1 columns of a select_multiple keep "question/choice").
# Metadata columns (starting with "_") are not changed.
shorten_names <- function(df) {
  nm <- names(df)
  sm <- str_detect(nm, "/") & !str_starts(nm, "_")
  parts <- str_split(nm, "/")
  short <- vapply(seq_along(nm), function(i) {
    p <- parts[[i]]
    if (!sm[i] || length(p) == 1) return(nm[i])
    # keep "question/choice" when the column before is the question itself
    q <- paste(head(p, -1), collapse = "/")
    if (q %in% nm) paste(tail(p, 2), collapse = "/") else tail(p, 1)
  }, "")
  if (anyDuplicated(short)) warning("Duplicated short names: ", paste(unique(short[duplicated(short)]), collapse = ", "),
                                    " — keep the group path for these columns (short_names = FALSE).")
  names(df) <- short
  df
}

# ---- 3. Replace choice names by their labels, from the XLSForm ---------------------
# form = the .xlsx of the form (FORM > More actions > Download XLS)
# kobo_label(d$statut, "a03_suivi_recifs.xlsx", "statut")
kobo_choices <- function(form_file) {
  ch <- read_excel(form_file, sheet = "choices")
  lab <- names(ch)[str_starts(names(ch), "label")][1]          # first label column
  ch |> select(list_name, name, label = all_of(lab))
}
kobo_label <- function(x, form_file, list_name) {
  ch <- kobo_choices(form_file)
  ch <- ch[ch$list_name == list_name, ]
  ch$label[match(x, ch$name)]
}

# ---- 4. Attach a repeat to its parent -----------------------------------------------
# child$_parent_index = parent$_index  (inside the SAME export file)
# join_parent(kobo$transects, kobo$main, c("site", "statut"))
join_parent <- function(child, parent, cols) {
  parent |>
    select(`_index`, all_of(cols)) |>
    rename(`_parent_index` = `_index`) |>
    right_join(child, by = "_parent_index", relationship = "one-to-many")
}

# ---- Example ------------------------------------------------------------------------
# kobo <- read_kobo("data/exports/a03_suivi_recifs_xml.xlsx")
# names(kobo)                       # "main" "transects" "poissons"
# tr <- join_parent(kobo$transects, kobo$main, c("site", "statut"))
# tr |> group_by(statut) |> summarise(corail = mean(corail_vivant))

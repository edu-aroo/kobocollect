# =============================================================================
# kobo_helpers.R — the XLSForms of the course, the simulated data, and an
# "exporter" that writes .xlsx files laid out like a KoboToolbox XLS export.
# -----------------------------------------------------------------------------
# Used by R/make_course_files.R (to write the files) and by the pages (to show
# the forms as tables and to compute the quiz answers).
#
#   S(type, name, label, ...)   one row of the "survey" sheet
#   C(list, name, label, ...)   rows of the "choices" sheet
#   xlsform(survey, choices, settings)  -> a form (a list of 3 data frames)
#   make_xlsform(form, file)    -> writes the .xlsx (one sheet per element)
#   kobo_export(data, form, file, headers = "xml"|"labels", groups = TRUE|FALSE)
#
# The simulated data are random but reproducible (set.seed in each function).
# =============================================================================

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

# ---- building blocks ---------------------------------------------------------
# One survey row. Any XLSForm column can be given by name; label/hint can be
# a single string or a named vector c(fr = "...", en = "...", mg = "...").
S <- function(type, name = "", label = "", ...) {
  extra <- list(...)
  row <- list(type = type, name = name)
  add_ml <- function(row, col, val) {
    if (length(val) > 1 || !is.null(names(val))) {
      for (l in names(val)) row[[paste0(col, "::", LANGS[[l]])]] <- unname(val[[l]])
    } else row[[col]] <- val
    row
  }
  if (!(length(label) == 1 && is.null(names(label)) && identical(label, ""))) row <- add_ml(row, "label", label)
  for (k in names(extra)) {
    if (k %in% c("hint", "constraint_message", "required_message")) row <- add_ml(row, k, extra[[k]])
    else row[[k]] <- extra[[k]]
  }
  as.data.frame(lapply(row, as.character), check.names = FALSE, stringsAsFactors = FALSE)
}
LANGS <- list(fr = "Français (fr)", en = "English (en)", mg = "Malagasy (mg)")

# Choices of one list. labels: character vector (one language) or a data frame
# with columns fr/en/mg. Extra columns (filters) can be given as named vectors.
C <- function(list_name, name, label, ...) {
  d <- data.frame(list_name = list_name, name = name, stringsAsFactors = FALSE)
  if (is.data.frame(label)) { for (l in names(label)) d[[paste0("label::", LANGS[[l]])]] <- label[[l]] }
  else d$label <- label
  ex <- list(...)
  for (k in names(ex)) d[[k]] <- ex[[k]]
  d
}

# bind rows with different columns (missing cells = "")
rbind_fill <- function(...) {
  l <- list(...); if (length(l) == 1 && is.list(l[[1]]) && !is.data.frame(l[[1]])) l <- l[[1]]
  cols <- unique(unlist(lapply(l, names)))
  out <- lapply(l, function(d) { for (c in setdiff(cols, names(d))) d[[c]] <- rep("", nrow(d)); d[cols] })
  r <- do.call(rbind, out); r[is.na(r)] <- ""; rownames(r) <- NULL; r
}

xlsform <- function(survey, choices = NULL, settings = NULL) {
  structure(list(survey = rbind_fill(survey), choices = if (!is.null(choices)) rbind_fill(choices),
                 settings = settings), class = "xlsform")
}

# Order columns the usual way, then write one sheet per element (bold header,
# frozen first row, sensible widths).
make_xlsform <- function(form, file) {
  first <- c("list_name", "type", "name", "label", "hint", "required", "required_message", "relevant",
             "constraint", "constraint_message", "calculation", "default", "appearance",
             "choice_filter", "repeat_count", "parameters")
  order_cols <- function(d) {
    nm <- names(d)
    key <- sapply(nm, function(x) { b <- sub("::.*$", "", x); i <- match(b, first); if (is.na(i)) 99 else i })
    d[order(key, seq_along(nm))]
  }
  # writexl writes clean .xlsx files that KoboToolbox (pyxform/openpyxl) reads
  # without problem; bold header row.
  sheets <- list()
  for (sh in c("survey", "choices", "settings")) {
    d <- form[[sh]]; if (is.null(d)) next
    sheets[[sh]] <- if (sh != "settings") order_cols(d) else d
  }
  writexl::write_xlsx(sheets, file, format_headers = TRUE)
  invisible(file)
}

# =============================================================================
# STRUCTURE OF A FORM: which field is in which group / repeat
# =============================================================================
form_fields <- function(form, lang = NULL) {
  s <- form$survey
  lab_col <- if (!is.null(lang)) paste0("label::", LANGS[[lang]]) else
    if ("label" %in% names(s)) "label" else grep("^label::", names(s), value = TRUE)[1]
  path <- character(0); cont <- "main"; cont_stack <- "main"
  plab <- character(0)
  out <- list()
  for (i in seq_len(nrow(s))) {
    ty <- trimws(s$type[i]); nm <- s$name[i]; lb <- s[[lab_col]][i]
    base <- sub(" .*$", "", ty)
    if (base %in% c("begin_group", "begin group")) { path <- c(path, nm); plab <- c(plab, lb); next }
    if (base %in% c("begin_repeat", "begin repeat")) {
      path <- c(path, nm); plab <- c(plab, lb); cont_stack <- c(cont_stack, nm); next }
    if (base %in% c("end_group", "end group")) { path <- head(path, -1); plab <- head(plab, -1); next }
    if (base %in% c("end_repeat", "end repeat")) {
      path <- head(path, -1); plab <- head(plab, -1); cont_stack <- head(cont_stack, -1); next }
    if (base %in% c("note")) next
    list_name <- if (base %in% c("select_one", "select_multiple", "rank")) sub("^\\S+\\s+", "", ty) else ""
    out[[length(out) + 1]] <- data.frame(name = nm, type = base, list_name = sub(" or_other$", "", list_name),
      label = if (is.na(lb) || lb == "") nm else lb, path = paste(c(path, nm), collapse = "/"),
      label_path = paste(c(plab, if (is.na(lb) || lb == "") nm else lb), collapse = "/"),
      container = tail(cont_stack, 1), stringsAsFactors = FALSE)
  }
  do.call(rbind, out)
}
# parent container of each repeat
repeat_parents <- function(form) {
  s <- form$survey; stack <- "main"; par <- c()
  for (i in seq_len(nrow(s))) {
    b <- sub(" .*$", "", trimws(s$type[i]))
    if (b %in% c("begin_repeat", "begin repeat")) { par[s$name[i]] <- tail(stack, 1); stack <- c(stack, s$name[i]) }
    if (b %in% c("end_repeat", "end repeat")) stack <- head(stack, -1)
  }
  par
}
choice_label <- function(form, list_name, names, lang = NULL) {
  ch <- form$choices
  col <- if (!is.null(lang)) paste0("label::", LANGS[[lang]]) else
    if ("label" %in% names(ch)) "label" else grep("^label::", names(ch), value = TRUE)[1]
  ch <- ch[ch$list_name == list_name, ]
  ch[[col]][match(names, ch$name)]
}

# =============================================================================
# THE EXPORTER — writes a file laid out like a KoboToolbox "XLS" export
#   data: list(main = df, <repeat name> = df with column .parent = row number
#         of the parent in ITS container). Columns = field names (xml names);
#         select_multiple / rank = choice names separated by spaces.
#   headers = "xml" (XML values and headers) or "labels" (Labels)
#   groups  = include groups in headers ("/" as separator)
# =============================================================================
META_MAIN <- c("_id", "_uuid", "_submission_time", "_validation_status", "_notes",
               "_status", "_submitted_by", "__version__", "_tags", "_index")
kobo_table <- function(data, form, container, headers = "xml", groups = TRUE, lang = NULL) {
  ff <- form_fields(form, lang); ff <- ff[ff$container == container, ]
  d <- data[[container]]; out <- list()
  hdr <- function(i) if (headers == "xml") { if (groups) ff$path[i] else ff$name[i] } else
                     { if (groups) ff$label_path[i] else ff$label[i] }
  for (i in seq_len(nrow(ff))) {
    nm <- ff$name[i]; v <- d[[nm]] %||% rep(NA, nrow(d)); h <- hdr(i)
    if (ff$type[i] == "select_one" && headers == "labels")
      v <- ifelse(is.na(v), NA, choice_label(form, ff$list_name[i], v, lang))
    if (ff$type[i] %in% c("select_multiple", "rank")) {
      parts <- strsplit(ifelse(is.na(v), "", v), " ")
      single <- if (headers == "labels") sapply(parts, function(p)
        if (!length(p)) NA else paste(choice_label(form, ff$list_name[i], p, lang), collapse = " ")) else v
      out[[h]] <- single
      if (ff$type[i] == "select_multiple") {
        ch <- form$choices[form$choices$list_name == ff$list_name[i], ]
        for (k in seq_len(nrow(ch))) {
          sub_h <- paste0(h, "/", if (headers == "labels") choice_label(form, ff$list_name[i], ch$name[k], lang) else ch$name[k])
          out[[sub_h]] <- ifelse(is.na(v), NA, as.integer(sapply(parts, function(p) ch$name[k] %in% p)))
        }
      }
      next
    }
    if (ff$type[i] == "geopoint") {
      out[[h]] <- v
      xy <- strsplit(ifelse(is.na(v), "", v), " ")
      pre <- if (groups && grepl("/", ff$path[i])) paste0(sub("/[^/]*$", "", ff$path[i]), "/_") else "_"
      for (k in 1:4) out[[paste0(pre, nm, c("_latitude", "_longitude", "_altitude", "_precision")[k])]] <-
          suppressWarnings(as.numeric(sapply(xy, function(p) if (length(p) >= k) p[k] else NA)))
      next
    }
    if (ff$type[i] == "image") { out[[h]] <- v; out[[paste0(h, "_URL")]] <- ifelse(is.na(v), NA,
        paste0("https://kc.kobotoolbox.org/media/original?media_file=demo%2Fattachments%2F", v)); next }
    out[[h]] <- v
  }
  out <- as.data.frame(out, check.names = FALSE, stringsAsFactors = FALSE)
  if (container == "main") {
    for (m in META_MAIN[META_MAIN != "_index"]) out[[m]] <- d[[m]] %||% NA
    out[["_index"]] <- seq_len(nrow(d))
  } else {
    par <- repeat_parents(form)[[container]]
    root_row <- function(cn, r) {          # main row of each repeat row
      while (cn != "main") { r <- data[[cn]]$.parent[r]; cn <- repeat_parents(form)[[cn]] }
      r
    }
    rr <- root_row(container, seq_len(nrow(d)))
    main <- data$main
    out[["_index"]] <- seq_len(nrow(d))
    out[["_parent_table_name"]] <- if (par == "main") sheet_title(form) else par
    out[["_parent_index"]] <- d$.parent
    out[["_submission__id"]] <- main[["_id"]][rr]
    out[["_submission__uuid"]] <- main[["_uuid"]][rr]
    out[["_submission__submission_time"]] <- main[["_submission_time"]][rr]
    out[["_submission__validation_status"]] <- main[["_validation_status"]][rr]
    out[["_submission__notes"]] <- NA
    out[["_submission__status"]] <- main[["_status"]][rr]
    out[["_submission__submitted_by"]] <- main[["_submitted_by"]][rr]
    out[["_submission___version__"]] <- main[["__version__"]][rr]
    out[["_submission__tags"]] <- NA
  }
  out
}
sheet_title <- function(form) {
  t <- form$settings$form_title[1] %||% "data"
  substr(gsub("[\\[\\]:*?/\\\\]", "", t), 1, 31)
}
kobo_flat <- function(data, form, headers = "xml", groups = TRUE, lang = NULL)
  kobo_table(data, form, "main", headers, groups, lang)

kobo_export <- function(data, form, file, headers = "xml", groups = TRUE, lang = NULL) {
  sheets <- list(); sheets[[sheet_title(form)]] <- kobo_table(data, form, "main", headers, groups, lang)
  for (r in names(repeat_parents(form))) sheets[[substr(r, 1, 31)]] <- kobo_table(data, form, r, headers, groups, lang)
  writexl::write_xlsx(sheets, file, format_headers = TRUE)
  invisible(sheets)
}

# ---- fake submission metadata --------------------------------------------------
fake_meta <- function(n, start_date, end_date, enumerators, versions, seed_shift = 0) {
  dates <- sort(as.Date(start_date) + sample(0:as.integer(as.Date(end_date) - as.Date(start_date)), n, TRUE))
  hex <- function(k) paste(sample(c(0:9, letters[1:6]), k, TRUE), collapse = "")
  uuid <- replicate(n, paste(hex(8), hex(4), paste0("4", hex(3)), paste0(sample(c("8", "9", "a", "b"), 1), hex(3)), hex(12), sep = "-"))
  t0 <- sprintf("%02d:%02d:%02d", sample(7:11, n, TRUE), sample(0:59, n, TRUE), sample(0:59, n, TRUE))
  sub_time <- paste0(format(dates + sample(0:3, n, TRUE, prob = c(.5, .3, .15, .05))), "T", sprintf("%02d", sample(14:20, n, TRUE)), ":", sprintf("%02d", sample(0:59, n, TRUE)), ":", sprintf("%02d", sample(0:59, n, TRUE)))
  st_dt <- paste0(format(dates), "T", t0, ".000+03:00")
  en_dt <- paste0(format(dates), "T", format(as.POSIXct(paste(dates, t0), tz = "UTC") + sample(240:1500, n, TRUE), "%H:%M:%S"), ".000+03:00")
  list(date = dates, start = st_dt, end = en_dt, today = format(dates),
       deviceid = paste0("collect:", replicate(n, paste(sample(c(LETTERS, 0:9), 16, TRUE), collapse = ""))),
       `_id` = 410000000 + seq_len(n) * 37 + seed_shift, `_uuid` = uuid, `_submission_time` = sub_time,
       `_validation_status` = rep(NA, n), `_status` = "submitted_via_web",
       `_submitted_by` = sample(enumerators, n, TRUE),
       `__version__` = versions)
}
add_meta <- function(df, meta) {
  for (k in c("_id", "_uuid", "_submission_time", "_validation_status", "_status", "_submitted_by", "__version__"))
    df[[k]] <- rep_len(if (is.null(meta[[k]])) NA else meta[[k]], nrow(df))
  df
}
pick_multi <- function(options, probs, n, min1 = TRUE) {
  sapply(seq_len(n), function(i) {
    s <- options[runif(length(options)) < probs]
    if (min1 && !length(s)) s <- options[which.max(probs)]
    paste(s, collapse = " ")
  })
}

# =============================================================================
# LEVEL 1 FORMS
# =============================================================================
VILLAGES <- C("village", c("ambolimailaka", "ifaty", "mangily", "madiorano", "andrevo"),
  data.frame(fr = c("Ambolimailaka", "Ifaty", "Mangily", "Madiorano", "Andrevo"),
             en = c("Ambolimailaka", "Ifaty", "Mangily", "Madiorano", "Andrevo"),
             mg = c("Ambolimailaka", "Ifaty", "Mangily", "Madiorano", "Andrevo")))
ENGINS <- C("engin", c("ligne", "filet_maillant", "fusil", "senne", "glanage"),
  data.frame(fr = c("Ligne à main", "Filet maillant", "Fusil harpon", "Senne de plage", "Pêche à pied (glanage)"),
             en = c("Hand line", "Gillnet", "Speargun", "Beach seine", "Gleaning (on foot)"),
             mg = c("Taritarika", "Harato", "Basim-panjonoana", "Kaokobe", "Fihaza an-tongotra")))
ESPECES <- C("espece", c("poulpe", "poisson_recif", "calmar", "langouste", "crabe", "holothurie"),
  data.frame(fr = c("Poulpe", "Poissons de récif", "Calmar", "Langouste", "Crabe", "Holothurie"),
             en = c("Octopus", "Reef fish", "Squid", "Spiny lobster", "Crab", "Sea cucumber"),
             mg = c("Horita", "Trondro haran-dranomasina", "Angisy", "Oramena", "Drakaka", "Zanga")))

form_landing <- function(multilingual = FALSE) {
  L <- function(fr, en, mg) if (multilingual) c(fr = fr, en = en, mg = mg) else fr
  sv <- list(
    S("start", "start"), S("end", "end"), S("today", "today"), S("deviceid", "deviceid"),
    S("note", "intro", L("**Fiche de débarquement** — une fiche par pirogue, au retour de pêche.",
                         "**Landing form** — one form per canoe, when it comes back from fishing.",
                         "**Taratasy fanaraha-maso ny trondro tonga** — taratasy iray isaky ny lakana.")),
    S("date", "date_debarq", L("Date du débarquement", "Landing date", "Daty nahatongavana"), required = "yes",
      hint = L("Jour du retour de pêche", "Day the canoe came back", "Andro niverenana avy nanjono")),
    S("select_one village", "village", L("Village", "Village", "Tanàna"), required = "yes"),
    S("text", "nom_pecheur", L("Nom du chef de pirogue", "Name of the canoe captain", "Anaran'ny tompon-dakana"), required = "yes"),
    S("integer", "age", L("Âge du chef de pirogue (années)", "Age of the canoe captain (years)", "Taonan'ny tompon-dakana"),
      hint = L("Si la personne ne sait pas, estimez", "If the person does not know, estimate", "Raha tsy fantany dia vinavinao")),
    S("integer", "nb_pecheurs", L("Nombre de pêcheurs à bord", "Number of fishers on board", "Isan'ny mpanjono tao anaty lakana"), required = "yes"),
    S("select_one engin", "engin", L("Engin principal", "Main fishing gear", "Fitaovana fanjonoana lehibe"), required = "yes"),
    S("select_multiple espece", "especes", L("Espèces débarquées", "Species landed", "Karazana azo"), required = "yes",
      hint = L("Cochez toutes les espèces présentes", "Tick all the species present", "Mariho daholo ireo karazana azo")),
    S("decimal", "poids_total", L("Poids total débarqué (kg)", "Total weight landed (kg)", "Lanjan'ny azo rehetra (kg)"), required = "yes",
      hint = L("Pesé avec la balance de la coopérative", "Weighed with the cooperative's scale", "Nolanjaina tamin'ny mizanan'ny kaoperativa")),
    S("geopoint", "gps", L("Position du site de débarquement", "Location of the landing site", "Toerana nahatongavana (GPS)")),
    S("image", "photo", L("Photo de la capture", "Photo of the catch", "Sarin'ny azo"), parameters = "max-pixels=1024"),
    S("text", "remarque", L("Remarques", "Remarks", "Fanamarihana")))
  ch <- list(VILLAGES, ENGINS, ESPECES)
  if (!multilingual) ch <- lapply(ch, function(d) { d$label <- d[["label::Français (fr)"]]; d[c("list_name", "name", "label")] })
  st <- data.frame(form_title = "Fiche de débarquement", form_id = "debarquement_ranobe", version = "2026-01-v1",
                   stringsAsFactors = FALSE)
  if (multilingual) st$default_language <- "Français (fr)"
  xlsform(sv, ch, st)
}
form_landing_to_translate <- function() {
  f <- form_landing()
  names(f$survey)[names(f$survey) == "label"] <- "label::Français (fr)"
  names(f$survey)[names(f$survey) == "hint"]  <- "hint::Français (fr)"
  f$survey[["label::Malagasy (mg)"]] <- ""
  f$survey[["hint::Malagasy (mg)"]] <- ""
  names(f$choices)[names(f$choices) == "label"] <- "label::Français (fr)"
  f$choices[["label::Malagasy (mg)"]] <- ""
  f
}

# Six deliberate errors (the page lists them in the solution)
form_with_errors <- function() {
  f <- form_landing()
  s <- f$survey
  s$name[s$name == "nom_pecheur"] <- "nom pecheur"            # 1 space in a name
  s$name[s$name == "nb_pecheurs"] <- "age"                    # 2 duplicate name
  s$type[s$type == "select_one engin"] <- "select_one engins" # 3 list not in choices
  s$type[s$name == "age"][1] <- "integr"                      # 4 unknown type
  s$name[s$name == "poids_total"] <- "1_poids"                # 5 name starts with a digit
  f$survey <- s
  ch <- f$choices
  ch$name[ch$list_name == "village" & ch$name == "madiorano"] <- "ifaty"   # 6 duplicate choice name
  f$choices <- ch
  f
}
ERRORS_K04 <- data.frame(
  row = NA, sheet = c("survey", "survey", "survey", "survey", "survey", "choices"),
  what_fr = c("nom avec un espace", "nom en double", "liste absente de choices", "type inconnu",
              "nom qui commence par un chiffre", "choix en double dans une liste"),
  stringsAsFactors = FALSE)

sim_landings <- function() {
  set.seed(2026)
  n <- 120
  ver <- c(rep("2026-01-v1", 46), rep("2026-02-v2", n - 46))
  m <- fake_meta(n, "2026-01-05", "2026-03-27", c("enq_fara", "enq_tojo", "enq_mamy"), ver)
  vil <- sample(VILLAGES$name, n, TRUE, prob = c(.3, .22, .18, .18, .12))
  eng <- sample(ENGINS$name, n, TRUE, prob = c(.34, .26, .14, .1, .16))
  sp <- sapply(eng, function(e) {
    p <- switch(e, ligne = c(.15, .85, .3, .02, .05, 0), filet_maillant = c(.1, .9, .2, .05, .2, 0),
                fusil = c(.55, .7, .1, .25, .05, .05), senne = c(.02, .8, .5, 0, .1, 0),
                glanage = c(.9, .05, .05, 0, .35, .3))
    pick_multi(ESPECES$name, p, 1)
  })
  nb <- ifelse(eng %in% c("senne"), sample(4:8, n, TRUE), ifelse(eng == "glanage", 1L, sample(1:3, n, TRUE)))
  w <- round(rlnorm(n, log(ifelse(eng == "senne", 38, ifelse(eng == "glanage", 4, 11))), .55), 1)
  age <- sample(17:68, n, TRUE); age[sample(n, 7)] <- NA
  lat <- round(-23.15 + runif(n, -.09, .09), 6); lon <- round(43.61 + runif(n, -.02, .02), 6)
  gps <- paste(lat, lon, round(runif(n, 0, 12), 1), round(runif(n, 3, 15), 1)); gps[sample(n, 9)] <- NA
  noms <- c("Rasoa", "Tsimihety", "Bezara", "Velo", "Manjary", "Fanomezana", "Tovo", "Zafy", "Lahatra", "Mahasoa",
            "Rivo", "Faly", "Botra", "Soja", "Tahina", "Andry")
  photo <- ifelse(runif(n) < .8, paste0("IMG_", 2026010 + seq_len(n), ".jpg"), NA)
  rem <- rep(NA, n); rem[sample(n, 10)] <- sample(c("Mer agitée", "Balance en panne, poids estimé", "Retour tardif",
                                                  "Pirogue empruntée", "Vente directe sur la plage"), 10, TRUE)
  main <- data.frame(start = m$start, end = m$end, today = m$today, deviceid = m$deviceid,
    date_debarq = format(m$date), village = vil, nom_pecheur = sample(noms, n, TRUE), age = age,
    nb_pecheurs = nb, engin = eng, especes = unname(sp), poids_total = w, gps = gps, photo = photo,
    remarque = rem, stringsAsFactors = FALSE)
  main <- add_meta(main, m)
  main$`_validation_status` <- ifelse(runif(n) < .35, "Approved", NA)
  # version 2 added "crabe": version-1 forms never contain it
  main$especes[main$`__version__` == "2026-01-v1"] <- sapply(main$especes[main$`__version__` == "2026-01-v1"], function(x) {
    p <- setdiff(strsplit(x, " ")[[1]], "crabe"); if (!length(p)) "poisson_recif" else paste(p, collapse = " ") })
  list(main = main)
}

# ---- Practice session (Level 1) -------------------------------------------------
form_practice_seagrass <- function() {
  sv <- list(S("start", "start"), S("end", "end"),
    S("date", "date_suivi", "Date du suivi", required = "yes"),
    S("select_one station", "station", "Station", required = "yes"),
    S("integer", "quadrat", "Numéro du quadrat (1 à 10)", required = "yes"),
    S("select_one espece_h", "espece_dominante", "Espèce d'herbier dominante", required = "yes"),
    S("integer", "recouvrement", "Recouvrement de l'herbier (%)", required = "yes", hint = "Estimation visuelle dans le quadrat de 50 × 50 cm"),
    S("decimal", "hauteur_canopee", "Hauteur de la canopée (cm)"),
    S("select_multiple menace", "menaces", "Menaces observées", hint = "Plusieurs réponses possibles"),
    S("text", "observateur", "Observateur", required = "yes"))
  ch <- list(C("station", c("st1", "st2", "st3", "st4"), c("Ambolimailaka nord", "Ambolimailaka sud", "Ifaty lagon", "Mangily récif")),
             C("espece_h", c("thalassia", "syringodium", "cymodocea", "halodule"), c("Thalassia hemprichii", "Syringodium isoetifolium", "Cymodocea serrulata", "Halodule uninervis")),
             C("menace", c("aucune", "pietinement", "filet", "sediment", "algues"), c("Aucune", "Piétinement", "Traces de filet", "Envasement", "Prolifération d'algues")))
  xlsform(sv, ch, data.frame(form_title = "Suivi herbiers", form_id = "suivi_herbiers", version = "1"))
}
sim_practice_seagrass <- function() {
  set.seed(77); n <- 64
  m <- fake_meta(n, "2026-02-02", "2026-02-20", c("obs_lova", "obs_haja"), "1")
  st <- rep(c("st1", "st2", "st3", "st4"), each = 16)
  cov <- pmin(100, pmax(0, round(rnorm(n, c(st1 = 62, st2 = 45, st3 = 71, st4 = 30)[st], 15))))
  main <- data.frame(start = m$start, end = m$end, date_suivi = format(m$date), station = st,
    quadrat = rep(1:16, 4) %% 10 + 1, espece_dominante = sample(c("thalassia", "syringodium", "cymodocea", "halodule"), n, TRUE, c(.45, .2, .25, .1)),
    recouvrement = cov, hauteur_canopee = round(rnorm(n, 14, 4), 1),
    menaces = pick_multi(c("pietinement", "filet", "sediment", "algues"), c(.3, .12, .2, .15), n, FALSE),
    observateur = sample(c("Lova", "Haja"), n, TRUE), stringsAsFactors = FALSE)
  main$menaces[main$menaces == ""] <- "aucune"
  main$hauteur_canopee[sample(n, 5)] <- NA
  list(main = add_meta(main, m))
}
form_practice1_errors <- function() {
  f <- form_practice_seagrass()
  s <- f$survey
  s$type[s$name == "station"] <- "select_one stations"        # 1 list not in choices
  s$name[s$name == "hauteur_canopee"] <- "hauteur canopee"     # 2 space in a name
  s$type[s$name == "menaces"] <- "select_multipe menace"       # 3 unknown type (typo)
  s$name[s$name == "observateur"] <- "quadrat"                 # 4 duplicate name
  f$survey <- s
  f$settings$form_id <- "suivi-herbiers-v1"                   # not an error (hyphens are allowed)
  f
}

# ---- Level 1 final project: octopus gleaning — the paper "test interviews" -------
FICHES_K07 <- data.frame(
  fiche = 1:8,
  date = c("2026-03-02", "2026-03-02", "2026-03-03", "2026-03-03", "2026-03-04", "2026-03-04", "2026-03-05", "2026-03-05"),
  village = c("Ambolimailaka", "Ambolimailaka", "Ifaty", "Ifaty", "Mangily", "Madiorano", "Madiorano", "Ambolimailaka"),
  nom = c("Soa", "Velontiana", "Zaramanana", "Fela", "Tsiry", "Masy", "Noro", "Lalao"),
  sexe = c("Femme", "Femme", "Femme", "Homme", "Homme", "Femme", "Femme", "Femme"),
  age = c(34, 51, 27, 19, 45, 38, NA, 62),
  heures = c(3, 4, 2.5, 3, 5, 3.5, 2, 4),
  nb_poulpes = c(4, 6, 2, 0, 9, 3, 1, 5),
  poids = c(3.2, 5.1, 1.4, 0, 8.6, 2.2, 0.7, 4.0),
  outils = c("Bâton crochet ; Seau", "Bâton crochet", "Bâton crochet ; Masque", "Masque", "Fusil harpon ; Masque", "Bâton crochet ; Seau", "Seau", "Bâton crochet ; Seau"),
  vente = c("Collecteur", "Collecteur", "Consommation familiale", "Pas de capture", "Collecteur", "Marché", "Consommation familiale", "Marché"),
  stringsAsFactors = FALSE)

# =============================================================================
# LEVEL 2 FORMS
# =============================================================================
form_calculate <- function() {
  sv <- list(
    S("text", "num_pirogue", "Numéro de la pirogue", required = "yes", hint = "Peint sur la coque, ex. AMB-014"),
    S("select_one village", "village", "Village", required = "yes"),
    S("integer", "annee_naissance", "Année de naissance du chef de pirogue"),
    S("calculate", "age", "", calculation = "int(format-date(today(), '%Y')) - ${annee_naissance}"),
    S("integer", "nb_pecheurs", "Nombre de pêcheurs", required = "yes"),
    S("decimal", "poids_poulpe", "Poids de poulpe vendu (kg)", required = "yes"),
    S("integer", "prix_kg", "Prix payé par le collecteur (Ariary/kg)", required = "yes"),
    S("calculate", "valeur", "", calculation = "${poids_poulpe} * ${prix_kg}"),
    S("calculate", "part_pecheur", "", calculation = "round(${valeur} div ${nb_pecheurs}, 0)"),
    S("calculate", "classe_capture", "", calculation = "if(${poids_poulpe} >= 10, 'grosse', if(${poids_poulpe} >= 3, 'moyenne', 'petite'))"),
    S("calculate", "code_fiche", "", calculation = "concat(${village}, '-', ${num_pirogue}, '-', format-date(today(), '%Y%m%d'))"),
    S("note", "resume", "Valeur de la vente : ${valeur} Ar — part par pêcheur : ${part_pecheur} Ar — capture ${classe_capture} — âge du chef : ${age} ans"))
  ch <- list(C("village", VILLAGES$name, VILLAGES[["label::Français (fr)"]]))
  xlsform(sv, ch, data.frame(form_title = "Vente de poulpe", form_id = "vente_poulpe", version = "1"))
}
calc_examples <- function() {   # inputs of the quiz of Session I0, and their results
  d <- data.frame(poids = c(12.4, 2.5, 7), prix = c(9000, 8500, 9200), nb = c(3, 1, 4))
  d$valeur <- d$poids * d$prix
  d$part <- round(d$valeur / d$nb)
  d$classe <- ifelse(d$poids >= 10, "grosse", ifelse(d$poids >= 3, "moyenne", "petite"))
  d
}

form_relevant_start <- function() {
  sv <- list(
    S("select_one oui_non", "peche", "Pratiquez-vous la pêche ?", required = "yes"),
    S("select_multiple engin", "engins", "Quels engins utilisez-vous ?", required = "yes"),
    S("text", "engin_autre", "Précisez l'autre engin"),
    S("integer", "jours_semaine", "Combien de jours par semaine allez-vous en mer ?", required = "yes"),
    S("select_one oui_non", "pirogue", "Possédez-vous une pirogue ?", required = "yes"),
    S("select_one type_pirogue", "type_pirogue", "Type de pirogue"),
    S("integer", "nb_enfants", "Nombre d'enfants de moins de 15 ans dans le ménage", required = "yes"),
    S("integer", "nb_scolarises", "Combien de ces enfants vont à l'école ?"))
  ch <- list(C("oui_non", c("oui", "non"), c("Oui", "Non")),
             C("engin", c(ENGINS$name, "autre"), c(ENGINS[["label::Français (fr)"]], "Autre")),
             C("type_pirogue", c("monoxyle", "balancier", "moteur"), c("Monoxyle sans balancier", "Pirogue à balancier", "Pirogue à moteur")))
  xlsform(sv, ch, data.frame(form_title = "Ménage — pêche", form_id = "menage_peche_relevant", version = "1"))
}
form_constraint_errors <- function() {
  sv <- list(
    S("integer", "age", "Âge du répondant", required = "yes", constraint = ". >= 15 and . <= 99",
      constraint_message = "L'âge doit être compris entre 15 et 99 ans"),
    S("integer", "jours_semaine", "Jours de pêche par semaine", constraint = ". > 0 or . < 7",
      constraint_message = "Entre 0 et 7 jours"),
    S("decimal", "poids", "Poids débarqué (kg)", constraint = ". >= 0 and . <= 500"),
    S("date", "date_enquete", "Date de l'enquête", constraint = ". <= today()",
      constraint_message = "La date ne peut pas être dans le futur"),
    S("text", "telephone", "Téléphone", constraint = "regex(., '^03[2-9][0-9]{7}$')",
      constraint_message = "10 chiffres, commence par 03 (ex. 0341234567)"),
    S("integer", "nb_adultes", "Nombre d'adultes", required = "yes"),
    S("integer", "nb_enfants", "Nombre d'enfants", required = "yes"),
    S("integer", "taille_menage", "Taille totale du ménage", constraint = "${taille_menage} = ${nb_adultes} + ${nb_enfants}",
      constraint_message = "Doit être égal à adultes + enfants"),
    S("integer", "prix_kg", "Prix du poulpe (Ar/kg)", constraint = ". >= 3000 and <= 20000",
      constraint_message = "Entre 3 000 et 20 000 Ar"))
  xlsform(sv, NULL, data.frame(form_title = "Contraintes à corriger", form_id = "contraintes", version = "1"))
}

PROBLEMES <- C("probleme", c("baisse_captures", "prix_bas", "meteo", "conflits", "acces_marche"),
  c("Baisse des captures", "Prix de vente trop bas", "Mauvais temps plus fréquent", "Conflits entre pêcheurs", "Accès difficile au marché"))
form_household <- function() {
  sv <- list(
    S("start", "start"), S("end", "end"), S("today", "today"),
    S("begin_group", "identification", "Identification", appearance = "field-list"),
    S("select_one enqueteur", "enqueteur", "Enquêteur", required = "yes"),
    S("select_one village", "village", "Village", required = "yes"),
    S("date", "date_enquete", "Date de l'enquête", required = "yes", constraint = ". <= today()",
      constraint_message = "La date ne peut pas être dans le futur"),
    S("end_group"),
    S("begin_group", "menage", "Le ménage"),
    S("select_one sexe", "chef_sexe", "Sexe du chef de ménage", required = "yes"),
    S("integer", "chef_age", "Âge du chef de ménage", required = "yes", constraint = ". >= 15 and . <= 100",
      constraint_message = "Entre 15 et 100 ans"),
    S("integer", "nb_membres", "Nombre de personnes dans le ménage (chef compris)", required = "yes",
      constraint = ". >= 1 and . <= 20", constraint_message = "Entre 1 et 20"),
    S("begin_repeat", "membres", "Membre du ménage", repeat_count = "${nb_membres}"),
    S("calculate", "num_membre", "", calculation = "position(..)"),
    S("text", "prenom", "Prénom du membre ${num_membre}", required = "yes"),
    S("select_one sexe", "sexe", "Sexe", required = "yes"),
    S("integer", "age_membre", "Âge (années révolues)", required = "yes", constraint = ". >= 0 and . <= 110"),
    S("select_one oui_non", "scolarise", "Va à l'école ?", required = "yes", relevant = "${age_membre} >= 6 and ${age_membre} <= 17"),
    S("select_one activite", "activite", "Activité principale", required = "yes", relevant = "${age_membre} >= 15"),
    S("calculate", "est_enfant", "", calculation = "if(${age_membre} < 15, 1, 0)"),
    S("end_repeat"),
    S("calculate", "nb_enfants", "", calculation = "sum(${est_enfant})"),
    S("note", "note_enfants", "Ce ménage compte ${nb_enfants} enfant(s) de moins de 15 ans."),
    S("end_group"),
    S("begin_group", "peche", "La pêche"),
    S("select_one oui_non", "pratique_peche", "Le ménage pratique-t-il la pêche ?", required = "yes"),
    S("select_multiple engin", "engins", "Engins utilisés", required = "yes", relevant = "${pratique_peche} = 'oui'"),
    S("integer", "jours_semaine", "Jours de pêche par semaine", relevant = "${pratique_peche} = 'oui'", required = "yes",
      constraint = ". >= 0 and . <= 7", constraint_message = "Entre 0 et 7"),
    S("integer", "revenu_peche", "Revenu mensuel de la pêche (Ariary)", relevant = "${pratique_peche} = 'oui'",
      constraint = ". >= 0"),
    S("integer", "revenu_autre", "Revenu mensuel des autres activités (Ariary)", constraint = ". >= 0"),
    S("calculate", "revenu_total", "", calculation = "coalesce(${revenu_peche}, 0) + coalesce(${revenu_autre}, 0)"),
    S("end_group"),
    S("begin_group", "avis", "Avis"),
    S("rank probleme", "problemes", "Classez les problèmes du plus important (en haut) au moins important"),
    S("select_one accord", "avis_amp", "« L'aire marine protégée profite à mon ménage »", required = "yes", appearance = "likert"),
    S("end_group"))
  ch <- list(C("enqueteur", c("fara", "tojo", "mamy"), c("Fara", "Tojo", "Mamy")),
             C("village", VILLAGES$name, VILLAGES[["label::Français (fr)"]]),
             C("sexe", c("f", "m"), c("Femme", "Homme")),
             C("oui_non", c("oui", "non"), c("Oui", "Non")),
             C("activite", c("peche", "algoculture", "commerce", "agriculture", "autre", "sans"), c("Pêche", "Algoculture", "Commerce", "Agriculture", "Autre", "Sans activité")),
             C("engin", ENGINS$name, ENGINS[["label::Français (fr)"]]),
             PROBLEMES,
             C("accord", c("1", "2", "3", "4", "5"), c("Pas du tout d'accord", "Plutôt pas d'accord", "Neutre", "Plutôt d'accord", "Tout à fait d'accord")))
  xlsform(sv, ch, data.frame(form_title = "Enquête ménages pêche", form_id = "menages_peche_2026", version = "2026-04-v1"))
}
sim_households <- function() {
  set.seed(415); n <- 80
  m <- fake_meta(n, "2026-04-06", "2026-04-24", c("enq_fara", "enq_tojo", "enq_mamy"), "2026-04-v1")
  nb <- pmin(12, rpois(n, 4.2) + 1)
  peche <- ifelse(runif(n) < .82, "oui", "non")
  rev_p <- ifelse(peche == "oui", round(rlnorm(n, log(240000), .5), -3), NA)
  rev_a <- round(rlnorm(n, log(90000), .8), -3); rev_a[sample(n, 14)] <- NA
  prob <- sapply(1:n, function(i) paste(sample(PROBLEMES$name, 5, prob = c(.35, .25, .2, .08, .12)), collapse = " "))
  main <- data.frame(start = m$start, end = m$end, today = m$today,
    enqueteur = sub("enq_", "", m$`_submitted_by`), village = sample(VILLAGES$name, n, TRUE, c(.3, .25, .2, .15, .1)),
    date_enquete = format(m$date), chef_sexe = sample(c("f", "m"), n, TRUE, c(.27, .73)),
    chef_age = sample(20:75, n, TRUE), nb_membres = nb, nb_enfants = NA,
    pratique_peche = peche,
    engins = ifelse(peche == "oui", pick_multi(ENGINS$name, c(.5, .35, .15, .1, .2), n), NA),
    jours_semaine = ifelse(peche == "oui", sample(2:7, n, TRUE), NA),
    revenu_peche = rev_p, revenu_autre = rev_a,
    revenu_total = ifelse(is.na(rev_p), 0, rev_p) + ifelse(is.na(rev_a), 0, rev_a),
    problemes = prob, avis_amp = as.character(sample(1:5, n, TRUE, c(.08, .14, .2, .38, .2))), stringsAsFactors = FALSE)
  main <- add_meta(main, m)
  prenoms_f <- c("Soa", "Noro", "Lalao", "Masy", "Fela", "Tiana", "Vola", "Hanta", "Nirina", "Faly")
  prenoms_m <- c("Tovo", "Rivo", "Zafy", "Botra", "Tsiry", "Andry", "Mahery", "Jao", "Lova", "Rado")
  mem <- do.call(rbind, lapply(1:n, function(i) {
    k <- nb[i]
    sx <- c(main$chef_sexe[i], sample(c("f", "m"), k - 1, TRUE))
    ag <- c(main$chef_age[i], if (k > 1) sample(c(0:17, 0:17, 18:60), k - 1, TRUE))
    data.frame(.parent = i, num_membre = seq_len(k),
      prenom = ifelse(sx == "f", sample(prenoms_f, k, TRUE), sample(prenoms_m, k, TRUE)), sexe = sx, age_membre = ag,
      scolarise = ifelse(ag >= 6 & ag <= 17, sample(c("oui", "non"), k, TRUE, c(.68, .32)), NA),
      activite = ifelse(ag >= 15, sample(c("peche", "algoculture", "commerce", "agriculture", "autre", "sans"), k, TRUE, c(.42, .15, .12, .08, .08, .15)), NA),
      est_enfant = as.integer(ag < 15), stringsAsFactors = FALSE)
  }))
  main$nb_enfants <- tapply(mem$est_enfant, factor(mem$.parent, levels = 1:n), sum)
  list(main = main, membres = mem)
}

# ---- Level 2 final project: the paper interviews (fishers and their trips) -------
FICHES_I07 <- list(
  pecheurs = data.frame(fiche = 1:5, village = c("Ifaty", "Ifaty", "Mangily", "Ambolimailaka", "Madiorano"),
    nom = c("Bezara", "Lahatra", "Manjary", "Tovo", "Velo"), annee_naissance = c(1979, 1995, 1968, 2001, 1986),
    pirogue = c("Oui", "Non", "Oui", "Oui", "Non"), type_pirogue = c("Pirogue à balancier", "—", "Pirogue à moteur", "Pirogue à balancier", "—"),
    nb_sorties = c(3, 2, 4, 1, 2),
    classement = c("Baisse des captures > Prix bas > Mauvais temps", "Prix bas > Baisse des captures > Accès au marché",
                   "Mauvais temps > Baisse des captures > Prix bas", "Baisse des captures > Mauvais temps > Conflits",
                   "Prix bas > Accès au marché > Baisse des captures"), stringsAsFactors = FALSE),
  sorties = data.frame(fiche = c(1, 1, 1, 2, 2, 3, 3, 3, 3, 4, 5, 5), sortie = c(1, 2, 3, 1, 2, 1, 2, 3, 4, 1, 1, 2),
    engin = c("Ligne à main", "Ligne à main", "Fusil harpon", "Pêche à pied", "Pêche à pied", "Filet maillant", "Filet maillant",
              "Ligne à main", "Filet maillant", "Fusil harpon", "Ligne à main", "Pêche à pied"),
    heures = c(6, 5, 4, 3, 3.5, 8, 7, 6, 8, 5, 6, 2.5),
    poids = c(8.5, 6, 4.2, 2.1, 3.4, 22, 18.5, 9, 25.5, 6.8, 7.2, 1.6),
    prix = c(4000, 4000, 9000, 9500, 9500, 3500, 3500, 4000, 3500, 9000, 4200, 9500), stringsAsFactors = FALSE))

# =============================================================================
# LEVEL 3 — cascades, choice filters, nested repeats
# =============================================================================
admin_units <- function() {
  x <- list(
    "Atsimo-Andrefana" = list(
      "Toliara II" = c("Belalanda", "Ankililoaka", "Milenaka", "Soalara Sud", "Manombo Sud", "Saint Augustin"),
      "Morombe"    = c("Morombe", "Befandefa", "Antanimieva", "Ambahikily"),
      "Toliara I"  = c("Toliara")),
    "Menabe" = list(
      "Morondava"  = c("Morondava", "Belo sur Mer", "Bemanonga", "Analaiva"),
      "Belo sur Tsiribihina" = c("Belo sur Tsiribihina", "Tsimafana")),
    "Boeny" = list(
      "Mahajanga I"  = c("Mahajanga"),
      "Mahajanga II" = c("Belobaka", "Boanamary", "Katsepy")))
  out <- do.call(rbind, lapply(names(x), function(r) do.call(rbind, lapply(names(x[[r]]), function(d)
    data.frame(region = r, district = d, commune = x[[r]][[d]], stringsAsFactors = FALSE)))))
  out
}
slug <- function(x) {
  x <- iconv(x, "UTF-8", "ASCII//TRANSLIT"); x <- tolower(gsub("[^A-Za-z0-9]+", "_", x)); gsub("^_|_$", "", x)
}
cascade_choices <- function(adm = admin_units()) {
  reg <- unique(adm$region); dis <- unique(adm[c("region", "district")])
  rbind_fill(
    C("region", slug(reg), reg),
    C("district", slug(dis$district), dis$district, region = slug(dis$region)),
    C("commune", slug(paste(adm$district, adm$commune)), adm$commune, region = slug(adm$region), district = slug(adm$district)))
}

HABITATS <- C("habitat", c("recif", "herbier", "mangrove"), c("Récif corallien", "Herbier marin", "Mangrove"))
ESP_HAB <- data.frame(list_name = "espece_h", name = c("poulpe", "poisson_recif", "langouste", "holothurie", "oursin",
                                                    "poisson_herbier", "seiche", "crabe_mangrove", "crevette", "huitre"),
  label = c("Poulpe", "Poissons de récif", "Langouste", "Holothurie", "Oursin", "Poissons d'herbier", "Seiche", "Crabe de mangrove", "Crevette", "Huître"),
  habitat = c("recif", "recif", "recif", "herbier", "herbier", "herbier", "herbier", "mangrove", "mangrove", "mangrove"), stringsAsFactors = FALSE)
form_choice_filter <- function() {
  sv <- list(
    S("select_one habitat", "habitat", "Habitat prospecté", required = "yes"),
    S("select_one espece_h", "espece", "Espèce principale observée", required = "yes", choice_filter = "habitat = ${habitat}"),
    S("select_multiple espece_h", "especes_ciblees", "Espèces ciblées par les pêcheurs ce jour (tous habitats)", required = "yes"),
    S("select_one espece_h", "espece_principale", "Parmi elles, laquelle rapporte le plus ?", required = "yes",
      choice_filter = "selected(${especes_ciblees}, name)"))
  xlsform(sv, list(HABITATS, ESP_HAB), data.frame(form_title = "Filtres de choix", form_id = "filtres_choix", version = "1"))
}
form_cascade <- function() {
  sv <- list(
    S("select_one region", "region", "Région", required = "yes"),
    S("select_one district", "district", "District", required = "yes", choice_filter = "region = ${region}"),
    S("select_one commune", "commune", "Commune", required = "yes", choice_filter = "district = ${district}"),
    S("text", "site", "Nom du site ou du village", required = "yes"))
  xlsform(sv, list(cascade_choices()), data.frame(form_title = "Cascade administrative", form_id = "cascade_admin", version = "1"))
}

FAMILLES <- C("famille", c("acanthuridae", "chaetodontidae", "labridae", "lutjanidae", "pomacentridae", "scaridae", "serranidae", "siganidae"),
  c("Acanthuridae (chirurgiens)", "Chaetodontidae (papillons)", "Labridae (labres)", "Lutjanidae (vivaneaux)",
    "Pomacentridae (demoiselles)", "Scaridae (perroquets)", "Serranidae (mérous)", "Siganidae (sigans)"))
form_reef <- function() {
  sv <- list(
    S("start", "start"), S("end", "end"),
    S("begin_group", "localisation", "Localisation"),
    S("select_one region", "region", "Région", required = "yes"),
    S("select_one district", "district", "District", required = "yes", choice_filter = "region = ${region}"),
    S("select_one commune", "commune", "Commune", required = "yes", choice_filter = "district = ${district}"),
    S("text", "site", "Nom du site", required = "yes"),
    S("select_one statut", "statut", "Statut de protection", required = "yes"),
    S("geopoint", "gps", "Position du bateau au début de la plongée"),
    S("end_group"),
    S("begin_group", "plongee", "Plongée"),
    S("date", "date_plongee", "Date", required = "yes", constraint = ". <= today()"),
    S("select_multiple observateur", "observateurs", "Observateurs", required = "yes", constraint = "count-selected(.) >= 2",
      constraint_message = "Au moins deux plongeurs (binôme)"),
    S("integer", "visibilite", "Visibilité horizontale (m)", constraint = ". >= 0 and . <= 40"),
    S("integer", "nb_transects", "Nombre de transects réalisés", required = "yes", constraint = ". >= 1 and . <= 6"),
    S("end_group"),
    S("begin_repeat", "transects", "Transect", repeat_count = "${nb_transects}"),
    S("calculate", "num_transect", "", calculation = "position(..)"),
    S("decimal", "profondeur", "Profondeur du transect ${num_transect} (m)", required = "yes", constraint = ". > 0 and . <= 30"),
    S("integer", "corail_vivant", "Corail dur vivant (%)", required = "yes", constraint = ". >= 0 and . <= 100"),
    S("integer", "corail_mort", "Corail mort et débris (%)", required = "yes", constraint = ". >= 0 and . <= 100"),
    S("integer", "algues", "Macroalgues (%)", required = "yes", constraint = ". >= 0 and . <= 100"),
    S("integer", "sable", "Sable et roche nue (%)", required = "yes",
      constraint = "${corail_vivant} + ${corail_mort} + ${algues} + . = 100", constraint_message = "Le total des 4 catégories doit faire 100 %"),
    S("begin_repeat", "poissons", "Observation de poissons (transect ${num_transect})"),
    S("select_one famille", "famille", "Famille", required = "yes"),
    S("select_one classe_taille", "classe_taille", "Classe de taille", required = "yes"),
    S("integer", "nombre", "Nombre d'individus", required = "yes", constraint = ". >= 1"),
    S("end_repeat"),
    S("calculate", "nb_poissons_transect", "", calculation = "sum(${nombre})"),
    S("end_repeat"),
    S("calculate", "couv_moy", "", calculation = "round(sum(${corail_vivant}) div count(${num_transect}), 1)"),
    S("text", "remarques", "Remarques"))
  ch <- list(cascade_choices(),
    C("statut", c("amp_nt", "amp_reserve", "lmma", "non_protege"), c("AMP — zone d'utilisation durable", "AMP — réserve (no-take)", "LMMA / Dina communautaire", "Non protégé")),
    C("observateur", c("hery", "lova", "nomena", "rindra", "soa"), c("Hery", "Lova", "Nomena", "Rindra", "Soa")),
    FAMILLES,
    C("classe_taille", c("t0_10", "t10_20", "t20_30", "t30p"), c("< 10 cm", "10–20 cm", "20–30 cm", "> 30 cm")))
  xlsform(sv, ch, data.frame(form_title = "Suivi des récifs", form_id = "suivi_recifs_2026", version = "2026-05-v1"))
}
sim_reef <- function() {
  set.seed(531)
  sites <- data.frame(region = c("atsimo_andrefana", "atsimo_andrefana", "atsimo_andrefana", "atsimo_andrefana", "atsimo_andrefana", "atsimo_andrefana", "menabe", "menabe"),
    district = c("toliara_ii", "toliara_ii", "toliara_ii", "toliara_ii", "morombe", "morombe", "morondava", "morondava"),
    commune = c("toliara_ii_belalanda", "toliara_ii_belalanda", "toliara_ii_soalara_sud", "toliara_ii_saint_augustin", "morombe_morombe", "morombe_befandefa", "morondava_belo_sur_mer", "morondava_belo_sur_mer"),
    site = c("Ankaraiky", "Massif des roses", "Anakao récif", "Sarodrano", "Andavadoaka", "Nosy Hao", "Kivalo", "Lohatany"),
    statut = c("amp_reserve", "amp_nt", "lmma", "non_protege", "lmma", "lmma", "amp_nt", "non_protege"), stringsAsFactors = FALSE)
  n <- 24; idx <- rep(1:8, each = 3)
  m <- fake_meta(n, "2026-05-04", "2026-06-12", c("hery_rf", "lova_rf"), "2026-05-v1")
  base_cv <- c(amp_reserve = 42, amp_nt = 34, lmma = 30, non_protege = 21)
  main <- cbind(data.frame(start = m$start, end = m$end), sites[idx, ], stringsAsFactors = FALSE)
  main$gps <- paste(round(-23.3 + runif(n, -.6, .8), 6), round(43.6 + runif(n, -.2, .3), 6), 0, round(runif(n, 3, 9), 1))
  main$date_plongee <- format(m$date)
  main$observateurs <- pick_multi(c("hery", "lova", "nomena", "rindra", "soa"), c(.7, .6, .4, .3, .3), n)
  one <- !grepl(" ", main$observateurs); main$observateurs[one] <- paste(main$observateurs[one], "nomena")
  main$visibilite <- sample(6:22, n, TRUE)
  main$nb_transects <- sample(2:4, n, TRUE, c(.2, .5, .3))
  tr <- do.call(rbind, lapply(1:n, function(i) {
    k <- main$nb_transects[i]
    cv <- pmax(2, round(rnorm(k, base_cv[main$statut[i]], 8)))
    cm <- round(runif(k, 5, 25)); al <- round(runif(k, 3, 25)); sa <- 100 - cv - cm - al
    data.frame(.parent = i, num_transect = 1:k, profondeur = round(runif(k, 3, 14), 1),
      corail_vivant = cv, corail_mort = cm, algues = al, sable = sa, stringsAsFactors = FALSE)
  }))
  pf <- do.call(rbind, lapply(seq_len(nrow(tr)), function(j) {
    k <- sample(3:8, 1); st <- main$statut[tr$.parent[j]]
    fam <- sample(FAMILLES$name, k, prob = c(.16, .1, .14, .07, .25, .14, .06, .08))
    big <- if (st %in% c("amp_reserve", "amp_nt")) c(.2, .35, .3, .15) else c(.35, .4, .2, .05)
    cl <- vapply(fam, function(fm) {
      p <- if (fm %in% c("pomacentridae", "chaetodontidae")) c(.65, .35, 0, 0) else
           if (fm %in% c("labridae", "siganidae", "acanthuridae")) c(.25, .45, .25, .05) else big
      sample(c("t0_10", "t10_20", "t20_30", "t30p"), 1, prob = p) }, "")
    data.frame(.parent = j, famille = fam, classe_taille = cl,
               nombre = ifelse(fam == "pomacentridae", sample(8:60, k, TRUE), sample(1:15, k, TRUE)), stringsAsFactors = FALSE)
  }))
  tr$nb_poissons_transect <- tapply(pf$nombre, factor(pf$.parent, levels = seq_len(nrow(tr))), sum)
  main$couv_moy <- round(tapply(tr$corail_vivant, factor(tr$.parent, levels = 1:n), mean), 1)
  main$remarques <- NA; main$remarques[c(5, 17)] <- c("Courant fort, transect 3 écourté", "Blanchissement léger observé")
  main <- add_meta(main, m)
  list(main = main, transects = tr, poissons = pf)
}

# ---- Level 3 practice: fishers, trips, catches (nested) ---------------------------
form_practice_adv <- function() {
  sv <- list(
    S("begin_group", "id", "Identification"),
    S("select_one region", "region", "Région", required = "yes"),
    S("select_one district", "district", "District", required = "yes", choice_filter = "region = ${region}"),
    S("select_one commune", "commune", "Commune", required = "yes", choice_filter = "district = ${district}"),
    S("text", "pecheur", "Nom du pêcheur", required = "yes"),
    S("end_group"),
    S("begin_repeat", "sorties", "Sortie de pêche"),
    S("date", "date_sortie", "Date de la sortie", required = "yes"),
    S("select_one engin", "engin", "Engin", required = "yes"),
    S("begin_repeat", "captures", "Capture"),
    S("select_one espece", "espece", "Espèce", required = "yes"),
    S("decimal", "poids", "Poids (kg)", required = "yes"),
    S("end_repeat"),
    S("end_repeat"))
  ch <- list(cascade_choices(), C("engin", ENGINS$name, ENGINS[["label::Français (fr)"]]),
             C("espece", ESPECES$name, ESPECES[["label::Français (fr)"]]))
  xlsform(sv, ch, data.frame(form_title = "Carnet de pêche", form_id = "carnet_peche", version = "1"))
}
sim_practice_adv <- function() {
  set.seed(606); n <- 30
  m <- fake_meta(n, "2026-06-01", "2026-06-20", c("enq_fara", "enq_mamy"), "1")
  com <- sample(c("toliara_ii_belalanda", "toliara_ii_milenaka", "morombe_befandefa", "morondava_belo_sur_mer"), n, TRUE)
  adm <- cascade_choices(); cc <- adm[adm$list_name == "commune", ]
  main <- data.frame(region = cc$region[match(com, cc$name)], district = cc$district[match(com, cc$name)], commune = com,
    pecheur = paste("Pêcheur", sprintf("%02d", 1:n)), stringsAsFactors = FALSE)
  main <- add_meta(main, m)
  so <- do.call(rbind, lapply(1:n, function(i) { k <- sample(1:4, 1)
    data.frame(.parent = i, date_sortie = format(as.Date("2026-06-01") + sort(sample(0:19, k))),
               engin = sample(ENGINS$name, k, TRUE, c(.4, .3, .1, .05, .15)), stringsAsFactors = FALSE) }))
  ca <- do.call(rbind, lapply(seq_len(nrow(so)), function(j) { k <- sample(1:3, 1)
    sp <- sample(ESPECES$name, k, prob = c(.3, .35, .12, .05, .1, .08))
    data.frame(.parent = j, espece = sp, poids = round(rlnorm(k, log(ifelse(sp == "poisson_recif", 6, 2.5)), .6), 1), stringsAsFactors = FALSE) }))
  list(main = main, sorties = so, captures = ca)
}

# ---- Level 3 final project: complete household survey ---------------------------
form_final_adv <- function() {
  h <- form_household()
  s <- h$survey
  i <- which(s$name == "village")
  casc <- rbind_fill(list(
    S("select_one region", "region", "Région", required = "yes"),
    S("select_one district", "district", "District", required = "yes", choice_filter = "region = ${region}"),
    S("select_one commune", "commune", "Commune", required = "yes", choice_filter = "district = ${district}"),
    S("text", "village", "Village ou fokontany", required = "yes")))
  s <- rbind_fill(list(s[1:(i - 1), ], casc, s[(i + 1):nrow(s), ]))
  # catches of the last 7 days: second repeat, with a choice filter on the gear used
  j <- which(s$name == "revenu_peche")
  add <- rbind_fill(list(
    S("begin_repeat", "captures", "Capture des 7 derniers jours", relevant = "${pratique_peche} = 'oui'"),
    S("select_one engin", "engin_capture", "Engin utilisé", required = "yes", choice_filter = "selected(${engins}, name)"),
    S("select_one espece", "espece", "Espèce", required = "yes"),
    S("decimal", "poids", "Poids (kg)", required = "yes", constraint = ". > 0 and . <= 300"),
    S("integer", "prix_kg", "Prix de vente (Ar/kg)", constraint = ". >= 0"),
    S("calculate", "valeur", "", calculation = "${poids} * coalesce(${prix_kg}, 0)"),
    S("end_repeat"),
    S("calculate", "valeur_semaine", "", calculation = "sum(${valeur})")))
  s <- rbind_fill(list(s[1:j, ], add, s[(j + 1):nrow(s), ]))
  ch <- h$choices; ch <- ch[ch$list_name != "village", ]
  ch <- rbind_fill(list(ch, cascade_choices(), C("espece", ESPECES$name, ESPECES[["label::Français (fr)"]])))
  xlsform(list(s), list(ch), data.frame(form_title = "Enquête ménages pêche complète", form_id = "menages_peche_complet", version = "2026-07-v1"))
}
sim_final_adv <- function() {
  b <- sim_households()
  set.seed(707)
  n <- nrow(b$main)
  com <- sample(c("toliara_ii_belalanda", "toliara_ii_milenaka", "toliara_ii_soalara_sud", "morombe_befandefa", "morondava_belo_sur_mer", "mahajanga_ii_katsepy"),
                n, TRUE, c(.25, .2, .15, .15, .15, .1))
  cc <- cascade_choices(); cc <- cc[cc$list_name == "commune", ]
  main <- b$main
  main$region <- cc$region[match(com, cc$name)]; main$district <- cc$district[match(com, cc$name)]; main$commune <- com
  main$village <- paste("Village", toupper(substr(com, nchar(com) - 2, nchar(com))), sample(1:3, n, TRUE))
  pe <- which(main$pratique_peche == "oui")
  cap <- do.call(rbind, lapply(pe, function(i) {
    eng <- strsplit(main$engins[i], " ")[[1]]; k <- sample(0:4, 1, prob = c(.1, .3, .3, .2, .1)); if (!k) return(NULL)
    e <- if (length(eng) == 1) rep(eng, k) else sample(eng, k, TRUE)
    sp <- vapply(e, function(x) switch(x, glanage = sample(c("poulpe", "holothurie", "crabe"), 1, prob = c(.7, .15, .15)),
                 fusil = sample(c("poulpe", "poisson_recif", "langouste"), 1), sample(c("poisson_recif", "calmar"), 1, prob = c(.8, .2))), "")
    w <- round(rlnorm(k, log(ifelse(sp == "poisson_recif", 7, 2.5)), .6), 1)
    pr <- unname(c(poulpe = 9000, poisson_recif = 4000, calmar = 6000, langouste = 30000, crabe = 5000, holothurie = 15000)[sp]) + sample(c(-500, 0, 500), k, TRUE)
    pr[runif(k) < .1] <- NA
    data.frame(.parent = i, engin_capture = e, espece = sp, poids = w, prix_kg = pr, valeur = w * ifelse(is.na(pr), 0, pr), stringsAsFactors = FALSE)
  }))
  main$valeur_semaine <- ifelse(main$pratique_peche == "oui", tapply(cap$valeur, factor(cap$.parent, levels = 1:n), sum), NA)
  main$valeur_semaine[main$pratique_peche == "oui" & is.na(main$valeur_semaine)] <- 0
  list(main = main, membres = b$membres, captures = cap)
}

# ---- Level 2 practice: a household form with 4 errors ------------------------------
form_l2_errors <- function() {
  f <- form_household()
  s <- f$survey
  s$relevant[s$name == "engins"] <- "${peche_pratique} = 'oui'"      # 1 unknown question in relevant
  s$calculation[s$name == "nb_enfants"] <- "sum(${est_enfants})"      # 2 unknown question in calculation
  s$type[s$name == "avis_amp"] <- "select_one acord"                  # 3 list not in choices
  s <- s[-nrow(s), ]                                                  # 4 last end_group removed
  f$survey <- s
  f$settings$form_id <- "menages_erreurs"
  f
}

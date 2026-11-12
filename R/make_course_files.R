# =============================================================================
# make_course_files.R — builds ALL the files that students download:
#   data/forms/    XLSForms (examples, starting files, files with errors)
#   data/exports/  simulated KoboToolbox exports (XLS, as KoboToolbox writes them)
#   data/fiches/   paper "test interviews" to type in during the final projects
#   data/*.zip     one zip per level
#
# Run it once (and again after any change):   source("R/make_course_files.R")
# Then rebuild the site:                        source("R/build_site.R")
#
# Every quiz answer is COMPUTED by the pages from these files (hidden chunks),
# so if you change something here, the answers follow.
# Needs: writexl, readxl (install.packages(c("writexl", "readxl")))
# =============================================================================
source("R/kobo_helpers.R")      # make_xlsform(), kobo_export() and the course data

dir.create("data/forms",   recursive = TRUE, showWarnings = FALSE)
dir.create("data/exports", recursive = TRUE, showWarnings = FALSE)
dir.create("data/fiches",  recursive = TRUE, showWarnings = FALSE)

# =============================================================================
# LEVEL 1 — BEGINNER
# =============================================================================

# ---- 1. The landing form (Sessions 2, 4, 5) ----------------------------------
f <- form_landing()                     # defined in R/kobo_helpers.R
make_xlsform(f, "data/forms/k02_debarquement.xlsx")

# ---- 2. Same form, in three languages (Session 3) -----------------------------
make_xlsform(form_landing(multilingual = TRUE), "data/forms/k03_debarquement_multilingue.xlsx")

# ---- 3. Starting file of Session 3: the form to translate -----------------------
make_xlsform(form_landing_to_translate(), "data/forms/k03_a_traduire.xlsx")

# ---- 4. A form with 6 errors (Session 4) ---------------------------------------
make_xlsform(form_with_errors(), "data/forms/k04_erreurs.xlsx")

# ---- 5. Simulated export of the landing survey (Session 5) ----------------------
ld <- sim_landings()
kobo_export(ld, form_landing(), "data/exports/k05_debarquements_labels.xlsx", headers = "labels")
kobo_export(ld, form_landing(), "data/exports/k05_debarquements_xml.xlsx",    headers = "xml")
write.csv(kobo_flat(ld, form_landing(), headers = "xml"), "data/exports/k05_debarquements_xml.csv",
          row.names = FALSE, na = "", fileEncoding = "UTF-8")

# ---- 6. Practice session (Session 6) --------------------------------------------
make_xlsform(form_practice1_errors(), "data/forms/k06_ex2_erreurs.xlsx")
pr <- sim_practice_seagrass()
kobo_export(pr, form_practice_seagrass(), "data/exports/k06_herbiers_xml.xlsx", headers = "xml")

# =============================================================================
# LEVEL 2 — INTERMEDIATE
# =============================================================================
make_xlsform(form_calculate(),      "data/forms/i00_calculs.xlsx")
make_xlsform(form_relevant_start(), "data/forms/i01_depart_relevant.xlsx")
make_xlsform(form_constraint_errors(), "data/forms/i02_contraintes_a_corriger.xlsx")
make_xlsform(form_household(),      "data/forms/i05_menage_peche.xlsx")
make_xlsform(form_l2_errors(),      "data/forms/i06_menage_erreurs.xlsx")
hh <- sim_households()
kobo_export(hh, form_household(), "data/exports/i05_menages_xml.xlsx", headers = "xml", groups = TRUE)
kobo_export(hh, form_household(), "data/exports/i03_menages_groupes_xml.xlsx", headers = "xml", groups = TRUE)
kobo_export(hh, form_household(), "data/exports/i03_menages_sans_groupes_xml.xlsx", headers = "xml", groups = FALSE)

# =============================================================================
# LEVEL 3 — ADVANCED
# =============================================================================
adm <- admin_units()
write.csv(adm, "data/forms/a02_regions_districts_communes.csv", row.names = FALSE, fileEncoding = "UTF-8")
make_xlsform(form_choice_filter(), "data/forms/a01_choice_filter.xlsx")
make_xlsform(form_cascade(),       "data/forms/a02_cascade.xlsx")
make_xlsform(form_reef(),          "data/forms/a03_suivi_recifs.xlsx")
rf <- sim_reef()
kobo_export(rf, form_reef(), "data/exports/a03_suivi_recifs_xml.xlsx",    headers = "xml", groups = TRUE)
kobo_export(rf, form_reef(), "data/exports/a03_suivi_recifs_labels.xlsx", headers = "labels", groups = TRUE)
make_xlsform(form_final_adv(),     "data/forms/a07_enquete_complete_reference.xlsx")
fa7 <- sim_final_adv()
kobo_export(fa7, form_final_adv(), "data/exports/a07_enquete_menages_xml.xlsx", headers = "xml", groups = TRUE)
pa <- sim_practice_adv()
kobo_export(pa, form_practice_adv(), "data/exports/a06_pecheurs_xml.xlsx", headers = "xml", groups = TRUE)

# =============================================================================
# Zips (one per level) — what students download on the home page
# =============================================================================
zip_level <- function(zipfile, pattern, extra = NULL) {
  files <- list.files("data", recursive = TRUE)
  files <- c(file.path("data", files[grepl(pattern, files) & !grepl("\\.zip$|reference", files)]), extra)
  if (file.exists(zipfile)) file.remove(zipfile)
  utils::zip(zipfile, files, flags = "-q9X")
}
zip_level("data/kobo_niveau1.zip", "^(forms|exports|fiches)/k0")
zip_level("data/kobo_niveau2.zip", "^(forms|exports|fiches)/i0")
zip_level("data/kobo_niveau3.zip", "^(forms|exports|fiches)/a0", extra = "templates/kobo_import.R")
message("Course files written in data/.")

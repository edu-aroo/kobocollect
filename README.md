# Collecte de données avec KoboToolbox — Data collection with KoboToolbox

*by Aroo Falinirina* — version 1.0 (2026-11)

A bilingual (EN/FR), self-study course on **KoboToolbox**, built with the same system as
*R4Marine Research*: R Markdown website, student login, saved progress, scored quizzes,
sessions that unlock at 75 %, certificates per level and a watermark. All the data are
**simulated** (Bay of Ranobe and other coastal sites of Madagascar), each with its "collection" context.

| Level | Sessions | Topics |
|---|---|---|
| Beginner (≈ 17 h) | 0–7 | account and interface, Formbuilder, XLSForm (required, hint), multilingual forms, import/deploy/collect (Enketo, KoboCollect), downloading data; practice (6) and final project (7) |
| Intermediate (≈ 20 h) | I0–I7 | calculate, relevant, constraint, group, rank, repeat; practice (I6) and final project (I7) |
| Advanced (≈ 23 h) | A0–A7 | complete form from paper to KoboToolbox, choice_filter, cascades region › district › commune, exports for analysis, groups and repeats in R (readxl, dplyr, tidyr); practice (A6) and final project (A7) |

33 quizzes (306 questions). Each level has a cheatsheet page. Slides: two decks in French for the
Beginner level (`slides/`); decks for Levels 2–3 can be added the same way.

---

## 1. What is in this folder

```
kobo-training/
├── kobo-training.Rproj          <- open this in RStudio
├── _site.yml                    <- navbar, theme, output folder (docs/), files never published
├── index.Rmd                    <- home page: one dashboard per level
├── 00-…Rmd … 07-…Rmd            <- Beginner (06 = practice, 07 = final project)
├── i00-…Rmd … i07-…Rmd          <- Intermediate
├── a00-…Rmd … a07-…Rmd          <- Advanced
├── cheatsheet*.Rmd, common-errors.Rmd, glossary.Rmd, downloads.Rmd, help.Rmd,
│   certificate.Rmd, cert-preview.Rmd, whats-new.Rmd
├── assets/
│   ├── config.js                <- THE file to edit: title, author, Google Script URL, levels, pages
│   ├── course.js / course.css   <- engine of the R course (login, progress, quizzes, certificates)
│   └── img/*.svg                <- drawings (cycle, XLSForm sheets, export sheets, cascade)
├── R/
│   ├── build_site.R             <- builds the website into docs/ (USE THIS)
│   ├── make_course_files.R      <- writes ALL the student files (XLSForms, exports, zips)
│   ├── kobo_helpers.R           <- the forms of the course, the simulators, the "Kobo exporter"
│   ├── course_helpers.R         <- quiz(), q_num(), q_mcq(), q_text(), xls(), ui(), xf(), fa()…
│   ├── ui_labels.csv            <- ALL KoboToolbox / KoboCollect button names (French, English)
│   ├── make_accounts.R, make_pdf_kit.R
├── data/forms/                  <- XLSForms given to students (examples, files with errors)
├── data/exports/                <- simulated KoboToolbox XLS exports (main sheet + repeat sheets)
├── data/kobo_niveau1/2/3.zip    <- one zip per level
├── templates/kobo_import.R      <- R helper for students: read_kobo(), shorten_names(), kobo_label(), join_parent()
├── slides/                      <- French decks of the Beginner level
├── pdf_kit/                     <- PDF version of the sessions (never published)
├── apps-script/Code.gs          <- the Google Apps Script "backend" (same as the R course)
└── docs/                        <- THE BUILT WEBSITE (what GitHub publishes)
```

## 2. Build the site

1. Open `kobo-training.Rproj` in RStudio.
2. Install once: `install.packages(c("rmarkdown", "knitr", "jsonlite", "readxl", "writexl", "dplyr", "tidyr", "stringr"))`.
3. *(Only if you change the forms or the data)* `source("R/make_course_files.R")` — rewrites
   `data/forms/`, `data/exports/` and the three zips.
4. Build: **`source("R/build_site.R")`** (renders every page, rebuilds the quiz index, `docs/.nojekyll`).
5. Open `docs/index.html`. Without a Google Script URL the site runs in **demo mode**:
   `demo` / `demo` (student, Beginner) and `teacher` / `teacher` (sees everything).

> Quiz answers are **computed by R at build time** from the files of `data/` (hidden `answers` chunks).
> If you change a form or a simulated export, the answers follow automatically.

## 3. Publish and connect the Google Sheet

Same steps as the R course (see its README, sections 3–4):

1. New GitHub repository (e.g. `kobo-course` on `edu-aroo`) → *Settings → Pages* → branch `main`, folder **`/docs`**.
2. **New** Google Sheet (not the one of the R course) → *Extensions → Apps Script* → paste `apps-script/Code.gs`.
3. In `Code.gs`: set `SITE_URL` (e.g. `"https://edu-aroo.github.io/kobo-course/"`) and check `ALERT_EMAIL`.
4. Run `setup`, then `installTriggers`; *Deploy → New deployment → Web app* (Execute as Me, Anyone) → copy the URL.
5. Paste it in `assets/config.js` → `scriptUrl`, rebuild, push. Run `testQuizIndex`.

Rules (unchanged): 2 attempts per quiz, best attempt counts, 75 % per session and per level,
sessions open one after the other, the next **level is opened by you** (column `level` of the
`students` tab, e.g. `beginner, intermediate`), help page + e-mail when a student is stuck,
`open_pages` to unblock or let a student skip sessions, `resetQuiz` for 2 new attempts.

The browser storage keys are `kobo_…` (not `rc_…`), so the R course and this course can be
open on the same GitHub Pages domain without mixing logins.

## 4. Button names: `ui()` and `R/ui_labels.csv`

Every button is written with `` `r ui("deploy")` `` → **DÉPLOYER** *(DEPLOY)*. All the labels are in
`R/ui_labels.csv`. Column `checked`: `doc` = English name taken from the official documentation
(support.kobotoolbox.org); `no` = **French name to check** in the current KoboToolbox interface.
Check them once in KoboToolbox in French, correct the CSV if needed, set `checked` to `yes`, rebuild.

## 5. The course files (`R/kobo_helpers.R`)

- Forms are written in R (`S()` = one survey row, `C()` = choices, `xlsform()`), saved with `writexl`
  (clean `.xlsx` that KoboToolbox reads; `openxlsx` files caused errors with pyxform).
- All forms were checked with **pyxform 4.5 + ODK Validate** (the converter used by KoboToolbox):
  the correct forms convert without error; the "error" files fail with the messages quoted in the
  pages (Sessions 4, 6, I6 and *Error messages*). If KoboToolbox updates pyxform, the wording may
  change slightly — re-check with a test upload.
- `kobo_export()` writes simulated exports laid out like KoboToolbox XLS exports: first sheet named
  after the form title, one sheet per repeat, `group/question` headers, 0/1 columns for
  `select_multiple`, GPS sub-columns, metadata (`_id`, `_uuid`, `_submission_time`, `_validation_status`,
  `_submitted_by`, `__version__`, `_index`) and, in repeat sheets, `_parent_table_name`,
  `_parent_index`, `_submission__…`.
- **Administrative list** (Session A2): a **partial example** (3 regions, 7 districts, 21 communes) to
  learn the method — the pages say so. Malagasy labels (Session 3) are a **draft**: please check them.

## 6. Final projects

- **Beginner (7)** and **Intermediate (I7)**: students build the form from specifications, type
  paper "test interviews" given on the page, download their own export and answer from it. If their
  form and typing are right, they get the expected answers (computed from `FICHES_K07` / `FICHES_I07`).
- **Advanced (A7)**: students build the complete form (reference: `data/forms/a07_enquete_complete_reference.xlsx`,
  shown only in the solution and excluded from the zip) and analyse the given export in R.

## 7. Slides and PDF kit

`source("slides/render_slides.R")` → `slides/deb1_seances0-3.html`, `slides/deb2_seances4-7.html`
(keys: → / Space, ←, F, O, N, Ctrl + P). PDF kit: `source("R/make_pdf_kit.R"); make_pdf_kit("beginner", "fr")`.

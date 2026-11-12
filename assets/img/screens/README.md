# Screenshots (optional)

The course uses drawn illustrations (SVG). You can add real screenshots of
KoboToolbox / KoboCollect: put a PNG in this folder and call it in a page with
`` `r fig_shot("name", "caption EN", "légende FR")` `` (function in `R/course_helpers.R`).
If `assets/img/screens/name.png` exists it is shown; otherwise the drawing
`assets/img/name.svg` is used.

Suggested screenshots (interface in French, no personal data visible):

| File name | Session | What to capture |
|---|---|---|
| `kobo-projects.png` | 0 | project list with the NOUVEAU button |
| `kobo-formbuilder.png` | 1 | Formbuilder with 3–4 questions and the + button |
| `kobo-question-settings.png` | 1 | settings (⚙) of a question: data column name, mandatory, hint |
| `kobo-upload-error.png` | 4 | an upload error message |
| `kobo-collect-data.png` | 4 | FORM tab → Collect data menu (the web links) |
| `kobocollect-setup.png` | 4 | KoboCollect: "Manually enter project details" screen |
| `kobo-downloads.png` | 5, A3 | DATA → Downloads with the advanced options open |

When you take them, also check the French button names in `R/ui_labels.csv`
(column `checked` → `yes`).

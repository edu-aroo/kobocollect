# ==============================================================================
# render_slides.R — build the slide decks into slides/   source("slides/render_slides.R")
# Each deck is ONE self-contained .html file (works offline, can be copied on a
# USB key). Open it in a browser. Keys: arrows / space = move, F = full screen,
# O = overview of all slides, N = show the speaker notes, Ctrl + P = PDF.
# Level 1 (Beginner): two decks of about 1 h 30. Levels 2 and 3: to be added.
# ==============================================================================
decks <- c("slides/deb1_seances0-3.Rmd", "slides/deb2_seances4-7.Rmd")
decks <- decks[file.exists(decks)]
for (f in decks) {
  message("Rendering ", f)
  rmarkdown::render(f, encoding = "UTF-8", quiet = TRUE)
}
message("Slides written in slides/*.html")

# _setup.R — shared setup for the slide decks (sourced in each .Rmd)
# Code chunks run from the PROJECT ROOT (root.dir), so paths are the same as in the course.
source("R/course_helpers.R")          # fig_svg(), xls(), ui(), key() and the course forms
knitr::opts_chunk$set(echo = FALSE)

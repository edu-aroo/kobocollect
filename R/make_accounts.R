# =============================================================================
# make_accounts.R — generate usernames and passwords for your students
# -----------------------------------------------------------------------------
# 1. Put your students' names in the vector below (or read them from a file:
#    students <- read.csv("my_list.csv")$name ).
# 2. Run the script: it writes accounts_to_paste.csv (NOT in docs/, so it is
#    never published).
# 3. Open the CSV, copy the 4 columns and paste them in the "students" tab of
#    your Google Sheet (below the header row). Send each student his/her login.
# =============================================================================

students <- c("Hery Rakoto", "Fara Rasoa", "Tiana Andriamanana")   # <- edit

set.seed(as.numeric(Sys.time()))     # different passwords each time you run it

# username = first letter of first name + last name, lower case, no spaces/accents
make_username <- function(full_name) {
  x <- iconv(tolower(full_name), to = "ASCII//TRANSLIT")   # é -> e
  parts <- strsplit(x, " ")[[1]]
  u <- paste0(substr(parts[1], 1, 1), parts[length(parts)])
  gsub("[^a-z0-9]", "", u)
}

# password = 3 letters + 4 digits, easy to read (no 0/O or 1/l confusion)
make_password <- function() {
  paste0(paste(sample(c(letters[-c(12, 15)]), 3, TRUE), collapse = ""),
         paste(sample(2:9, 4, TRUE), collapse = ""))
}

accounts <- data.frame(
  username  = make.unique(sapply(students, make_username), sep = ""),  # avoids duplicates
  password  = replicate(length(students), make_password()),
  full_name = students,
  active    = "yes"
)
accounts
write.csv(accounts, "accounts_to_paste.csv", row.names = FALSE)

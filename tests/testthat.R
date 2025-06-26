library(testthat)
library(lubridate)

# Load only the helper functions without executing the script
lines <- readLines("whiteRRabbit.R")
start <- grep("^robust_parse_numeric", lines)
end_section <- grep("^# ---- Functions", lines)[1] - 1
code <- paste(lines[start:end_section], collapse="\n")

eval(parse(text = code), envir = .GlobalEnv)

# Run tests

test_dir("tests/testthat")

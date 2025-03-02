#!/usr/bin/env Rscript
################################################################################
# whiteRRabbit.R
#
# Derived from WhiteRabbitMain.java in the WhiteRabbit project:
#   https://github.com/OHDSI/WhiteRabbit/blob/master/whiterabbit/src/main/java/org/ohdsi/whiterabbit/WhiteRabbitMain.java
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software distributed
# under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
################################################################################

suppressPackageStartupMessages({
    library(optparse)
    library(data.table)
    library(openxlsx)
    library(lubridate) # for date/time parsing
})

# ---- Command-line options ----------------------------------------------------
option_list <- list(
    make_option(c("-w", "--working_folder"),
        type = "character", default = NULL,
        help = "Folder where input files are located (required)", metavar = "DIR"
    ),
    make_option(c("-d", "--delimiter"),
        type = "character", default = "tab",
        help = "Delimiter to use: 'tab' or 'comma' [default: %default]", metavar = "DELIM"
    ),
    make_option(c("-o", "--output_dir"),
        type = "character", default = ".",
        help = "Output directory [default: current directory]", metavar = "OUTDIR"
    ),
    make_option(c("-f", "--output_format"),
        type = "character", default = "xlsx",
        help = "Output format: 'xlsx' (one Excel file) or 'tsv' (multiple TSVs) [default: %default]",
        metavar = "FORMAT"
    ),
    make_option(c("-m", "--maxRows"),
        type = "integer", default = -1,
        help = "Maximum rows to read per file (-1 for all) [default: %default]", metavar = "N"
    ),
    make_option(c("-x", "--maxDistinctValues"),
        type = "integer", default = 1000,
        help = "Maximum distinct values to display in 'Frequencies' [default: %default]", metavar = "N"
    ),
    make_option(c("-p", "--prefix"),
        type = "character", default = "ScanReport",
        help = "Prefix for output files [default: %default]", metavar = "PREFIX"
    ),
    make_option(c("-c", "--cpus"),
        type = "integer", default = 1,
        help = "Number of threads to use for data.table [default: %default]", metavar = "CPUS"
    ),
    make_option(c("-e", "--exclude_cols"),
        type = "character", default = NULL,
        help = "Comma-separated list of columns to exclude from summary", metavar = "COLS"
    ),
    make_option(c("-s", "--shift_dates"),
        action = "store_true", default = FALSE,
        help = "If set, randomly shift date/datetime columns by ±5 days before summarizing"
    )
)

parser <- OptionParser(option_list = option_list)
opts <- parse_args(parser)

# Validate required arguments
if (is.null(opts$working_folder)) {
    print_help(parser)
    stop("Error: --working_folder must be specified.", call. = FALSE)
}

# ---- Setup and file discovery -----------------------------------------------
workdir <- normalizePath(opts$working_folder)
outdir <- normalizePath(opts$output_dir, mustWork = FALSE)
prefix <- opts$prefix

if (!dir.exists(workdir)) {
    stop("Working folder does not exist: ", workdir, call. = FALSE)
}

# Create output directory if it doesn't exist
if (!dir.exists(outdir)) {
    dir.create(outdir, recursive = TRUE)
    message("Created output directory: ", outdir)
}

# Decide which file pattern to scan
if (tolower(opts$delimiter) == "tab") {
    file_pattern <- "\\.tsv$"
    read_sep <- "\t"
} else {
    file_pattern <- "\\.csv$"
    read_sep <- ","
}

# Find matching files
files <- list.files(path = workdir, pattern = file_pattern, full.names = TRUE)
if (length(files) == 0) {
    stop("No input files found in ", workdir, " matching pattern ", file_pattern, call. = FALSE)
}

# ---- Set data.table threads --------------------------------------------------
setDTthreads(opts$cpus)
message("Using data.table with ", getDTthreads(), " thread(s).")

# Prepare list of excluded columns
excluded_cols <- character(0)
if (!is.null(opts$exclude_cols)) {
    excluded_cols <- unlist(strsplit(opts$exclude_cols, ","))
    excluded_cols <- trimws(excluded_cols)
    if (length(excluded_cols) > 0) {
        message("Excluding columns: ", paste(excluded_cols, collapse = ", "))
    }
}

# ---- Helper: attempt date/time parsing ---------------------------------------
# This tries to parse a column with several common formats (ISO8601, y-m-d, etc.)
# If successful on enough non-empty rows, we convert the entire column.
detect_and_parse_dates <- function(x) {
    # Work on a copy of x
    x_clean <- x[!is.na(x) & x != ""]
    if (length(x_clean) == 0) {
        return(x)
    } # No data to parse

    # Try parse with ymd_hms (handles "1966-04-28T04:00:00Z" and variants)
    # We'll do a small sample to avoid huge overhead
    sample_size <- min(length(x_clean), 1000)
    x_sample <- sample(x_clean, sample_size)

    # If parsing fails for all or most, we skip
    parsed_sample <- suppressWarnings(ymd_hms(x_sample, quiet = TRUE))
    # If that didn't work well, try ymd
    if (all(is.na(parsed_sample))) {
        parsed_sample <- suppressWarnings(ymd(x_sample, quiet = TRUE))
        if (all(is.na(parsed_sample))) {
            # If we get here, we didn't parse well
            return(x) # Return original
        } else {
            # ymd parsing was somewhat successful
            # check success rate
            success_rate <- sum(!is.na(parsed_sample)) / length(parsed_sample)
            if (success_rate < 0.8) {
                return(x)
            }
            # If enough success, parse entire vector
            parsed_full <- suppressWarnings(ymd(x, quiet = TRUE))
            return(parsed_full)
        }
    } else {
        # ymd_hms was somewhat successful
        success_rate <- sum(!is.na(parsed_sample)) / length(parsed_sample)
        if (success_rate < 0.8) {
            return(x)
        }
        parsed_full <- suppressWarnings(ymd_hms(x, quiet = TRUE))
        return(parsed_full)
    }
}

# ---- Functions ---------------------------------------------------------------

# Count lines quickly (for total row count) without reading full data
count_lines_fast <- function(filepath) {
    if (.Platform$OS.type == "windows") {
        # Fallback for Windows if wc not available
        n <- length(readLines(filepath))
        return(n)
    } else {
        cmd <- sprintf("wc -l '%s' | awk '{print $1}'", filepath)
        out <- system(cmd, intern = TRUE)
        return(as.integer(out))
    }
}

# For each file, read up to maxRows, parse date/time columns if possible,
# then optionally shift them, then compute column-level stats.
scan_file <- function(filepath, maxRows, read_sep, maxDistinctValues,
                      excluded_cols, shiftDates) {
    totalRows <- count_lines_fast(filepath) - 1L # subtract 1 for header row

    # If maxRows == -1, read entire file
    if (maxRows < 0) {
        dt <- fread(filepath, sep = read_sep, showProgress = FALSE)
        nRowsChecked <- nrow(dt)
    } else {
        dt <- fread(filepath, sep = read_sep, nrows = maxRows, showProgress = FALSE)
        nRowsChecked <- min(totalRows, maxRows)
    }

    # Attempt date/time parsing on each column
    for (colName in names(dt)) {
        # If it's already numeric or factor, skip; only parse character columns
        if (is.character(dt[[colName]])) {
            dt[[colName]] <- detect_and_parse_dates(dt[[colName]])
        }
    }

    # Optionally shift date/datetime columns by ±5 days
    if (shiftDates) {
        for (colName in names(dt)) {
            x <- dt[[colName]]
            if (inherits(x, "Date") || inherits(x, "POSIXt")) {
                offsets <- sample(-5:5, length(x), replace = TRUE)
                dt[[colName]] <- x + offsets
            }
        }
    }

    # Basic stats about the table
    nFields <- ncol(dt)

    # Identify how many columns are 100% empty or missing
    all_empty <- sapply(dt, function(x) {
        sumNA <- sum(is.na(x))
        sumEmpty <- sum(x == "", na.rm = TRUE)
        (sumNA + sumEmpty) == length(x)
    })
    nFieldsEmpty <- sum(all_empty)

    # Exclude any columns specified by the user
    cols_to_process <- setdiff(names(dt), excluded_cols)

    # Column-level stats
    column_summaries <- list()

    for (colName in cols_to_process) {
        x <- dt[[colName]]
        col_class <- class(x)

        # Count missing (NA) and empty ("")
        nMissing <- sum(is.na(x))
        nEmpty <- sum(x == "", na.rm = TRUE)

        # Frequencies for non‐numeric, non-date columns (ignoring missing/empty)
        freqText <- ""
        if (!is.numeric(x) && !inherits(x, "Date") && !inherits(x, "POSIXt")) {
            x_nonmissing <- x[!is.na(x) & x != ""]
            tab <- sort(table(x_nonmissing), decreasing = TRUE)
            if (length(tab) > 0) {
                if (length(tab) > maxDistinctValues) {
                    tab <- tab[1:maxDistinctValues]
                }
                freqText <- paste(
                    sprintf("%s: %d", names(tab), as.integer(tab)),
                    collapse = ", "
                )
            }
        }

        # Summaries for numeric columns
        numStatsText <- ""
        if (is.numeric(x)) {
            x_num <- x[!is.na(x) & x != ""]
            if (length(x_num) > 0) {
                mn <- mean(x_num)
                sdev <- sd(x_num)
                med <- median(x_num)
                qs <- quantile(x_num, probs = c(0.25, 0.75))
                lowest <- min(x_num)
                highest <- max(x_num)
                numStatsText <- sprintf(
                    "min=%.2f, max=%.2f, median=%.2f, mean=%.2f, sd=%.2f, Q1=%.2f, Q3=%.2f",
                    lowest, highest, med, mn, sdev, qs[1], qs[2]
                )
            } else {
                numStatsText <- "No numeric data (all missing/empty)."
            }
        }

        # Summaries for date/datetime columns
        dateStatsText <- ""
        if (inherits(x, "Date") || inherits(x, "POSIXt")) {
            x_date <- x[!is.na(x)]
            if (length(x_date) > 0) {
                earliest <- min(x_date)
                latest <- max(x_date)
                med_dt <- median(as.numeric(x_date)) # numeric for median
                # Convert back to date/time
                med_dt <- if (inherits(x, "POSIXt")) {
                    as.POSIXct(med_dt, origin = "1970-01-01", tz = tz(x_date))
                } else {
                    as.Date(med_dt, origin = "1970-01-01")
                }
                dateStatsText <- sprintf(
                    "Earliest=%s, Latest=%s, Median=%s",
                    as.character(earliest),
                    as.character(latest),
                    as.character(med_dt)
                )
            } else {
                dateStatsText <- "No date data (all missing)."
            }
        }

        # Combine numericStats + dateStats if needed
        # We'll store them in a single "NumericStats" column for convenience,
        # or you could store them separately
        combinedStats <- if (dateStatsText != "" && numStatsText != "") {
            paste(dateStatsText, " | ", numStatsText)
        } else if (dateStatsText != "") {
            dateStatsText
        } else {
            numStatsText
        }

        column_summaries[[colName]] <- data.frame(
            Column = colName,
            DataType = paste(col_class, collapse = ", "),
            MissingCount = nMissing,
            EmptyCount = nEmpty,
            Frequencies = freqText,
            NumericStats = combinedStats,
            stringsAsFactors = FALSE
        )
    }

    # Combine all column summaries into one data frame
    if (length(column_summaries) > 0) {
        df_summary <- do.call(rbind, column_summaries)
    } else {
        df_summary <- data.frame(Message = "No columns found or all excluded", stringsAsFactors = FALSE)
    }

    list(
        file = filepath,
        totalRows = totalRows,
        nRowsChecked = nRowsChecked,
        nFields = nFields,
        nFieldsEmpty = nFieldsEmpty,
        summaryDF = df_summary
    )
}

# ---- Main scanning ----------------------------------------------------------
results <- list()
for (f in files) {
    cat("Scanning file:", f, "\n")
    res <- scan_file(
        filepath = f,
        maxRows = opts$maxRows,
        read_sep = read_sep,
        maxDistinctValues = opts$maxDistinctValues,
        excluded_cols = excluded_cols,
        shiftDates = opts$shift_dates
    )
    results[[f]] <- res
}

# Build the overview data frame
overview_list <- lapply(results, function(x) {
    data.frame(
        Table = basename(x$file),
        Description = "No description",
        N_rows = x$totalRows,
        N_rows_checked = x$nRowsChecked,
        N_Fields = x$nFields,
        N_Fields_Empty = x$nFieldsEmpty,
        stringsAsFactors = FALSE
    )
})
df_overview <- do.call(rbind, overview_list)

# ---- Output logic -----------------------------------------------------------
fmt <- tolower(opts$output_format)

if (fmt == "xlsx") {
    # Create a single Excel workbook
    wb <- createWorkbook()

    # 1) Overview sheet
    addWorksheet(wb, "Overview")
    writeData(wb, "Overview", df_overview, headerStyle = createStyle(textDecoration = "bold"))
    setColWidths(wb, "Overview", cols = 1:ncol(df_overview), widths = "auto")
    freezePane(wb, "Overview", firstRow = TRUE)

    # 2) One sheet per file
    for (nm in names(results)) {
        shtName <- basename(nm)
        # Clean up sheet name (max 31 chars, remove invalid chars)
        shtName <- gsub("[\\/?*:]", "_", shtName)
        if (nchar(shtName) > 31) {
            shtName <- substr(shtName, 1, 31)
        }

        addWorksheet(wb, shtName)
        df <- results[[nm]]$summaryDF
        writeData(wb, shtName, df, headerStyle = createStyle(textDecoration = "bold"))
        setColWidths(wb, shtName, cols = 1:ncol(df), widths = "auto")
        freezePane(wb, shtName, firstRow = TRUE)
    }

    out_xlsx <- file.path(outdir, paste0(prefix, ".xlsx"))
    saveWorkbook(wb, out_xlsx, overwrite = TRUE)
    message("Wrote Excel file: ", out_xlsx)
} else if (fmt == "tsv") {
    # Write one TSV for the overview
    overview_path <- file.path(outdir, paste0(prefix, "_Overview.tsv"))
    fwrite(df_overview, file = overview_path, sep = "\t")
    message("Wrote overview TSV: ", overview_path)

    # Write one TSV per file
    for (nm in names(results)) {
        shtName <- basename(nm)
        shtName <- gsub("[\\/?*:]", "_", shtName)
        df <- results[[nm]]$summaryDF

        out_tsv <- file.path(outdir, paste0(prefix, "_", shtName, ".tsv"))
        fwrite(df, file = out_tsv, sep = "\t")
        message("Wrote file TSV: ", out_tsv)
    }
} else {
    stop("Unsupported --output_format. Use 'xlsx' or 'tsv'.", call. = FALSE)
}

message("All done.")

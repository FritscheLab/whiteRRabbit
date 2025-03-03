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
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
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
        type = "integer", default = 100000,
        help = "Maximum rows to read per file (-1 for all). If random_sample is TRUE, a random sample of maxRows is used [default: %default]", metavar = "N"
    ),
    make_option(c("-x", "--maxDistinctValues"),
        type = "integer", default = 50,
        help = "Maximum distinct values to display in Frequencies [default: %default]", metavar = "N"
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
    ),
    make_option(c("--scan_field_values"),
        action = "store_true", default = TRUE,
        help = "Scan field values to generate frequency tables [default: %default]"
    ),
    make_option(c("--min_cell_count"),
        type = "integer", default = 5,
        help = "Minimum count threshold for a value to appear in frequency tables [default: %default]", metavar = "N"
    ),
    make_option(c("--random_sample"),
        action = "store_true", default = TRUE,
        help = "Randomly sample rows from table if total rows exceed maxRows [default: %default]"
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

# ---- Helper: robust parse for numeric ----------------------------------------
robust_parse_numeric <- function(x_char, success_threshold = 0.8) {
    if (!is.character(x_char)) {
        return(x_char)
    }
    x_nonempty <- x_char[!is.na(x_char) & x_char != ""]
    if (length(x_nonempty) == 0) {
        return(x_char)
    }
    sample_size <- min(length(x_nonempty), 1000)
    x_sample <- sample(x_nonempty, sample_size)
    nums <- suppressWarnings(as.numeric(x_sample))
    sr <- sum(!is.na(nums)) / length(nums)
    if (sr < success_threshold) {
        return(x_char)
    }
    parsed_full <- suppressWarnings(as.numeric(x_char))
    # Compare NAs introduced
    na_new <- is.na(parsed_full) & !is.na(x_char) & x_char != ""
    if (any(na_new)) {
        return(x_char)
    }
    parsed_full
}

# ---- Helper: robust parse for date/time --------------------------------------
robust_parse_date <- function(x_char, success_threshold = 0.8) {
    if (!is.character(x_char)) {
        return(x_char)
    }
    x_nonempty <- x_char[!is.na(x_char) & x_char != ""]
    if (length(x_nonempty) == 0) {
        return(x_char)
    }
    sample_size <- min(length(x_nonempty), 1000)
    x_sample <- sample(x_nonempty, sample_size)
    possible_orders <- c(
        "Ymd HMS", "Ymd HM", "Ymd", "YmdT",
        "mdY HMS", "mdY HM", "mdY",
        "dmy HMS", "dmy HM", "dmy"
    )
    sample_parsed <- tryCatch(
        {
            suppressWarnings(parse_date_time(x_sample, orders = possible_orders, tz = "UTC", quiet = TRUE))
        },
        error = function(e) {
            rep(NA, length(x_sample))
        }
    )
    sr <- sum(!is.na(sample_parsed)) / length(sample_parsed)
    if (sr < success_threshold) {
        return(x_char)
    }
    parsed_full <- tryCatch(
        {
            suppressWarnings(parse_date_time(x_char, orders = possible_orders, tz = "UTC", quiet = TRUE))
        },
        error = function(e) {
            rep(NA, length(x_char))
        }
    )
    sr2 <- sum(!is.na(parsed_full)) / length(parsed_full)
    if (sr2 < success_threshold) {
        return(x_char)
    }
    parsed_full
}

# ---- Functions ---------------------------------------------------------------
count_lines_fast <- function(filepath) {
    if (.Platform$OS.type == "windows") {
        n <- length(readLines(filepath))
        return(n)
    } else {
        cmd <- sprintf("wc -l '%s' | awk '{print $1}'", filepath)
        out <- system(cmd, intern = TRUE)
        return(as.integer(out))
    }
}

scan_file <- function(filepath, maxRows, read_sep, maxDistinctValues,
                      excluded_cols, shiftDates, random_sample,
                      scan_field_values, min_cell_count) {
    # Get total number of lines (including header)
    total_lines <- count_lines_fast(filepath)
    data_rows <- total_lines - 1L

    if (maxRows > 0 && random_sample && data_rows > maxRows) {
        if (.Platform$OS.type != "windows") {
            # Non-Windows: Use AWK-based sampling
            tmp_lines <- tempfile("rand_lines")
            sampled_lines <- sort(sample(2:total_lines, maxRows))
            writeLines(as.character(sampled_lines), con = tmp_lines)

            awk_cmd <- sprintf(
                "awk 'NR==FNR { a[$1]=1; next } (FNR==1) || (FNR in a)' %s %s",
                shQuote(tmp_lines), shQuote(filepath)
            )
            dt <- fread(cmd = awk_cmd, sep = read_sep, colClasses = "character")
            nRowsChecked <- nrow(dt)
            unlink(tmp_lines)
        } else {
            # Windows alternative: only if there are at least twice as many data rows as maxRows
            if (data_rows >= 2 * maxRows) {
                first_part <- fread(filepath, sep = read_sep, nrows = maxRows, colClasses = "character")
                last_part <- fread(filepath, sep = read_sep, skip = total_lines - maxRows, colClasses = "character")
                # Set column names for the last part using the header from the first part
                setnames(last_part, names(first_part))
                dt <- unique(rbindlist(list(first_part, last_part)))
                dt <- dt[sample(.N, maxRows)]
                nRowsChecked <- nrow(dt)
            } else {
                dt <- fread(filepath, sep = read_sep, showProgress = FALSE, colClasses = "character")
                nRowsChecked <- nrow(dt)
                if (maxRows > 0 && random_sample && nRowsChecked > maxRows) {
                    dt <- dt[sample(.N, maxRows)]
                    nRowsChecked <- nrow(dt)
                }
            }
        }
    } else {
        dt <- fread(filepath, sep = read_sep, showProgress = FALSE, colClasses = "character")
        nRowsChecked <- nrow(dt)
        if (maxRows > 0 && random_sample && nRowsChecked > maxRows) {
            dt <- dt[sample(.N, maxRows)]
            nRowsChecked <- nrow(dt)
        }
    }

    # Attempt numeric then date/time parse for each column
    for (colName in names(dt)) {
        dt[[colName]] <- robust_parse_numeric(dt[[colName]])
        if (is.character(dt[[colName]])) {
            dt[[colName]] <- robust_parse_date(dt[[colName]])
        }
    }

    # Optionally shift date/datetime columns
    if (shiftDates) {
        for (colName in names(dt)) {
            x <- dt[[colName]]
            if (inherits(x, "Date") || inherits(x, "POSIXt")) {
                offsets <- sample(-5:5, length(x), replace = TRUE)
                dt[[colName]] <- x + days(offsets)
            }
        }
    }

    nFields <- ncol(dt)
    all_empty <- sapply(dt, function(x) {
        sumNA <- sum(is.na(x))
        sumEmpty <- if (is.character(x)) {
            sum(x == "", na.rm = TRUE)
        } else {
            0
        }
        (sumNA + sumEmpty) == length(x)
    })
    nFieldsEmpty <- sum(all_empty)
    cols_to_process <- setdiff(names(dt), excluded_cols)

    column_summaries <- list()
    freq_list <- list()

    for (colName in cols_to_process) {
        x <- dt[[colName]]
        col_class <- class(x)

        nMissing <- sum(is.na(x))
        nEmpty <- if (is.character(x)) {
            sum(x == "", na.rm = TRUE)
        } else {
            0
        }

        if (is.character(x)) {
            x_nonmissing <- x[!is.na(x) & x != ""]
        } else {
            x_nonmissing <- x[!is.na(x)]
        }
        distinct_count <- length(unique(x_nonmissing))

        # Generate frequency table if scan_field_values is TRUE
        freqDF <- data.frame()
        if (scan_field_values && !(inherits(x, "Date") || inherits(x, "POSIXt"))) {
            if (distinct_count > 0) {
                tab <- sort(table(x_nonmissing), decreasing = TRUE)
                # Only include values that appear at least min_cell_count times
                tab <- tab[tab >= min_cell_count]
                if (length(tab) > maxDistinctValues) {
                    tab <- tab[1:maxDistinctValues]
                }
                if (length(tab) > 0) {
                    freqDF <- data.frame(
                        Column = colName,
                        Value = names(tab),
                        Count = as.integer(tab),
                        Percentage = as.numeric(tab) / sum(tab),
                        stringsAsFactors = FALSE
                    )
                }
            }
            if (nrow(freqDF) > 0) {
                freq_list[[colName]] <- freqDF
            }
        }

        # Numeric statistics
        minVal <- NA
        maxVal <- NA
        medianVal <- NA
        meanVal <- NA
        sdVal <- NA
        q1Val <- NA
        q3Val <- NA
        iqrVal <- NA
        if (is.numeric(x)) {
            x_num <- x[!is.na(x)]
            if (length(x_num) > 0) {
                minVal <- min(x_num, na.rm = TRUE)
                maxVal <- max(x_num, na.rm = TRUE)
                medianVal <- median(x_num, na.rm = TRUE)
                meanVal <- mean(x_num, na.rm = TRUE)
                sdVal <- sd(x_num, na.rm = TRUE)
                qs <- quantile(x_num, probs = c(0.25, 0.75), na.rm = TRUE)
                q1Val <- qs[1]
                q3Val <- qs[2]
                iqrVal <- q3Val - q1Val
            }
        }

        # Date statistics
        earliestVal <- NA
        latestVal <- NA
        medianDateVal <- NA
        if (inherits(x, "Date") || inherits(x, "POSIXt")) {
            x_date <- x[!is.na(x)]
            if (length(x_date) > 0) {
                earliestVal <- min(x_date, na.rm = TRUE)
                latestVal <- max(x_date, na.rm = TRUE)
                med_dt_num <- median(as.numeric(x_date), na.rm = TRUE)
                if (inherits(x, "POSIXt")) {
                    tz_value <- "UTC"
                    idx_nonna <- which(!is.na(x_date))
                    if (length(idx_nonna) > 0) {
                        tz_value <- tz(x_date[idx_nonna[1]])
                        if (is.null(tz_value) || tz_value == "") tz_value <- "UTC"
                    }
                    medianDateVal <- as.POSIXct(med_dt_num, origin = "1970-01-01", tz = tz_value)
                } else {
                    medianDateVal <- as.Date(med_dt_num, origin = "1970-01-01")
                }
            }
        }

        column_summaries[[colName]] <- data.frame(
            Column = colName,
            DataType = paste(col_class, collapse = ", "),
            MissingCount = nMissing,
            EmptyCount = nEmpty,
            DistinctCount = distinct_count,
            MinVal = minVal,
            MaxVal = maxVal,
            MedianVal = medianVal,
            MeanVal = meanVal,
            SDVal = sdVal,
            Q1Val = q1Val,
            Q3Val = q3Val,
            IQRVal = iqrVal,
            EarliestVal = if (!is.na(earliestVal)) as.character(earliestVal) else NA,
            LatestVal = if (!is.na(latestVal)) as.character(latestVal) else NA,
            MedianDateVal = if (!is.na(medianDateVal)) as.character(medianDateVal) else NA,
            stringsAsFactors = FALSE
        )
    }

    summaryDF <- if (length(column_summaries) > 0) {
        do.call(rbind, column_summaries)
    } else {
        data.frame(Message = "No columns found or all excluded", stringsAsFactors = FALSE)
    }

    freqDF <- if (length(freq_list) > 0) {
        do.call(rbind, freq_list)
    } else {
        data.frame()
    }

    list(
        file = filepath,
        totalRows = total_lines,
        nRowsChecked = nRowsChecked,
        nFields = ncol(dt),
        nFieldsEmpty = sum(all_empty),
        summaryDF = summaryDF,
        freqDF = freqDF
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
        shiftDates = opts$shift_dates,
        random_sample = opts$random_sample,
        scan_field_values = opts$scan_field_values,
        min_cell_count = opts$min_cell_count
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
    wb <- createWorkbook()
    # Overview
    addWorksheet(wb, "Overview")
    writeData(wb, "Overview", df_overview, headerStyle = createStyle(textDecoration = "bold"))
    setColWidths(wb, "Overview", cols = 1:ncol(df_overview), widths = "auto")
    freezePane(wb, "Overview", firstRow = TRUE)

    # Summaries & Frequencies
    for (nm in names(results)) {
        shtName <- basename(nm)
        shtName <- gsub("[\\/?*:]", "_", shtName)
        if (nchar(shtName) > 31) {
            shtName <- substr(shtName, 1, 31)
        }
        # Summary
        addWorksheet(wb, shtName)
        df_sum <- results[[nm]]$summaryDF
        writeData(wb, shtName, df_sum, headerStyle = createStyle(textDecoration = "bold"))
        setColWidths(wb, shtName, cols = 1:ncol(df_sum), widths = "auto")
        freezePane(wb, shtName, firstRow = TRUE)
        # Frequencies (only if frequency data exists)
        df_freq <- results[[nm]]$freqDF
        if (nrow(df_freq) > 0) {
            freqSheetName <- paste0(shtName, "_Freq")
            if (nchar(freqSheetName) > 31) {
                freqSheetName <- substr(freqSheetName, 1, 31)
            }
            addWorksheet(wb, freqSheetName)
            writeData(wb, freqSheetName, df_freq, headerStyle = createStyle(textDecoration = "bold"))
            setColWidths(wb, freqSheetName, cols = 1:ncol(df_freq), widths = "auto")
            freezePane(wb, freqSheetName, firstRow = TRUE)
        }
    }
    out_xlsx <- file.path(outdir, paste0(prefix, ".xlsx"))
    saveWorkbook(wb, out_xlsx, overwrite = TRUE)
    message("Wrote Excel file: ", out_xlsx)
} else if (fmt == "tsv") {
    overview_path <- file.path(outdir, paste0(prefix, "_Overview.tsv"))
    fwrite(df_overview, file = overview_path, sep = "\t")
    message("Wrote overview TSV: ", overview_path)
    for (nm in names(results)) {
        shtName <- basename(nm)
        shtName <- gsub("[\\/?*:]", "_", shtName)
        df_sum <- results[[nm]]$summaryDF
        sum_tsv <- file.path(outdir, paste0(prefix, "_", shtName, "_Summary.tsv"))
        fwrite(df_sum, file = sum_tsv, sep = "\t")
        message("Wrote summary TSV: ", sum_tsv)
        df_freq <- results[[nm]]$freqDF
        if (nrow(df_freq) > 0) {
            freq_tsv <- file.path(outdir, paste0(prefix, "_", shtName, "_Freq.tsv"))
            fwrite(df_freq, file = freq_tsv, sep = "\t")
            message("Wrote frequencies TSV: ", freq_tsv)
        }
    }
} else {
    stop("Unsupported --output_format. Use 'xlsx' or 'tsv'.", call. = FALSE)
}

message("All done.")

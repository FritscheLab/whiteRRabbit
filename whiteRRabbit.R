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
        type = "integer", default = -1,
        help = "Maximum rows to read per file (-1 for all) [default: %default]", metavar = "N"
    ),
    make_option(c("-x", "--maxDistinctValues"),
        type = "integer", default = 1000,
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

# ---- Helper: robust date/time parsing with parse_date_time -------------------
# We'll allow multiple possible orders. If <80% parse successfully, revert to char.
robust_parse_date <- function(x_char) {
    if (length(x_char) == 0) {
        return(x_char)
    }

    # Filter out NA / "" to see if there's anything to parse
    x_nonempty <- x_char[!is.na(x_char) & x_char != ""]
    if (length(x_nonempty) == 0) {
        return(x_char)
    } # nothing to parse

    # Sample to avoid big overhead
    sample_size <- min(length(x_nonempty), 1000)
    x_sample <- sample(x_nonempty, sample_size)

    # We can define multiple "orders" to catch various formats
    possible_orders <- c(
        "Ymd HMS", # e.g. 2023-08-10 13:25:30
        "Ymd HM", # e.g. 2023-08-10 13:25
        "Ymd", # e.g. 2023-08-10
        "YmdT", # e.g. 2023-08-10T13:25:30Z
        "mdY HMS",
        "mdY HM",
        "mdY",
        "dmy HMS",
        "dmy HM",
        "dmy"
    )

    # Parse the sample
    parsed_sample <- suppressWarnings(
        parse_date_time(x_sample, orders = possible_orders, tz = "UTC", quiet = TRUE)
    )
    # Evaluate success rate
    success_rate <- sum(!is.na(parsed_sample)) / length(parsed_sample)
    if (success_rate < 0.8) {
        return(x_char) # revert to original char
    }

    # If success, parse entire column
    parsed_full <- suppressWarnings(
        parse_date_time(x_char, orders = possible_orders, tz = "UTC", quiet = TRUE)
    )
    # We won't error if partial parse occurs, those rows become NA
    # If the parse results in mostly NA, you can do another success check if desired
    return(parsed_full)
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
# then optionally shift them, then compute column-level stats
# plus a separate data frame for frequencies.
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

    # Attempt robust date/time parsing on each character column
    for (colName in names(dt)) {
        if (is.character(dt[[colName]])) {
            dt[[colName]] <- robust_parse_date(dt[[colName]])
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

    # Frequencies data for each column
    freq_list <- list()

    for (colName in cols_to_process) {
        x <- dt[[colName]]
        col_class <- class(x)

        # Count missing (NA) and empty ("")
        nMissing <- sum(is.na(x))
        nEmpty <- sum(x == "", na.rm = TRUE)

        # Distinct count for entire column
        x_nonmissing <- x[!is.na(x) & x != ""]
        distinct_count <- length(unique(x_nonmissing))

        # Frequencies: if distinct_count > 0, we gather them
        freqDF <- data.frame()
        if (distinct_count > 0) {
            tab <- sort(table(x_nonmissing), decreasing = TRUE)
            if (length(tab) > maxDistinctValues) {
                tab <- tab[1:maxDistinctValues]
            }
            if (length(tab) > 0) {
                freqDF <- data.frame(
                    Column = colName,
                    Value = names(tab),
                    Count = as.integer(tab),
                    Percentage = as.numeric(tab) / sum(tab) * 100,
                    stringsAsFactors = FALSE
                )
            }
        }
        if (nrow(freqDF) > 0) {
            freq_list[[colName]] <- freqDF
        }

        # Summaries for numeric columns
        minVal <- NA
        maxVal <- NA
        medianVal <- NA
        meanVal <- NA
        sdVal <- NA
        q1Val <- NA
        q3Val <- NA
        iqrVal <- NA

        if (is.numeric(x)) {
            x_num <- x[!is.na(x) & x != ""]
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

        # Summaries for date/datetime columns
        earliestVal <- NA
        latestVal <- NA
        medianDateVal <- NA
        if (inherits(x, "Date") || inherits(x, "POSIXt")) {
            x_date <- x[!is.na(x)]
            if (length(x_date) > 0) {
                earliestVal <- min(x_date, na.rm = TRUE)
                latestVal <- max(x_date, na.rm = TRUE)
                med_dt_num <- median(as.numeric(x_date), na.rm = TRUE)

                # We might guess a tz from the first non-NA entry, else use UTC
                tz_value <- "UTC"
                if (inherits(x, "POSIXt")) {
                    non_na_idx <- which(!is.na(x_date))
                    if (length(non_na_idx) > 0) {
                        tz_value <- tz(x_date[non_na_idx[1]])
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
            # numeric stats
            MinVal = minVal,
            MaxVal = maxVal,
            MedianVal = medianVal,
            MeanVal = meanVal,
            SDVal = sdVal,
            Q1Val = q1Val,
            Q3Val = q3Val,
            IQRVal = iqrVal,
            # date stats
            EarliestVal = if (!is.na(earliestVal)) as.character(earliestVal) else NA,
            LatestVal = if (!is.na(latestVal)) as.character(latestVal) else NA,
            MedianDateVal = if (!is.na(medianDateVal)) as.character(medianDateVal) else NA,
            stringsAsFactors = FALSE
        )
    }

    # Combine all column summaries into one data frame
    summaryDF <- if (length(column_summaries) > 0) {
        do.call(rbind, column_summaries)
    } else {
        data.frame(Message = "No columns found or all excluded", stringsAsFactors = FALSE)
    }

    # Combine all frequencies data into one data frame
    freqDF <- if (length(freq_list) > 0) {
        do.call(rbind, freq_list)
    } else {
        data.frame() # empty
    }

    list(
        file = filepath,
        totalRows = totalRows,
        nRowsChecked = nRowsChecked,
        nFields = ncol(dt),
        nFieldsEmpty = nFieldsEmpty,
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

    # 2) One summary sheet + one frequencies sheet per file
    for (nm in names(results)) {
        shtName <- basename(nm)
        # Clean up sheet name (max 31 chars, remove invalid chars)
        shtName <- gsub("[\\/?*:]", "_", shtName)
        if (nchar(shtName) > 31) {
            shtName <- substr(shtName, 1, 31)
        }

        # Add summary sheet
        addWorksheet(wb, shtName)
        df_sum <- results[[nm]]$summaryDF
        writeData(wb, shtName, df_sum, headerStyle = createStyle(textDecoration = "bold"))
        setColWidths(wb, shtName, cols = 1:ncol(df_sum), widths = "auto")
        freezePane(wb, shtName, firstRow = TRUE)

        # Add frequencies sheet if freqDF is non-empty
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
    # Write one TSV for the overview
    overview_path <- file.path(outdir, paste0(prefix, "_Overview.tsv"))
    fwrite(df_overview, file = overview_path, sep = "\t")
    message("Wrote overview TSV: ", overview_path)

    # For each table, write summary and frequencies TSV
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

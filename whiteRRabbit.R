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

# ---- Helper: attempt date/time parsing ---------------------------------------
# Tries to parse a column with common formats (ISO8601, y-m-d, etc.)
# If parsing is successful on >= 80% of sampled values, convert the entire column.
detect_and_parse_dates <- function(x) {
    x_clean <- x[!is.na(x) & x != ""]
    if (length(x_clean) == 0) {
        return(x)
    }
    sample_size <- min(length(x_clean), 1000)
    x_sample <- sample(x_clean, sample_size)

    # Try ymd_hms first
    parsed_sample <- suppressWarnings(ymd_hms(x_sample, quiet = TRUE))
    if (all(is.na(parsed_sample))) {
        # Try ymd
        parsed_sample <- suppressWarnings(ymd(x_sample, quiet = TRUE))
        if (all(is.na(parsed_sample))) {
            # Could not parse as date/time
            return(x)
        } else {
            # ymd success rate
            success_rate <- sum(!is.na(parsed_sample)) / length(parsed_sample)
            if (success_rate < 0.8) {
                return(x)
            }
            parsed_full <- suppressWarnings(ymd(x, quiet = TRUE))
            return(parsed_full)
        }
    } else {
        # ymd_hms partial success
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

    # Frequencies data for each column
    freq_list <- list()

    for (colName in cols_to_process) {
        x <- dt[[colName]]
        col_class <- class(x)

        # Count missing (NA) and empty ("")
        nMissing <- sum(is.na(x))
        nEmpty <- sum(x == "", na.rm = TRUE)

        # Distinct count for entire column
        # (We might not always show it, but it's handy.)
        distinct_count <- length(unique(x[!is.na(x) & x != ""]))

        # Frequencies: if distinct_count <= maxDistinctValues, we store them
        # for the "Frequencies" sheet.
        # We'll do it for all columns. If you only want frequencies for non-numeric,
        # add a condition here.
        freqDF <- data.frame()
        x_nonmissing <- x[!is.na(x) & x != ""]
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
                minVal <- min(x_num)
                maxVal <- max(x_num)
                medianVal <- median(x_num)
                meanVal <- mean(x_num)
                sdVal <- sd(x_num)
                qs <- quantile(x_num, probs = c(0.25, 0.75))
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
                earliestVal <- min(x_date)
                latestVal <- max(x_date)
                med_dt_num <- median(as.numeric(x_date))
                if (inherits(x, "POSIXt")) {
                    medianDateVal <- as.POSIXct(med_dt_num, origin = "1970-01-01", tz = tz(x_date))
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
            MinVal = if (!is.na(minVal)) sprintf("%.2f", minVal) else NA,
            MaxVal = if (!is.na(maxVal)) sprintf("%.2f", maxVal) else NA,
            MedianVal = if (!is.na(medianVal)) sprintf("%.2f", medianVal) else NA,
            MeanVal = if (!is.na(meanVal)) sprintf("%.2f", meanVal) else NA,
            SDVal = if (!is.na(sdVal)) sprintf("%.2f", sdVal) else NA,
            Q1Val = if (!is.na(q1Val)) sprintf("%.2f", q1Val) else NA,
            Q3Val = if (!is.na(q3Val)) sprintf("%.2f", q3Val) else NA,
            IQRVal = if (!is.na(iqrVal)) sprintf("%.2f", iqrVal) else NA,
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

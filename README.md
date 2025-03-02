# whiteRRabbit

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0.html)

## Overview

**whiteRRabbit** is an R-based data profiling tool derived from the [OHDSI WhiteRabbit](https://github.com/OHDSI/WhiteRabbit) Java application. It scans large delimited files (`.csv`, `.tsv`), producing column-level summaries such as missing counts, empty values, value frequencies, basic numeric statistics, and date/time summaries.

The tool is optimized with `data.table` for efficient handling of large datasets and supports multi-threading, configurable limits, and multiple output formats.

---

## ✨ Features

- Supports **CSV** and **TSV** file scanning.
- Computes:
  - Row and field counts.
  - Missing and empty value statistics.
  - Frequencies of distinct values (limited to top N).
  - Numeric summaries (min, max, median, mean, standard deviation, quartiles, IQR).
  - Date/time parsing and summaries (Earliest, Latest, Median date).
- Handles multiple files within a folder.
- Outputs:
  - **Excel workbook (`.xlsx`)** with an Overview sheet, individual summary sheets for each file, and optional frequency sheets.
  - **TSV files** for downstream processing, including overview, summary, and frequency files.
- Multi-threaded using `data.table`.
- Fully parameterized via the command line (`optparse`).
- **New Functionality:**
  - **Exclude Columns:** Use `--exclude_cols` to omit specified columns from the summary.
  - **Shift Dates:** Use the `--shift_dates` flag to randomly shift date/datetime columns by ±5 days before summarizing.

---

## 🚀 Installation

### 1️⃣ Install R (≥ 4.0) and [mamba](https://mamba.readthedocs.io/en/latest/) (optional but recommended):

```bash
mamba create -n whiteRRabbit -c conda-forge r-base r-data.table r-optparse r-openxlsx r-lubridate
mamba activate whiteRRabbit
```

Or install packages in R directly:

```r
install.packages(c("data.table", "optparse", "openxlsx", "lubridate"))
```

### 2️⃣ Clone the repository:

```bash
git clone https://github.com/FritscheLab/whiteRRabbit.git
cd whiteRRabbit
```

---

## ⚡ Usage

```bash
Rscript whiteRRabbit.R \
  --working_folder "/path/to/input_folder" \
  --delimiter "tab" \
  --output_dir "/path/to/output_folder" \
  --output_format "xlsx" \
  --maxRows -1 \
  --maxDistinctValues 1000 \
  --prefix "MyScanReport" \
  --cpus 4 \
  --exclude_cols "col1,col2" \
  --shift_dates
```

For a **full list of options and detailed examples**, see the [whiteRRabbit documentation](/doc/whiteRRabbit.md).

---

## 🛠 Project Structure

```
whiteRRabbit/
├── whiteRRabbit.R      # Main script
├── README.md           # Repository overview
└── /doc/
    └── whiteRRabbit.md # Detailed usage documentation
```

---

## 📂 Outputs

Depending on the chosen `--output_format`:

### XLSX
- `ScanReport.xlsx`
  - **Overview** sheet: Summary of all scanned files.
  - One sheet per input file with column-level summaries.
  - Additional frequency sheet(s) per file (if frequency data exists).

### TSV
- `ScanReport_Overview.tsv`
- One TSV per input file for column summaries.
- Additional TSV file(s) for frequency data (if available).

---

## 🧩 Cross-Platform Compatibility
✅ Linux  
✅ macOS  
✅ Windows (with R installed)

---

## ⚠️ Error Handling

- Stops if:
  - `--working_folder` is missing.
  - No input files matching the specified delimiter are found.
  - An unsupported output format is provided.
- Automatically creates output directories if missing.

---

## 📖 Inspiration

Derived from the [OHDSI WhiteRabbit](https://github.com/OHDSI/WhiteRabbit) Java tool, adapted into R for integration into FritscheLab workflows and enhanced with additional functionality for date shifting and column exclusion.

---

## 📄 License

This project is licensed under the [GNU General Public License v3.0 (2025)](https://www.gnu.org/licenses/gpl-3.0.html).

---

## 👤 Author

Fritsche Lab  
[https://github.com/FritscheLab](https://github.com/FritscheLab)

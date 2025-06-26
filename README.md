# whiteRRabbit

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://www.apache.org/licenses/LICENSE-2.0)

## Overview

**whiteRRabbit** is an R-based data profiling tool derived from the [OHDSI WhiteRabbit](https://github.com/OHDSI/WhiteRabbit) Java application. It scans large delimited files (`.csv`, `.tsv`), producing column-level summaries such as missing counts, empty values, value frequencies, basic numeric statistics, and date/time summaries.

The tool is optimized with `data.table` for efficient handling of large datasets and supports multi-threading, configurable limits, and multiple output formats.

---

## ✨ Features

- Supports **CSV** and **TSV** file scanning.
- Computes:
  - Row and field counts.
  - Missing and empty value statistics.
  - Frequencies of distinct values by scanning field values (with configurable minimum cell count).
  - Numeric summaries (min, max, median, mean, standard deviation, quartiles, IQR).
  - Date/time parsing and summaries (Earliest, Latest, Median date).
- Handles multiple files within a folder.
- Outputs:
  - **Excel workbook (`.xlsx`)** with an Overview sheet, individual summary sheets for each file, and additional frequency sheets (if frequency data exists).
  - **TSV files** for downstream processing, including overview, summary, and frequency files.
- Multi-threaded processing using `data.table`.
- Fully parameterized via the command line (`optparse`).

**New Functionality:**
- **Exclude Columns:** Use `--exclude_cols` to omit specified columns from the summary.
- **Shift Dates:** Use the `--shift_dates` flag to randomly shift date/datetime columns by ±5 days before summarizing.
- **Field Value Scanning:** Generate frequency tables for field values with `--scan_field_values` (enabled by default) and set a minimum cell count with `--min_cell_count`.
- **Random Sampling:** Use `--random_sample` (enabled by default) to randomly sample rows when total rows exceed `--maxRows` (default: 100000).

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
  --maxRows 100000 \
  --maxDistinctValues 1000 \
  --prefix "MyScanReport" \
  --cpus 4 \
  --exclude_cols "col1,col2" \
  --shift_dates \
  --scan_field_values \
  --min_cell_count 5 \
  --random_sample
```

*Note:* By default, `--maxRows` is set to 100000 (i.e. only 100,000 rows are processed per file). Use `-1` to process all rows.

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
- `<prefix>.xlsx` (default prefix: ScanReport)
  - **Overview** sheet: Summary of all scanned files.
  - One sheet per input file with column-level summaries.
  - Additional frequency sheet(s) per file (if frequency data exists).

### TSV
- `<prefix>_Overview.tsv`
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

Derived from the [OHDSI WhiteRabbit](https://github.com/OHDSI/WhiteRabbit) Java tool, adapted into R for integration into FritscheLab workflows and enhanced with additional functionality for date shifting, column exclusion, field value scanning, and random sampling.

### ⚠️ Warning / Disclaimer

This implementation of **whiteRRabbit** is inspired by the summary statistics approach from [OHDSI WhiteRabbit](https://github.com/OHDSI/WhiteRabbit). However, this version may lack several features present in the original tool—especially those related to privacy protection. **Do not assume that the generated summary statistics are completely free of individual-level or sensitive data.** Always review the output thoroughly and ensure compliance with all applicable local regulations and data protection policies before sharing any generated files. When in doubt, consult your legal or regulatory authorities.

---

## 📄 License

This project is licensed under the [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0).

---

## 👤 Author

Fritsche Lab  
[https://github.com/FritscheLab](https://github.com/FritscheLab)

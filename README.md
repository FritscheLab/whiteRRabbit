# whiteRRabbit

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0.html)

## Overview

**whiteRRabbit** is an R-based data profiling tool derived from the [OHDSI WhiteRabbit](https://github.com/OHDSI/WhiteRabbit) Java application. It scans large delimited files (`.csv`, `.tsv`), producing column-level summaries such as missing counts, empty values, value frequencies, and basic numeric statistics.

The tool is optimized with `data.table` for efficient handling of large datasets and supports multi-threading, configurable limits, and multiple output formats.

---

## ✨ Features

- Supports **CSV** and **TSV** file scanning.
- Computes:
  - Row and field counts.
  - Missing and empty value statistics.
  - Frequencies of distinct values (limited to top N).
  - Numeric summaries (mean, standard deviation, quantiles).
- Handles multiple files within a folder.
- Outputs:
  - **Excel workbook (`.xlsx`)** with overview and per-file summaries.
  - **TSV files** for downstream processing.
- Multi-threaded using `data.table`.
- Fully parameterized via the command line (`optparse`).

---

## 🚀 Installation

### 1️⃣ Install R (≥ 4.0) and [mamba](https://mamba.readthedocs.io/en/latest/) (optional but recommended):

```bash
mamba create -n whiteRRabbit -c conda-forge r-base r-data.table r-optparse r-openxlsx
mamba activate whiteRRabbit
```

Or install packages in R directly:

```r
install.packages(c("data.table", "optparse", "openxlsx"))
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
  --maxDistinctValues 500 \
  --prefix "MyScanReport" \
  --cpus 4
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
  - One sheet per input file with column-level statistics.

### TSV
- `ScanReport_Overview.tsv`
- One TSV per input file with column-level statistics.

---

## 🧩 Cross-Platform Compatibility
✅ Linux  
✅ macOS  
✅ Windows (with R installed)

---

## ⚠️ Error Handling

- Stops if:
  - `--working_folder` is missing.
  - No input files matching the delimiter are found.
  - Unsupported output format is provided.
- Automatically creates output directories if missing.

---

## 📖 Inspiration

Derived from the [OHDSI WhiteRabbit](https://github.com/OHDSI/WhiteRabbit) Java tool, adapted into R for integration into FritscheLab workflows and enhanced compatibility with data.table and tidy R environments.

---

## 📄 License

This project is licensed under the [GNU General Public License v3.0 (2025)](https://www.gnu.org/licenses/gpl-3.0.html).

---

## 👤 Author

Fritsche Lab  
[https://github.com/FritscheLab](https://github.com/FritscheLab)

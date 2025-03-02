# whiteRRabbit Documentation

## 📌 Overview

**whiteRRabbit** is an R-based profiling tool designed to scan delimited text files (TSV or CSV) and create a comprehensive scan report summarizing the data structure and content. It provides essential metrics for understanding the quality and characteristics of large tabular datasets, serving as a lightweight and cross-platform alternative to [OHDSI WhiteRabbit](https://github.com/OHDSI/WhiteRabbit).

---

## ⚙️ Command-Line Usage

### Basic Example:
```bash
Rscript whiteRRabbit.R \
  --working_folder "/data/input" \
  --delimiter "comma" \
  --output_dir "/data/output" \
  --output_format "xlsx" \
  --maxRows -1 \
  --maxDistinctValues 1000 \
  --prefix "DatasetScan" \
  --cpus 4 \
  --exclude_cols "colA,colB" \
  --shift_dates
```

---

## 🎛️ Argument Reference

| Argument                   | Type        | Default              | Description |
| -------------------------- | ----------- | -------------------- | ----------- |
| `-w, --working_folder`     | `character` | **(Required)**       | Directory containing the input files to scan. |
| `-d, --delimiter`          | `character` | `"tab"`              | File delimiter: `"tab"` for `.tsv` or `"comma"` for `.csv`. |
| `-o, --output_dir`         | `character` | `"."` (current dir)  | Directory where output files will be saved. |
| `-f, --output_format`      | `character` | `"xlsx"`             | Output format: `"xlsx"` for a single Excel workbook or `"tsv"` for multiple TSV files. |
| `-m, --maxRows`            | `integer`   | `-1` (all rows)      | Maximum number of rows to process per file. |
| `-x, --maxDistinctValues`  | `integer`   | `1000`               | Maximum number of unique values to display in frequency summaries. |
| `-p, --prefix`             | `character` | `"ScanReport"`       | Prefix to use in output file names. |
| `-c, --cpus`               | `integer`   | `1`                  | Number of CPU threads to use with `data.table`. |
| `-e, --exclude_cols`       | `character` | `NULL`               | Comma-separated list of columns to exclude from the summary. |
| `-s, --shift_dates`        | (flag)      | `FALSE`              | If set, randomly shifts date/datetime columns by ±5 days before summarizing. |

---

## 📊 Output Details

### 📁 Output Files

| Format | File(s) | Description |
| ------ | ------- | ----------- |
| `xlsx` | `ScanReport.xlsx` | Single workbook containing an **Overview** sheet, individual summary sheets for each scanned file, and optional frequency sheets (if frequency data exists). |
| `tsv`  | `ScanReport_Overview.tsv` | Overview TSV summarizing all scanned files. |
| `tsv`  | `ScanReport_<filename>_Summary.tsv` | Column-level summary TSV for each scanned file. |
| `tsv`  | `ScanReport_<filename>_Freq.tsv` | Frequency TSV for each scanned file (if applicable). |

### 📝 Overview Sheet Example
| Table      | Description    | N_rows | N_rows_checked | N_Fields | N_Fields_Empty |
| ---------- | -------------- | ------ | -------------- | -------- | --------------- |
| example.tsv| No description | 50000  | 50000          | 20       | 2               |

### 📝 Column Summary Example
The summary for each file includes detailed statistics for each column. For example:

| Column      | DataType    | MissingCount | EmptyCount | DistinctCount | MinVal | MaxVal | MedianVal | MeanVal | SDVal | Q1Val | Q3Val | IQRVal | EarliestVal | LatestVal  | MedianDateVal |
|-------------|-------------|--------------|------------|---------------|--------|--------|-----------|---------|-------|-------|-------|--------|-------------|------------|---------------|
| age         | numeric     | 0            | 0          | 45            | 21.00  | 65.00  | 42.00     | 42.00   | 10.50 | 28.00 | 56.00 | 28.00  | NA          | NA         | NA            |
| signup_date | Date        | 2            | 0          | 30            | NA     | NA     | NA        | NA      | NA    | NA    | NA    | NA     | 2020-01-01  | 2022-12-31 | 2021-06-15    |

*Note:* Numeric summary columns (MinVal, MaxVal, etc.) will be `NA` for non-numeric columns, and date summary columns (EarliestVal, LatestVal, MedianDateVal) will be `NA` for non-date columns.

---

## 🔍 Processing Logic

For each input file:
1. **Line Count**: Quickly estimates total rows using system utilities (`wc -l` on Unix or a full file read on Windows).
2. **Partial Reads**: Respects the `--maxRows` option to limit processing.
3. **Column Profiling**:
   - Counts missing (`NA`) and empty (`""`) values.
   - Calculates top N frequencies for categorical data (if the distinct count is within `--maxDistinctValues`).
   - Computes numeric summaries (min, max, median, mean, standard deviation, quartiles, and IQR) for numeric columns.
   - Parses date/time columns using common formats and computes date statistics (Earliest, Latest, Median date).
4. **Optional Features**:
   - **Exclude Columns:** Columns specified via `--exclude_cols` are omitted from the summary.
   - **Shift Dates:** If the `--shift_dates` flag is set, date/datetime columns are randomly shifted by ±5 days.
5. **Overview Assembly**: Creates an overview table summarizing all scanned files.
6. **Output Generation**: Produces either an `.xlsx` workbook or multiple `.tsv` files based on the `--output_format` option.

---

## 🧠 Performance Notes

- **Multi-threading** is enabled via `data.table::setDTthreads()` based on the `--cpus` option.
- Optimized for large files; typical for millions of rows per file.
- Windows-compatible, with fallback methods for line counting if Unix utilities are unavailable.

---

## 🛠 Troubleshooting

| Issue                         | Potential Cause                                    | Suggested Solution                                      |
| ----------------------------- | -------------------------------------------------- | ------------------------------------------------------- |
| No files found in directory   | Incorrect `--working_folder` or delimiter mismatch | Verify the folder path and ensure files match the specified delimiter (`.tsv` for "tab", `.csv` for "comma"). |
| Unsupported output format     | An invalid value for `--output_format`             | Use either `"xlsx"` or `"tsv"` for `--output_format`.    |
| High memory usage             | Large files with high row counts or high-cardinality columns | Use `--maxRows` or reduce `--maxDistinctValues` to limit resource usage. |

---

## 🧩 Cross-Platform Compatibility
- ✅ Linux (Ubuntu, CentOS)
- ✅ macOS
- ✅ Windows (with R 4.0+ and appropriate packages)

---

## 📜 License

This project is licensed under the [GNU General Public License v3.0 (2025)](https://www.gnu.org/licenses/gpl-3.0.html).

---

## 👥 Authors and Acknowledgments

- **Developed by:** Fritsche Lab
- **Inspiration:** Adapted from [OHDSI WhiteRabbit](https://github.com/OHDSI/WhiteRabbit)

# doc/whiteRRabbit.md

# whiteRRabbit Documentation

## 📌 Overview

**whiteRRabbit** is an R-based profiling tool designed to scan delimited text files (TSV or CSV) to create a comprehensive scan report summarizing data structure and content. It provides essential metrics for understanding the quality and characteristics of large tabular datasets, serving as a lightweight and cross-platform alternative to [OHDSI WhiteRabbit](https://github.com/OHDSI/WhiteRabbit). An added functionality allows for the random shifting of date/datetime columns by ±5 days for anonymization.

---

## ⚙️ Command-Line Usage

### Basic Example:
```bash
Rscript whiteRRabbit.R \
  --working_folder "/data/input" \
  --delimiter "comma" \
  --output_dir "/data/output" \
  --output_format "xlsx" \
  --maxRows 50000 \
  --maxDistinctValues 1000 \
  --prefix "DatasetScan" \
  --cpus 4 \
  --shift_dates
```

---

## 🎛️ Argument Reference

| Argument                  | Type       | Default    | Description                                                                               |
| ------------------------- | ---------- | ---------- | ----------------------------------------------------------------------------------------- |
| `-w, --working_folder`    | character  | **(Required)** | Directory containing the input files to scan.                                            |
| `-d, --delimiter`         | character  | `"tab"`    | File delimiter: `"tab"` for `.tsv` or `"comma"` for `.csv`.                               |
| `-o, --output_dir`        | character  | `"."` (current directory) | Directory where output files will be saved.                                        |
| `-f, --output_format`     | character  | `"xlsx"`   | `"xlsx"` for Excel output or `"tsv"` for plain text files.                                |
| `-m, --maxRows`           | integer    | `-1`       | Maximum number of rows to process per file.                                               |
| `-x, --maxDistinctValues` | integer    | `1000`     | Maximum number of unique values to show in frequency summaries.                           |
| `-p, --prefix`            | character  | `"ScanReport"` | Prefix to use in output file names.                                                       |
| `-c, --cpus`              | integer    | `1`        | Number of CPU threads to use with `data.table`.                                           |
| `-s, --shift_dates`       | flag       | `FALSE`    | If set, randomly shift date/datetime columns by ±5 days before summarizing.               |

---

## 📊 Output Details

### 📁 Output Files

| Format | File | Description |
| ------ | ---- | ----------- |
| `xlsx` | `ScanReport.xlsx` | Single workbook containing an **Overview** and one sheet per scanned file with column summaries. |
| `tsv`  | `ScanReport_Overview.tsv` | Summary of all files scanned. |
| `tsv`  | `ScanReport_<filename>.tsv` | Column-level summaries for each scanned file. |

### 📝 Overview Sheet Example
| Table       | Description    | N_rows | N_rows_checked | N_Fields | N_Fields_Empty |
| ----------- | -------------- | ------ | -------------- | -------- | --------------- |
| example.tsv | No description | 50000  | 50000          | 20       | 2               |

### 📝 Column Summary Example
| Column | DataType  | MissingCount | EmptyCount | Frequencies                | NumericStats                                            |
| ------ | --------- | ------------ | ---------- | -------------------------- | ------------------------------------------------------- |
| age    | numeric   | 0            | 0          |                            | mean=35.2, sd=10.5, Q1=28, median=34, Q3=42               |
| gender | character | 0            | 0          | Male: 3000, Female: 2000   |                                                         |

---

## 🔍 Processing Logic

For each input file:
1. **Line Count**: Quickly estimates total rows using system utilities (`wc` on Unix).
2. **Partial Reads**: Respects `--maxRows` to limit processing.
3. **Column Profiling**:
   - Counts missing and empty values.
   - Calculates top N frequencies for categorical data.
   - Computes mean, SD, and quartiles for numeric fields.
   - Attempts to parse date/datetime columns and optionally shifts them by ±5 days if `--shift_dates` is set.
4. **Overview Assembly**: Creates an overview table summarizing all scanned files.
5. **Output Generation**: Produces either `.xlsx` or `.tsv` outputs based on user preference.

---

## 🧠 Performance Notes

- **Multi-threading** is handled via `data.table::setDTthreads()`.
- Efficient for large files; typical for millions of rows per file.
- Windows-compatible, though the `wc -l` optimization is disabled on Windows (fallback to reading full file line counts).

---

## 💡 Best Practices

- Use `--maxRows` to sample large files and speed up profiling.
- Adjust `--maxDistinctValues` to manage memory usage when profiling high-cardinality categorical fields.
- Use `mamba` environments for reproducible installations.
- Prefer `"xlsx"` output for easy browsing; use `"tsv"` for programmatic post-processing.
- Enable `--shift_dates` when date anonymization is required.

---

## 🛠 Troubleshooting

| Issue                             | Solution                                                        |
| --------------------------------- | ----------------------------------------------------------------|
| No files found in directory       | Verify `--working_folder` path and delimiter setting (`csv` vs. `tsv`). |
| Unsupported output format         | Ensure `--output_format` is either `"xlsx"` or `"tsv"`.           |
| Memory usage too high             | Lower `--maxRows` or `--maxDistinctValues`.                      |

---

## 🧩 Cross-Platform Compatibility
- ✅ Linux (Ubuntu, CentOS)
- ✅ macOS
- ✅ Windows (R 4.0+ with appropriate packages)

---

## 📜 License

This project is licensed under the [GNU General Public License v3.0 (2025)](https://www.gnu.org/licenses/gpl-3.0.html).

---

## 👥 Authors and Acknowledgments

- **Developed by:** Fritsche Lab
- **Inspiration:** Adapted from [OHDSI WhiteRabbit](https://github.com/OHDSI/WhiteRabbit)

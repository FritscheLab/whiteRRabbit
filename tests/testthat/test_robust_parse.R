library(testthat)

# Test robust_parse_numeric

test_that("robust_parse_numeric parses numeric strings", {
  x <- c("1", "2", "3", NA, "")
  result <- robust_parse_numeric(x)
  expect_type(result, "double")
  expect_equal(result[1:3], c(1, 2, 3))
  expect_true(is.na(result[4]))
  expect_true(is.na(result[5]))
})

# If values are mostly non-numeric, should return original

test_that("robust_parse_numeric returns original when parsing fails", {
  x <- c("a", "b", "1")
  result <- robust_parse_numeric(x, success_threshold = 0.8)
  expect_identical(result, x)
})

# Test robust_parse_date

test_that("robust_parse_date parses date strings", {
  x <- c("2023-01-01", "2023-12-31", "2023-06-15", "2024-02-01")
  result <- robust_parse_date(x)
  expect_s3_class(result, "POSIXct")
  expect_equal(format(result[1], "%Y-%m-%d"), "2023-01-01")
  expect_equal(format(result[4], "%Y-%m-%d"), "2024-02-01")
})

# Mixed non-date should return original

test_that("robust_parse_date returns original when parsing fails", {
  x <- c("notadate", "2023-01-01")
  result <- robust_parse_date(x, success_threshold = 0.8)
  expect_identical(result, x)
})

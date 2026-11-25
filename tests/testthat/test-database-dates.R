testthat::test_that("date columns use the SQL DATE type", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)

  column_id <- add_typed_column(connection, "visit_date", "date")

  testthat::expect_equal(get_column_definition(connection, column_id)$data_type, "date")
  testthat::expect_true("visit_date" %in% list_record_columns(connection))
  testthat::expect_error(add_typed_column(connection, "unsupported", "datetime"), "non pris en charge")
})

testthat::test_that("validate_date_value accepts strict ISO calendar dates", {
  testthat::expect_equal(validate_date_value("2024-02-29"), as.Date("2024-02-29"))
  testthat::expect_true(is.na(validate_date_value(NA_character_)))
  testthat::expect_true(is.na(validate_date_value("")))
})

testthat::test_that("validate_date_value rejects invalid and ambiguous dates", {
  testthat::expect_error(validate_date_value("2023-02-29"), "YYYY-MM-DD")
  testthat::expect_error(validate_date_value("2024-13-01"), "YYYY-MM-DD")
  testthat::expect_error(validate_date_value("01/02/2024"), "YYYY-MM-DD")
  testthat::expect_error(validate_date_value(c("2024-01-01", "2024-01-02")), "Une seule date")
})

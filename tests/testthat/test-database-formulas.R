testthat::test_that("binary numeric formulas recalculate from source columns", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  height_id <- add_typed_column(connection, "height", "real")
  weight_id <- add_typed_column(connection, "weight", "real")
  add_derived_column(connection, "bmi_numerator", list(
    mode = "binary",
    left_id = weight_id,
    operator = "multiply",
    right_id = height_id
  ))

  calculated <- calculate_derived_columns(
    data.frame(height = c(2, 3), weight = c(4, 5)),
    list_column_definitions(connection)
  )

  testthat::expect_equal(calculated$bmi_numerator, c(8, 15))
})

testthat::test_that("integer source arithmetic is promoted before overflow", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  left_id <- add_typed_column(connection, "left_value", "integer")
  right_id <- add_typed_column(connection, "right_value", "integer")
  add_derived_column(connection, "sum_value", list(
    mode = "binary", left_id = left_id, operator = "add", right_id = right_id
  ))

  calculated <- calculate_derived_columns(
    data.frame(left_value = 2000000000L, right_value = 2000000000L),
    list_column_definitions(connection)
  )

  testthat::expect_equal(calculated$sum_value, 4000000000)
})

testthat::test_that("missing inputs and division by zero produce missing results", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  numerator_id <- add_typed_column(connection, "numerator", "real")
  denominator_id <- add_typed_column(connection, "denominator", "real")
  add_derived_column(connection, "ratio", list(
    mode = "binary",
    left_id = numerator_id,
    operator = "divide",
    right_id = denominator_id
  ))

  calculated <- calculate_derived_columns(
    data.frame(numerator = c(4, 4, 4), denominator = c(2, 0, NA_real_)),
    list_column_definitions(connection)
  )

  testthat::expect_equal(calculated$ratio[[1]], 2)
  testthat::expect_true(all(is.na(calculated$ratio[2:3])))
})

testthat::test_that("date formulas calculate day differences and comparisons", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  start_id <- add_typed_column(connection, "start_date", "date")
  end_id <- add_typed_column(connection, "end_date", "date")
  add_derived_column(connection, "duration_days", list(
    mode = "binary",
    left_id = start_id,
    operator = "days_between",
    right_id = end_id
  ))
  add_derived_column(connection, "ends_later", list(
    mode = "binary",
    left_id = end_id,
    operator = "greater_than",
    right_id = start_id
  ))

  calculated <- calculate_derived_columns(
    data.frame(
      start_date = as.Date(c("2024-02-28", NA)),
      end_date = as.Date(c("2024-03-01", "2024-03-02"))
    ),
    list_column_definitions(connection)
  )

  testthat::expect_equal(calculated$duration_days[[1]], -2)
  testthat::expect_true(is.na(calculated$duration_days[[2]]))
  testthat::expect_true(calculated$ends_later[[1]])
})

testthat::test_that("conditional formulas compare columns and return selected values", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  value_id <- add_typed_column(connection, "value", "integer")
  threshold_id <- add_typed_column(connection, "threshold", "integer")
  add_derived_column(connection, "classification", list(
    mode = "if_else",
    left_id = value_id,
    operator = "greater_than",
    right_id = threshold_id,
    true_value = "high",
    false_value = "low",
    result_type = "text"
  ))

  calculated <- calculate_derived_columns(
    data.frame(value = c(8L, 2L, NA_integer_), threshold = c(5L, 5L, 5L)),
    list_column_definitions(connection)
  )

  testthat::expect_equal(calculated$classification[1:2], c("high", "low"))
  testthat::expect_true(is.na(calculated$classification[[3]]))
})

testthat::test_that("conditional formulas compare a column with a fixed numeric value", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  age_id <- add_typed_column(connection, "age", "integer")
  add_derived_column(connection, "adult_status", list(
    mode = "if_else",
    left_id = age_id,
    operator = "greater_or_equal",
    right_mode = "constant",
    right_value = "18",
    true_value = "adult",
    false_value = "minor",
    result_type = "text"
  ))

  calculated <- calculate_derived_columns(
    data.frame(age = c(17L, 18L, 25L, NA_integer_)),
    list_column_definitions(connection)
  )

  testthat::expect_equal(calculated$adult_status[1:3], c("minor", "adult", "adult"))
  testthat::expect_true(is.na(calculated$adult_status[[4]]))
})

testthat::test_that("fixed comparison values are converted to the source column type", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  event_date_id <- add_typed_column(connection, "event_date", "date")
  add_derived_column(connection, "before_cutoff", list(
    mode = "if_else",
    left_id = event_date_id,
    operator = "less_than",
    right_mode = "constant",
    right_value = "2024-01-01",
    true_value = "before",
    false_value = "after",
    result_type = "text"
  ))

  calculated <- calculate_derived_columns(
    data.frame(event_date = as.Date(c("2023-12-31", "2024-01-01", NA))),
    list_column_definitions(connection)
  )

  testthat::expect_equal(calculated$before_cutoff[1:2], c("before", "after"))
  testthat::expect_true(is.na(calculated$before_cutoff[[3]]))
  testthat::expect_error(add_derived_column(connection, "bad_cutoff", list(
    mode = "if_else",
    left_id = event_date_id,
    operator = "less_than",
    right_mode = "constant",
    right_value = "31-12-2024",
    true_value = "before",
    false_value = "after",
    result_type = "text"
  )), "YYYY-MM-DD")
})

testthat::test_that("text columns can be conditionally compared with a fixed string", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  status_id <- add_typed_column(connection, "status", "text")
  add_derived_column(connection, "is_approved", list(
    mode = "if_else",
    left_id = status_id,
    operator = "equal",
    right_mode = "constant",
    right_value = "approved",
    true_value = "yes",
    false_value = "no",
    result_type = "text"
  ))

  calculated <- calculate_derived_columns(
    data.frame(status = c("approved", "pending", NA_character_)),
    list_column_definitions(connection)
  )

  testthat::expect_equal(calculated$is_approved[1:2], c("yes", "no"))
  testthat::expect_true(is.na(calculated$is_approved[[3]]))
})

testthat::test_that("all comparison operators preserve missing comparisons", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  left_id <- add_typed_column(connection, "left_value", "integer")
  right_id <- add_typed_column(connection, "right_value", "integer")
  operators <- c("equal", "not_equal", "greater_than", "greater_or_equal", "less_than", "less_or_equal")

  for (operator in operators) {
    add_derived_column(connection, paste0("result_", operator), list(
      mode = "binary", left_id = left_id, operator = operator, right_id = right_id
    ))
  }

  calculated <- calculate_derived_columns(
    data.frame(left_value = c(1L, 2L, NA_integer_), right_value = c(1L, 1L, 1L)),
    list_column_definitions(connection)
  )

  testthat::expect_equal(calculated$result_equal, c(TRUE, FALSE, NA))
  testthat::expect_equal(calculated$result_not_equal, c(FALSE, TRUE, NA))
  testthat::expect_equal(calculated$result_greater_than, c(FALSE, TRUE, NA))
  testthat::expect_equal(calculated$result_greater_or_equal, c(TRUE, TRUE, NA))
  testthat::expect_equal(calculated$result_less_than, c(FALSE, FALSE, NA))
  testthat::expect_equal(calculated$result_less_or_equal, c(TRUE, FALSE, NA))
})

testthat::test_that("derived columns can be chained and circular definitions are rejected", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  first_id <- add_typed_column(connection, "first_value", "integer")
  second_id <- add_typed_column(connection, "second_value", "integer")
  sum_id <- add_derived_column(connection, "sum_value", list(
    mode = "binary",
    left_id = first_id,
    operator = "add",
    right_id = second_id
  ))
  testthat::expect_equal(read_derived_formula(connection, sum_id)$operator, "add")
  testthat::expect_error(read_derived_formula(connection, first_id), "ne possède pas de formule")
  doubled_id <- add_derived_column(connection, "doubled_sum", list(
    mode = "binary",
    left_id = sum_id,
    operator = "multiply",
    right_id = second_id
  ))

  calculated <- calculate_derived_columns(
    data.frame(first_value = 2L, second_value = 3L),
    list_column_definitions(connection)
  )
  testthat::expect_equal(calculated$doubled_sum, 15)

  testthat::expect_error(
    update_derived_formula(connection, sum_id, list(
      mode = "binary",
      left_id = doubled_id,
      operator = "add",
      right_id = second_id
    )),
    "circulaire"
  )
})

testthat::test_that("derived formulas reject missing sources and incompatible operators", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  value_id <- add_typed_column(connection, "value", "integer")
  date_id <- add_typed_column(connection, "event_date", "date")

  testthat::expect_error(add_derived_column(connection, "missing_source", list(
    mode = "binary", left_id = "unknown", operator = "add", right_id = value_id
  )), "n'existe pas")
  testthat::expect_error(add_derived_column(connection, "invalid_add", list(
    mode = "binary", left_id = value_id, operator = "add", right_id = date_id
  )), "types numériques")
  testthat::expect_error(add_derived_column(connection, "invalid_operator", list(
    mode = "binary", left_id = value_id, operator = "execute", right_id = value_id
  )), "Opération non autorisée")
  testthat::expect_error(add_derived_column(connection, "payload", list(
    mode = "binary", left_id = value_id, operator = "add", right_id = value_id
  )), "existe déjà")
  testthat::expect_error(add_derived_column(connection, "invalid_branch", list(
    mode = "if_else",
    left_id = value_id,
    operator = "greater_than",
    right_id = value_id,
    true_value = "not-a-number",
    false_value = "0",
    result_type = "integer"
  )), "résultat entier")
})

testthat::test_that("date formulas calculate complete months and years", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  start_id <- add_typed_column(connection, "start_date", "date")
  end_id <- add_typed_column(connection, "end_date", "date")

  add_derived_column(connection, "months_elapsed", list(
    mode = "binary", left_id = start_id, operator = "months_between", right_id = end_id
  ))
  add_derived_column(connection, "years_elapsed", list(
    mode = "binary", left_id = start_id, operator = "years_between", right_id = end_id
  ))

  calculated <- calculate_derived_columns(
    data.frame(
      start_date = as.Date(c("2024-02-28", "2024-02-29", "2024-05-31", "2024-05-31", NA)),
      end_date = as.Date(c("2024-04-27", "2024-03-28", "2022-05-30", "2026-05-31", "2024-01-01"))
    ),
    list_column_definitions(connection)
  )

  testthat::expect_equal(calculated$months_elapsed, c(-1L, 0L, 24L, -24L, NA_integer_))
  testthat::expect_equal(calculated$years_elapsed, c(0L, 0L, 2L, -2L, NA_integer_))
})

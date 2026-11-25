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

  testthat::expect_equal(calculated$duration_days[[1]], 2)
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

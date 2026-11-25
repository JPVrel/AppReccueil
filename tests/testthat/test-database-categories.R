testthat::test_that("categorical columns create text storage and typed metadata", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)

  column_id <- add_typed_column(connection, "cohort", "categorical")
  definition <- get_column_definition(connection, column_id)

  testthat::expect_equal(definition$data_type, "categorical")
  testthat::expect_equal(definition$sql_name, "cohort")
  testthat::expect_true("cohort" %in% list_record_columns(connection))
})

testthat::test_that("category entries can be listed and edited", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  column_id <- add_typed_column(connection, "cohort", "categorical")
  category_id <- add_category_entry(connection, column_id, "control", "Control")

  update_category_entry(connection, category_id, "comparison", "Comparison")
  category <- list_category_entries(connection, column_id)

  testthat::expect_equal(category$code, "comparison")
  testthat::expect_equal(category$label, "Comparison")
})

testthat::test_that("editing a category code updates stored responses", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  column_id <- add_typed_column(connection, "cohort", "categorical")
  category_id <- add_category_entry(connection, column_id, "control", "Control")
  DBI::dbExecute(
    connection,
    "INSERT INTO collection_records (id, created_at, payload, cohort) VALUES ('row-1', CURRENT_TIMESTAMP, '{}', 'control')"
  )

  update_category_entry(connection, category_id, "reference", "Reference")
  saved_code <- DBI::dbGetQuery(connection, "SELECT cohort FROM collection_records WHERE id = 'row-1'")$cohort

  testthat::expect_equal(saved_code, "reference")
})

testthat::test_that("category codes and labels safely preserve SQL quote characters", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  column_id <- add_typed_column(connection, "site", "categorical")
  category_id <- add_category_entry(connection, column_id, "west's_site", "West site's cohort")
  DBI::dbExecute(
    connection,
    "INSERT INTO collection_records (id, created_at, payload, site) VALUES ('row-1', CURRENT_TIMESTAMP, '{}', 'west''s_site')"
  )

  update_category_entry(connection, category_id, "north's_site", "North site's cohort")
  saved_code <- DBI::dbGetQuery(connection, "SELECT site FROM collection_records WHERE id = 'row-1'")$site
  category <- list_category_entries(connection, column_id)

  testthat::expect_equal(saved_code, "north's_site")
  testthat::expect_equal(category$label, "North site's cohort")
})

testthat::test_that("category codes are unique and labels cannot be empty", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  column_id <- add_typed_column(connection, "cohort", "categorical")
  category_id <- add_category_entry(connection, column_id, "control", "Control")

  testthat::expect_error(add_category_entry(connection, column_id, "control", "Other"), "existe déjà")
  testthat::expect_error(add_category_entry(connection, column_id, "case", ""), "obligatoires")
  testthat::expect_error(update_category_entry(connection, category_id, "case", " "), "obligatoires")
  case_id <- add_category_entry(connection, column_id, "case", "Case")
  testthat::expect_error(update_category_entry(connection, category_id, "case", "Duplicate"), "existe déjà")
  testthat::expect_error(remove_category_entry(connection, category_id, category_id), "différente")

  other_column_id <- add_typed_column(connection, "arm", "categorical")
  other_category_id <- add_category_entry(connection, other_column_id, "other", "Other")
  testthat::expect_error(
    remove_category_entry(connection, category_id, other_category_id),
    "même dictionnaire"
  )
  testthat::expect_true(case_id %in% list_category_entries(connection, column_id)$category_id)
})

testthat::test_that("removing a category requires and applies a replacement", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  column_id <- add_typed_column(connection, "cohort", "categorical")
  control_id <- add_category_entry(connection, column_id, "control", "Control")
  case_id <- add_category_entry(connection, column_id, "case", "Case")
  DBI::dbExecute(
    connection,
    "INSERT INTO collection_records (id, created_at, payload, cohort) VALUES ('row-1', CURRENT_TIMESTAMP, '{}', 'control')"
  )

  testthat::expect_error(remove_category_entry(connection, control_id), "réaffectation")
  remove_category_entry(connection, control_id, case_id)
  saved_code <- DBI::dbGetQuery(connection, "SELECT cohort FROM collection_records WHERE id = 'row-1'")$cohort

  testthat::expect_equal(saved_code, "case")
  testthat::expect_equal(list_category_entries(connection, column_id)$code, "case")
})

testthat::test_that("dictionary operations are blocked for hidden or non-categorical fields", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  text_id <- add_typed_column(connection, "comment", "text")
  category_id <- add_typed_column(connection, "cohort", "categorical")
  entry_id <- add_category_entry(connection, category_id, "control", "Control")

  testthat::expect_error(list_category_entries(connection, text_id), "uniquement pour les colonnes catégorielles")
  hide_column(connection, category_id)
  testthat::expect_error(update_category_entry(connection, entry_id, "reference", "Reference"), "masquée")
})

testthat::test_that("category text has an explicit length limit", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  category_id <- add_typed_column(connection, "cohort", "categorical")

  testthat::expect_error(add_category_entry(connection, category_id, strrep("A", 256), "Label"), "255 caractères")
})

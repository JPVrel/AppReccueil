testthat::test_that("database management display helpers handle empty and populated choices", {
  testthat::expect_length(select_choices(character(), character()), 0)
  testthat::expect_named(select_choices("column-id", "Participant age"), "Participant age")
  testthat::expect_equal(nrow(column_table_data(empty_column_definitions())), 0L)
})

testthat::test_that("initialization can read reactive state outside a consumer", {
  state <- shiny::reactiveVal("ready")
  input <- shiny::reactiveValues(dictionary_column_id = "cohort-id")

  testthat::expect_equal(read_reactive_state(state), "ready")
  testthat::expect_equal(read_shiny_input(input, "dictionary_column_id"), "cohort-id")
})

testthat::test_that("the variable table describes stored, categorical, date, and derived fields", {
  formula <- yaml::as.yaml(list(
    mode = "binary",
    left_id = "weight-id",
    operator = "divide",
    right_id = "height-id"
  ))
  definitions <- data.frame(
    column_id = c("weight-id", "height-id", "cohort-id", "date-id", "bmi-id"),
    name = c("weight", "height", "cohort", "visit_date", "bmi"),
    sql_name = c("weight", "height", "cohort", "visit_date", NA_character_),
    data_type = c("real", "real", "categorical", "date", "real"),
    is_hidden = rep(FALSE, 5),
    formula = c(NA_character_, NA_character_, NA_character_, NA_character_, formula)
  )

  variable_table <- column_table_data(definitions)

  testthat::expect_named(variable_table, c("Variable", "Type", "Nature", "Formule"))
  testthat::expect_equal(variable_table$Nature, c("Stockée", "Stockée", "Catégorielle", "Date", "Dérivée"))
  testthat::expect_equal(variable_table$Formule[[5]], "weight / height")
  testthat::expect_equal(nrow(column_table_data(empty_column_definitions())), 0L)
})

testthat::test_that("the category table exposes codes and labels", {
  categories <- data.frame(code = c("control", "case"), label = c("Control", "Case"))

  testthat::expect_equal(
    category_table_data(categories),
    data.frame(Code = c("control", "case"), Libellé = c("Control", "Case"))
  )
})

testthat::test_that("formula editor values are reconstructed from a stored definition", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  left_id <- add_typed_column(connection, "left_value", "integer")
  right_id <- add_typed_column(connection, "right_value", "integer")
  formula_id <- add_derived_column(connection, "classification", list(
    mode = "if_else",
    left_id = left_id,
    operator = "greater_than",
    right_id = right_id,
    true_value = "high",
    false_value = "low",
    result_type = "text"
  ))

  editor_values <- formula_editor_values(connection, formula_id)

  testthat::expect_equal(editor_values$mode, "if_else")
  testthat::expect_equal(editor_values$left_id, left_id)
  testthat::expect_equal(editor_values$operator, "greater_than")
  testthat::expect_equal(editor_values$true_value, "high")
  testthat::expect_equal(editor_values$false_value, "low")
})

testthat::test_that("the management UI handles types, dictionaries, formulas, and archives", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  management_server <- function(input, output, session) {
    database_management_server(input, output, session, connection, shiny::reactiveVal(0L))
  }

  shiny::testServer(management_server, {
    external_connection <- connection

    session$setInputs(
      new_column_name = "cohort",
      new_column_type = "categorical",
      add_column = 1
    )
    testthat::expect_match(output$column_status, "Colonne ajoutée : cohort")
    cohort_id <- DBI::dbGetQuery(
      external_connection,
      "SELECT column_id FROM column_definitions WHERE name = 'cohort'"
    )$column_id[[1]]

    session$setInputs(
      dictionary_column_id = cohort_id,
      new_category_code = "control",
      new_category_label = "Control",
      add_category = 1
    )
    control_id <- DBI::dbGetQuery(
      external_connection,
      "SELECT category_id FROM category_dictionary WHERE code = 'control'"
    )$category_id[[1]]
    session$setInputs(
      new_category_code = "case",
      new_category_label = "Case",
      add_category = 2
    )
    case_id <- DBI::dbGetQuery(
      external_connection,
      "SELECT category_id FROM category_dictionary WHERE code = 'case'"
    )$category_id[[1]]
    DBI::dbExecute(
      external_connection,
      "INSERT INTO collection_records (id, created_at, payload, cohort) VALUES ('ui-row', CURRENT_TIMESTAMP, '{}', 'control')"
    )

    session$setInputs(
      category_to_edit = control_id,
      edited_category_code = "reference",
      edited_category_label = "Reference",
      update_category = 1
    )
    testthat::expect_match(output$column_status, "réponses existantes synchronisées")
    testthat::expect_equal(
      DBI::dbGetQuery(external_connection, "SELECT cohort FROM collection_records WHERE id = 'ui-row'")$cohort,
      "reference"
    )

    session$setInputs(
      category_to_remove = control_id,
      replacement_category = case_id,
      remove_category = 1
    )
    testthat::expect_match(output$column_status, "Réponses réaffectées")
    testthat::expect_equal(
      DBI::dbGetQuery(external_connection, "SELECT cohort FROM collection_records WHERE id = 'ui-row'")$cohort,
      "case"
    )

    session$setInputs(
      new_column_name = "visit_date",
      new_column_type = "date",
      add_column = 2
    )
    testthat::expect_equal(
      DBI::dbGetQuery(external_connection, "SELECT data_type FROM column_definitions WHERE name = 'visit_date'")$data_type,
      "date"
    )

    session$setInputs(new_column_name = "start_score", new_column_type = "integer", add_column = 3)
    session$setInputs(new_column_name = "end_score", new_column_type = "integer", add_column = 4)
    source_ids <- DBI::dbGetQuery(
      external_connection,
      "SELECT name, column_id FROM column_definitions WHERE name IN ('start_score', 'end_score')"
    )
    session$setInputs(
      derived_column_name = "score_change",
      formula_mode = "binary",
      formula_left_id = source_ids$column_id[source_ids$name == "end_score"],
      formula_operator = "subtract",
      formula_right_id = source_ids$column_id[source_ids$name == "start_score"],
      add_derived_column = 1
    )
    testthat::expect_match(output$column_status, "Variable dérivée créée : score_change")
    formula_definitions <- list_column_definitions(external_connection)
    calculated <- calculate_derived_columns(
      data.frame(start_score = c(5L, NA_integer_), end_score = c(8L, 10L)),
      formula_definitions
    )
    testthat::expect_equal(calculated$score_change[[1]], 3)
    testthat::expect_true(is.na(calculated$score_change[[2]]))

    derived_id <- DBI::dbGetQuery(
      external_connection,
      "SELECT column_id FROM column_definitions WHERE name = 'score_change'"
    )$column_id[[1]]
    session$setInputs(
      derived_column_to_edit = derived_id,
      formula_mode = "binary",
      formula_left_id = source_ids$column_id[source_ids$name == "start_score"],
      formula_operator = "add",
      formula_right_id = source_ids$column_id[source_ids$name == "end_score"],
      update_derived_formula = 1
    )
    testthat::expect_match(output$column_status, "Formule mise à jour")
    updated_calculation <- calculate_derived_columns(
      data.frame(start_score = 5L, end_score = 8L),
      list_column_definitions(external_connection)
    )
    testthat::expect_equal(updated_calculation$score_change, 13)

    session$setInputs(column_to_hide = "cohort", hide_column = 1)
    testthat::expect_match(output$column_status, "Colonne masquée")
    testthat::expect_no_error(session$setInputs(dictionary_column_id = character()))
    session$setInputs(new_column_name = "cohort", new_column_type = "categorical", add_column = 5)
    session$setInputs(column_to_restore = cohort_id, restore_column = 1)
    testthat::expect_match(output$column_status, "cohort_2")
    testthat::expect_true("cohort_2" %in% list_column_definitions(external_connection)$name)
  })
})

testthat::test_that("spreadsheet header events route editable fields and reject system columns", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  management_server <- function(input, output, session) {
    database_management_server(input, output, session, connection, shiny::reactiveVal(0L))
  }

  shiny::testServer(management_server, {
    session$setInputs(new_column_name = "age", new_column_type = "integer", add_column = 1)

    session$setInputs(database_spreadsheet_header_dblclick = "age")
    testthat::expect_match(output$column_status, "age.*chargée pour modification")

    session$setInputs(database_spreadsheet_header_dblclick = "id")
    testthat::expect_match(output$column_status, "n'est pas une variable modifiable")
  })
})

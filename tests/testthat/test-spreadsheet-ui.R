testthat::test_that("the app exposes a central spreadsheet tab and management tab", {
  ui_html <- htmltools::renderTags(build_app_ui())$html
  css <- paste(readLines(file.path(project_dir, "shiny", "www", "app.css"), warn = FALSE), collapse = "\n")

  testthat::expect_match(ui_html, "Base de données")
  testthat::expect_match(ui_html, "Gestion des entrées")
  testthat::expect_match(ui_html, "Éléments supprimés")
  testthat::expect_match(ui_html, "database_spreadsheet")
  testthat::expect_match(ui_html, "download_database_csv")
  testthat::expect_match(ui_html, "download_database_xlsx")
  testthat::expect_match(ui_html, "download_database_rds")
  testthat::expect_match(ui_html, "Gestion des colonnes")
  testthat::expect_match(ui_html, "recueil-dblclick-hint")
  testthat::expect_match(ui_html, "application_tabs")
  testthat::expect_match(css, "\\.recueil-card \\.recueil-export-actions \\.btn \\{[[:space:]]*margin: 0;")
})

testthat::test_that("spreadsheet UI documents double-click header editing hook", {
  ui_html <- htmltools::renderTags(database_spreadsheet_ui())$html
  callback <- as.character(spreadsheet_header_callback())

  testthat::expect_match(ui_html, "database_spreadsheet")
  testthat::expect_match(callback, "database_spreadsheet_header_dblclick")
  testthat::expect_match(callback, "database_spreadsheet_row_dblclick")
  testthat::expect_match(callback, "dblclick")
  testthat::expect_true(grepl("table.table().container()", callback, fixed = TRUE))
  testthat::expect_match(callback, "thead tr:first-child th")
})

testthat::test_that("spreadsheet date values are formatted as ISO strings", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  add_typed_column(connection, "DDN", "date")

  formatted <- format_spreadsheet_dates(
    connection,
    data.frame(DDN = as.Date(c("1993-07-05", NA)))
  )

  testthat::expect_identical(formatted$DDN, c("1993-07-05", NA_character_))
})

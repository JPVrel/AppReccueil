testthat::test_that("the app exposes a central spreadsheet tab and management tab", {
  ui_html <- htmltools::renderTags(build_app_ui())$html

  testthat::expect_match(ui_html, "Base de données")
  testthat::expect_match(ui_html, "database_spreadsheet")
  testthat::expect_match(ui_html, "download_database_csv")
  testthat::expect_match(ui_html, "Gestion des variables")
  testthat::expect_match(ui_html, "application_tabs")
})

testthat::test_that("spreadsheet UI documents double-click header editing hook", {
  ui_html <- htmltools::renderTags(database_spreadsheet_ui())$html
  callback <- as.character(spreadsheet_header_callback())

  testthat::expect_match(ui_html, "database_spreadsheet")
  testthat::expect_match(callback, "database_spreadsheet_header_dblclick")
  testthat::expect_match(callback, "dblclick")
  testthat::expect_true(grepl("table.table().container()", callback, fixed = TRUE))
  testthat::expect_match(callback, "thead tr:first-child th")
})

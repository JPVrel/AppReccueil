testthat::test_that("build_shiny_app returns a Shiny application", {
  testthat::expect_s3_class(build_shiny_app(), "shiny.appobj")
})

testthat::test_that("the UI renders the database column-management tab", {
  ui_html <- htmltools::renderTags(build_app_ui())$html

  testthat::expect_match(ui_html, "Colonnes de la BDD")
  testthat::expect_match(ui_html, "add_column")
  testthat::expect_match(ui_html, "rename_column")
})

testthat::test_that("the collection status changes after starting", {
  shiny::testServer(build_app_server(), {
    testthat::expect_equal(output$status, "Aucun recueil n'est commencé.")
    session$setInputs(start_collection = 1)
    testthat::expect_equal(output$status, "Le parcours de recueil est prêt à être défini.")
  })
})

testthat::test_that("a configured Shiny session initializes the database", {
  database_config <- list(
    mode = "local",
    local = list(path = tempfile(fileext = ".sqlite"))
  )

  shiny::testServer(build_app_server(database_config), {
    testthat::expect_true(file.exists(database_config$local$path))
    testthat::expect_match(output$column_names, "payload")

    session$setInputs(
      new_column_name = "age",
      new_column_type = "INTEGER",
      add_column = 1
    )
    testthat::expect_match(output$column_names, "age")
    testthat::expect_match(output$column_status, "Colonne ajoutée : age")

    session$setInputs(
      column_to_rename = "age",
      renamed_column_name = "participant_age",
      rename_column = 1
    )
    testthat::expect_match(output$column_names, "participant_age")
    testthat::expect_match(output$column_status, "Colonne renommée : participant_age")
    testthat::expect_false(grepl("\\nage\\n", output$column_names))

    session$setInputs(
      new_column_name = "participant_age",
      new_column_type = "INTEGER",
      add_column = 2
    )
    testthat::expect_match(output$column_status, "existe déjà")

    session$setInputs(
      new_column_name = "invalid-name",
      new_column_type = "TEXT",
      add_column = 3
    )
    testthat::expect_match(output$column_status, "commencer par une lettre")
  })
})

testthat::test_that("column-management actions explain when no database is connected", {
  shiny::testServer(build_app_server(), {
    session$setInputs(
      new_column_name = "age",
      new_column_type = "INTEGER",
      add_column = 1
    )
    testthat::expect_match(output$column_status, "base de données n'est pas connectée")
  })
})

# Construit uniquement l'interface visuelle. Cette séparation rend possible
# une évolution du formulaire sans modifier le lanceur local.
build_app_ui <- function() {
  shiny::fluidPage(
    shiny::tags$head(
      shiny::tags$meta(name = "viewport", content = "width=device-width, initial-scale=1"),
      shiny::tags$link(rel = "stylesheet", href = "app.css")
    ),
    shiny::div(
      class = "app-header",
      shiny::div(
        shiny::h1("Application de recueil"),
        shiny::p(class = "app-subtitle", "Préparez, consultez et restaurez vos observations")
      )
    ),
    shiny::tabsetPanel(
      id = "application_tabs",
      database_home_ui(),
      record_entry_ui(),
      database_spreadsheet_ui(),
      database_management_ui(),
      deleted_items_ui()
    )
  )
}

# Construit la logique réactive de l'application. La connexion est créée
# par session pour isoler les utilisateurs lorsque l'application sera distante.
build_app_server <- function(database_config = NULL, export_dir = NULL) {
  function(input, output, session) {
    project_dir <- if (!is.null(database_config$project_dir)) {
      database_config$project_dir
    } else {
      normalizePath(getwd())
    }
    data_dir <- if (!is.null(database_config$local$path)) {
      dirname(database_config$local$path)
    } else {
      file.path(project_dir, "data")
    }
    dir.create(data_dir, recursive = TRUE, showWarnings = FALSE)

    session_export_dir <- export_dir
    if (is.null(session_export_dir)) {
      session_export_dir <- database_spreadsheet_export_dir(project_dir)
    }

    connection <- shiny::reactiveVal(NULL)
    vault <- shiny::reactiveVal(NULL)
    database_refresh <- shiny::reactiveVal(0L)

    if (!is.null(database_config) && identical(database_config$mode, "remote")) {
      remote_connection <- connect_database(database_config)
      initialize_database(remote_connection)
      connection(remote_connection)
      vault(list(
        connection = remote_connection,
        vault_path = "base distante",
        password = NULL,
        encrypted = FALSE,
        remote = TRUE,
        working_path = NULL,
        workspace = NULL,
        lock_path = NULL
      ))
    }

    database_home_server(
      input,
      output,
      session,
      data_dir,
      connection,
      vault,
      database_refresh
    )
    session$onSessionEnded(function() {
      active_vault <- shiny::isolate(vault())
      if (!is.null(active_vault)) {
        try(close_database_state(active_vault), silent = TRUE)
      }
    })

    output$download_database_csv <- encrypted_database_spreadsheet_download_handler(
      vault,
      session_export_dir,
      "csv",
      function() input$database_export_password
    )
    output$download_database_xlsx <- encrypted_database_spreadsheet_download_handler(
      vault,
      session_export_dir,
      "xlsx",
      function() input$database_export_password
    )
    output$download_database_rds <- encrypted_database_spreadsheet_download_handler(
      vault,
      session_export_dir,
      "rds",
      function() input$database_export_password
    )

    database_spreadsheet_server(input, output, connection, database_refresh)
    database_management_server(input, output, session, connection, database_refresh)
    record_entry_server(input, output, session, connection, database_refresh)
    deleted_items_server(input, output, session, connection, database_refresh)
    session$onFlushed(function() {
      for (output_id in c(
        "database_spreadsheet",
        "record_questionnaire_fields",
        "record_form_actions",
        "record_entry_status",
        "deleted_columns_table",
        "deleted_records_table",
        "deleted_items_status",
        "active_variables_table",
        "archived_variables_table",
        "category_entries",
        "column_status",
        "spreadsheet_status",
        "download_database_csv",
        "download_database_xlsx",
        "download_database_rds"
      )) {
        shiny::outputOptions(output, output_id, suspendWhenHidden = FALSE)
      }
    }, once = TRUE)
  }
}

# Assemble l'interface et le serveur dans l'objet attendu par Shiny.
build_shiny_app <- function(database_config = NULL) {
  shiny::shinyApp(build_app_ui(), build_app_server(database_config))
}

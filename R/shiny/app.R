# Construit uniquement l'interface visuelle. Cette séparation rend possible
# une évolution du formulaire sans modifier le lanceur local.
build_app_ui <- function() {
  shiny::fluidPage(
    shiny::titlePanel("Application de recueil de données"),
    shiny::tabsetPanel(
      id = "application_tabs",
      shiny::tabPanel(
        "Accueil",
        value = "home",
        shiny::sidebarLayout(
          shiny::sidebarPanel(
            shiny::h4("Parcours"),
            shiny::p("Cette application servira à structurer et enregistrer les données de recherche."),
            shiny::actionButton("start_collection", "Commencer un recueil", class = "btn-primary")
          ),
          shiny::mainPanel(
            shiny::h3("Bienvenue"),
            shiny::p("La première version prépare l'interface. Les champs de recueil seront ajoutés progressivement."),
            shiny::textOutput("status")
          )
        )
      ),
      database_spreadsheet_ui(),
      database_management_ui()
    )
  )
}

# Construit la logique réactive de l'application. La connexion est créée
# par session pour isoler les utilisateurs lorsque l'application sera distante.
build_app_server <- function(database_config = NULL, export_dir = NULL) {
  function(input, output, session) {
    session_export_dir <- export_dir
    if (is.null(session_export_dir)) {
      project_dir <- if (is.null(database_config)) {
        normalizePath(getwd())
      } else {
        database_config$project_dir
      }
      session_export_dir <- database_spreadsheet_export_dir(project_dir)
    }

    connection <- NULL
    if (!is.null(database_config)) {
      connection <- connect_database(database_config)
      initialize_database(connection)
      session$onSessionEnded(function() disconnect_database(connection))
    }
    database_refresh <- shiny::reactiveVal(0L)

    collection_started <- shiny::reactiveVal(FALSE)

    # Pour l'instant, le bouton simule simplement le début d'un recueil.
    # Les champs métier remplaceront cette étape dans une prochaine version.
    shiny::observeEvent(input$start_collection, {
      collection_started(TRUE)
    })

    output$status <- shiny::renderText({
      if (collection_started()) {
        "Le parcours de recueil est prêt à être défini."
      } else {
        "Aucun recueil n'est commencé."
      }
    })

    output$download_database_csv <- database_spreadsheet_download_handler(
      connection,
      session_export_dir,
      "csv"
    )
    output$download_database_xlsx <- database_spreadsheet_download_handler(
      connection,
      session_export_dir,
      "xlsx"
    )
    output$download_database_rds <- database_spreadsheet_download_handler(
      connection,
      session_export_dir,
      "rds"
    )

    database_spreadsheet_server(input, output, connection, database_refresh)
    database_management_server(input, output, session, connection, database_refresh)
  }
}

# Assemble l'interface et le serveur dans l'objet attendu par Shiny.
build_shiny_app <- function(database_config = NULL) {
  shiny::shinyApp(build_app_ui(), build_app_server(database_config))
}

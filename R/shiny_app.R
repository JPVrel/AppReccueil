# Construit uniquement l'interface visuelle. Cette séparation rend possible
# une évolution du formulaire sans modifier le lanceur local.
build_app_ui <- function() {
  shiny::fluidPage(
    shiny::titlePanel("Application de recueil de données"),
    shiny::tabsetPanel(
      shiny::tabPanel(
        "Accueil",
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
      shiny::tabPanel(
        "Colonnes de la BDD",
        shiny::fluidRow(
          shiny::column(
            width = 6,
            shiny::h3("Colonnes de la table des recueils"),
            shiny::p("Les colonnes techniques sont protégées. Renommer une colonne conserve les valeurs existantes."),
            shiny::verbatimTextOutput("column_names")
          ),
          shiny::column(
            width = 6,
            shiny::h3("Ajouter une colonne"),
            shiny::textInput("new_column_name", "Nom de la colonne"),
            shiny::selectInput(
              "new_column_type",
              "Type de données",
              choices = allowed_record_column_types()
            ),
            shiny::actionButton("add_column", "Ajouter la colonne"),
            shiny::hr(),
            shiny::h3("Renommer une colonne"),
            shiny::selectInput("column_to_rename", "Colonne personnalisée", choices = character()),
            shiny::textInput("renamed_column_name", "Nouveau nom"),
            shiny::actionButton("rename_column", "Renommer la colonne"),
            shiny::textOutput("column_status")
          )
        )
      )
    )
  )
}

# Construit la logique réactive de l'application. La connexion est créée
# par session pour isoler les utilisateurs lorsque l'application sera distante.
build_app_server <- function(database_config = NULL) {
  function(input, output, session) {
    connection <- NULL
    if (!is.null(database_config)) {
      connection <- connect_database(database_config)
      initialize_database(connection)
      session$onSessionEnded(function() disconnect_database(connection))
    }

    columns <- shiny::reactiveVal(
      if (is.null(connection)) character() else list_record_columns(connection)
    )
    column_status <- shiny::reactiveVal("")

    refresh_column_controls <- function() {
      columns(list_record_columns(connection))
      custom_columns <- setdiff(columns(), protected_record_columns())
      shiny::updateSelectInput(
        session,
        "column_to_rename",
        choices = custom_columns
      )
    }

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

    output$column_names <- shiny::renderText({
      paste(columns(), collapse = "\n")
    })
    output$column_status <- shiny::renderText(column_status())

    shiny::observeEvent(input$add_column, {
      if (is.null(connection)) {
        column_status("La base de données n'est pas connectée.")
        return()
      }

      tryCatch({
        add_record_column(connection, input$new_column_name, input$new_column_type)
        refresh_column_controls()
        column_status(paste("Colonne ajoutée :", input$new_column_name))
      }, error = function(condition) {
        column_status(conditionMessage(condition))
      })
    })

    shiny::observeEvent(input$rename_column, {
      if (is.null(connection)) {
        column_status("La base de données n'est pas connectée.")
        return()
      }

      tryCatch({
        rename_record_column(connection, input$column_to_rename, input$renamed_column_name)
        refresh_column_controls()
        column_status(paste("Colonne renommée :", input$renamed_column_name))
      }, error = function(condition) {
        column_status(conditionMessage(condition))
      })
    })
  }
}

# Assemble l'interface et le serveur dans l'objet attendu par Shiny.
build_shiny_app <- function(database_config = NULL) {
  shiny::shinyApp(build_app_ui(), build_app_server(database_config))
}

# Construit uniquement l'interface visuelle. Cette séparation rend possible
# une évolution du formulaire sans modifier le lanceur local.
build_app_ui <- function() {
  shiny::fluidPage(
    shiny::titlePanel("Application de recueil de données"),
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
  )
}

# Construit la logique réactive de l'application.
build_app_server <- function() {
  function(input, output, session) {
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
  }
}

# Assemble l'interface et le serveur dans l'objet attendu par Shiny.
build_shiny_app <- function() {
  shiny::shinyApp(build_app_ui(), build_app_server())
}

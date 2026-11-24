library(shiny)

ui <- fluidPage(
  titlePanel("Application de recueil de données"),
  sidebarLayout(
    sidebarPanel(
      h4("Parcours"),
      p("Cette application servira à structurer et enregistrer les données de recherche."),
      actionButton("start_collection", "Commencer un recueil", class = "btn-primary")
    ),
    mainPanel(
      h3("Bienvenue"),
      p("La première version prépare l'interface. Les champs de recueil seront ajoutés progressivement."),
      textOutput("status")
    )
  )
)

server <- function(input, output, session) {
  collection_started <- reactiveVal(FALSE)

  observeEvent(input$start_collection, {
    collection_started(TRUE)
  })

  output$status <- renderText({
    if (collection_started()) {
      "Le parcours de recueil est prêt à être défini."
    } else {
      "Aucun recueil n'est commencé."
    }
  })
}

shinyApp(ui, server)

# Données affichées dans la vue centrale, y compris les variables dérivées calculées à la lecture.
database_spreadsheet_data <- function(connection) {
  records <- read_collection_records(connection)
  records[, setdiff(names(records), "payload"), drop = FALSE]
}

write_database_spreadsheet_csv <- function(connection, file) {
  records <- if (is.null(connection)) empty_database_spreadsheet() else database_spreadsheet_data(connection)
  utils::write.csv(records, file, row.names = FALSE, na = "", fileEncoding = "UTF-8")
  invisible(file)
}

database_spreadsheet_export_dir <- function(project_dir) {
  file.path(project_dir, "exports")
}

next_spreadsheet_export_path <- function(export_dir, export_time = Sys.time()) {
  dir.create(export_dir, recursive = TRUE, showWarnings = FALSE)
  timestamp <- format(export_time, "%Y%m%d-%H%M%S", tz = "UTC")
  base_name <- paste0("recueil-", timestamp)
  candidate <- file.path(export_dir, paste0(base_name, ".csv"))
  suffix <- 2L

  while (file.exists(candidate)) {
    candidate <- file.path(export_dir, paste0(base_name, "-", suffix, ".csv"))
    suffix <- suffix + 1L
  }

  candidate
}

archive_database_spreadsheet_csv <- function(
  connection,
  export_dir,
  export_time = Sys.time()
) {
  export_path <- next_spreadsheet_export_path(export_dir, export_time)
  write_database_spreadsheet_csv(connection, export_path)
  export_path
}

empty_database_spreadsheet <- function() {
  data.frame(
    id = character(),
    created_at = as.POSIXct(character())
  )
}

# Résout un en-tête visible vers une seule définition modifiable.
# Les colonnes système et les variables masquées restent volontairement non éditables ici.
spreadsheet_header_edit_target <- function(definitions, header_name) {
  if (length(header_name) != 1L || is.na(header_name) || !nzchar(header_name)) {
    return(NULL)
  }

  active <- definitions[!definitions$is_hidden & definitions$name == header_name, , drop = FALSE]
  if (nrow(active) == 0L) {
    return(NULL)
  }
  if (nrow(active) > 1L) {
    stop("L'en-tête sélectionné est ambigu ; corrige les noms de variables avant édition.")
  }

  active
}

spreadsheet_header_callback <- function() {
  # DataTables clone l'en-tête quand scrollX est activé ; déléguer au conteneur
  # capte les doubles-clics sur l'en-tête réellement visible.
  DT::JS(
    "var container = table.table().container();",
    "$(container).on('dblclick', 'thead tr:first-child th', function() {",
    "  var columnIndex = $(this).index();",
    "  var headerName = table.column(columnIndex).header().textContent.trim();",
    "  if (headerName) Shiny.setInputValue('database_spreadsheet_header_dblclick', headerName, { priority: 'event' });",
    "});"
  )
}

database_spreadsheet_ui <- function() {
  shiny::tabPanel(
    "Base de données",
    value = "spreadsheet",
    shiny::p("Vue centralisée des observations. Double-clique sur un en-tête pour ouvrir les paramètres de cette variable."),
    shiny::downloadButton("download_database_csv", "Exporter en CSV"),
    DT::DTOutput("database_spreadsheet"),
    shiny::textOutput("spreadsheet_status")
  )
}

database_spreadsheet_server <- function(input, output, connection, refresh_trigger) {
  output$database_spreadsheet <- DT::renderDT({
    refresh_trigger()
    if (is.null(connection)) {
      records <- empty_database_spreadsheet()
    } else {
      records <- database_spreadsheet_data(connection)
    }

    DT::datatable(
      records,
      rownames = FALSE,
      filter = "top",
      options = list(
        dom = "ftip",
        pageLength = 25,
        lengthMenu = c(10, 25, 50, 100),
        scrollX = TRUE,
        autoWidth = TRUE
      ),
      callback = spreadsheet_header_callback()
    )
  }, server = TRUE)
}

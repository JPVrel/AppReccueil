# Données affichées dans la vue centrale, y compris les variables dérivées calculées à la lecture.
database_spreadsheet_data <- function(connection) {
  records <- read_collection_records(connection)
  records[, setdiff(names(records), "payload"), drop = FALSE]
}

neutralize_csv_formulas <- function(records) {
  character_columns <- names(records)[vapply(records, is.character, logical(1))]

  for (column in character_columns) {
    value <- records[[column]]
    formula_like <- !is.na(value) & grepl("^[[:space:]]*[=+@-]", value)
    value[formula_like] <- paste0("'", value[formula_like])
    records[[column]] <- value
  }

  records
}

write_database_spreadsheet <- function(connection, file, format = c("csv", "xlsx", "rds")) {
  format <- match.arg(format)
  records <- if (is.null(connection)) empty_database_spreadsheet() else database_spreadsheet_data(connection)

  switch(
    format,
    csv = utils::write.csv(
      neutralize_csv_formulas(records),
      file,
      row.names = FALSE,
      na = "",
      fileEncoding = "UTF-8"
    ),
    xlsx = writexl::write_xlsx(records, path = file),
    rds = saveRDS(records, file)
  )
  invisible(file)
}

write_database_spreadsheet_csv <- function(connection, file) {
  write_database_spreadsheet(connection, file, "csv")
}

database_spreadsheet_export_dir <- function(project_dir) {
  file.path(project_dir, "exports")
}

reserve_spreadsheet_export_path <- function(path) {
  lock_dir <- paste0(path, ".lock")
  if (!dir.create(lock_dir, showWarnings = FALSE)) {
    if (dir.exists(lock_dir) || file.exists(path)) {
      return(FALSE)
    }
    stop("Le chemin d'export ne peut pas être réservé.")
  }
  on.exit(unlink(lock_dir, recursive = TRUE), add = TRUE)

  if (file.exists(path)) {
    return(FALSE)
  }

  reserved <- file.create(path)
  if (!reserved && !file.exists(path)) {
    stop("Le fichier d'export ne peut pas être créé.")
  }
  if (reserved) {
    Sys.chmod(path, mode = "0600")
  }
  reserved
}

next_spreadsheet_export_path <- function(
  export_dir,
  export_time = Sys.time(),
  format = c("csv", "xlsx", "rds")
) {
  format <- match.arg(format)
  dir.create(export_dir, recursive = TRUE, showWarnings = FALSE)
  if (!dir.exists(export_dir)) {
    stop("Le dossier d'exports ne peut pas être créé.")
  }

  timestamp <- format(export_time, "%Y%m%d-%H%M%S", tz = "UTC")
  base_name <- paste0("recueil-", timestamp)
  candidate <- file.path(export_dir, paste0(base_name, ".", format))
  suffix <- 2L

  while (!reserve_spreadsheet_export_path(candidate)) {
    candidate <- file.path(export_dir, paste0(base_name, "-", suffix, ".", format))
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

archive_database_spreadsheet <- function(
  connection,
  export_dir,
  format = c("csv", "xlsx", "rds"),
  export_time = Sys.time()
) {
  format <- match.arg(format)
  export_path <- next_spreadsheet_export_path(export_dir, export_time, format)
  write_database_spreadsheet(connection, export_path, format)
  export_path
}

database_spreadsheet_download_handler <- function(connection, export_dir, format) {
  last_export_name <- shiny::reactiveVal(NULL)
  format <- match.arg(format, c("csv", "xlsx", "rds"))

  shiny::downloadHandler(
    filename = function() {
      export_path <- next_spreadsheet_export_path(export_dir, format = format)
      export_name <- basename(export_path)
      last_export_name(export_name)
      export_name
    },
    content = function(file) {
      export_name <- shiny::isolate(last_export_name())
      if (is.null(export_name) || !nzchar(export_name)) {
        export_path <- next_spreadsheet_export_path(export_dir, format = format)
        export_name <- basename(export_path)
      }

      archive_path <- file.path(export_dir, export_name)
      write_database_spreadsheet(connection, archive_path, format)
      if (!file.copy(archive_path, file, overwrite = TRUE)) {
        stop("Le fichier d'export ne peut pas être copié vers le téléchargement.")
      }
    }
  )
}

encrypted_database_spreadsheet_download_handler <- function(
  vault_state,
  export_dir,
  format,
  export_password = function() NULL
) {
  format <- match.arg(format, c("csv", "xlsx", "rds"))
  current_export <- shiny::reactiveVal(NULL)

  read_export_password <- function() {
    password <- shiny::isolate(export_password())
    if (is.null(password) || !nzchar(password)) {
      return(NULL)
    }
    validate_vault_password(password)
    password
  }

  reserve_export <- function(password) {
    if (is.null(password)) {
      next_spreadsheet_export_path(export_dir, format = format)
    } else {
      next_encrypted_export_path(export_dir, format)
    }
  }

  shiny::downloadHandler(
    filename = function() {
      if (is.null(shiny::isolate(vault_state()))) {
        stop("Ouvre une base avant d'exporter.")
      }
      password <- read_export_password()
      export_path <- reserve_export(password)
      current_export(list(path = export_path, password = password))
      basename(export_path)
    },
    content = function(file) {
      vault <- shiny::isolate(vault_state())
      if (is.null(vault)) {
        stop("Ouvre une base chiffrée avant d'exporter.")
      }

      export <- shiny::isolate(current_export())
      if (is.null(export)) {
        password <- read_export_password()
        export <- list(path = reserve_export(password), password = password)
      }
      workspace <- new_private_database_workspace()
      on.exit(unlink(workspace$directory, recursive = TRUE), add = TRUE)
      plain_path <- file.path(workspace$directory, paste0("export.", format))
      write_database_spreadsheet(vault$connection, plain_path, format)
      Sys.chmod(plain_path, mode = "0600")
      if (is.null(export$password)) {
        copied <- file.copy(plain_path, export$path, overwrite = TRUE)
      } else {
        encrypt_file_with_password(plain_path, export$path, export$password)
        copied <- TRUE
      }
      if (!copied || !file.copy(export$path, file, overwrite = TRUE)) {
        stop("L'export chiffré ne peut pas être copié vers le téléchargement.")
      }
    }
  )
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
    "});",
    "$(container).on('dblclick', 'tbody tr', function() {",
    "  var rowData = table.row(this).data();",
    "  if (rowData && rowData[0]) Shiny.setInputValue('database_spreadsheet_row_dblclick', rowData[0], { priority: 'event' });",
    "});"
  )
}

database_spreadsheet_ui <- function() {
  shiny::tabPanel(
    "Base de données",
    value = "spreadsheet",
    shiny::p("Vue centralisée des observations. Double-clique sur un en-tête pour ouvrir les paramètres de cette variable."),
    shiny::div(
      class = "btn-toolbar",
      role = "toolbar",
      shiny::div(
        class = "btn-group",
        role = "group",
        shiny::downloadButton("download_database_csv", "CSV"),
        shiny::downloadButton("download_database_xlsx", "Excel (.xlsx)"),
        shiny::downloadButton("download_database_rds", "R data frame (.rds)")
      ),
      shiny::passwordInput(
        "database_export_password",
        "Mot de passe pour chiffrer l'export (facultatif, 12 caractères minimum si utilisé)"
      ),
      shiny::p("Si ce champ reste vide, le fichier sera exporté sans chiffrement.")
    ),
    DT::DTOutput("database_spreadsheet"),
    shiny::textOutput("spreadsheet_status")
  )
}

database_spreadsheet_server <- function(input, output, connection, refresh_trigger) {
  output$database_spreadsheet <- DT::renderDT({
    refresh_trigger()
    current_connection <- if (is.function(connection)) connection() else connection
    if (is.null(current_connection)) {
      records <- empty_database_spreadsheet()
    } else {
      records <- database_spreadsheet_data(current_connection)
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

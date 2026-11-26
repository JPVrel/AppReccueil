record_field_input_id <- function(field_name) {
  paste0("record_field__", field_name)
}

record_entry_ui <- function() {
  shiny::tabPanel(
    "Gestion des entrées",
    value = "entry_management",
    shiny::h2(class = "recueil-page-title", "Gestion des entrées"),
    shiny::p(class = "recueil-page-subtitle", "Recherchez une entrée existante, modifiez-la ou créez-en une nouvelle."),
    shiny::div(
      class = "recueil-grid",
      shiny::div(
        class = "recueil-card recueil-span-6",
        shiny::h3("Rechercher une entrée à modifier"),
        shiny::selectizeInput(
          "record_to_edit",
          "Entrée",
          choices = character(),
          options = list(placeholder = "Saisissez un ID ou une date", maxOptions = 1000)
        ),
        shiny::actionButton("load_record", "Charger l'entrée", class = "btn-primary")
      ),
      shiny::div(
        class = "recueil-card recueil-span-6",
        shiny::h3("Format de l'ID"),
        shiny::textInput("record_id_prefix", "Préfixe", value = "row_"),
        shiny::numericInput("record_id_number", "Prochain numéro", value = 1, min = 1, step = 1),
        shiny::textInput("record_id_value", "ID de cette entrée")
      )
    ),
    shiny::div(
      class = "recueil-card recueil-span-12",
      shiny::h3("Données de l'entrée"),
      shiny::uiOutput("record_questionnaire_fields"),
      shiny::div(class = "recueil-action-bar", shiny::uiOutput("record_form_actions")),
      shiny::div(class = "recueil-status", shiny::textOutput("record_entry_status"))
    )
  )
}

deleted_items_ui <- function() {
  shiny::tabPanel(
    "Éléments supprimés",
    value = "deleted_items",
    shiny::h2(class = "recueil-page-title", "Éléments supprimés"),
    shiny::p(class = "recueil-page-subtitle", "Retrouvez les colonnes ou entrées masquées et restaurez-les sous leur nom ou avec un identifiant alternatif."),
    shiny::div(
      class = "recueil-grid",
      shiny::div(
        class = "recueil-card recueil-span-6",
        shiny::h3("Colonnes masquées"),
        shiny::tableOutput("deleted_columns_table"),
        shiny::selectInput("deleted_column_id", "Colonne à restaurer", choices = character()),
        shiny::textInput("deleted_column_new_name", "Nouvelle entête si nécessaire", placeholder = "Optionnel : seulement en cas de collision"),
        shiny::actionButton("restore_deleted_column", "Restaurer la colonne", class = "btn-primary")
      ),
      shiny::div(
        class = "recueil-card recueil-span-6",
        shiny::h3("Entrées masquées"),
        shiny::tableOutput("deleted_records_table"),
        shiny::selectInput("deleted_record_id", "Observation à restaurer", choices = character()),
        shiny::textInput("deleted_record_new_id", "Nouvel ID si nécessaire", placeholder = "Optionnel : seulement en cas de collision"),
        shiny::actionButton("restore_deleted_record", "Restaurer l'observation", class = "btn-primary")
      )
    ),
    shiny::div(class = "recueil-status", shiny::textOutput("deleted_items_status"))
  )
}

record_entry_server <- function(input, output, session, connection, refresh_trigger) {
  current_connection <- function() {
    if (is.function(connection)) shiny::isolate(connection()) else connection
  }
  editing_record_id <- shiny::reactiveVal(NULL)
  record_status <- shiny::reactiveVal("")
  form_generation <- shiny::reactiveVal(0L)
  field_signature <- shiny::reactiveVal(NULL)
  field_input_cache <- new.env(parent = emptyenv())
  field_input_cache$values <- list()

  active_connection <- function() {
    if (is.function(connection)) connection() else connection
  }

  shiny::observe({
    field_input_cache$values <- shiny::reactiveValuesToList(input)
  })

  shiny::observe({
    refresh_trigger()
    active <- active_connection()
    signature <- if (is.null(active)) {
      NULL
    } else {
      definitions <- active_record_field_definitions(active)
      definitions[, c("column_id", "name", "data_type"), drop = FALSE]
    }
    if (!identical(signature, shiny::isolate(field_signature()))) {
      field_signature(signature)
      form_generation(form_generation() + 1L)
    }
  })

  output$record_questionnaire_fields <- shiny::renderUI({
    form_generation()
    active <- active_connection()
    if (is.null(active)) {
      return(shiny::p("Ouvrez une base avant de remplir le questionnaire."))
    }

    definitions <- active_record_field_definitions(active)
    cached_values <- field_input_cache$values
    cached_value <- function(input_id, fallback = "") {
      value <- cached_values[[input_id]]
      if (is.null(value)) fallback else value
    }
    shiny::div(
      class = "recueil-field-grid",
      shiny::tagList(lapply(seq_len(nrow(definitions)), function(row_index) {
        definition <- definitions[row_index, , drop = FALSE]
        field_name <- definition$name[[1]]
        input_id <- record_field_input_id(field_name)
        data_type <- definition$data_type[[1]]

        if (identical(data_type, "categorical")) {
          categories <- list_category_entries(active, definition$column_id[[1]])
          category_choices <- if (nrow(categories) == 0L) {
            character()
          } else {
            stats::setNames(categories$code, paste0(categories$label, " (", categories$code, ")"))
          }
          choices <- c(
            stats::setNames("", ""),
            category_choices
          )
          selected <- cached_value(input_id)
          if (!selected %in% unname(choices)) selected <- ""
          return(shiny::selectInput(input_id, field_name, choices = choices, selected = selected))
        }
        if (identical(data_type, "boolean")) {
          selected <- cached_value(input_id)
          if (!selected %in% c("", "TRUE", "FALSE")) selected <- ""
          return(shiny::selectInput(
            input_id,
            field_name,
            choices = stats::setNames(c("", "TRUE", "FALSE"), c("", "Oui", "Non")),
            selected = selected
          ))
        }
        if (identical(data_type, "date")) {
          return(shiny::dateInput(
            input_id,
            field_name,
            value = cached_value(input_id, NULL),
            language = "fr",
            format = "yyyy-mm-dd",
            weekstart = 1
          ))
        }
        shiny::textInput(input_id, field_name, value = cached_value(input_id))
      }))
    )
  })

  output$record_form_actions <- shiny::renderUI({
    if (is.null(active_connection())) {
      return(NULL)
    }
    actions <- list(
      shiny::actionButton("new_record", "Nouvelle entrée"),
      shiny::actionButton("save_record", "Enregistrer l'entrée", class = "btn-primary")
    )
    if (!is.null(editing_record_id())) {
      actions <- c(actions, list(shiny::actionButton("mask_record", "Supprimer (masquer) l'entrée", class = "btn-warning")))
    }
    do.call(shiny::tagList, actions)
  })

  output$record_entry_status <- shiny::renderText(record_status())

  generated_record_id <- function() {
    prefix <- input$record_id_prefix
    number <- input$record_id_number
    if (is.null(prefix) || !nzchar(prefix)) prefix <- "row_"
    if (is.null(number) || is.na(number)) number <- 1
    new_collection_record_id(current_connection(), prefix, number)
  }

  refresh_record_choices <- function() {
    active <- current_connection()
    if (is.null(active)) {
      shiny::updateSelectizeInput(session, "record_to_edit", choices = character(), server = FALSE)
      return(invisible(NULL))
    }
    records <- read_collection_records(active)
    choices <- if (nrow(records) == 0L) {
      character()
    } else {
      labels <- paste(records$id, "—", records$created_at)
      stats::setNames(records$id, labels)
    }
    shiny::updateSelectizeInput(
      session,
      "record_to_edit",
      choices = choices,
      selected = shiny::isolate(input$record_to_edit),
      server = nrow(records) > 0L
    )
    invisible(NULL)
  }

  reset_questionnaire <- function(record_id = NULL) {
    if (is.null(record_id)) record_id <- generated_record_id()
    editing_record_id(NULL)
    shiny::updateTextInput(session, "record_id_value", value = record_id)
    definitions <- active_record_field_definitions(current_connection())
    cleared_values <- stats::setNames(vector("list", nrow(definitions)), vapply(
      definitions$name,
      record_field_input_id,
      character(1)
    ))
    for (field_name in definitions$name) {
      input_id <- record_field_input_id(field_name)
      data_type <- definitions$data_type[match(field_name, definitions$name)]
      cleared_values[[input_id]] <- if (data_type == "date") NA else ""
    }
    field_input_cache$values <- cleared_values
    for (field_name in definitions$name) {
      input_id <- record_field_input_id(field_name)
      data_type <- definitions$data_type[match(field_name, definitions$name)]
      if (data_type %in% c("categorical", "boolean")) {
        shiny::updateSelectInput(session, input_id, selected = "")
      } else if (identical(data_type, "date")) {
        shiny::updateDateInput(session, input_id, value = NA)
      } else {
        shiny::updateTextInput(session, input_id, value = "")
      }
    }
    form_generation(form_generation() + 1L)
  }

  load_record <- function(record_id) {
    active <- current_connection()
    if (is.null(active) || length(record_id) != 1L || is.na(record_id) || !nzchar(record_id)) {
      return(invisible(NULL))
    }
    records <- read_collection_records(active)
    selected <- records[records$id == record_id, , drop = FALSE]
    if (nrow(selected) != 1L) {
      show_error_popup("Cette entrée n'existe plus ou est masquée.")
      return(invisible(NULL))
    }
    definitions <- active_record_field_definitions(active)
    editing_record_id(record_id)
    shiny::updateTextInput(session, "record_id_value", value = record_id)
    for (field_name in definitions$name) {
      value <- selected[[field_name]][[1]]
      data_type <- definitions$data_type[match(field_name, definitions$name)]
      input_id <- record_field_input_id(field_name)
      if (is.na(value)) {
        value <- ""
      } else if (inherits(value, "Date")) {
        value <- format(value, "%Y-%m-%d")
      } else if (identical(data_type, "boolean")) {
        value <- if (isTRUE(value)) "TRUE" else "FALSE"
      } else {
        value <- as.character(value)
      }
      field_input_cache$values[[input_id]] <- value
      if (data_type %in% c("categorical", "boolean")) {
        shiny::updateSelectInput(session, input_id, selected = value)
      } else if (identical(data_type, "date")) {
        shiny::updateDateInput(session, input_id, value = if (nzchar(value)) value else NA)
      } else {
        shiny::updateTextInput(session, input_id, value = value)
      }
    }
    shiny::updateTabsetPanel(session, "application_tabs", selected = "entry_management")
    form_generation(form_generation() + 1L)
    record_status(paste("Entrée", record_id, "chargée pour modification."))
    invisible(selected)
  }

  shiny::observe({
    refresh_trigger()
    if (is.function(connection)) connection()
    refresh_record_choices()
  })

  shiny::observeEvent(list(active_connection(), input$record_id_prefix, input$record_id_number), {
    if (is.null(current_connection()) || !is.null(editing_record_id())) return()
    tryCatch(
      shiny::updateTextInput(session, "record_id_value", value = generated_record_id()),
      error = function(condition) NULL
    )
  }, ignoreInit = FALSE)

  questionnaire_values <- function() {
    definitions <- active_record_field_definitions(current_connection())
    values <- stats::setNames(vector("list", nrow(definitions)), definitions$name)
    for (field_name in definitions$name) {
      value <- input[[record_field_input_id(field_name)]]
      values[[field_name]] <- if (is.null(value)) "" else value
    }
    values
  }

  shiny::observeEvent(input$new_record, {
    if (is.null(current_connection())) {
      show_error_popup("Ouvrez une base avant de créer une entrée.")
      return()
    }
    reset_questionnaire()
    record_status("Nouvelle entrée prête.")
  })

  shiny::observeEvent(input$load_record, load_record(input$record_to_edit))
  shiny::observeEvent(input$database_spreadsheet_row_dblclick, load_record(input$database_spreadsheet_row_dblclick))

  shiny::observeEvent(input$save_record, {
    active <- current_connection()
    if (is.null(active)) {
      show_error_popup("Ouvrez une base avant d'enregistrer une entrée.")
      return()
    }
    tryCatch({
      editing_id <- editing_record_id()
      input_record_id <- input$record_id_value
      new_id <- if (length(input_record_id) != 1L || is.na(input_record_id)) {
        ""
      } else {
        trimws(as.character(input_record_id))
      }
      current_generated_id <- tryCatch(generated_record_id(), error = function(condition) NULL)
      configured_prefix <- input$record_id_prefix
      configured_number <- input$record_id_number
      if (is.null(configured_prefix) || !nzchar(configured_prefix)) configured_prefix <- "row_"
      if (is.null(configured_number) || is.na(configured_number)) configured_number <- 1
      configured_id <- paste0(
        configured_prefix,
        format(configured_number, scientific = FALSE, trim = TRUE)
      )
      auto_id <- is.null(editing_id) &&
        (!nzchar(new_id) || identical(new_id, configured_id) || identical(new_id, current_generated_id))
      if (is.null(editing_id)) {
        if (auto_id) {
          if (is.null(current_generated_id)) current_generated_id <- generated_record_id()
          new_id <- current_generated_id
        }
        saved_id <- insert_collection_record(active, questionnaire_values(), new_id)
        editing_record_id(saved_id)
        record_status(paste("Entrée enregistrée sous l'ID", saved_id, "."))
        show_operation_toast(paste("Entrée ajoutée :", saved_id))
        if (auto_id) {
          current_number <- input$record_id_number
          if (is.null(current_number) || is.na(current_number)) current_number <- 1
          saved_number <- substring(saved_id, nchar(configured_prefix, type = "chars") + 1L)
          next_number <- if (grepl("^[0-9]+$", saved_number)) {
            as.double(saved_number) + 1
          } else {
            as.double(current_number) + 1
          }
          shiny::updateNumericInput(session, "record_id_number", value = next_number)
        }
      } else {
        saved_id <- update_collection_record(active, editing_id, new_id, questionnaire_values())
        editing_record_id(saved_id)
        record_status(paste("Entrée", saved_id, "mise à jour."))
        show_operation_toast(paste("Entrée modifiée :", saved_id))
      }
      shiny::updateTextInput(session, "record_id_value", value = saved_id)
      refresh_trigger(refresh_trigger() + 1L)
    }, error = function(condition) {
      show_error_popup(conditionMessage(condition))
    })
  })

  shiny::observeEvent(input$mask_record, {
    active <- current_connection()
    record_id <- editing_record_id()
    if (is.null(active) || is.null(record_id)) {
      show_error_popup("Ouvrez une entrée avant de la masquer.")
      return()
    }
    shiny::showModal(shiny::modalDialog(
      title = "Masquer cette observation ?",
      shiny::p(paste("L'entrée", record_id, "sera masquée, pas supprimée définitivement.")),
      shiny::p(class = "recueil-help", "Elle restera disponible dans Éléments supprimés pour restauration."),
      footer = shiny::tagList(
        shiny::actionButton("confirm_mask_record", "Masquer", class = "btn-warning"),
        shiny::modalButton("Annuler")
      ),
      easyClose = FALSE
    ))
  })

  shiny::observeEvent(input$confirm_mask_record, {
    active <- current_connection()
    record_id <- editing_record_id()
    if (is.null(active) || is.null(record_id)) {
      shiny::removeModal()
      return()
    }
    tryCatch({
      mask_collection_record(active, record_id)
      editing_record_id(NULL)
      refresh_trigger(refresh_trigger() + 1L)
      record_status(paste("Entrée", record_id, "masquée et restaurable depuis Éléments supprimés."))
      show_operation_toast(paste("Entrée masquée :", record_id))
      form_generation(form_generation() + 1L)
      shiny::removeModal()
    }, error = function(condition) {
      show_error_popup(conditionMessage(condition))
    })
  })
}

deleted_items_server <- function(input, output, session, connection, refresh_trigger) {
  status <- shiny::reactiveVal("")
  active_connection <- function() {
    if (is.function(connection)) shiny::isolate(connection()) else connection
  }

  refresh_deleted_choices <- function() {
    active <- active_connection()
    if (is.null(active)) {
      shiny::updateSelectInput(session, "deleted_column_id", choices = character())
      shiny::updateSelectInput(session, "deleted_record_id", choices = character())
      return(invisible(NULL))
    }
    definitions <- list_column_definitions(active, include_hidden = TRUE)
    deleted_columns <- definitions[definitions$is_hidden, , drop = FALSE]
    choices <- select_choices(
      deleted_columns$column_id,
      paste0(deleted_columns$name, " (", deleted_columns$data_type, ")")
    )
    rows <- list_deleted_collection_records(active)
    record_choices <- if (nrow(rows) == 0L) character() else {
      select_choices(rows$id, paste0(rows$id, " — ", rows$created_at))
    }
    shiny::updateSelectInput(session, "deleted_column_id", choices = choices)
    shiny::updateSelectInput(session, "deleted_record_id", choices = record_choices)
    invisible(NULL)
  }

  output$deleted_columns_table <- shiny::renderTable({
    refresh_trigger()
    active <- active_connection()
    if (is.null(active)) {
      return(data.frame(Variable = "Ouvre une base pour consulter les colonnes masquées."))
    }
    all <- list_column_definitions(active, include_hidden = TRUE)
    deleted <- all[all$is_hidden, , drop = FALSE]
    column_table_data(deleted, all)
  }, striped = TRUE, bordered = TRUE, hover = TRUE, rownames = FALSE)

  output$deleted_records_table <- shiny::renderTable({
    refresh_trigger()
    active <- active_connection()
    if (is.null(active)) {
      return(data.frame(ID = "Ouvre une base pour consulter les observations masquées."))
    }
    records <- list_deleted_collection_records(active)
    if (nrow(records) == 0L) {
      return(data.frame(ID = "Aucune observation masquée."))
    }
    names(records)[names(records) == "id"] <- "ID"
    names(records)[names(records) == "created_at"] <- "Créée le"
    records[, setdiff(names(records), "payload"), drop = FALSE]
  }, striped = TRUE, bordered = TRUE, hover = TRUE, rownames = FALSE)

  output$deleted_items_status <- shiny::renderText(status())
  refresh_deleted_choices()
  shiny::observeEvent(refresh_trigger(), refresh_deleted_choices(), ignoreInit = TRUE)
  if (is.function(connection)) {
    shiny::observeEvent(connection(), refresh_deleted_choices(), ignoreInit = TRUE)
  }

  shiny::observeEvent(input$restore_deleted_column, {
    active <- active_connection()
    if (is.null(active)) {
      status("Ouvrez une base avant de restaurer une colonne.")
      return()
    }
    tryCatch({
      requested_name <- trimws(input$deleted_column_new_name)
      restored_name <- restore_column(
        active,
        input$deleted_column_id,
        if (nzchar(requested_name)) requested_name else NULL
      )
      refresh_deleted_choices()
      refresh_trigger(refresh_trigger() + 1L)
      status(paste("Colonne restaurée sous l'entête", restored_name, "."))
      show_operation_toast(paste("Colonne restaurée :", restored_name))
    }, error = function(condition) {
      status(conditionMessage(condition))
    })
  })

  shiny::observeEvent(input$restore_deleted_record, {
    active <- active_connection()
    if (is.null(active)) {
      status("Ouvrez une base avant de restaurer une observation.")
      return()
    }
    tryCatch({
      requested_id <- trimws(input$deleted_record_new_id)
      restored_id <- restore_collection_record(
        active,
        input$deleted_record_id,
        if (nzchar(requested_id)) requested_id else NULL
      )
      refresh_deleted_choices()
      refresh_trigger(refresh_trigger() + 1L)
      status(paste("Observation restaurée sous l'ID", restored_id, "."))
      show_operation_toast(paste("Entrée restaurée :", restored_id))
    }, error = function(condition) {
      status(conditionMessage(condition))
    })
  })
}
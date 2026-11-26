record_field_input_id <- function(field_name) {
  paste0("record_field__", field_name)
}

record_entry_ui <- function() {
  shiny::tabPanel(
    "Questionnaire",
    value = "record_entry",
    shiny::h2(class = "recueil-page-title", "Questionnaire de recueil"),
    shiny::p(class = "recueil-page-subtitle", "Créez une nouvelle observation ou modifiez celle sélectionnée dans le tableur."),
    shiny::div(
      class = "recueil-grid",
      shiny::div(
        class = "recueil-card recueil-span-12",
        shiny::h3("Identification"),
        shiny::textInput("record_id_value", "ID de l'observation", placeholder = "Généré automatiquement si laissé vide")
      ),
      shiny::div(
        class = "recueil-card recueil-span-12",
        shiny::h3("Réponses"),
        shiny::uiOutput("record_questionnaire_fields")
      ),
      shiny::div(
        class = "recueil-card recueil-span-12",
        shiny::div(class = "recueil-action-bar", shiny::uiOutput("record_form_actions")),
        shiny::div(class = "recueil-status", shiny::textOutput("record_entry_status"))
      )
    )
  )
}

deleted_items_ui <- function() {
  shiny::tabPanel(
    "Éléments supprimés",
    value = "deleted_items",
    shiny::h2(class = "recueil-page-title", "Éléments supprimés"),
    shiny::p(class = "recueil-page-subtitle", "Retrouvez les variables ou observations masquées et restaurez-les sous leur nom ou avec un identifiant alternatif."),
    shiny::div(
      class = "recueil-grid",
      shiny::div(
        class = "recueil-card recueil-span-6",
        shiny::h3("Variables masquées"),
        shiny::tableOutput("deleted_columns_table"),
        shiny::selectInput("deleted_column_id", "Colonne à restaurer", choices = character()),
        shiny::textInput("deleted_column_new_name", "Nouvelle entête si nécessaire", placeholder = "Optionnel : seulement en cas de collision"),
        shiny::actionButton("restore_deleted_column", "Restaurer la colonne", class = "btn-primary")
      ),
      shiny::div(
        class = "recueil-card recueil-span-6",
        shiny::h3("Observations masquées"),
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

  active_connection <- function() {
    if (is.function(connection)) connection() else connection
  }

  output$record_questionnaire_fields <- shiny::renderUI({
    refresh_trigger()
    form_generation()
    active <- active_connection()
    if (is.null(active)) {
      return(shiny::p("Ouvrez une base avant de remplir le questionnaire."))
    }

    definitions <- active_record_field_definitions(active)
    shiny::div(
      class = "recueil-field-grid",
      shiny::tagList(lapply(seq_len(nrow(definitions)), function(row_index) {
        definition <- definitions[row_index, , drop = FALSE]
        field_name <- definition$name[[1]]
        input_id <- record_field_input_id(field_name)
        data_type <- definition$data_type[[1]]

        if (identical(data_type, "categorical")) {
          categories <- list_category_entries(active, definition$column_id[[1]])
          choices <- c(
            stats::setNames("", ""),
            stats::setNames(categories$code, paste0(categories$label, " (", categories$code, ")"))
          )
          return(shiny::selectInput(input_id, field_name, choices = choices))
        }
        if (identical(data_type, "boolean")) {
          return(shiny::selectInput(
            input_id,
            field_name,
            choices = stats::setNames(c("", "TRUE", "FALSE"), c("", "Oui", "Non"))
          ))
        }
        if (identical(data_type, "date")) {
          return(shiny::dateInput(
            input_id,
            field_name,
            value = NULL,
            language = "fr",
            format = "yyyy-mm-dd",
            weekstart = 1
          ))
        }
        shiny::textInput(input_id, field_name, value = "")
      }))
    )
  })

  output$record_form_actions <- shiny::renderUI({
    if (is.null(active_connection())) {
      return(NULL)
    }
    actions <- list(
      shiny::actionButton("new_record", "Nouvelle observation"),
      shiny::actionButton("save_record", "Enregistrer l'observation", class = "btn-primary")
    )
    if (!is.null(editing_record_id())) {
      actions <- c(actions, list(shiny::actionButton("mask_record", "Supprimer (masquer) l'observation", class = "btn-warning")))
    }
    do.call(shiny::tagList, actions)
  })

  output$record_entry_status <- shiny::renderText(record_status())

  reset_questionnaire <- function(record_id = new_collection_record_id(current_connection())) {
    editing_record_id(NULL)
    shiny::updateTextInput(session, "record_id_value", value = record_id)
    definitions <- active_record_field_definitions(current_connection())
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
      record_status("Ouvrez une base avant de créer une observation.")
      return()
    }
    reset_questionnaire()
    record_status("Nouveau questionnaire prêt.")
  })

  shiny::observeEvent(input$database_spreadsheet_row_dblclick, {
    active <- current_connection()
    record_id <- input$database_spreadsheet_row_dblclick
    if (is.null(active) || length(record_id) != 1L || is.na(record_id) || !nzchar(record_id)) {
      return()
    }
    records <- read_collection_records(active)
    selected <- records[records$id == record_id, , drop = FALSE]
    if (nrow(selected) != 1L) {
      record_status("Cette observation n'existe plus ou est masquée.")
      return()
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
      if (data_type %in% c("categorical", "boolean")) {
        shiny::updateSelectInput(session, input_id, selected = value)
      } else if (identical(data_type, "date")) {
        shiny::updateDateInput(session, input_id, value = if (nzchar(value)) value else NA)
      } else {
        shiny::updateTextInput(session, input_id, value = value)
      }
    }
    shiny::updateTabsetPanel(session, "application_tabs", selected = "record_entry")
    form_generation(form_generation() + 1L)
    record_status(paste("Observation", record_id, "chargée pour modification."))
  })

  shiny::observeEvent(input$save_record, {
    active <- current_connection()
    if (is.null(active)) {
      record_status("Ouvrez une base avant d'enregistrer une observation.")
      return()
    }
    tryCatch({
      editing_id <- editing_record_id()
      new_id <- input$record_id_value
      if (is.null(editing_id)) {
        saved_id <- insert_collection_record(active, questionnaire_values(), new_id)
        editing_record_id(saved_id)
        record_status(paste("Observation enregistrée sous l'ID", saved_id, "."))
      } else {
        saved_id <- update_collection_record(active, editing_id, new_id, questionnaire_values())
        editing_record_id(saved_id)
        record_status(paste("Observation", saved_id, "mise à jour."))
      }
      shiny::updateTextInput(session, "record_id_value", value = saved_id)
      refresh_trigger(refresh_trigger() + 1L)
    }, error = function(condition) {
      record_status(conditionMessage(condition))
    })
  })

  shiny::observeEvent(input$mask_record, {
    active <- current_connection()
    record_id <- editing_record_id()
    if (is.null(active) || is.null(record_id)) {
      record_status("Ouvrez une observation avant de la masquer.")
      return()
    }
    shiny::showModal(shiny::modalDialog(
      title = "Masquer cette observation ?",
      shiny::p(paste("L'observation", record_id, "sera masquée, pas supprimée définitivement.")),
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
      record_status(paste("Observation", record_id, "masquée et restaurable depuis Éléments supprimés."))
      form_generation(form_generation() + 1L)
      shiny::removeModal()
    }, error = function(condition) {
      record_status(conditionMessage(condition))
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
    if (!is.function(connection)) refresh_trigger()
    active <- active_connection()
    if (is.null(active)) {
      return(data.frame(Variable = "Ouvre une base pour consulter les colonnes masquées."))
    }
    all <- list_column_definitions(active, include_hidden = TRUE)
    deleted <- all[all$is_hidden, , drop = FALSE]
    column_table_data(deleted, all)
  }, striped = TRUE, bordered = TRUE, hover = TRUE, rownames = FALSE)

  output$deleted_records_table <- shiny::renderTable({
    if (!is.function(connection)) refresh_trigger()
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
    }, error = function(condition) {
      status(conditionMessage(condition))
    })
  })
}
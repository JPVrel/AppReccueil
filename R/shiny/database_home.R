database_home_ui <- function() {
  shiny::tabPanel(
    "Accueil",
    value = "home",
    shiny::h3("Base de données locale"),
    shiny::textOutput("database_overview"),
    shiny::uiOutput("open_database_controls"),
    shiny::uiOutput("create_database_controls"),
    shiny::hr(),
    shiny::h3("Importer des données"),
    shiny::fileInput(
      "import_file",
      "Choisir un fichier CSV, Excel ou RDS (ou un export chiffré .enc)",
      accept = c(".csv", ".xlsx", ".rds", ".enc")
    ),
    shiny::uiOutput("import_file_password_ui"),
    shiny::uiOutput("import_file_status"),
    shiny::uiOutput("import_type_controls"),
    shiny::uiOutput("import_action_controls"),
    shiny::textOutput("database_workflow_status")
  )
}

database_home_server <- function(
  input,
  output,
  session,
  data_dir,
  connection_state,
  vault_state,
  refresh_trigger
) {
  workflow_status <- shiny::reactiveVal("")
  merge_plan <- shiny::reactiveVal(NULL)

  imported_data <- shiny::reactive({
    shiny::req(input$import_file$datapath)
    tryCatch(
      read_database_import_upload(
        input$import_file$datapath,
        input$import_file$name,
        input$import_file_password
      ),
      error = identity
    )
  })

  current_import <- function() {
    result <- imported_data()
    if (inherits(result, "error")) {
      stop(conditionMessage(result))
    }
    result
  }

  import_types <- function(imported) {
    types <- stats::setNames(vector("list", ncol(imported)), names(imported))
    for (field_name in names(imported)) {
      type <- input[[paste0("import_type__", field_name)]]
      if (is.null(type) || !type %in% column_definition_types()) {
        stop("Choisis un type pour chaque colonne avant de créer la base.")
      }
      types[[field_name]] <- type
    }
    unlist(types, use.names = TRUE)
  }

  activate_vault <- function(vault) {
    vault_state(vault)
    connection_state(vault$connection)
    refresh_trigger(refresh_trigger() + 1L)
    security <- if (isTRUE(vault$encrypted)) "chiffrée" else "sans mot de passe"
    workflow_status(paste("Base ouverte", security, ":", basename(vault$vault_path)))
  }

  output$database_overview <- shiny::renderText({
    active <- vault_state()
    if (!is.null(active)) {
      if (isTRUE(active$remote)) {
        return("Base distante connectée.")
      }
      security <- if (isTRUE(active$encrypted)) "chiffrée" else "sans mot de passe"
      return(paste("Base active (", security, ") :", normalizePath(active$vault_path, mustWork = FALSE)))
    }

    encrypted <- list_local_database_vaults(data_dir)
    unencrypted <- list_unencrypted_local_databases(data_dir)
    paste(
      "Bases chiffrées disponibles :", length(encrypted),
      "| bases SQLite non chiffrées à protéger :", length(unencrypted)
    )
  })
  output$database_workflow_status <- shiny::renderText(workflow_status())

  output$open_database_controls <- shiny::renderUI({
    if (!is.null(vault_state())) {
      active <- vault_state()
      close_label <- if (isTRUE(active$remote)) {
        "Fermer la connexion distante"
      } else if (isTRUE(active$encrypted)) {
        "Fermer et rechiffrer la base"
      } else {
        "Fermer la base"
      }
      status_text <- if (isTRUE(active$remote)) {
        "La connexion distante configurée dans database.yml est active."
      } else if (isTRUE(active$encrypted)) {
        "La copie temporaire privée sera rechiffrée à la fermeture."
      } else {
        "Cette base reste enregistrée sans chiffrement sur le disque."
      }
      return(shiny::tagList(
        shiny::p(status_text),
        shiny::actionButton("close_database", close_label)
      ))
    }

    encrypted <- list_local_database_vaults(data_dir)
    unencrypted <- list_unencrypted_local_databases(data_dir)
    controls <- list()
    if (length(encrypted) > 0L) {
      controls <- c(controls, list(
        shiny::h4("Ouvrir une base chiffrée"),
        shiny::selectInput(
          "database_to_open",
          "Base locale",
          choices = stats::setNames(encrypted, basename(encrypted))
        ),
        shiny::passwordInput("open_database_password", "Mot de passe"),
        shiny::actionButton("open_database", "Ouvrir la base", class = "btn-primary")
      ))
    }
    if (length(unencrypted) > 0L) {
      controls <- c(controls, list(
        shiny::h4("Ouvrir une base SQLite sans chiffrement"),
        shiny::selectInput(
          "plain_database_to_open",
          "Base locale",
          choices = stats::setNames(unencrypted, basename(unencrypted))
        ),
        shiny::actionButton("open_plain_database", "Ouvrir sans mot de passe"),
        shiny::h4("Protéger une base SQLite existante"),
        shiny::p("Une copie chiffrée sera créée. Le fichier source restera en clair et devra être supprimé séparément après vérification."),
        shiny::selectInput(
          "plain_database_to_protect",
          "Base SQLite à copier",
          choices = stats::setNames(unencrypted, basename(unencrypted))
        ),
        shiny::passwordInput("protect_database_password", "Nouveau mot de passe"),
        shiny::passwordInput("protect_database_password_confirm", "Confirmer le mot de passe"),
        shiny::actionButton("protect_database", "Créer une copie chiffrée")
      ))
    }
    if (length(controls) == 0L) {
      controls <- list(shiny::p("Aucune base locale n'existe encore. Crée une base ou importe un fichier."))
    }
    do.call(shiny::tagList, controls)
  })

  output$create_database_controls <- shiny::renderUI({
    if (!is.null(vault_state())) {
      return(NULL)
    }

    shiny::tagList(
      shiny::h4("Créer une autre base"),
      shiny::textInput("new_database_name", "Nom de la base", value = "recueil"),
      shiny::passwordInput("new_database_password", "Mot de passe (facultatif, 12 caractères minimum si utilisé)"),
      shiny::passwordInput("new_database_password_confirm", "Confirmer le mot de passe"),
      shiny::actionButton("create_database", "Créer et ouvrir", class = "btn-primary")
    )
  })

  output$import_file_status <- shiny::renderUI({
    if (is.null(input$import_file$datapath)) {
      return(shiny::p("Les colonnes d'un fichier importé seront associées à des types avant la création de la base."))
    }
    imported <- imported_data()
    if (inherits(imported, "error")) {
      return(shiny::div(class = "alert alert-danger", conditionMessage(imported)))
    }
    shiny::p(nrow(imported), " lignes et ", ncol(imported), " colonnes détectées.")
  })

  output$import_file_password_ui <- shiny::renderUI({
    if (is.null(input$import_file$name) || !grepl("[.]enc$", tolower(input$import_file$name))) {
      return(NULL)
    }
    shiny::passwordInput("import_file_password", "Mot de passe de l'export chiffré")
  })

  output$import_type_controls <- shiny::renderUI({
    if (!is.null(vault_state()) || is.null(input$import_file$datapath)) {
      return(NULL)
    }
    imported <- imported_data()
    if (inherits(imported, "error")) {
      return(NULL)
    }
    choices <- c("Choisir un type" = "", database_import_types())
    shiny::tagList(
      shiny::h4("Type des colonnes"),
      lapply(names(imported), function(field_name) {
        shiny::selectInput(
          paste0("import_type__", field_name),
          field_name,
          choices = choices,
          selected = ""
        )
      })
    )
  })

  output$import_action_controls <- shiny::renderUI({
    if (is.null(input$import_file$datapath)) {
      return(NULL)
    }
    imported <- imported_data()
    if (inherits(imported, "error")) {
      return(NULL)
    }

    if (is.null(vault_state())) {
      return(shiny::p("Les types ci-dessus seront appliqués lors de la création de la base."))
    }

    definitions <- list_column_definitions(connection_state())
    common <- definitions$name[!is.na(definitions$sql_name) & definitions$name %in% names(imported)]
    if (length(common) == 0L) {
      return(shiny::div(class = "alert alert-warning", "Aucune colonne du fichier ne correspond aux champs physiques de cette base."))
    }
    shiny::tagList(
      shiny::selectInput(
        "import_merge_key",
        "Colonne identifiante unique",
        choices = common,
        selected = common[[1]]
      ),
      shiny::actionButton("prepare_import_merge", "Comparer et intégrer le fichier", class = "btn-primary")
    )
  })

  output$merge_conflict_choices <- shiny::renderUI({
    plan <- merge_plan()
    if (is.null(plan)) {
      return(NULL)
    }
    shiny::tagList(lapply(seq_along(plan$conflicts), function(index) {
      conflict <- plan$conflicts[[index]]
      existing <- if (import_value_is_missing(conflict$current_value)) "(vide)" else as.character(conflict$current_value)
      incoming <- if (import_value_is_missing(conflict$incoming_value)) "(vide)" else as.character(conflict$incoming_value)
      shiny::wellPanel(
        shiny::strong(paste("Clé", as.character(conflict$key_value), "|", conflict$field)),
        shiny::p("Valeur actuelle : ", existing),
        shiny::p("Valeur importée : ", incoming),
        shiny::radioButtons(
          paste0("import_conflict_choice_", index),
          "Conserver quelle valeur ?",
          choices = c("Base actuelle" = "existing", "Fichier importé" = "imported"),
          selected = "existing",
          inline = TRUE
        )
      )
    }))
  })

  shiny::observeEvent(input$open_database, {
    tryCatch({
      vault <- open_database_vault(input$database_to_open, input$open_database_password)
      activate_vault(vault)
      shiny::updateTextInput(session, "open_database_password", value = "")
    }, error = function(condition) {
      workflow_status(conditionMessage(condition))
    })
  })

  shiny::observeEvent(input$open_plain_database, {
    tryCatch({
      database <- open_unencrypted_database(input$plain_database_to_open)
      activate_vault(database)
      workflow_status(paste("Base ouverte sans chiffrement :", basename(database$vault_path)))
    }, error = function(condition) {
      workflow_status(conditionMessage(condition))
    })
  })

  shiny::observeEvent(input$protect_database, {
    tryCatch({
      validate_vault_password(
        input$protect_database_password,
        input$protect_database_password_confirm
      )
      source_path <- input$plain_database_to_protect
      encrypted_path <- paste0(source_path, ".enc")
      create_encrypted_database_copy(source_path, encrypted_path, input$protect_database_password)
      vault <- open_database_vault(encrypted_path, input$protect_database_password)
      activate_vault(vault)
      workflow_status(paste(
        "Copie chiffrée ouverte. La source en clair est conservée à",
        source_path
      ))
    }, error = function(condition) {
      workflow_status(conditionMessage(condition))
    })
  })

  shiny::observeEvent(input$create_database, {
    created_path <- NULL
    vault <- NULL
    database_created <- FALSE
    tryCatch({
      password <- optional_vault_password(
        input$new_database_password,
        input$new_database_password_confirm
      )
      imported <- NULL
      imported_types <- NULL
      if (!is.null(input$import_file$datapath)) {
        imported <- current_import()
        imported_types <- import_types(imported)
        convert_database_import(imported, imported_types)
      }
      created_path <- database_local_path(
        data_dir,
        input$new_database_name,
        encrypted = !is.null(password)
      )
      if (is.null(password)) {
        create_unencrypted_database(created_path)
        database_created <- TRUE
        vault <- open_unencrypted_database(created_path)
      } else {
        create_database_vault(created_path, password)
        database_created <- TRUE
        vault <- open_database_vault(created_path, password)
      }
      if (!is.null(imported)) {
        create_imported_database(vault$connection, imported, imported_types)
      }
      activate_vault(vault)
      shiny::updateTextInput(session, "new_database_password", value = "")
      shiny::updateTextInput(session, "new_database_password_confirm", value = "")
      shiny::updateTextInput(session, "import_file_password", value = "")
      workflow_status(paste("Base créée et ouverte :", basename(created_path)))
    }, error = function(condition) {
      can_remove_created_database <- database_created && is.null(vault)
      if (!is.null(vault)) {
        close_result <- try(close_database_state(vault), silent = TRUE)
        can_remove_created_database <- database_created && !inherits(close_result, "try-error")
      }
      if (can_remove_created_database && !is.null(created_path)) {
        if (grepl("[.]sqlite[.]enc$", created_path)) {
          unlink(created_path)
        } else {
          remove_database_files(created_path)
        }
      }
      workflow_status(conditionMessage(condition))
    })
  })

  shiny::observeEvent(input$close_database, {
    vault <- shiny::isolate(vault_state())
    if (is.null(vault)) {
      return()
    }
    tryCatch({
      close_database_state(vault)
      vault_state(NULL)
      connection_state(NULL)
      refresh_trigger(refresh_trigger() + 1L)
      status <- if (isTRUE(vault$encrypted)) "Base rechiffrée et fermée." else "Base fermée."
      workflow_status(status)
    }, error = function(condition) {
      workflow_status(paste("Échec de fermeture :", conditionMessage(condition)))
    })
  })

  shiny::observeEvent(input$prepare_import_merge, {
    tryCatch({
      plan <- prepare_import_merge(
        connection_state(),
        current_import(),
        input$import_merge_key
      )
      merge_plan(plan)
      if (length(plan$conflicts) == 0L) {
        result <- apply_import_merge(connection_state(), plan)
        refresh_trigger(refresh_trigger() + 1L)
        workflow_status(paste(
          "Import intégré :", result$inserted, "nouvelle(s) observation(s) et",
          result$filled, "valeur(s) complétée(s)."
        ))
        merge_plan(NULL)
      } else {
        shiny::showModal(shiny::modalDialog(
          title = paste(length(plan$conflicts), "conflit(s) à arbitrer"),
          shiny::p("Choisis quelle valeur conserver pour chaque champ en conflit. Rien ne sera appliqué avant validation."),
          shiny::uiOutput("merge_conflict_choices"),
          footer = shiny::tagList(
            shiny::actionButton("apply_import_conflicts", "Appliquer les choix", class = "btn-primary"),
            shiny::modalButton("Annuler")
          ),
          easyClose = FALSE,
          size = "l"
        ))
      }
    }, error = function(condition) {
      merge_plan(NULL)
      workflow_status(conditionMessage(condition))
    })
  })

  shiny::observeEvent(input$apply_import_conflicts, {
    plan <- shiny::isolate(merge_plan())
    if (is.null(plan)) {
      return()
    }
    choices <- vapply(seq_along(plan$conflicts), function(index) {
      choice <- input[[paste0("import_conflict_choice_", index)]]
      if (is.null(choice)) "" else choice
    }, character(1))
    tryCatch({
      result <- apply_import_merge(connection_state(), plan, choices)
      shiny::removeModal()
      merge_plan(NULL)
      refresh_trigger(refresh_trigger() + 1L)
      workflow_status(paste(
        "Import intégré :", result$inserted, "nouvelle(s) observation(s),",
        result$filled, "valeur(s) complétée(s) et", result$conflicts,
        "conflit(s) arbitré(s)."
      ))
    }, error = function(condition) {
      workflow_status(conditionMessage(condition))
    })
  })
}
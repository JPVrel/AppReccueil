# Cet onglet gère les métadonnées et le schéma ; aucune colonne n'est supprimée physiquement.
database_management_ui <- function() {
  shiny::tabPanel(
    "Gestion des variables",
    value = "column_manager",
    shiny::h2(class = "recueil-page-title", "Gestion des variables"),
    shiny::p(class = "recueil-page-subtitle", "Structurez les champs, gérez les catégories et créez des variables calculées."),
    shiny::div(
      class = "recueil-grid",
      shiny::div(
        class = "recueil-card recueil-span-6",
        shiny::h3("Ajouter une variable"),
        shiny::textInput("new_column_name", "Nom de la variable (sans espaces)"),
        shiny::p(
          class = "recueil-help",
          "Commencez par une lettre ; utilisez uniquement lettres sans accents, chiffres et underscores (_), 64 caractères maximum."
        ),
        shiny::selectInput(
          "new_column_type",
          "Type",
          choices = c("Texte"="text","Nombre entier"="integer","Nombre décimal"="real","Date"="date","Catégorielle"="categorical")
        ),
        shiny::actionButton("add_column", "Ajouter", class = "btn-primary")
      ),
      shiny::div(
        class = "recueil-card recueil-span-6",
        shiny::h3("Variables actives"),
        shiny::tableOutput("active_variables_table")
      ),
      shiny::div(
        class = "recueil-card recueil-span-6",
        shiny::h3("Renommer ou masquer"),
        shiny::div(
          class = "recueil-action-section",
          shiny::h4("Renommer une variable"),
          shiny::selectInput("column_to_rename", "Variable", choices = character()),
          shiny::textInput("renamed_column_name", "Nouvelle entête"),
          shiny::div(class = "recueil-action-bar", shiny::actionButton("rename_column", "Renommer"))
        ),
        shiny::div(
          class = "recueil-action-section",
          shiny::h4("Masquer une variable"),
          shiny::selectInput("column_to_hide", "Variable", choices = character()),
          shiny::div(class = "recueil-action-bar", shiny::actionButton("hide_column", "Masquer", class = "btn-warning"))
        )
      ),
      shiny::div(
        class = "recueil-card recueil-span-6",
        shiny::h3("Variables masquées"),
        shiny::tableOutput("archived_variables_table"),
        shiny::selectInput("column_to_restore", "Restaurer", choices = character()),
        shiny::actionButton("restore_column", "Restaurer la variable", class = "btn-primary")
      )
    ),
    shiny::div(
      class = "recueil-grid",
      shiny::div(
        class = "recueil-card recueil-span-6",
        shiny::h3("Dictionnaire catégoriel"),
        shiny::selectInput("dictionary_column_id", "Colonne catégorielle", choices = character()),
        shiny::tableOutput("category_entries"),
        shiny::textInput("new_category_code", "Code de la catégorie"),
        shiny::textInput("new_category_label", "Libellé affiché"),
        shiny::actionButton("add_category", "Ajouter une catégorie"),
        shiny::selectInput("category_to_edit", "Modifier une entrée", choices = character()),
        shiny::textInput("edited_category_code", "Nouveau code"),
        shiny::textInput("edited_category_label", "Nouveau libellé"),
        shiny::actionButton("update_category", "Enregistrer la catégorie"),
        shiny::selectInput("category_to_remove", "Catégorie à réaffecter puis retirer", choices = character()),
        shiny::selectInput("replacement_category", "Réaffecter vers", choices = character()),
        shiny::actionButton("remove_category", "Réaffecter et retirer")
      ),
      shiny::div(
        class = "recueil-card recueil-span-6",
        shiny::h3("Variable dérivée"),
        shiny::p("Choisissez deux colonnes. Les résultats sont calculés dynamiquement ; les valeurs manquantes et une division par zéro donnent un résultat manquant."),
        shiny::textInput("derived_column_name", "Nom de la variable dérivée"),
        shiny::selectInput(
          "formula_mode",
          "Type de formule",
          choices = c("Opération entre colonnes" = "binary", "Condition SI/SINON" = "if_else")
        ),
        shiny::selectInput("formula_left_id", "Première colonne", choices = character()),
        shiny::selectInput(
          "formula_operator",
          "Opération",
          choices = c(
            "Addition" = "add",
            "Soustraction" = "subtract",
            "Multiplication" = "multiply",
            "Division" = "divide",
            "Première − deuxième (jours)" = "days_between",
            "Première − deuxième (mois complets)" = "months_between",
            "Première − deuxième (années complètes)" = "years_between",
            "Égal à" = "equal",
            "Différent de" = "not_equal",
            "Supérieur à" = "greater_than",
            "Supérieur ou égal" = "greater_or_equal",
            "Inférieur à" = "less_than",
            "Inférieur ou égal" = "less_or_equal"
          )
        ),
        shiny::selectInput("formula_right_id", "Deuxième colonne", choices = character()),
        shiny::conditionalPanel(
          condition = "input.formula_mode == 'if_else'",
          shiny::selectInput(
            "formula_result_type",
            "Type du résultat",
            choices = c("Texte" = "text", "Entier" = "integer", "Décimal" = "real", "Date" = "date", "Booléen" = "boolean")
          ),
          shiny::textInput("formula_true_value", "Valeur si la condition est vraie"),
          shiny::textInput("formula_false_value", "Valeur si la condition est fausse")
        ),
        shiny::actionButton("add_derived_column", "Créer la variable dérivée"),
        shiny::selectInput("derived_column_to_edit", "Modifier une formule existante", choices = character()),
        shiny::actionButton("update_derived_formula", "Mettre à jour la formule")
      )
    ),
    shiny::div(class = "recueil-status", shiny::textOutput("column_status"))
  )
}

empty_column_definitions <- function() {
  data.frame(
    column_id = character(),
    name = character(),
    sql_name = character(),
    data_type = character(),
    is_hidden = logical(),
    formula = character()
  )
}

select_choices <- function(values, labels) {
  if (length(values) == 0L) {
    return(character())
  }

  stats::setNames(values, labels)
}

format_formula_summary <- function(formula, definitions) {
  # Remplace les identifiants internes par les noms que l'utilisateur connaît.
  source_names <- definitions$name[match(c(formula$left_id, formula$right_id), definitions$column_id)]
  source_names[is.na(source_names)] <- c(formula$left_id, formula$right_id)[is.na(source_names)]
  operator_labels <- c(
    add = "+",
    subtract = "-",
    multiply = "*",
    divide = "/",
    days_between = "première − deuxième en jours",
    months_between = "première − deuxième en mois",
    years_between = "première − deuxième en années",
    equal = "=",
    not_equal = "≠",
    greater_than = ">",
    greater_or_equal = "≥",
    less_than = "<",
    less_or_equal = "≤"
  )
  operator_label <- unname(operator_labels[[formula$operator]])

  if (identical(formula$mode, "if_else")) {
    return(paste0(
      "SI ", source_names[[1]], " ", operator_label, " ", source_names[[2]],
      " ALORS ", formula$true_value, " SINON ", formula$false_value
    ))
  }

  paste(source_names[[1]], operator_label, source_names[[2]])
}

column_table_data <- function(definitions, all_definitions = definitions) {
  # Les mêmes colonnes alimentent le tableau actif et le tableau d'archives.
  if (nrow(definitions) == 0L) {
    return(data.frame(
      Variable = character(),
      Type = character(),
      Nature = character(),
      Formule = character()
    ))
  }

  has_formula <- !is.na(definitions$formula) & nzchar(definitions$formula)
  type_labels <- c(
    text = "Texte",
    integer = "Entier",
    real = "Décimal",
    numeric = "Numérique",
    date = "Date",
    boolean = "Booléen",
    categorical = "Catégorielle"
  )
  formula_text <- rep("", nrow(definitions))
  for (row_index in which(has_formula)) {
    formula <- yaml::yaml.load(definitions$formula[[row_index]])
    formula_text[[row_index]] <- format_formula_summary(formula, all_definitions)
  }

  data.frame(
    Variable = definitions$name,
    Type = unname(type_labels[definitions$data_type]),
    Nature = ifelse(
      has_formula,
      "Dérivée",
      ifelse(definitions$data_type == "categorical", "Catégorielle", ifelse(definitions$data_type == "date", "Date", "Stockée"))
    ),
    Formule = formula_text,
    check.names = FALSE
  )
}

category_table_data <- function(categories) {
  data.frame(
    Code = categories$code,
    Libellé = categories$label,
    check.names = FALSE
  )
}

# Les fonctions appelées pendant l'initialisation n'ont pas toujours de contexte
# réactif actif ; isolate permet de lire leur état sans enregistrer de dépendance.
read_reactive_state <- function(state) {
  shiny::isolate(state())
}

# Même règle pour les valeurs input consultées pendant le rafraîchissement initial.
read_shiny_input <- function(input, input_name) {
  shiny::isolate(input[[input_name]])
}

formula_editor_values <- function(connection, column_id) {
  formula <- read_derived_formula(connection, column_id)
  list(
    mode = formula$mode,
    left_id = formula$left_id,
    operator = formula$operator,
    right_id = formula$right_id,
    result_type = formula$result_type,
    true_value = formula$true_value,
    false_value = formula$false_value
  )
}

database_management_server <- function(
  input,
  output,
  session,
  connection,
  refresh_trigger,
  error_popup = function(message) {
    shiny::showModal(shiny::modalDialog(
      title = "Erreur",
      shiny::p(message),
      easyClose = TRUE,
      footer = shiny::modalButton("Fermer")
    ))
  }
) {
  definitions <- shiny::reactiveVal(empty_column_definitions())
  column_status <- shiny::reactiveVal("")
  show_column_error <- function(message) {
    column_status("")
    error_popup(message)
    invisible(NULL)
  }
  current_connection <- function() {
    if (is.function(connection)) shiny::isolate(connection()) else connection
  }

  refresh_category_entry_choices <- function(selected_column = input$dictionary_column_id) {
    current_definitions <- read_reactive_state(definitions)
    categorical <- current_definitions[
      current_definitions$data_type == "categorical" & !current_definitions$is_hidden,
      ,
      drop = FALSE
    ]
    if (length(selected_column) == 1L && !is.na(selected_column) &&
      selected_column %in% categorical$column_id) {
      categories <- list_category_entries(current_connection(), selected_column)
      entry_choices <- select_choices(
        categories$category_id,
        paste(categories$label, "(", categories$code, ")")
      )
      shiny::updateSelectInput(session, "category_to_edit", choices = entry_choices)
      shiny::updateSelectInput(session, "category_to_remove", choices = entry_choices)
      shiny::updateSelectInput(session, "replacement_category", choices = entry_choices)
    } else {
      shiny::updateSelectInput(session, "category_to_edit", choices = character())
      shiny::updateSelectInput(session, "category_to_remove", choices = character())
      shiny::updateSelectInput(session, "replacement_category", choices = character())
    }
  }

  refresh_category_column_choices <- function() {
    current_definitions <- read_reactive_state(definitions)
    categorical <- current_definitions[
      current_definitions$data_type == "categorical" & !current_definitions$is_hidden,
      ,
      drop = FALSE
    ]
    choices <- select_choices(categorical$column_id, categorical$name)
    selected_column <- read_shiny_input(input, "dictionary_column_id")
    has_selected_column <- length(selected_column) == 1L &&
      !is.na(selected_column) &&
      selected_column %in% categorical$column_id
    if (!has_selected_column) {
      selected_column <- if (length(categorical$column_id) > 0L) categorical$column_id[[1]] else character()
    }

    shiny::updateSelectInput(
      session,
      "dictionary_column_id",
      choices = choices,
      selected = selected_column
    )
    refresh_category_entry_choices(selected_column)
  }

  refresh_controls <- function() {
    active_connection <- current_connection()
    if (is.null(active_connection)) {
      definitions(empty_column_definitions())
      return(invisible(NULL))
    }

    current_definitions <- list_column_definitions(active_connection, include_hidden = TRUE)
    definitions(current_definitions)
    active <- current_definitions[!current_definitions$is_hidden, , drop = FALSE]
    archived <- current_definitions[current_definitions$is_hidden, , drop = FALSE]
    active_choices <- select_choices(active$name, active$name)
    archived_choices <- select_choices(
      archived$column_id,
      paste0(archived$name, " [", archived$column_id, "]")
    )
    all_choices <- select_choices(
      active$column_id,
      paste0(active$name, " (", active$data_type, ")")
    )
    derived <- active[!is.na(active$formula) & nzchar(active$formula), , drop = FALSE]
    derived_choices <- select_choices(derived$column_id, derived$name)

    shiny::updateSelectInput(session, "column_to_rename", choices = active_choices)
    shiny::updateSelectInput(session, "column_to_hide", choices = active_choices)
    shiny::updateSelectInput(session, "column_to_restore", choices = archived_choices)
    shiny::updateSelectInput(session, "formula_left_id", choices = all_choices)
    shiny::updateSelectInput(session, "formula_right_id", choices = all_choices)
    shiny::updateSelectInput(session, "derived_column_to_edit", choices = derived_choices)
    refresh_category_column_choices()
  }

  current_column_id <- function(name) {
    current_definitions <- read_reactive_state(definitions)
    selected <- current_definitions[
      !current_definitions$is_hidden & current_definitions$name == name,
      ,
      drop = FALSE
    ]
    if (nrow(selected) != 1L) {
      stop("La colonne sélectionnée n'existe plus.")
    }
    selected$column_id[[1]]
  }

  run_action <- function(action, success_message) {
    if (is.null(current_connection())) {
      show_column_error("La base de données n'est pas connectée.")
      return(invisible(NULL))
    }

    tryCatch({
      result <- action()
      refresh_controls()
      refresh_trigger(refresh_trigger() + 1L)
      column_status(success_message(result))
    }, error = function(condition) {
      show_column_error(conditionMessage(condition))
    })
  }

  selected_formula <- function() {
    list(
      mode = input$formula_mode,
      left_id = input$formula_left_id,
      operator = input$formula_operator,
      right_id = input$formula_right_id,
      true_value = input$formula_true_value,
      false_value = input$formula_false_value,
      result_type = input$formula_result_type
    )
  }

  load_formula_editor <- function(column_id) {
    values <- tryCatch(formula_editor_values(current_connection(), column_id), error = function(condition) NULL)
    if (is.null(values)) {
      return(invisible(NULL))
    }

    shiny::updateSelectInput(session, "formula_mode", selected = values$mode)
    shiny::updateSelectInput(session, "formula_left_id", selected = values$left_id)
    shiny::updateSelectInput(session, "formula_operator", selected = values$operator)
    shiny::updateSelectInput(session, "formula_right_id", selected = values$right_id)
    if (identical(values$mode, "if_else")) {
      shiny::updateSelectInput(session, "formula_result_type", selected = values$result_type)
      shiny::updateTextInput(session, "formula_true_value", value = values$true_value)
      shiny::updateTextInput(session, "formula_false_value", value = values$false_value)
    }

    invisible(values)
  }

  output$active_variables_table <- shiny::renderTable({
    current <- definitions()
    active <- current[!current$is_hidden, , drop = FALSE]
    if (nrow(active) == 0L) {
      return(data.frame(Variable = "Aucune colonne personnalisée pour le moment."))
    }
    column_table_data(active, current)
  }, striped = TRUE, bordered = TRUE, hover = TRUE, rownames = FALSE)
  output$archived_variables_table <- shiny::renderTable({
    current <- definitions()
    archived <- current[current$is_hidden, , drop = FALSE]
    if (nrow(archived) == 0L) {
      return(data.frame(Variable = "Aucune colonne masquée."))
    }
    column_table_data(archived, current)
  }, striped = TRUE, bordered = TRUE, hover = TRUE, rownames = FALSE)
  output$category_entries <- shiny::renderTable({
    refresh_trigger()
    column_id <- input$dictionary_column_id
    current_definitions <- definitions()
    active_categories <- current_definitions[
      current_definitions$data_type == "categorical" & !current_definitions$is_hidden,
      ,
      drop = FALSE
    ]
    if (is.null(current_connection()) || length(column_id) != 1L || is.na(column_id) ||
      !column_id %in% active_categories$column_id) {
      return(data.frame(Code = "Aucune colonne catégorielle sélectionnée.", Libellé = ""))
    }
    categories <- list_category_entries(current_connection(), column_id)
    category_table_data(categories)
  }, striped = TRUE, bordered = TRUE, hover = TRUE, rownames = FALSE)
  output$column_status <- shiny::renderText(column_status())

  refresh_controls()
  shiny::observeEvent(refresh_trigger(), refresh_controls(), ignoreInit = TRUE)
  if (is.function(connection)) {
    shiny::observeEvent(connection(), refresh_controls(), ignoreInit = TRUE)
  }

  shiny::observeEvent(input$add_column, {
    run_action(
      function() add_typed_column(current_connection(), input$new_column_name, input$new_column_type),
      function(column_id) paste("Colonne ajoutée :", get_column_definition(current_connection(), column_id)$name[[1]])
    )
  })
  shiny::observeEvent(input$rename_column, {
    run_action(
      function() rename_column_definition(
        current_connection(),
        current_column_id(input$column_to_rename),
        input$renamed_column_name
      ),
      function(name) paste("Colonne renommée :", name)
    )
  })
  shiny::observeEvent(input$hide_column, {
    column_id <- tryCatch(current_column_id(input$column_to_hide), error = function(condition) NULL)
    if (is.null(column_id)) {
      show_column_error("Sélectionne une variable active à masquer.")
      return()
    }
    column_name <- get_column_definition(current_connection(), column_id)$name[[1]]
    shiny::showModal(shiny::modalDialog(
      title = "Masquer cette variable ?",
      shiny::p(paste("La variable", column_name, "sera masquée et restera disponible pour restauration.")),
      footer = shiny::tagList(
        shiny::actionButton("confirm_hide_column", "Masquer", class = "btn-warning"),
        shiny::modalButton("Annuler")
      ),
      easyClose = FALSE
    ))
  })

  shiny::observeEvent(input$confirm_hide_column, {
    shiny::removeModal()
    run_action(
      function() hide_column(current_connection(), current_column_id(input$column_to_hide)),
      function(...) "Colonne masquée. Elle reste récupérable."
    )
  })
  shiny::observeEvent(input$restore_column, {
    run_action(
      function() restore_column(current_connection(), input$column_to_restore),
      function(name) paste("Colonne restaurée sous le nom :", name)
    )
  })
  shiny::observeEvent(input$add_category, {
    run_action(
      function() add_category_entry(
        current_connection(),
        input$dictionary_column_id,
        input$new_category_code,
        input$new_category_label
      ),
      function(...) "Catégorie ajoutée."
    )
  })
  shiny::observeEvent(input$update_category, {
    run_action(
      function() update_category_entry(
        current_connection(),
        input$category_to_edit,
        input$edited_category_code,
        input$edited_category_label
      ),
      function(...) "Catégorie mise à jour et réponses existantes synchronisées."
    )
  })
  shiny::observeEvent(input$remove_category, {
    run_action(
      function() remove_category_entry(
        current_connection(),
        input$category_to_remove,
        input$replacement_category
      ),
      function(...) "Réponses réaffectées et catégorie retirée."
    )
  })
  shiny::observeEvent(input$add_derived_column, {
    run_action(
      function() add_derived_column(current_connection(), input$derived_column_name, selected_formula()),
      function(column_id) paste("Variable dérivée créée :", get_column_definition(current_connection(), column_id)$name[[1]])
    )
  })
  shiny::observeEvent(input$update_derived_formula, {
    run_action(
      function() update_derived_formula(
        current_connection(),
        input$derived_column_to_edit,
        selected_formula()
      ),
      function(...) "Formule mise à jour."
    )
  })

  shiny::observeEvent(input$derived_column_to_edit, {
    column_id <- input$derived_column_to_edit
    if (is.null(current_connection()) || length(column_id) != 1L || is.na(column_id) || !nzchar(column_id)) {
      return()
    }

    load_formula_editor(column_id)
  })

  shiny::observeEvent(input$database_spreadsheet_header_dblclick, {
    # Le nom de colonne reçu du navigateur est résolu dans le catalogue actif ;
    # les colonnes système et masquées ne deviennent jamais éditables par ce raccourci.
    header_name <- input$database_spreadsheet_header_dblclick
    target <- spreadsheet_header_edit_target(
      read_reactive_state(definitions),
      header_name
    )

    if (is.null(target)) {
      show_column_error(paste("L'en-tête", shQuote(header_name), "n'est pas une variable modifiable."))
      return()
    }

    active <- read_reactive_state(definitions)
    active <- active[!active$is_hidden, , drop = FALSE]
    shiny::updateSelectInput(
      session,
      "column_to_rename",
      choices = select_choices(active$name, active$name),
      selected = target$name[[1]]
    )
    shiny::updateTextInput(session, "renamed_column_name", value = target$name[[1]])
    shiny::updateTabsetPanel(session, "application_tabs", selected = "column_manager")

    if (identical(target$data_type[[1]], "categorical")) {
      shiny::updateSelectInput(
        session,
        "dictionary_column_id",
        selected = target$column_id[[1]]
      )
      refresh_category_entry_choices(target$column_id[[1]])
    }
    if (!is.na(target$formula[[1]]) && nzchar(target$formula[[1]])) {
      shiny::updateSelectInput(
        session,
        "derived_column_to_edit",
        selected = target$column_id[[1]]
      )
      load_formula_editor(target$column_id[[1]])
    }

    column_status(paste("Variable", shQuote(target$name[[1]]), "chargée pour modification."))
  })

  shiny::observeEvent(input$dictionary_column_id, refresh_category_entry_choices())
}

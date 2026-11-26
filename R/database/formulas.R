# Les formules sont des listes structurées avec une liste blanche d'opérateurs ;
# aucun texte fourni par l'utilisateur n'est évalué comme du code R.
formula_binary_operators <- function() {
  c(
    "add", "subtract", "multiply", "divide", "days_between", "months_between", "years_between",
    "equal", "not_equal", "greater_than", "greater_or_equal",
    "less_than", "less_or_equal"
  )
}

formula_comparison_operators <- function() {
  c("equal", "not_equal", "greater_than", "greater_or_equal", "less_than", "less_or_equal")
}

formula_source_ids <- function(formula) {
  if (identical(formula$mode, "binary")) {
    return(c(formula$left_id, formula$right_id))
  }
  if (identical(formula$mode, "if_else")) {
    right_mode <- formula$right_mode
    if (is.null(right_mode) || identical(right_mode, "column")) {
      return(c(formula$left_id, formula$right_id))
    }
    if (identical(right_mode, "constant")) {
      return(formula$left_id)
    }
    return(c(formula$left_id, formula$right_id))
  }

  stop("Mode de formule non autorisé.")
}

read_derived_formula <- function(connection, column_id) {
  definition <- get_column_definition(connection, column_id)
  if (!definition_has_formula(definition)) {
    stop("La colonne ne possède pas de formule.")
  }

  yaml::yaml.load(definition$formula[[1]])
}

definition_has_formula <- function(definition) {
  !is.na(definition$formula[[1]]) && nzchar(definition$formula[[1]])
}

is_numeric_column_type <- function(data_type) {
  data_type %in% c("integer", "real", "numeric")
}

validate_comparison_types <- function(left_type, right_type, operator) {
  comparable <- if (is_numeric_column_type(left_type) && is_numeric_column_type(right_type)) {
    TRUE
  } else if (identical(left_type, "date") && identical(right_type, "date")) {
    TRUE
  } else if (left_type %in% c("text", "categorical") && right_type %in% c("text", "categorical")) {
    operator %in% c("equal", "not_equal")
  } else if (identical(left_type, "boolean") && identical(right_type, "boolean")) {
    operator %in% c("equal", "not_equal")
  } else {
    FALSE
  }

  if (!isTRUE(comparable)) {
    stop("Les types des colonnes ne sont pas compatibles avec cette comparaison.")
  }

  invisible(TRUE)
}

convert_formula_comparison_constant <- function(value, data_type) {
  if (length(value) != 1L || is.na(value)) {
    stop("La valeur fixe de comparaison est obligatoire.")
  }
  value <- as.character(value)

  if (is_numeric_column_type(data_type)) {
    numeric_value <- suppressWarnings(as.numeric(value))
    if (is.na(numeric_value) || !is.finite(numeric_value)) {
      stop("La valeur fixe doit être un nombre fini valide.")
    }
    if (identical(data_type, "integer")) {
      if (numeric_value != floor(numeric_value) || numeric_value < -.Machine$integer.max - 1 ||
        numeric_value > .Machine$integer.max) {
        stop("La valeur fixe doit être un nombre entier valide.")
      }
      return(as.integer(numeric_value))
    }
    return(numeric_value)
  }

  if (identical(data_type, "date")) {
    date_value <- validate_date_value(value)
    if (is.na(date_value)) {
      stop("La valeur fixe de date doit respecter le format YYYY-MM-DD.")
    }
    return(date_value)
  }

  if (identical(data_type, "boolean")) {
    boolean_value <- tolower(value)
    if (!boolean_value %in% c("true", "false")) {
      stop("La valeur fixe booléenne doit être TRUE ou FALSE.")
    }
    return(identical(boolean_value, "true"))
  }

  if (data_type %in% c("text", "categorical")) {
    if (identical(data_type, "categorical") && !nzchar(value)) {
      stop("La valeur fixe catégorielle est obligatoire.")
    }
    return(value)
  }

  stop("Le type de la colonne ne permet pas une valeur fixe de comparaison.")
}

validate_formula_definition <- function(connection, formula) {
  if (!is.list(formula) || is.null(formula$mode)) {
    stop("La définition de formule est incomplète.")
  }

  if (!formula$mode %in% c("binary", "if_else")) {
    stop("Mode de formule non autorisé.")
  }

  if (identical(formula$mode, "binary")) {
    source_ids <- formula_source_ids(formula)
    if (length(source_ids) != 2L || anyNA(source_ids) || any(!nzchar(source_ids))) {
      stop("La formule doit référencer deux colonnes.")
    }
    sources <- lapply(source_ids, function(id) get_column_definition(connection, id))
    left_type <- sources[[1]]$data_type[[1]]
    right_type <- sources[[2]]$data_type[[1]]
    if (length(formula$operator) != 1L || !formula$operator %in% formula_binary_operators()) {
      stop("Opération non autorisée dans une formule.")
    }

    if (formula$operator %in% c("add", "subtract", "multiply", "divide")) {
      if (!is_numeric_column_type(left_type) || !is_numeric_column_type(right_type)) {
        stop("Les opérations arithmétiques nécessitent deux types numériques.")
      }
    } else if (identical(formula$operator, "days_between")) {
      if (!identical(left_type, "date") || !identical(right_type, "date")) {
        stop("Le calcul en jours nécessite deux colonnes de dates.")
      }
    } else if (formula$operator %in% c("months_between", "years_between")) {
      if (!identical(left_type, "date") || !identical(right_type, "date")) {
        stop("Le calcul en mois ou années nécessite deux colonnes de dates.")
      }
    } else {
      validate_comparison_types(left_type, right_type, formula$operator)
    }

    return(list(formula = formula, result_type = if (formula$operator %in% formula_comparison_operators()) "boolean" else if (formula$operator %in% c("days_between", "months_between", "years_between")) "integer" else "real"))
  }

  right_mode <- formula$right_mode
  if (is.null(right_mode)) right_mode <- "column"
  if (length(right_mode) != 1L || !right_mode %in% c("column", "constant")) {
    stop("Mode de comparaison non autorisé.")
  }
  formula$right_mode <- right_mode
  left_id <- formula$left_id
  if (length(left_id) != 1L || is.na(left_id) || !nzchar(left_id)) {
    stop("La condition doit référencer une colonne.")
  }
  left_definition <- get_column_definition(connection, left_id)
  left_type <- left_definition$data_type[[1]]
  if (identical(right_mode, "column")) {
    right_id <- formula$right_id
    if (length(right_id) != 1L || is.na(right_id) || !nzchar(right_id)) {
      stop("La condition doit référencer une deuxième colonne.")
    }
    right_type <- get_column_definition(connection, right_id)$data_type[[1]]
  } else {
    convert_formula_comparison_constant(formula$right_value, left_type)
    right_type <- left_type
  }

  if (length(formula$operator) != 1L || !formula$operator %in% formula_comparison_operators()) {
    stop("Opérateur de condition non autorisé.")
  }
  validate_comparison_types(left_type, right_type, formula$operator)

  result_type <- formula$result_type
  if (length(result_type) != 1L || is.na(result_type) || !result_type %in% c("text", "integer", "real", "date", "boolean")) {
    stop("Type de résultat conditionnel non autorisé.")
  }
  if (length(formula$true_value) != 1L || is.na(formula$true_value) ||
      length(formula$false_value) != 1L || is.na(formula$false_value)) {
    stop("Les deux résultats de la condition sont obligatoires.")
  }
  validate_formula_branch_value(formula$true_value, result_type)
  validate_formula_branch_value(formula$false_value, result_type)

  list(formula = formula, result_type = result_type)
}

formula_has_cycle <- function(definitions) {
  # Une visite en profondeur repère les références circulaires avant tout changement.
  visited <- character()

  visit <- function(column_id, visiting = character()) {
    if (column_id %in% visiting) {
      return(TRUE)
    }
    if (column_id %in% visited) {
      return(FALSE)
    }

    row <- definitions[definitions$column_id == column_id, , drop = FALSE]
    if (nrow(row) == 0L || !definition_has_formula(row)) {
      visited <<- c(visited, column_id)
      return(FALSE)
    }

    formula <- yaml::yaml.load(row$formula[[1]])
    dependencies <- formula_source_ids(formula)
    has_cycle <- any(vapply(
      dependencies,
      visit,
      logical(1),
      visiting = c(visiting, column_id)
    ))

    if (!has_cycle) {
      visited <<- c(visited, column_id)
    }

    has_cycle
  }

  has_formula <- !is.na(definitions$formula) & nzchar(definitions$formula)
  derived_ids <- definitions$column_id[has_formula]
  any(vapply(derived_ids, visit, logical(1)))
}

add_derived_column <- function(connection, name, formula) {
  validate_record_column_name(name)
  existing <- list_column_definitions(connection, include_hidden = TRUE)
  existing_names <- c(protected_record_columns(), existing$name, list_record_columns(connection))
  if (tolower(name) %in% tolower(existing_names)) {
    stop("Une colonne portant ce nom existe déjà.")
  }

  validated <- validate_formula_definition(connection, formula)
  column_id <- register_column_definition(
    connection,
    name = name,
    sql_name = NULL,
    data_type = validated$result_type,
    formula = validated$formula
  )

  if (formula_has_cycle(list_column_definitions(connection, include_hidden = TRUE))) {
    DBI::dbExecute(
      connection,
      paste("DELETE FROM column_definitions WHERE column_id =", quote_sql_value(connection, column_id))
    )
    stop("Une dépendance circulaire est interdite.")
  }

  column_id
}

update_derived_formula <- function(connection, column_id, formula) {
  definition <- get_column_definition(connection, column_id)
  if (!definition_has_formula(definition)) {
    stop("Seule une colonne dérivée peut recevoir une formule.")
  }

  validated <- validate_formula_definition(connection, formula)
  updated_definitions <- list_column_definitions(connection, include_hidden = TRUE)
  updated_definitions$formula[updated_definitions$column_id == column_id] <- yaml::as.yaml(validated$formula)
  updated_definitions$data_type[updated_definitions$column_id == column_id] <- validated$result_type
  if (formula_has_cycle(updated_definitions)) {
    stop("Une dépendance circulaire est interdite.")
  }

  DBI::dbExecute(
    connection,
    paste(
      "UPDATE column_definitions SET formula =",
      quote_sql_value(connection, yaml::as.yaml(validated$formula)),
      ", data_type =",
      quote_sql_value(connection, validated$result_type),
      "WHERE column_id =",
      quote_sql_value(connection, column_id)
    )
  )

  invisible(column_id)
}

compare_formula_values <- function(left, operator, right) {
  switch(
    operator,
    equal = left == right,
    not_equal = left != right,
    greater_than = left > right,
    greater_or_equal = left >= right,
    less_than = left < right,
    less_or_equal = left <= right
  )
}

convert_formula_branch <- function(value, result_type) {
  switch(
    result_type,
    text = as.character(value),
    integer = as.integer(value),
    real = as.numeric(value),
    date = validate_date_value(value),
    boolean = {
      parsed <- tolower(as.character(value))
      if (!parsed %in% c("true", "false")) {
        stop("Les résultats booléens doivent être TRUE ou FALSE.")
      }
      identical(parsed, "true")
    }
  )
}

validate_formula_branch_value <- function(value, result_type) {
  parsed <- suppressWarnings(convert_formula_branch(value, result_type))

  if (result_type == "integer") {
    numeric_value <- suppressWarnings(as.numeric(value))
    if (is.na(numeric_value) || !is.finite(numeric_value) || numeric_value != as.numeric(parsed)) {
      stop("Le résultat entier doit être un nombre entier valide.")
    }
  } else if (result_type == "real") {
    numeric_value <- suppressWarnings(as.numeric(value))
    if (is.na(numeric_value) || !is.finite(numeric_value)) {
      stop("Le résultat décimal doit être un nombre fini valide.")
    }
  } else if (result_type == "date" && is.na(parsed)) {
    stop("Le résultat date doit respecter le format YYYY-MM-DD.")
  }

  invisible(parsed)
}

calculate_formula <- function(formula, left, right, result_type) {
  if (identical(formula$mode, "if_else")) {
    condition <- compare_formula_values(left, formula$operator, right)
    missing <- is.na(condition)
    if (result_type == "text") {
      result <- rep(NA_character_, length(condition))
    } else if (result_type == "date") {
      result <- as.Date(rep(NA_character_, length(condition)))
    } else if (result_type == "boolean") {
      result <- rep(NA, length(condition))
    } else if (result_type == "integer") {
      result <- rep(NA_integer_, length(condition))
    } else {
      result <- rep(NA_real_, length(condition))
    }

    true_rows <- which(!missing & condition)
    false_rows <- which(!missing & !condition)
    result[true_rows] <- convert_formula_branch(formula$true_value, result_type)
    result[false_rows] <- convert_formula_branch(formula$false_value, result_type)
    return(result)
  }

  operator <- formula$operator
  if (operator %in% c("add", "subtract", "multiply", "divide")) {
    left <- as.numeric(left)
    right <- as.numeric(right)
    result <- switch(
      operator,
      add = left + right,
      subtract = left - right,
      multiply = left * right,
      divide = left / right
    )
    result[is.na(left) | is.na(right)] <- NA_real_
    if (operator == "divide") {
      result[!is.na(right) & right == 0] <- NA_real_
    }
    return(result)
  }

  if (operator == "days_between") {
    return(as.integer(as.Date(left) - as.Date(right)))
  }

  if (operator %in% c("months_between", "years_between")) {
    left <- as.Date(left)
    right <- as.Date(right)
    missing <- is.na(left) | is.na(right)

    left_year <- as.integer(format(left, "%Y"))
    right_year <- as.integer(format(right, "%Y"))
    left_month <- as.integer(format(left, "%m"))
    right_month <- as.integer(format(right, "%m"))
    left_day <- as.integer(format(left, "%d"))
    right_day <- as.integer(format(right, "%d"))

    months <- (left_year - right_year) * 12L + (left_month - right_month)
    adjust_positive <- !missing & months > 0L & left_day < right_day
    adjust_negative <- !missing & months < 0L & left_day > right_day
    months[adjust_positive] <- months[adjust_positive] - 1L
    months[adjust_negative] <- months[adjust_negative] + 1L

    if (identical(operator, "years_between")) {
      years <- integer(length(months))
      positive <- !missing & months >= 0L
      negative <- !missing & months < 0L
      years[positive] <- months[positive] %/% 12L
      years[negative] <- -((-months[negative]) %/% 12L)
      years[missing] <- NA_integer_
      return(as.integer(years))
    }

    months[missing] <- NA_integer_
    return(as.integer(months))
  }

  compare_formula_values(left, operator, right)
}

calculate_derived_columns <- function(data, definitions) {
  if (!is.data.frame(data)) {
    stop("Les données doivent être fournies sous forme de data.frame.")
  }
  if (formula_has_cycle(definitions)) {
    stop("Une dépendance circulaire est interdite.")
  }

  resolve_column <- function(column_id, visiting = character()) {
    if (column_id %in% visiting) {
      stop("Une dépendance circulaire est interdite.")
    }

    definition <- definitions[definitions$column_id == column_id, , drop = FALSE]
    if (nrow(definition) != 1L) {
      stop("Une colonne source de la formule n'existe pas.")
    }

    if (!definition_has_formula(definition)) {
      source_name <- definition$sql_name[[1]]
      if (is.na(source_name) || !source_name %in% names(data)) {
        stop("Une colonne source est absente des données.")
      }
      return(data[[source_name]])
    }

    # Les sources sont résolues par identifiant stable, même si leur nom SQL a changé.
    formula <- yaml::yaml.load(definition$formula[[1]])
    source_ids <- formula_source_ids(formula)
    left <- resolve_column(source_ids[[1]], c(visiting, column_id))
    validated <- validate_formula_definition_from_types(formula, definitions)
    right <- if (identical(formula$mode, "if_else") && identical(validated$right_mode, "constant")) {
      validated$right_value
    } else {
      resolve_column(source_ids[[2]], c(visiting, column_id))
    }
    calculate_formula(formula, left, right, validated$result_type)
  }

  has_formula <- !is.na(definitions$formula) & nzchar(definitions$formula)
  for (row_index in which(has_formula & !definitions$is_hidden)) {
    column <- definitions[row_index, , drop = FALSE]
    data[[column$name[[1]]]] <- resolve_column(column$column_id[[1]])
  }

  data
}

validate_formula_definition_from_types <- function(formula, definitions) {
  ids <- formula_source_ids(formula)
  left_row <- definitions[definitions$column_id == ids[[1]], , drop = FALSE]
  if (nrow(left_row) != 1L) {
    stop("Une colonne source de la formule n'existe pas.")
  }

  left_type <- left_row$data_type[[1]]
  right_mode <- if (identical(formula$mode, "if_else") && is.null(formula$right_mode)) {
    "column"
  } else if (identical(formula$mode, "binary")) {
    "column"
  } else {
    formula$right_mode
  }
  right_row <- if (identical(right_mode, "column")) {
    definitions[definitions$column_id == ids[[2]], , drop = FALSE]
  } else {
    left_row
  }
  if (nrow(right_row) != 1L) {
    stop("Une colonne source de la formule n'existe pas.")
  }
  right_type <- right_row$data_type[[1]]
  operator <- formula$operator
  right_value <- NULL

  if (formula$mode == "binary") {
    if (operator %in% c("add", "subtract", "multiply", "divide") &&
        (!is_numeric_column_type(left_type) || !is_numeric_column_type(right_type))) {
      stop("Les opérations arithmétiques nécessitent deux types numériques.")
    }
    if (operator == "days_between" &&
        (!identical(left_type, "date") || !identical(right_type, "date"))) {
      stop("Le calcul en jours nécessite deux colonnes de dates.")
    }
    if (operator %in% c("months_between", "years_between") &&
        (!identical(left_type, "date") || !identical(right_type, "date"))) {
      stop("Le calcul en jours, mois ou années nécessite deux colonnes de dates.")
    }
    if (operator %in% formula_comparison_operators()) {
      validate_comparison_types(left_type, right_type, operator)
    }
    result_type <- if (operator %in% formula_comparison_operators()) "boolean" else if (operator %in% c("days_between", "months_between", "years_between")) "integer" else "real"
  } else {
    if (!right_mode %in% c("column", "constant")) {
      stop("Mode de comparaison non autorisé.")
    }
    if (identical(right_mode, "constant")) {
      right_value <- convert_formula_comparison_constant(formula$right_value, left_type)
    }
    validate_comparison_types(left_type, right_type, operator)
    result_type <- formula$result_type
  }

  list(result_type = result_type, right_mode = right_mode, right_value = right_value)
}

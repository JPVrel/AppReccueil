# Les dates sont des jours calendaires sans heure ni fuseau, au format ISO strict.
validate_date_value <- function(value) {
  if (length(value) != 1L) {
    stop("Une seule date doit être fournie.")
  }
  if (is.na(value) || identical(value, "")) {
    return(as.Date(NA))
  }

  value <- as.character(value)
  if (!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", value)) {
    stop("La date doit respecter le format YYYY-MM-DD.")
  }

  year <- as.integer(substr(value, 1, 4))
  if (year < 1000L || year > 9999L) {
    stop("L'année doit être comprise entre 1000 et 9999.")
  }

  parsed_date <- suppressWarnings(as.Date(value, format = "%Y-%m-%d"))
  if (is.na(parsed_date) || format(parsed_date, "%Y-%m-%d") != value) {
    stop("La date doit être une date réelle au format YYYY-MM-DD.")
  }

  parsed_date
}

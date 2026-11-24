# Packages nécessaires pour utiliser l'application, hors outils de test.
runtime_packages <- function() {
  "shiny"
}

# Packages utilisés pour l'application et son développement.
required_packages <- function() {
  c(runtime_packages(), "testthat")
}

# Retourne uniquement les packages absents. installed_fn est injectable
# afin que cette fonction puisse être testée sans modifier l'installation R.
missing_packages <- function(
  packages = required_packages(),
  installed_fn = function(package) requireNamespace(package, quietly = TRUE)
) {
  packages[!vapply(packages, installed_fn, logical(1))]
}

# Installe seulement les packages manquants et ne réinstalle pas le reste.
# install_fn est injectable pour tester le choix des packages sans Internet.
install_dependencies <- function(
  packages = required_packages(),
  installed_fn = function(package) requireNamespace(package, quietly = TRUE),
  install_fn = utils::install.packages
) {
  missing <- missing_packages(packages, installed_fn)

  if (length(missing) > 0) {
    install_fn(missing, repos = "https://cloud.r-project.org")
  }

  invisible(missing)
}

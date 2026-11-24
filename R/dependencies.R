runtime_packages <- function() {
  "shiny"
}

required_packages <- function() {
  c(runtime_packages(), "testthat")
}

missing_packages <- function(
  packages = required_packages(),
  installed_fn = function(package) requireNamespace(package, quietly = TRUE)
) {
  packages[!vapply(packages, installed_fn, logical(1))]
}

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

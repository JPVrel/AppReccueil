# Packages nécessaires pour utiliser l'application, hors outils de test.
runtime_packages <- function() {
  c("shiny", "DT", "DBI", "RSQLite", "yaml", "writexl", "readxl", "openssl")
}

# Packages directs utilisés par les tests et le développement.
development_packages <- function() {
  c(runtime_packages(), "testthat", "htmltools")
}

# Packages directs de l'option PostgreSQL distante.
postgres_packages <- function() {
  c(runtime_packages(), "RPostgres")
}

# Conserve ce nom pour les appels historiques qui demandaient les dépendances de test.
required_packages <- function() {
  development_packages()
}

dependency_packages <- function(profile = c("runtime", "development", "postgres")) {
  profile <- match.arg(profile)
  switch(
    profile,
    runtime = runtime_packages(),
    development = development_packages(),
    postgres = postgres_packages()
  )
}

# Retourne uniquement les packages absents. installed_fn est injectable
# afin que cette fonction puisse être testée sans modifier l'installation R.
missing_packages <- function(
  packages = required_packages(),
  installed_fn = function(package) requireNamespace(package, quietly = TRUE)
) {
  packages[!vapply(packages, installed_fn, logical(1))]
}

openssl_install_configure_vars <- function(
  packages,
  platform = Sys.info()[["sysname"]],
  homebrew_roots = c("/opt/homebrew/opt/openssl@3", "/usr/local/opt/openssl@3")
) {
  if (!"openssl" %in% packages || !identical(platform, "Darwin")) {
    return(NULL)
  }

  available <- homebrew_roots[vapply(
    homebrew_roots,
    function(root) dir.exists(file.path(root, "include", "openssl")) && dir.exists(file.path(root, "lib")),
    logical(1)
  )]
  if (length(available) == 0L) {
    return(NULL)
  }

  prefix <- available[[1]]
  stats::setNames(
    paste(
      "INCLUDE_DIR=",
      file.path(prefix, "include"),
      "LIB_DIR=",
      file.path(prefix, "lib"),
      sep = ""
    ),
    "openssl"
  )
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
    configure_vars <- openssl_install_configure_vars(missing)
    if (is.null(configure_vars)) {
      install_fn(missing, repos = "https://cloud.r-project.org")
    } else {
      install_fn(
        missing,
        repos = "https://cloud.r-project.org",
        configure.vars = configure_vars
      )
    }
  }

  invisible(missing)
}

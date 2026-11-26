file_arg <- grep("^--file=", commandArgs(), value = TRUE)
if (length(file_arg) == 0L) {
  stop("Lancez ce script avec Rscript scripts/build_release.R.")
}
script_path <- sub("^--file=", "", file_arg[[1]])
project_dir <- dirname(dirname(normalizePath(script_path)))
source(file.path(project_dir, "R", "dependencies.R"))
source(file.path(project_dir, "R", "package_library.R"))

script_args <- commandArgs(trailingOnly = TRUE)
if (length(script_args) == 0L) {
  output_file <- NULL
} else if (length(script_args) == 1L && startsWith(script_args[[1]], "--output=")) {
  output_file <- sub("^--output=", "", script_args[[1]])
} else if (length(script_args) == 2L && identical(script_args[[1]], "--output")) {
  output_file <- script_args[[2]]
} else {
  stop("Usage: Rscript scripts/build_release.R [--output path/to/release.zip]")
}

r_minor <- strsplit(R.version$minor, ".", fixed = TRUE)[[1]][[1]]
r_family <- paste(R.version$major, r_minor, sep = ".")
system_name <- switch(
  Sys.info()[["sysname"]],
  Darwin = "macos",
  Windows = "windows",
  Linux = "linux",
  tolower(Sys.info()[["sysname"]])
)
release_name <- sprintf(
  "AppReccueil-%s-R%s-%s.zip",
  system_name,
  r_family,
  R.version$arch
)

if (is.null(output_file)) {
  output_file <- file.path(project_dir, "dist", release_name)
} else {
  output_file <- path.expand(output_file)
  if (!grepl("^(/|[A-Za-z]:|\\\\\\\\)", output_file)) {
    output_file <- file.path(project_dir, output_file)
  }
}

if (!grepl("\\.zip$", output_file, ignore.case = TRUE)) {
  stop("Le fichier de sortie doit avoir l'extension .zip.")
}

output_dir <- dirname(output_file)
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
output_file <- file.path(normalizePath(output_dir), basename(output_file))
if (file.exists(output_file) || dir.exists(output_file)) {
  stop("Le fichier de sortie existe déjà : ", output_file)
}

stage_root <- tempfile("appreccueil-release-", tmpdir = tempdir())
release_dir <- file.path(stage_root, "AppReccueil")
if (!dir.create(release_dir, recursive = TRUE)) {
  stop("Impossible de créer le dossier temporaire de release.")
}

for (directory in c("R", "shiny", "scripts")) {
  copied <- file.copy(
    file.path(project_dir, directory),
    release_dir,
    recursive = TRUE
  )
  if (!copied) {
    stop("Impossible de copier le dossier : ", directory)
  }
}

config_dir <- file.path(release_dir, "config")
dir.create(config_dir)
writeLines(
  c("database:", "  mode: local", "  local:", "    path: data/recueil.sqlite"),
  file.path(config_dir, "database.yml")
)

for (file in c("app.R", "launcher.R", "README.md", "renv.lock")) {
  copied <- file.copy(file.path(project_dir, file), release_dir)
  if (!copied) {
    stop("Impossible de copier le fichier : ", file)
  }
}

for (directory in c("data", "exports")) {
  output_directory <- file.path(release_dir, directory)
  dir.create(output_directory, recursive = TRUE, showWarnings = FALSE)
  writeLines(character(), file.path(output_directory, ".gitkeep"))
}

if (!requireNamespace("renv", quietly = TRUE)) {
  utils::install.packages("renv", repos = "https://cloud.r-project.org")
}

library_path <- project_package_library_path(release_dir)
dir.create(library_path, recursive = TRUE, showWarnings = FALSE)
renv::restore(
  project = release_dir,
  lockfile = file.path(release_dir, "renv.lock"),
  library = library_path,
  packages = runtime_packages(),
  prompt = FALSE
)

installed_packages <- rownames(utils::installed.packages(lib.loc = library_path))
missing_packages <- setdiff(runtime_packages(), installed_packages)
if (length(missing_packages) > 0L) {
  stop("Packages runtime absents de la bibliothèque de release : ", paste(missing_packages, collapse = ", "))
}

writeLines(
  c(
    "Application de recueil - release autonome côté packages R",
    paste("R family:", paste0(R.version$major, ".", r_minor)),
    paste("R platform:", R.version$platform),
    paste("Operating system:", Sys.info()[["sysname"]]),
    paste("Runtime packages:", paste(runtime_packages(), collapse = ", "))
  ),
  file.path(release_dir, "RELEASE.txt")
)

archive_status <- local({
  original_dir <- getwd()
  on.exit(setwd(original_dir), add = TRUE)
  setwd(stage_root)
  utils::zip(zipfile = output_file, files = "AppReccueil", flags = "-q -r9X")
})

if (!identical(as.integer(archive_status), 0L) || !file.exists(output_file)) {
  stop("La création de l'archive a échoué.")
}

normalizePath(output_file)
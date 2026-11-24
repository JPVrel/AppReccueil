# Script utilisable avec Rscript ou avec source() depuis la racine du projet.
file_arg <- grep("^--file=", commandArgs(), value = TRUE)
project_dir <- if (length(file_arg) > 0) {
	script_path <- sub("^--file=", "", file_arg[[1]])
	dirname(dirname(normalizePath(script_path)))
} else {
	normalizePath(getwd())
}
source(file.path(project_dir, "R", "dependencies.R"))

# Installe Shiny et testthat uniquement lorsqu'ils sont absents.
install_dependencies()

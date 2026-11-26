# Script utilisable avec Rscript ou avec source() depuis la racine du projet.
file_arg <- grep("^--file=", commandArgs(), value = TRUE)
project_dir <- if (length(file_arg) > 0) {
	script_path <- sub("^--file=", "", file_arg[[1]])
	dirname(dirname(normalizePath(script_path)))
} else {
	normalizePath(getwd())
}
source(file.path(project_dir, "R", "dependencies.R"))

script_args <- commandArgs(trailingOnly = TRUE)
profile <- "runtime"

if (length(script_args) > 0) {
	if (length(script_args) == 2L && identical(script_args[[1]], "--profile")) {
		profile <- script_args[[2]]
	} else if (length(script_args) == 1L && startsWith(script_args[[1]], "--profile=")) {
		profile <- sub("^--profile=", "", script_args[[1]])
	} else {
		stop("Usage: Rscript scripts/install_dependencies.R [--profile runtime|development|postgres]")
	}
}

if (!profile %in% c("runtime", "development", "postgres")) {
	stop("Profil inconnu : ", profile, ". Choisir runtime, development ou postgres.")
}

install_dependencies(dependency_packages(profile))

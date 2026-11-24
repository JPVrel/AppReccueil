file_arg <- grep("^--file=", commandArgs(), value = TRUE)
project_dir <- if (length(file_arg) > 0) {
	script_path <- sub("^--file=", "", file_arg[[1]])
	dirname(dirname(normalizePath(script_path)))
} else {
	normalizePath(getwd())
}
source(file.path(project_dir, "R", "dependencies.R"))

install_dependencies()

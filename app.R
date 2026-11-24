# Point d'entrée standard de Shiny. Positron attend que ce fichier retourne
# un objet shiny.appobj lorsqu'il est lancé avec « Run App ».
app_dir <- normalizePath(getwd())
source(file.path(app_dir, "R", "load_modules.R"))
load_modules(app_dir)

# L'interface et la logique Shiny sont assemblées dans un objet unique.
build_shiny_app()

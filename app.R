# Point d'entrée standard de Shiny. Positron attend que ce fichier retourne
# un objet shiny.appobj lorsqu'il est lancé avec « Run App ».
app_dir <- normalizePath(getwd())
source(file.path(app_dir, "R", "load_modules.R"))
load_modules(app_dir)

# La configuration est lue ici, mais la connexion sera ouverte par Shiny
# lorsqu'une session utilisateur commencera.
database_config <- read_database_config(file.path(app_dir, "config", "database.yml"))

# L'interface et la logique Shiny sont assemblées dans un objet unique.
build_shiny_app(database_config)

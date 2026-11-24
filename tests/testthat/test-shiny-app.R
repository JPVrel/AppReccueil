testthat::test_that("build_shiny_app returns a Shiny application", {
  testthat::expect_s3_class(build_shiny_app(), "shiny.appobj")
})

testthat::test_that("the collection status changes after starting", {
  shiny::testServer(build_app_server(), {
    testthat::expect_equal(output$status, "Aucun recueil n'est commencé.")
    session$setInputs(start_collection = 1)
    testthat::expect_equal(output$status, "Le parcours de recueil est prêt à être défini.")
  })
})

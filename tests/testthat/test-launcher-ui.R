testthat::test_that("launcher_status_text describes the server state", {
  testthat::expect_equal(
    launcher_status_text(NULL, "http://127.0.0.1:8000"),
    "Le serveur Shiny est arrêté."
  )
  testthat::expect_equal(
    launcher_status_text(1234L, "http://127.0.0.1:8000"),
    "Serveur lancé : http://127.0.0.1:8000"
  )
})

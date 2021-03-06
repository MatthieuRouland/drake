drake_context("map reduce")

test_with_dir("map_plan()", {
  skip_on_cran()
  fn <- function(a, b) {
    a + b
  }
  args <- expand.grid(a = 1:2, b = 3:5)
  plan1 <- map_plan(args = args, fun = fn)
  args$id <- LETTERS[seq_len(nrow(args))]
  plan2 <- map_plan(args = args, fun = fn)
  args$x <- args$id
  args$id <- NULL
  plan3 <- map_plan(args = args, fun = fn, id = x)
  plan4 <- map_plan(args = args, fun = "fn", id = "x", character_only = TRUE)
  plan5 <- map_plan(args = args, fun = fn, id = x, trace = TRUE)
  expect_equal(deparse_lang_col(plan1$command), deparse_lang_col(plan2$command))
  equivalent_plans(plan2, plan3)
  equivalent_plans(plan3, plan4)
  equivalent_plans(weak_as_tibble(cbind(plan3, args)), plan5)
  cache <- storr::storr_environment()
  make(plan2, session_info = FALSE, cache = cache)
  expect_equal(
    vapply(
      args$x, readd, FUN.VALUE = integer(1), USE.NAMES = FALSE,
      cache = cache, character_only = TRUE
    ),
    as.integer(args$a + args$b)
  )
})

test_with_dir("map_plan() onto a matrix", {
  skip_on_cran()
  skip_if_not_installed("datasets")
  my_model_fit <- function(x1, x2) {
    lm(as.formula(paste("mpg ~", x1, "+", x2)), data = datasets::mtcars)
  }
  covariates <- setdiff(colnames(datasets::mtcars), "mpg")
  args <- t(combn(covariates, 2))
  colnames(args) <- c("x1", "x2")
  plan <- map_plan(args, "my_model_fit")
  cache <- storr::storr_environment()
  make(plan, cache = cache, session_info = FALSE)
  x <- readd(plan$target[1], character_only = TRUE, cache = cache)
  expect_true(is.numeric(stats::coefficients(x)))
})

test_with_dir("map_plan() with symbols", {
  skip_on_cran()
  skip_if_not_installed("datasets")
  my_model_fit <- function(x1, x2, data) {
    formula <- as.formula(paste("mpg ~", x1, "+", x1))
    lm(formula, data = data)
  }
  covariates <- setdiff(colnames(datasets::mtcars), "mpg")
  args <- t(combn(covariates, 2))
  colnames(args) <- c("x1", "x2")
  args <- weak_as_tibble(args)
  args$data <- rlang::syms(rep("mtcars", nrow(args)))
  plan <- map_plan(args, my_model_fit)
  cache <- storr::storr_environment()
  make(plan, verbose = 0L, cache = cache)
  x <- readd(plan$target[1], character_only = TRUE, cache = cache)
  expect_true(is.numeric(stats::coefficients(x)))
})

test_with_dir("gather_plan()", {
  df <- drake_plan(data = simulate(center = MU, scale = SIGMA))
  m0 <- evaluate_plan(df, wildcard = "NULL", values = 1:2)
  equivalent_plans(m0, df)
  m1 <- evaluate_plan(df, rules = list(nothing = 1:2), expand = FALSE)
  equivalent_plans(m1, df)
  x <- expand_plan(df, values = c("rep1", "rep2"))
  x6 <- gather_plan(x, append = FALSE)
  y <- sanitize_plan(
    weak_tibble(
      target = "target",
      command = "list(data_rep1 = data_rep1, data_rep2 = data_rep2)"
    )
  )
  equivalent_plans(x6, y)
  z <- gather_plan(x, append = TRUE)
  equivalent_plans(z, bind_plans(x, y))
  x7 <- gather_plan(
    x, target = "my_summaries", gather = "rbind", append = FALSE
  )
  y <- weak_tibble(
    target = "my_summaries",
    command = "rbind(data_rep1 = data_rep1, data_rep2 = data_rep2)"
  )
  equivalent_plans(x7, y)
})

test_with_dir("reduce_plan()", {
  skip_on_cran() # CRAN gets whitelist tests only (check time limits).
  # Non-pairwise reduce
  x_plan <- evaluate_plan(
    drake_plan(x = VALUE),
    wildcard = "VALUE",
    values = 1:8
  )
  x <- reduce_plan(
    x_plan, target = "x_sum", pairwise = FALSE,
    begin = "", end = "", append = FALSE
  )
  x0 <- weak_tibble(
    target = "x_sum",
    command = paste0(x_plan$target, collapse = " + ")
  )
  equivalent_plans(x, x0)
  z <- reduce_plan(
    x_plan, target = "x_sum", pairwise = FALSE,
    begin = "", end = "", append = TRUE
  )
  z0 <- bind_plans(x_plan, x)
  equivalent_plans(z, z0)
  make(rbind(x_plan, x), session_info = FALSE)
  expect_equal(readd(x_sum), sum(1:8))
  clean(destroy = TRUE)

  # Pairwise reduce even number of targets
  x <- reduce_plan(x_plan, target = "x_sum", pairwise = TRUE)
  x0 <- weak_tibble(
    target = c(paste0("x_sum_", 1:6), "x_sum"),
    command = c(
      "x_1 + x_2", "x_3 + x_4", "x_5 + x_6", "x_7 + x_8",
      "x_sum_1 + x_sum_2", "x_sum_3 + x_sum_4",
      "x_sum_5 + x_sum_6"
    )
  )
  equivalent_plans(x, x0)
  x <- reduce_plan(
    x_plan, target = "x_sum", pairwise = FALSE,
    begin = "", end = ""
  )
  x0 <- weak_tibble(
    target = "x_sum",
    command = paste0(x_plan$target, collapse = " + ")
  )
  equivalent_plans(x, x0)
  x <- reduce_plan(x_plan, target = "x_sum", pairwise = TRUE)
  x0 <- weak_tibble(
    target = c(paste0("x_sum_", 1:6), "x_sum"),
    command = c(
      "x_1 + x_2", "x_3 + x_4", "x_5 + x_6", "x_7 + x_8",
      "x_sum_1 + x_sum_2", "x_sum_3 + x_sum_4",
      "x_sum_5 + x_sum_6"
    )
  )
  equivalent_plans(x, x0)
  make(rbind(x_plan, x), session_info = FALSE)
  expect_equal(readd(x_sum), sum(1:8))
  clean(destroy = TRUE)

  # Odd number of targets
  x_plan <- evaluate_plan(
    drake_plan(x = VALUE),
    wildcard = "VALUE",
    values = 1:9
  )
  x <- reduce_plan(x_plan, target = "x_sum", pairwise = TRUE)
  x0 <- weak_tibble(
    target = c(paste0("x_sum_", 1:7), "x_sum"),
    command = c(
      "x_1 + x_2", "x_3 + x_4", "x_5 + x_6", "x_7 + x_8",
      "x_9 + x_sum_1",
      "x_sum_2 + x_sum_3", "x_sum_4 + x_sum_5",
      "x_sum_6 + x_sum_7"
    )
  )
  equivalent_plans(x, x0)
  make(rbind(x_plan, x), session_info = FALSE)
  expect_equal(readd(x_sum), sum(1:9))
  clean(destroy = TRUE)

  # Arbitrary function in reduction
  x_plan <- evaluate_plan(
    drake_plan(x = VALUE),
    wildcard = "VALUE",
    values = 1:8
  )
  fun <- function(x, y) {
    x ^ 2 - 3 * y
  }
  x <- reduce_plan(x_plan, target = "x_sum", pairwise = TRUE,
                   begin = "fun(", op = ", ", end = ")")
  x0 <- weak_tibble(
    target = c(paste0("x_sum_", 1:6), "x_sum"),
    command = c(
      "fun(x_1, x_2)", "fun(x_3, x_4)", "fun(x_5, x_6)", "fun(x_7, x_8)",
      "fun(x_sum_1, x_sum_2)", "fun(x_sum_3, x_sum_4)",
      "fun(x_sum_5, x_sum_6)"
    )
  )
  equivalent_plans(x, x0)
  make(rbind(x_plan, x))
  out <- fun(
    fun(
      fun(1, 2),
      fun(3, 4)
    ),
    fun(
      fun(5, 6),
      fun(7, 8)
    )
  )
  expect_equal(readd(x_sum), out)
})

test_with_dir("gather_by()", {
  skip_on_cran()
  plan <- evaluate_plan(
    drake_plan(x = rnorm(m__), y = rexp(n__), z = 10),
    rules = list(
      m__ = 1:2,
      n__ = c("a", "b")
    ),
    trace = TRUE
  )
  x <- gather_by(plan, append = TRUE)
  new_row <- drake_plan(
    target = list(x_1 = x_1, x_2 = x_2, y_a = y_a, y_b = y_b, z = z)
  )
  y <- bind_plans(plan, new_row)
  equivalent_plans(x[, c("target", "command")], y)
  x <- gather_by(plan, append = TRUE, sep = ".")
  equivalent_plans(x[, c("target", "command")], y)
  z <- gather_by(plan, append = FALSE)
  equivalent_plans(z[, c("target", "command")], y[nrow(y), ])
  x <- gather_by(
    plan,
    n___from,
    prefix = "xyz",
    gather = "c",
    append = TRUE,
    sep = "."
  )
  y <- weak_tibble(
    target = c("xyz.y", "xyz.NA"),
    command = c("c(y_a = y_a, y_b = y_b)", "c(x_1 = x_1, x_2 = x_2, z = z)"),
    m__ = as.character(NA),
    m___from = as.character(NA),
    n__ = NA,
    n___from = c("y", NA)
  )
  y <- sanitize_plan(y)
  equivalent_plans(x, bind_plans(plan, y))
  x <- gather_by(plan, n___from, prefix = "xyz", gather = "c", append = TRUE)
  y <- weak_tibble(
    target = c("xyz_y", "xyz_NA"),
    command = c("c(y_a = y_a, y_b = y_b)", "c(x_1 = x_1, x_2 = x_2, z = z)"),
    m__ = as.character(NA),
    m___from = as.character(NA),
    n__ = NA,
    n___from = c("y", NA)
  )
  y <- sanitize_plan(y)
  expected <- bind_plans(plan, y)
  equivalent_plans(x[order(x$target), ], expected[order(expected$target), ])
  x <- gather_by(plan, m__, n__, prefix = "xyz", gather = "c", append = TRUE)
  y <- weak_tibble(
    target = c("xyz_1_NA", "xyz_2_NA", "xyz_NA_a", "xyz_NA_b", "xyz_NA_NA"),
    command = c(
      "c(x_1 = x_1)",
      "c(x_2 = x_2)",
      "c(y_a = y_a)",
      "c(y_b = y_b)",
      "c(z = z)"
    ),
    m__ = as.character(c(1, 2, NA, NA, NA)),
    m___from = as.character(NA),
    n__ = c(NA, NA, "a", "b", NA),
    n___from = as.character(NA)
  )
  y <- sanitize_plan(y)
  expected <- bind_plans(plan, y)
  equivalent_plans(x[order(x$target), ], expected[order(expected$target), ])
  plan$n___from <- c("x", "x", "y", "y", NA)
  x <- gather_by(
    plan,
    n___from,
    prefix = "xyz",
    gather = "c",
    append = TRUE,
    filter = n___from == "x"
  )
  new_row <- drake_plan(xyz_x = c(x_1 = x_1, x_2 = x_2))
  y <- bind_plans(plan, new_row)
  equivalent_plans(x[, c("target", "command")], y)
})

test_with_dir("reduce_by()", {
  skip_on_cran()
  plan <- evaluate_plan(
    drake_plan(x = rnorm(m__), y = rexp(n__), z = 10),
    rules = list(
      m__ = 1:4,
      n__ = c("a", "b")
    ),
    trace = TRUE
  )
  x <- reduce_by(plan, pairwise = FALSE, append = TRUE)
  new_row <- drake_plan(target = x_1 + x_2 + x_3 + x_4 + y_a + y_b + z)
  y <- bind_plans(plan, new_row)
  equivalent_plans(x[, c("target", "command")], y)
  z <- reduce_by(plan, pairwise = FALSE, append = FALSE)
  equivalent_plans(z[, c("target", "command")], y[nrow(y), ])
  x <- reduce_by(
    plan, m___from,
    prefix = "xyz",
    op = ", ",
    begin = "c(",
    end = ")",
    append = TRUE,
    sep = "."
  )
  y <- weak_tibble(
    target = c("xyz.1.x", "xyz.2.x", "xyz.x", "xyz.1.NA", "xyz.NA"),
    command = c(
      "c(x_1, x_2)",
      "c(x_3, x_4)",
      "c(xyz.1, xyz.2)",
      "c(y_a, y_b)",
      "c(z, xyz.1)"
    ),
    m__ = as.character(NA),
    m___from = c(rep("x", 3), rep(NA, 2)),
    n__ = as.character(NA),
    n___from = as.character(NA)
  )
  y <- sanitize_plan(y)
  expected <- bind_plans(plan, y)
  equivalent_plans(x[order(x$target), ], expected[order(expected$target), ])
  x <- reduce_by(
    plan, m___from,
    prefix = "xyz",
    op = ", ",
    begin = "c(",
    end = ")",
    append = TRUE
  )
  y <- weak_tibble(
    target = c("xyz_1_x", "xyz_2_x", "xyz_x", "xyz_1_NA", "xyz_NA"),
    command = c(
      "c(x_1, x_2)", "c(x_3, x_4)", "c(xyz_1, xyz_2)",
      "c(y_a, y_b)", "c(z, xyz_1)"
    ),
    m__ = as.character(NA),
    m___from = c(rep("x", 3), rep(NA, 2)),
    n__ = as.character(NA),
    n___from = as.character(NA)
  )
  y <- sanitize_plan(y)
  expected <- bind_plans(plan, y)
  equivalent_plans(x[order(x$target), ], expected[order(expected$target), ])
  x <- reduce_by(
    plan, m___from, prefix = "xyz", op = ", ", begin = "c(", end = ")",
    pairwise = FALSE, append = TRUE
  )
  y <- weak_tibble(
    target = c("xyz_x", "xyz_NA"),
    command = c("c(c(c(x_1, x_2), x_3), x_4)", "c(c(y_a, y_b), z)"),
    m__ = as.character(NA),
    m___from = c("x", NA),
    n__ = as.character(NA),
    n___from = as.character(NA)
  )
  y <- sanitize_plan(y)
  expected <- bind_plans(plan, y)
  equivalent_plans(x[order(x$target), ], expected[order(expected$target), ])
  x <- reduce_by(plan, m___from, n___from, append = TRUE)
  y <- weak_tibble(
    target = c(
      "target_1_x_NA",
      "target_2_x_NA",
      "target_x_NA",
      "target_NA_y"
    ),
    command = c(
      "x_1 + x_2",
      "x_3 + x_4",
      "target_1 + target_2",
      "y_a + y_b"
    ),
    m__ = as.character(NA),
    m___from = c(rep("x", 3), NA),
    n__ = as.character(NA),
    n___from = c(rep(NA, 3), "y")
  )
  y <- sanitize_plan(y)
  expected <- bind_plans(plan, y)
  equivalent_plans(x[order(x$target), ], expected[order(expected$target), ])
  x <- reduce_by(plan, m___from, n___from, pairwise = FALSE, append = TRUE)
  y <- weak_tibble(
    target = c(
      "target_x_NA",
      "target_NA_y",
      "target_NA_NA"
    ),
    command = c(
      "x_1 + x_2 + x_3 + x_4",
      "y_a + y_b",
      "z"
    ),
    m__ = as.character(NA),
    m___from = c("x", NA, NA),
    n__ = as.character(NA),
    n___from = c(NA, "y", NA)
  )
  y <- sanitize_plan(y)
  expected <- bind_plans(plan, y)
  equivalent_plans(x[order(x$target), ], expected[order(expected$target), ])
  plan$from <- c(rep("x", 4), rep("y", 2), NA)
  x <- reduce_by(
    plan,
    from,
    prefix = "xyz",
    append = TRUE,
    pairwise = FALSE,
    filter = from == "y"
  )
  new_row <- drake_plan(xyz_y = y_a + y_b)
  y <- bind_plans(plan, new_row)
  equivalent_plans(x[, c("target", "command")], y)
})

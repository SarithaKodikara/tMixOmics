context("m-product utilities")
# bltodo: add tests for matrix inputs
# bltodo: run on linux system to test parallel algorithms

#' @description Use for internal testing.
#' Performs a DCT-II transform using the stats::fft algorithm. Produces
#' identical output to the scipy.fft.dct implementation in Python.
#' @param vec A numeric real vector to transform.
#' @param ortho Logical, if TRUE the output is orthonormal.
#' @return A numeric vector representing the DCT-II of the input.
#' @seealso docs.scipy.org/doc/scipy/tutorial/fft.html
dctii_scipy_equivalent <- function(vec, ortho = TRUE) {
  # https://scipy.github.io/devdocs/reference/generated/scipy.fftpack.dct.html
  # https://stackoverflow.com/questions/11215162
  # NOTE: this is dtt output scaled by 2
  n <- length(vec)
  p <- exp(complex(imaginary = pi / 2 / n) * (seq(2 * n) - 1))
  unscaled_res <- Re(stats::fft(c(vec, rev(vec))) / p)[1:n]

  if (ortho) {
    return(
      c(
        sqrt(1 / (4 * n)) * unscaled_res[1],
        sqrt(1 / (2 * n)) * tail(unscaled_res, n - 1)
      )
    )
  } else {
    return(unscaled_res)
  }
}

test_that(
  "gsignal's dct2 is producing the same result as the Scipy algorithm",
  code = {
    test_vector <- array(c(19, 3, 6, 11))
    transforms <- dctii_m_transforms(length(test_vector))
    m <- transforms$m
    expect_equal(m(test_vector), matrix(dctii_scipy_equivalent(test_vector)))
  }
)

test_that(
  "facewise product works the same as the naive algorithm",
  code = {
    n <- 2
    p <- 4
    t <- 3
    set.seed(1)
    test_tensor1 <- array(rnorm(n * p * t), dim = c(n, p, t))
    test_tensor2 <- ft(test_tensor1)
    expected_result <- array(0, dim = c(n, n, t))
    for (i in 1:t) {
      expected_result[, , i] <- test_tensor1[, , i] %*% test_tensor2[, , i]
    }
    expect_equal(
      test_tensor1 %fp% test_tensor2,
      expected_result
    )
  }
)

test_that(
  "mode-3 product result matches naive nested for-loop algorithm",
  code = {
    n <- 2
    p <- 4
    t <- 3
    test_tensor1 <- array(1:(n * p * t), dim = c(2, 4, 3))
    m_mat <- gsignal::dctmtx(t)
    expected_result <- array(0, dim = c(2, 4, 3))
    for (nn in 1:n) {
      for (pp in 1:p) {
        expected_result[nn, pp, ] <- m_mat %*% test_tensor1[nn, pp, ]
      }
    }
    transforms <- dctii_m_transforms(t)
    m <- transforms$m
    expect_equal(m(test_tensor1), expected_result)
  }
)

test_that(
  "different mode-3 product algorithms produce equivalent results",
  code = {
    test_tensor1 <- array(1:24, dim = c(2, 4, 3))
    t <- dim(test_tensor1)[3]
    transforms_default <- dctii_m_transforms(t, bpparam = NULL)
    transforms_parallel <- dctii_m_transforms(
      t, bpparam = BiocParallel::MulticoreParam()
    )
    expect_equal(
      transforms_default$m(test_tensor1),
      # suppress warning "MulticoreParam() not supported on Windows, use
      # SnowParam()" when running tests on Windows
      suppressWarnings(
        transforms_parallel$m(test_tensor1)
      )
    )
  }
)

test_that(
  "forward and inverse dctii transforms invert each other",
  code = {
    test_tensor1 <- array(1:24, dim = c(2, 4, 3))
    transforms <- dctii_m_transforms(dim(test_tensor1)[3])
    m <- transforms$m
    minv <- transforms$minv
    expect_equal(test_tensor1, minv(m(test_tensor1)))
    expect_equal(test_tensor1, m(minv(test_tensor1)))
  }
)

test_that(
  # note this test does tend to throw warning messages on Windows
  "different binary facewise algorithms produce equivalent results",
  code = {
    test_tensor1 <- array(1:24, dim = c(2, 4, 3))
    test_tensor2 <- array(1:36, dim = c(4, 3, 3))
    expect_equal(
      facewise_product(test_tensor1, test_tensor2, bpparam = NULL),
      # suppress warning "MulticoreParam() not supported on Windows, use
      # SnowParam()" when running tests on Windows
      suppressWarnings(
        facewise_product(
          test_tensor1, test_tensor2,
          bpparam = BiocParallel::MulticoreParam()
        )
      )
    )
  }
)

test_that(
  "cumulative multi input facewise product works as expected compared to
  custom operator",
  code = {
    test_tensor1 <- array(1:24, dim = c(2, 4, 3))
    test_tensor2 <- array(1:60, dim = c(4, 5, 3))
    test_tensor3 <- array(1:90, dim = c(5, 6, 3))
    fp12 <- facewise_product(test_tensor1, test_tensor2)
    expected_cumulative_fp <- facewise_product(fp12, test_tensor3)
    expect_equal(
      facewise_product(test_tensor1, test_tensor2, test_tensor3),
      expected_cumulative_fp
    )
    expect_equal(
      test_tensor1 %fp% test_tensor2 %fp% test_tensor3,
      expected_cumulative_fp
    )
  }
)

test_that(
  "cumulative multi input m product works as expected",
  code = {
    test_tensor1 <- array(1:24, dim = c(2, 4, 3))
    test_tensor2 <- array(1:60, dim = c(4, 5, 3))
    test_tensor3 <- array(1:90, dim = c(5, 6, 3))
    mp12 <- m_product(test_tensor1, test_tensor2)
    expected_cumulative_mp <- m_product(mp12, test_tensor3)
    expect_equal(
      m_product(test_tensor1, test_tensor2, test_tensor3),
      expected_cumulative_mp
    )
  }
)

test_that(
  "m_product() throws appropriate errors",
  code = {
    test_tensor1 <- array(1:24, dim = c(2, 4, 3))
    dummy_m <- function() 0
    # only defining m without minv
    expect_error(
      m_product(test_tensor1, m = dummy_m),
      "If explicitly defined, both m and its inverse must be defined as
      functions"
    )
    # accidentally adding () to an input meaning it is not a callable
    expect_error(
      m_product(test_tensor1, m = dummy_m()),
      "If explicitly defined, both m and its inverse must be defined as
      functions"
    )
    expect_error(
      m_product(test_tensor1, m = dummy_m(), minv = dummy_m),
      "If explicitly defined, both m and its inverse must be defined as
      functions"
    )
  }
)

test_that(
  "facewise_crossproduct works as intended",
  code = {
    n <- 2
    p <- 4
    t <- 3
    set.seed(1)
    test_tensor1 <- array(rnorm(n * p * t), dim = c(n, p, t))

    expect_equal(
      facewise_crossproduct(test_tensor1, test_tensor1),
      ft(test_tensor1) %fp% test_tensor1
    )
  }
)

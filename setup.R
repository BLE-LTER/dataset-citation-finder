# ================================================================
# setup.R
# ONE-TIME PACKAGE INSTALLATION
# ================================================================
#
# Run this file once after cloning the repository. It installs any
# required R packages that are not already installed on your computer.
# This script modifies your local R package library
# ================================================================

required_packages <- c(
  "EDIutils",
  "httr",
  "jsonlite",
  "dplyr",
  "purrr",
  "stringr",
  "tibble",
  "tidyr",
  "openxlsx",
  "pdftools"
)

installed <- rownames(installed.packages())
missing <- setdiff(required_packages, installed)

if (length(missing)) {
  message("Installing missing packages: ", paste(missing, collapse = ", "))
  install.packages(missing)
} else {
  message("All required packages are already installed.")
}

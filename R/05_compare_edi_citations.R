# ================================================================
# 05_compare_edi_citations.R
# COMPARE CITATION FINDER RESULTS WITH EDI JOURNAL CITATIONS
# ================================================================
#
# PURPOSE:
# Retrieve journal citations recorded for each EDI dataset series and
# compare them with paper-dataset relationships produced by the Citation
# Finder. This report supports manual review; it does not add citations
# to EDI automatically.
#
# INPUTS:
# Citation_finder_output/Data_Registry.xlsx
# Citation_finder_output/Publication_Search_Results.xlsx
# EDI settings from config.R and EDI_API_KEY from .Renviron.
#
# EDI API KEY:
# EDI_API_KEY authenticates EDIutils requests used to retrieve journal
# citations from EDI. Store the key in .Renviron, not in this script.
#
# OUTPUT:
# Citation_finder_output/EDI_Journal_Citation_Comparison.xlsx
#   Sheet: EDI_Citation_Comparison
#
# OUTPUT COLUMNS:
# Dataset_Package_ID, Dataset_DOI, Dataset_Title, Paper_DOI, Paper_Title,
# Year, EDI_Citation_ID, EDI_Status.
#
# EDI_Status VALUES:
# Already in EDI                - exact dataset-series + paper DOI pair is
#                                 in both Citation Finder and EDI.
# Missing from EDI              - Citation Finder found the relationship,
#                                 but EDI does not contain that exact pair.
# In EDI - Not in Citation Finder - EDI contains a citation that Citation
#                                   Finder did not match; this includes EDI
#                                   citations with no paper DOI.
#
# FILE BEHAVIOR:
# The output directory is defined in config.R. If it does not exist,
# this script announces and creates it. An existing workbook with the
# same name is overwritten. A completion message prints the saved path.
# ================================================================


# ================================================================
# LOAD PROJECT CONFIGURATION AND SHARED HELPERS
# ================================================================

project_root <- if (file.exists("config.R")) {
  "."
} else if (file.exists("../config.R")) {
  ".."
} else {
  stop(
    "Could not find config.R. Run the workflow from the repository root or R folder.",
    call. = FALSE
  )
}

project_root <- normalizePath(project_root, winslash = "/", mustWork = TRUE)

# Load the project .Renviron before config.R so API keys are available
# whether the script is run from the project root or from R/.
renviron_file <- file.path(project_root, ".Renviron")

if (file.exists(renviron_file)) {
  readRenviron(renviron_file)
} else {
  warning(
    paste0("Could not find project .Renviron at: ", renviron_file),
    call. = FALSE
  )
}
source(file.path(project_root, "config.R"))
source(file.path(project_root, "R", "utils.R"))
load_citation_finder_packages()
ensure_output_dir()

if (is.null(edi_scope) || !nzchar(trimws(edi_scope))) {
  stop("edi_scope is required for this script. Set it in config.R.", call. = FALSE)
}

if (is.null(edi_key) || !nzchar(trimws(edi_key))) {
  stop(
    paste0(
      "EDI_API_KEY could not be found. Add it to .Renviron and restart R.\n",
      "See README.md for setup instructions."
    ),
    call. = FALSE
  )
}

cat("EDI API key loaded successfully.\n")


# ================================================================
# LOCAL HELPERS
# safe() and clean_doi() are shared in R/utils.R.
# ================================================================

# ------------------------------------------------
# EXTRACT DOI FROM TEXT
# ------------------------------------------------

extract_doi <- function(x) {
  
  if (
    is.null(x) ||
    length(x) == 0 ||
    is.na(x) ||
    x == ""
  ) {
    return(NA_character_)
  }
  
  doi <- stringr::str_extract(
    x,
    stringr::regex(
      "10\\.[0-9]{4,9}/[-._;()/:A-Z0-9]+",
      ignore_case = TRUE
    )
  )
  
  clean_doi(
    doi
  )
}


# ------------------------------------------------
# CREATE DATASET SERIES ID
#
# Example:
# knb-lter-ble.3.25
# becomes
# knb-lter-ble.3
# ------------------------------------------------

get_series_id <- function(package_id) {
  
  if (
    is.null(package_id) ||
    is.na(package_id)
  ) {
    return(NA_character_)
  }
  
  parts <- strsplit(
    package_id,
    "\\."
  )[[1]]
  
  if (length(parts) < 3) {
    return(package_id)
  }
  
  paste(
    parts[1:(length(parts) - 1)],
    collapse = "."
  )
}


# ================================================================
# 4. CHECK INPUT FILES
# ================================================================

if (!file.exists(data_registry_file)) {
  stop(
    paste(
      "Could not find:",
      data_registry_file
    )
  )
}


if (!file.exists(publication_results_file)) {
  stop(
    paste(
      "Could not find:",
      publication_results_file
    )
  )
}


# ================================================================
# 5. READ DATA REGISTRY
# ================================================================

cat(
  "\n========================================\n",
  "READING DATA REGISTRY\n",
  "========================================\n"
)


data_registry <- openxlsx::read.xlsx(
  data_registry_file,
  sheet = "Data_Registry"
)


# Keep only datasets archived in EDI
edi_registry <- data_registry %>%
  dplyr::filter(
    Scope == edi_scope
  ) %>%
  dplyr::mutate(
    
    Dataset_DOI =
      clean_doi(
        Dataset_DOI
      ),
    
    Dataset_Series_ID =
      paste0(
        Scope,
        ".",
        Identifier
      )
    
  ) %>%
  dplyr::select(
    Dataset_Series_ID,
    Package_ID,
    Dataset_DOI,
    Dataset_Title
  )


cat(
  "EDI registry rows:",
  nrow(edi_registry),
  "\n"
)


# ================================================================
# 6. CREATE ONE ROW PER DATASET SERIES
#
# Keep one real revision-level package ID for each series.
# EDI requires a revisioned package ID such as knb-lter-ble.3.1.
# With list_all = TRUE, citations are retrieved across the series.
# ================================================================

edi_series <- edi_registry %>%
  dplyr::group_by(
    Dataset_Series_ID
  ) %>%
  dplyr::summarise(
    
    Query_Package_ID =
      dplyr::first(
        Package_ID[
          !is.na(Package_ID) &
            Package_ID != ""
        ]
      ),
    
    Dataset_Title =
      dplyr::first(
        Dataset_Title
      ),
    
    .groups = "drop"
  )

cat(
  "Unique EDI dataset series:",
  nrow(edi_series),
  "
"
)

cat(
  "
Package IDs that will be sent to EDI:
"
)

print(
  edi_series %>%
    dplyr::select(
      Dataset_Series_ID,
      Query_Package_ID
    )
)


# ================================================================
# 7. LOGIN TO EDI
# ================================================================

cat(
  "\n========================================\n",
  "LOGGING INTO EDI\n",
  "========================================\n"
)


EDIutils::login(
  key = edi_key
)


cat(
  "EDI login complete.\n"
)


# ================================================================
# 8. GET JOURNAL CITATIONS FROM EDI
#
# EDIutils::list_data_package_citations() already returns the fields
# we need:
#   journalCitationId
#   packageId
#   articleDoi
#   articleTitle
#   articleUrl
#
# We therefore use those columns directly.
# ================================================================

cat(
  "
========================================
",
  "GETTING EDI JOURNAL CITATIONS
",
  "========================================
"
)


edi_citations_raw <- purrr::map_dfr(
  
  seq_len(
    nrow(
      edi_series
    )
  ),
  
  function(i) {
    
    dataset_series_id <-
      edi_series$Dataset_Series_ID[i]
    
    query_package_id <-
      edi_series$Query_Package_ID[i]
    
    dataset_title <-
      edi_series$Dataset_Title[i]
    
    
    cat(
      "[",
      i,
      "/",
      nrow(edi_series),
      "] ",
      query_package_id,
      "
",
sep = ""
    )
    
    
    citations <- tryCatch(
      
      EDIutils::list_data_package_citations(
        packageId = query_package_id,
        as = "data.frame",
        list_all = TRUE,
        env = "production"
      ),
      
      error = function(e) {
        
        message(
          "Could not retrieve citations for ",
          query_package_id,
          ": ",
          conditionMessage(e)
        )
        
        NULL
      }
    )
    
    
    if (
      is.null(citations) ||
      nrow(citations) == 0
    ) {
      
      return(
        tibble::tibble(
          Dataset_Series_ID = character(),
          EDI_Package_ID = character(),
          Dataset_Title = character(),
          EDI_Citation_ID = character(),
          Paper_DOI = character(),
          EDI_Paper_Title = character(),
          EDI_Article_URL = character()
        )
      )
    }
    
    
    required_cols <- c(
      "journalCitationId",
      "packageId",
      "articleDoi",
      "articleTitle",
      "articleUrl"
    )
    
    
    missing_cols <- setdiff(
      required_cols,
      names(citations)
    )
    
    
    if (length(missing_cols) > 0) {
      
      stop(
        paste0(
          "EDI citation response is missing expected column(s): ",
          paste(
            missing_cols,
            collapse = ", "
          ),
          "
Returned columns were: ",
          paste(
            names(citations),
            collapse = ", "
          )
        )
      )
    }
    
    
    citations %>%
      dplyr::transmute(
        
        Dataset_Series_ID =
          dataset_series_id,
        
        EDI_Package_ID =
          as.character(
            packageId
          ),
        
        Dataset_Title =
          dataset_title,
        
        EDI_Citation_ID =
          as.character(
            journalCitationId
          ),
        
        Paper_DOI =
          clean_doi(
            articleDoi
          ),
        
        EDI_Paper_Title =
          dplyr::na_if(
            trimws(
              as.character(
                articleTitle
              )
            ),
            ""
          ),
        
        EDI_Article_URL =
          dplyr::na_if(
            trimws(
              as.character(
                articleUrl
              )
            ),
            ""
          )
      )
  }
)


cat(
  "
EDI citation records retrieved:",
  nrow(edi_citations_raw),
  "
"
)


cat(
  "EDI citation records with a DOI:",
  sum(
    !is.na(
      edi_citations_raw$Paper_DOI
    )
  ),
  "
"
)


cat(
  "EDI citation records without a DOI:",
  sum(
    is.na(
      edi_citations_raw$Paper_DOI
    )
  ),
  "
"
)


if (
  nrow(edi_citations_raw) > 0
) {
  
  cat(
    "
Example EDI citations retrieved:
"
  )
  
  print(
    edi_citations_raw %>%
      dplyr::select(
        Dataset_Series_ID,
        EDI_Package_ID,
        EDI_Citation_ID,
        Paper_DOI,
        EDI_Paper_Title
      ) %>%
      utils::head(
        15
      )
  )
}


# ================================================================
# 9. LOGOUT OF EDI
# ================================================================

try(
  EDIutils::logout(),
  silent = TRUE
)


# Keep ALL EDI citation records, including records without a DOI.
# Records without a DOI cannot be matched automatically to
# Publication Search, but they should still appear in the final
# workbook as citations that are already recorded in EDI.

edi_citations <- edi_citations_raw %>%
  dplyr::mutate(
    
    Paper_DOI =
      clean_doi(
        Paper_DOI
      )
    
  ) %>%
  dplyr::distinct(
    Dataset_Series_ID,
    EDI_Citation_ID,
    .keep_all = TRUE
  )


cat(
  "
EDI journal citation records:",
  nrow(edi_citations),
  "
"
)


# ================================================================
# 10. READ PUBLICATION SEARCH RESULTS
# ================================================================

cat(
  "
========================================
",
  "READING PUBLICATION SEARCH RESULTS
",
  "========================================
"
)

zip_check <- tryCatch(
  utils::unzip(
    publication_results_file,
    list = TRUE
  ),
  error = function(e) NULL
)

if (is.null(zip_check)) {
  stop(
    paste0(
      "Publication_Search_Results.xlsx could not be opened as a valid .xlsx file:
",
      publication_results_file,
      "

Close Excel, allow any file synchronization to finish, and try again."
    )
  )
}

available_sheets <- openxlsx::getSheetNames(
  publication_results_file
)

cat(
  "Available sheets:",
  paste(
    available_sheets,
    collapse = ", "
  ),
  "
"
)

if (
  "Final_Relationships" %in%
  available_sheets
) {
  
  publication_search <- openxlsx::read.xlsx(
    publication_results_file,
    sheet = "Final_Relationships"
  )
  
} else if (
  "Publication_Search" %in%
  available_sheets
) {
  
  publication_search <- openxlsx::read.xlsx(
    publication_results_file,
    sheet = "Publication_Search"
  )
  
} else {
  
  stop(
    paste(
      "Could not find Final_Relationships or Publication_Search.",
      "Available sheets:",
      paste(
        available_sheets,
        collapse = ", "
      )
    )
  )
}

cat(
  "Publication search relationships:",
  nrow(publication_search),
  "
"
)


# ================================================================
# 11. STANDARDIZE PUBLICATION SEARCH
# ================================================================

publication_search <- publication_search %>%
  dplyr::mutate(
    
    Paper_DOI =
      clean_doi(
        Paper_DOI
      ),
    
    Dataset_DOI =
      clean_doi(
        Dataset_DOI
      )
  )


# Attach the dataset series ID using the registry DOI
publication_search <- publication_search %>%
  dplyr::left_join(
    
    edi_registry %>%
      dplyr::select(
        Dataset_DOI,
        Dataset_Series_ID
      ) %>%
      dplyr::distinct(),
    
    by = "Dataset_DOI"
  )


# Only relationships belonging to EDI datasets
publication_search <- publication_search %>%
  dplyr::filter(
    !is.na(Dataset_Series_ID),
    !is.na(Paper_DOI)
  )


# ================================================================
# 12. STANDARDIZE OPTIONAL COLUMNS
# ================================================================

if (
  !"Dataset_Title" %in%
  names(publication_search)
) {
  
  publication_search <- publication_search %>%
    dplyr::left_join(
      
      edi_series %>%
        dplyr::select(
          Dataset_Series_ID,
          Dataset_Title
        ),
      
      by = "Dataset_Series_ID"
    )
}


if (
  !"Paper_Title" %in%
  names(publication_search)
) {
  
  publication_search$Paper_Title <-
    NA_character_
}


if (
  !"Year" %in%
  names(publication_search)
) {
  
  publication_search$Year <-
    NA_integer_
}





# ================================================================
# 13. ONE ROW PER PAPER-DATASET RELATIONSHIP
# ================================================================

publication_relationships <- publication_search %>%
  dplyr::select(
    Dataset_Series_ID,
    Dataset_DOI,
    Dataset_Title,
    Paper_DOI,
    Paper_Title,
    Year
  ) %>%
  dplyr::distinct()


# ================================================================
# 14. COMPARE WITH EDI
#
# IMPORTANT:
# Match on BOTH:
#
# Dataset_Series_ID + Paper_DOI
#
# A publication recorded for one dataset should not
# automatically count as present for another dataset.
# ================================================================

edi_doi_relationships <- edi_citations %>%
  dplyr::filter(
    !is.na(Paper_DOI)
  ) %>%
  dplyr::group_by(
    Dataset_Series_ID,
    Paper_DOI
  ) %>%
  dplyr::summarise(
    
    EDI_Citation_ID =
      paste(
        sort(
          unique(
            EDI_Citation_ID[
              !is.na(EDI_Citation_ID) &
                EDI_Citation_ID != ""
            ]
          )
        ),
        collapse = "; "
      ),
    
    .groups = "drop"
  ) %>%
  dplyr::mutate(
    EDI_Citation_ID =
      dplyr::na_if(
        EDI_Citation_ID,
        ""
      )
  )


comparison <- publication_relationships %>%
  dplyr::left_join(
    
    edi_doi_relationships,
    
    by = c(
      "Dataset_Series_ID",
      "Paper_DOI"
    )
  ) %>%
  dplyr::mutate(
    
    EDI_Status =
      dplyr::if_else(
        !is.na(EDI_Citation_ID),
        "Already in EDI",
        "Missing from EDI"
      )
  )


# ================================================================
# 15. ALSO INCLUDE EDI CITATIONS THAT WERE NOT FOUND BY
#     PUBLICATION SEARCH
#
# This includes:
# - EDI citations with a DOI that Citation Finder did not find
# - EDI citations that do not have a DOI
# ================================================================

edi_only <- edi_citations %>%
  dplyr::filter(
    
    is.na(Paper_DOI) |
      
      !paste(
        Dataset_Series_ID,
        Paper_DOI,
        sep = "||"
      ) %in%
      
      paste(
        publication_relationships$Dataset_Series_ID,
        publication_relationships$Paper_DOI,
        sep = "||"
      )
    
  ) %>%
  dplyr::left_join(
    
    edi_registry %>%
      dplyr::select(
        Package_ID,
        Dataset_DOI
      ) %>%
      dplyr::distinct(),
    
    by = c(
      "EDI_Package_ID" = "Package_ID"
    )
  ) %>%
  dplyr::transmute(
    
    Dataset_Series_ID,
    
    Dataset_DOI,
    
    Dataset_Title,
    
    Paper_DOI,
    
    Paper_Title =
      EDI_Paper_Title,
    
    Year =
      NA_integer_,
    
    EDI_Citation_ID,
    
    EDI_Status =
      "In EDI - Not in Citation Finder"
  )


# ================================================================
# 16. FINAL ONE-SHEET TABLE
# ================================================================

final_comparison <- dplyr::bind_rows(
  comparison,
  edi_only
) %>%
  dplyr::mutate(
    .relationship_key = dplyr::if_else(
      is.na(Paper_DOI),
      paste0(Dataset_Series_ID, "||EDI||", EDI_Citation_ID),
      paste0(Dataset_Series_ID, "||DOI||", Paper_DOI)
    )
  ) %>%
  dplyr::distinct(
    .relationship_key,
    .keep_all = TRUE
  ) %>%
  dplyr::select(
    -.relationship_key,
    
    Dataset_Package_ID =
      Dataset_Series_ID,
    
    Dataset_DOI,
    
    Dataset_Title,
    
    Paper_DOI,
    
    Paper_Title,
    
    Year,
    
    EDI_Citation_ID,
    
    EDI_Status
    
  ) %>%
  dplyr::arrange(
    EDI_Status,
    Dataset_Package_ID,
    Paper_Title
  )
# ================================================================
# 17. SUMMARY
# ================================================================

cat(
  "\n========================================\n",
  "EDI JOURNAL CITATION COMPARISON\n",
  "========================================\n"
)


cat(
  "Total paper-dataset relationships:",
  nrow(final_comparison),
  "\n"
)


cat(
  "Already in EDI:",
  sum(
    final_comparison$EDI_Status ==
      "Already in EDI",
    na.rm = TRUE
  ),
  "\n"
)


cat(
  "Missing from EDI:",
  sum(
    final_comparison$EDI_Status ==
      "Missing from EDI",
    na.rm = TRUE
  ),
  "\n"
)


cat(
  "In EDI - Not in Citation Finder:",
  sum(
    final_comparison$EDI_Status ==
      "In EDI - Not in Citation Finder",
    na.rm = TRUE
  ),
  "\n"
)


# ================================================================
# 18. CREATE EXCEL WORKBOOK
# ================================================================

wb <- openxlsx::createWorkbook()


openxlsx::addWorksheet(
  wb,
  "EDI_Citation_Comparison"
)


openxlsx::writeData(
  wb,
  "EDI_Citation_Comparison",
  final_comparison
)


# ================================================================
# 19. FORMAT EXCEL
# ================================================================

header_style <- openxlsx::createStyle(
  textDecoration = "bold",
  border = "Bottom"
)


openxlsx::addStyle(
  
  wb,
  
  sheet =
    "EDI_Citation_Comparison",
  
  style =
    header_style,
  
  rows =
    1,
  
  cols =
    seq_len(
      ncol(
        final_comparison
      )
    ),
  
  gridExpand =
    TRUE
)


openxlsx::freezePane(
  
  wb,
  
  sheet =
    "EDI_Citation_Comparison",
  
  firstRow =
    TRUE
)


openxlsx::setColWidths(
  
  wb,
  
  sheet =
    "EDI_Citation_Comparison",
  
  cols =
    seq_len(
      ncol(
        final_comparison
      )
    ),
  
  widths =
    "auto"
)


openxlsx::addFilter(wb,sheet = "EDI_Citation_Comparison",
                    rows = 1,
                    cols = seq_len(ncol(final_comparison))
)


# ================================================================
# 20. SAVE
# ================================================================

openxlsx::saveWorkbook(wb,edi_journal_citation_file,overwrite =TRUE)


cat(
  "\n========================================\n",
  "EXPORT COMPLETE\n",
  "========================================\n",
  "Saved as:\n",
  normalizePath(
    edi_journal_citation_file,
    winslash = "/",
    mustWork = FALSE
  ),
  "\n",
  "========================================\n"
)
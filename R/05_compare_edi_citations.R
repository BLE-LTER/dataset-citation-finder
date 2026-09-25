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
# Read from the directory set by output_dir in config.R:
#   Data_Registry.xlsx, created by R/01_get_dataset_dois.R.
#   Publication_Search_Results.xlsx, created by
#     R/02_find_dataset_citations.R. Its EDI_Citations sheet holds the
#     journal citations recorded in EDI; this script reads that sheet
#     instead of querying EDI itself. Rerun R/02_find_dataset_citations.R
#     to refresh EDI journal citation data.
# EDI settings from config.R (edi_scope). No EDI API key is needed here;
# EDI_API_KEY is only used by R/02_find_dataset_citations.R.
#
# OUTPUT:
# EDI_Journal_Citation_Comparison.xlsx, written to the directory set by
# output_dir in config.R (by default Citation_finder_output in the
# repository root).
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
source(file.path(project_root, "config.R"))
source(file.path(project_root, "R", "utils.R"))
load_citation_finder_packages()
ensure_output_dir()

# This report is EDI-specific: it compares Citation Finder results with
# journal citations recorded in EDI. A site that does not archive its
# datasets in EDI should skip this script. See README.md.

if (is.null(edi_scope) || !nzchar(trimws(edi_scope))) {
  stop(
    paste0(
      "edi_scope is required for this script. Set it in config.R, or skip ",
      "this script if your site does not archive datasets in EDI."
    ),
    call. = FALSE
  )
}

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
# 1. CHECK INPUT FILES AND STAGE LOCAL COPIES
# ================================================================

# prepare_xlsx_for_read() (R/utils.R) checks that each workbook exists and
# is readable, names the script to rerun if it is not, and returns a local
# temporary copy so a cloud-synced or locked original cannot fail the read.

data_registry_local <- prepare_xlsx_for_read(
  data_registry_file,
  created_by = "R/01_get_dataset_dois.R"
)

publication_results_local <- prepare_xlsx_for_read(
  publication_results_file,
  created_by = "R/02_find_dataset_citations.R"
)


# ================================================================
# 2. READ DATA REGISTRY
# ================================================================

cat(
  "\n========================================\n",
  "READING DATA REGISTRY\n",
  "========================================\n"
)


data_registry <- openxlsx::read.xlsx(
  data_registry_local,
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
# 3. CREATE ONE ROW PER DATASET SERIES
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
# 4. READ EDI JOURNAL CITATIONS FROM PUBLICATION SEARCH RESULTS
# ================================================================
#
# R/02_find_dataset_citations.R already queries EDI once and saves
# every dataset series' journal citations in the EDI_Citations sheet
# of Publication_Search_Results.xlsx. Reading that sheet here, instead
# of logging in to EDI and querying it again, avoids repeating the
# same request a second time.
#
# Rerun R/02_find_dataset_citations.R first if EDI journal citation
# data needs to be refreshed; this script no longer queries EDI
# itself.
# ================================================================

cat(
  "\n========================================\n",
  "READING EDI JOURNAL CITATIONS\n",
  "========================================\n"
)


publication_results_sheets <- openxlsx::getSheetNames(
  publication_results_local
)


if (!"EDI_Citations" %in% publication_results_sheets) {
  stop(
    paste0(
      'Publication_Search_Results.xlsx does not contain an "EDI_Citations" ',
      "sheet. Rerun R/02_find_dataset_citations.R first; it retrieves EDI ",
      "journal citations and saves them to that sheet.\nAvailable sheets: ",
      paste(
        publication_results_sheets,
        collapse = ", "
      )
    ),
    call. = FALSE
  )
}


edi_citations_raw <- openxlsx::read.xlsx(
  publication_results_local,
  sheet = "EDI_Citations"
)


cat(
  "EDI citation records read from Publication_Search_Results.xlsx: ",
  nrow(edi_citations_raw),
  "\n",
  sep = ""
)


cat(
  "EDI citation records with a DOI:",
  sum(
    !is.na(
      edi_citations_raw$Paper_DOI
    )
  ),
  "\n"
)


cat(
  "EDI citation records without a DOI:",
  sum(
    is.na(
      edi_citations_raw$Paper_DOI
    )
  ),
  "\n"
)


if (
  nrow(edi_citations_raw) > 0
) {
  
  cat(
    "\nExample EDI citations read:\n"
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
  "\nEDI journal citation records:",
  nrow(edi_citations),
  "\n"
)

# ================================================================
# 5. READ PUBLICATION SEARCH RESULTS
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

available_sheets <- openxlsx::getSheetNames(
  publication_results_local
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
    publication_results_local,
    sheet = "Final_Relationships"
  )
  
} else if (
  "Publication_Search" %in%
  available_sheets
) {
  
  publication_search <- openxlsx::read.xlsx(
    publication_results_local,
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
# 6. STANDARDIZE PUBLICATION SEARCH
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
# 7. STANDARDIZE OPTIONAL COLUMNS
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
# 8. ONE ROW PER PAPER-DATASET RELATIONSHIP
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
# 9. COMPARE WITH EDI
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
# 10. ALSO INCLUDE EDI CITATIONS THAT WERE NOT FOUND BY
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
        Dataset_Series_ID,
        Registry_Dataset_DOI = Dataset_DOI
      ) %>%
      dplyr::group_by(
        Dataset_Series_ID
      ) %>%
      dplyr::summarise(
        
        Registry_Dataset_DOI =
          dplyr::first(
            Registry_Dataset_DOI[
              !is.na(Registry_Dataset_DOI) &
                Registry_Dataset_DOI != ""
            ]
          ),
        
        .groups = "drop"
      ),
    
    by = "Dataset_Series_ID"
  ) %>%
  dplyr::mutate(
    
    Dataset_DOI =
      dplyr::coalesce(
        Dataset_DOI,
        Registry_Dataset_DOI
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
# 11. FINAL ONE-SHEET TABLE
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
# 12. SUMMARY
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
# 13. CREATE EXCEL WORKBOOK
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
# 14. FORMAT EXCEL
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
# 15. SAVE
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
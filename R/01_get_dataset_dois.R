# ================================================================
# 01_get_dataset_dois.R
# BUILD THE DATASET REGISTRY
# ================================================================
#
# PURPOSE:
# A dataset registry is the master list of dataset DOIs.
#
# DATASET SOURCES:
# 1. EDI: all revisions with DOIs in the configured EDI scope.
# 2. Zotero: datasets archived outside EDI that are represented in the
#    configured public/readable Zotero group and carry external_tag.
#    The default BLE configuration uses this Zotero convention; other sites may leave the
#    Zotero settings blank and use EDI only.
#
# CONFIGURATION:
# Edit config.R. EDI harvesting requires both edi_scope and EDI_API_KEY.
# EDI is required for this script. Zotero is optional and requires
# zotero_group_id and external_tag.
#
# OUTPUT:
# Citation_finder_output/Data_Registry.xlsx
#   Sheet: Data_Registry
#
# OUTPUT COLUMNS:
# Scope, Identifier, Revision, Dataset_Title, Package_ID, Dataset_DOI,
# Registry_Source, Registry_Category, Zotero_Item_Key, Final_URL.
#
# FILE BEHAVIOR:
# The output directory is defined in config.R. If it does not exist,
# this script announces and creates it. An existing Data_Registry.xlsx
# is overwritten. A completion message prints the saved path and counts.
#
# NEXT STEP:
# Run R/02_find_dataset_citations.R after this script completes.
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


# ================================================================
# 1. CHECK EDI CONFIGURATION AND OPTIONAL ZOTERO SOURCE
# ================================================================

if (is.null(edi_scope) || length(edi_scope) != 1 || !nzchar(trimws(edi_scope))) {
  stop("edi_scope is required for this script. Set it in config.R.", call. = FALSE)
}

if (is.null(edi_key) || length(edi_key) != 1 || !nzchar(trimws(edi_key))) {
  stop(
    paste0(
      "EDI_API_KEY could not be found. Add it to .Renviron and restart R.\n",
      "See README.md for setup instructions."
    ),
    call. = FALSE
  )
}

cat("EDI API key loaded successfully.\n")

has_zotero_group <- !is.null(zotero_group_id) &&
  length(zotero_group_id) == 1 &&
  nzchar(trimws(zotero_group_id))

has_external_tag <- !is.null(external_tag) &&
  length(external_tag) == 1 &&
  nzchar(trimws(external_tag))

has_zotero <- has_zotero_group && has_external_tag

if (!has_zotero) {
  warning(
    paste0(
      "Zotero external-dataset harvesting will be skipped. Provide both ",
      "zotero_group_id and external_tag in config.R to include it."
    ),
    call. = FALSE
  )
}

empty_registry <- function() {
  tibble::tibble(
    Scope = character(),
    Identifier = character(),
    Revision = integer(),
    Dataset_Title = character(),
    Package_ID = character(),
    Dataset_DOI = character(),
    Registry_Source = character(),
    Registry_Category = character(),
    Zotero_Item_Key = character()
  )
}


# ================================================================
# 2. HARVEST EDI DATASET DOIS
# ================================================================

edi_registry <- empty_registry()

cat(
  "\n========================================\n",
  "GETTING EDI DATASET REGISTRY\n",
  "========================================\n"
)

EDIutils::login(key = edi_key)
edi_current <- EDIutils::search_data_packages(
  query = paste0(
    'q=*:*&fq=scope:"',
    edi_scope,
    '"&fl=packageid,title,doi,scope'
  ),
  as = "data.frame",
  env = "production"
)

edi_series <- edi_current %>%
  dplyr::mutate(
    packageid = as.character(packageid),
    scope = stringr::str_extract(packageid, "^[^.]+"),
    identifier = stringr::str_match(packageid, "^[^.]+\\.([0-9]+)\\.")[, 2]
  ) %>%
  dplyr::filter(!is.na(identifier)) %>%
  dplyr::distinct(scope, identifier, .keep_all = TRUE)

revisions <- purrr::pmap_dfr(
  list(edi_series$scope, edi_series$identifier, edi_series$title),
  function(scope, identifier, title) {
    revisions_found <- tryCatch(
      EDIutils::list_data_package_revisions(
        scope = scope,
        identifier = as.numeric(identifier),
        env = "production"
      ),
      error = function(e) NULL
    )
    
    if (is.null(revisions_found)) {
      return(tibble::tibble())
    }
    
    tibble::tibble(
      Scope = scope,
      Identifier = identifier,
      Revision = as.integer(revisions_found),
      Dataset_Title = title,
      Package_ID = paste(scope, identifier, revisions_found, sep = ".")
    )
  }
)

revisions$Dataset_DOI <- purrr::map_chr(
  revisions$Package_ID,
  ~ clean_doi(
    tryCatch(
      EDIutils::read_data_package_doi(
        .x,
        as_url = FALSE,
        env = "production"
      )[1],
      error = function(e) NA_character_
    )
  )
)

edi_registry <- revisions %>%
  dplyr::filter(!is.na(Dataset_DOI)) %>%
  dplyr::distinct(Dataset_DOI, .keep_all = TRUE) %>%
  dplyr::mutate(
    Registry_Source = "EDI",
    Registry_Category = "Dataset Registry",
    Zotero_Item_Key = NA_character_
  )

EDIutils::logout()


# ================================================================
# 3. HARVEST EXTERNALLY ARCHIVED DATASETS FROM ZOTERO
# ================================================================
#
# The default BLE configuration uses a Zotero tag to mark datasets that are funded/used by the
# site but archived outside EDI. The Zotero group must be readable by
# the Zotero API for this unauthenticated request to work.
# ================================================================

zotero_registry <- empty_registry()

if (has_zotero) {
  cat(
    "\n========================================\n",
    "GETTING EXTERNALLY ARCHIVED DATASETS FROM ZOTERO\n",
    "========================================\n"
  )
  
  external_items <- paginate_json(
    paste0(
      "https://api.zotero.org/groups/",
      zotero_group_id,
      "/items/top"
    ),
    list(tag = external_tag),
    user_agent = "LTER-dataset-registry"
  )
  
  zotero_registry <- purrr::map_dfr(
    external_items,
    function(item) {
      d <- item$data
      direct <- clean_doi(safe(d$DOI))
      possible <- extract_dois(
        paste(
          safe(d$DOI, ""),
          safe(d$url, ""),
          safe(d$extra, "")
        )
      )
      
      doi <- if (!is.na(direct)) {
        direct
      } else if (length(possible)) {
        possible[1]
      } else {
        NA_character_
      }
      
      tibble::tibble(
        Scope = NA_character_,
        Identifier = NA_character_,
        Revision = NA_integer_,
        Dataset_Title = safe(d$title),
        Package_ID = NA_character_,
        Dataset_DOI = doi,
        Registry_Source = "Zotero",
        Registry_Category = external_tag,
        Zotero_Item_Key = safe(item$key)
      )
    }
  ) %>%
    dplyr::filter(!is.na(Dataset_DOI)) %>%
    dplyr::distinct(Dataset_DOI, .keep_all = TRUE)
}


# ================================================================
# 4. BUILD MASTER DATA REGISTRY
# ================================================================

data_registry <- dplyr::bind_rows(
  edi_registry,
  zotero_registry
) %>%
  
  dplyr::mutate(
    
    Dataset_DOI =
      clean_doi(
        Dataset_DOI
      ),
    
    Final_URL =
      ifelse(
        !is.na(Dataset_DOI) &
          Dataset_DOI != "",
        paste0(
          "https://doi.org/",
          Dataset_DOI
        ),
        NA_character_
      )
  ) %>%
  
  dplyr::distinct(
    Dataset_DOI,
    .keep_all = TRUE
  ) %>%
  
  dplyr::arrange(
    Scope,
    suppressWarnings(as.numeric(Identifier)),
    Revision,
    Dataset_Title
  ) %>%
  
  dplyr::select(
    Scope,
    Identifier,
    Revision,
    Dataset_Title,
    Package_ID,
    Dataset_DOI,
    Registry_Source,
    Registry_Category,
    Zotero_Item_Key,
    Final_URL
  )


# ================================================================
# 5. SAVE DATA REGISTRY
# ================================================================

openxlsx::write.xlsx(
  list(
    Data_Registry = data_registry
  ),
  file = data_registry_file,
  overwrite = TRUE
)


cat(
  "\n========================================\n",
  "DATASET REGISTRY COMPLETE\n",
  "========================================\n",
  "Saved: ", data_registry_file, "\n",
  "EDI dataset rows: ", nrow(edi_registry), "\n",
  "External dataset rows: ", nrow(zotero_registry), "\n",
  "Total registry rows: ", nrow(data_registry), "\n",
  "========================================\n"
)

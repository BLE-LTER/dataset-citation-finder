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
#    configured readable Zotero group and carry external_tag. The default
#    BLE configuration uses this Zotero convention; other sites may leave
#    the Zotero settings blank and build the registry from EDI only.
#
# This script only discovers DOIs from these two sources. Datasets
# archived anywhere else must be added to the registry by hand; see
# README.md for the column list to use.
#
# CONFIGURATION:
# Edit config.R. The two sources are independent of each other:
#   EDI    needs edi_scope (config.R) and EDI_API_KEY (.Renviron).
#   Zotero needs zotero_group_id and external_tag (config.R).
# At least one source must be configured. If one of them is incomplete,
# this script warns, skips that source, and builds the registry from the
# other one. If both are incomplete, it stops and lists what is needed.
#
# OUTPUT:
# Data_Registry.xlsx, written to the directory set by output_dir in
# config.R (by default Citation_finder_output in the repository root).
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
source(file.path(project_root, "config.R"))
source(file.path(project_root, "R", "utils.R"))
load_citation_finder_packages()
ensure_output_dir()


# ================================================================
# LOCAL HELPERS
# Functions shared across scripts are in R/utils.R.
# ================================================================

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

# Returns TRUE when a config.R setting is a single, non-empty value.
is_configured <- function(setting) {
  !is.null(setting) &&
    length(setting) == 1 &&
    !is.na(setting) &&
    nzchar(trimws(setting))
}


# ================================================================
# 1. DECIDE WHICH DATASET SOURCES CAN BE HARVESTED
# ================================================================
#
# EDI and Zotero are independent. Each source is used only when all of
# its settings are present. A missing source produces a warning and is
# skipped; if neither source is usable the script stops here.
# ================================================================

has_edi_scope <- is_configured(edi_scope)
has_edi_key <- is_configured(edi_key)
has_edi <- has_edi_scope && has_edi_key

has_zotero_group <- is_configured(zotero_group_id)
has_external_tag <- is_configured(external_tag)
has_zotero <- has_zotero_group && has_external_tag

# Explain exactly which EDI setting is missing, because the scope lives in
# config.R and the key lives in .Renviron.
if (!has_edi) {
  missing_edi <- c(
    if (!has_edi_scope) "edi_scope (set it in config.R)",
    if (!has_edi_key) "EDI_API_KEY (add it to .Renviron and restart R)"
  )

  cat(
    "\nEDI harvesting will be SKIPPED. Missing: ",
    paste(missing_edi, collapse = "; "),
    "\n",
    sep = ""
  )
}

if (!has_zotero) {
  missing_zotero <- c(
    if (!has_zotero_group) "zotero_group_id",
    if (!has_external_tag) "external_tag"
  )

  cat(
    "\nZotero harvesting of externally archived datasets will be SKIPPED. ",
    "Missing in config.R: ",
    paste(missing_zotero, collapse = ", "),
    "\n",
    sep = ""
  )
}

if (!has_edi && !has_zotero) {
  stop(
    paste0(
      "No dataset source is configured, so the registry cannot be built.\n",
      "Provide at least one of the following in config.R:\n",
      "  - edi_scope (for example \"knb-lter-ble\"), together with ",
      "EDI_API_KEY in .Renviron; and/or\n",
      "  - zotero_group_id and external_tag, to collect datasets that are ",
      "archived outside EDI.\n",
      "See README.md for setup instructions. Sites that archive datasets ",
      "elsewhere can also create Data_Registry.xlsx by hand and go ",
      "straight to R/02_find_dataset_citations.R."
    ),
    call. = FALSE
  )
}

if (!has_edi) {
  warning(
    "EDI settings are incomplete. Building the registry from Zotero only.",
    call. = FALSE
  )
}

if (!has_zotero) {
  warning(
    "Zotero settings are incomplete. Building the registry from EDI only.",
    call. = FALSE
  )
}


# ================================================================
# 2. HARVEST EDI DATASET DOIS
# ================================================================

edi_registry <- empty_registry()

if (has_edi) {
  cat(
    "\n========================================\n",
    "GETTING EDI DATASET REGISTRY\n",
    "========================================\n"
  )

  cat("EDI API key loaded successfully.\n")

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
}


# ================================================================
# 3. HARVEST EXTERNALLY ARCHIVED DATASETS FROM ZOTERO
# ================================================================
#
# The default BLE configuration uses a Zotero tag (external_tag) to mark
# datasets that the site funded or used but that are archived somewhere
# other than EDI. The request below is unauthenticated, so the Zotero
# group must be readable through the Zotero API for this to work.
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

if (nrow(data_registry) == 0) {
  warning(
    paste0(
      "The dataset registry is empty. The configured source(s) returned no ",
      "dataset DOIs. Check edi_scope, and the Zotero group and external_tag, ",
      "in config.R."
    ),
    call. = FALSE
  )
}

openxlsx::write.xlsx(
  list(
    Data_Registry = data_registry
  ),
  file = data_registry_file,
  overwrite = TRUE
)


# Report which sources were actually used, so the counts below are not
# mistaken for a complete picture of the site's datasets.
sources_used <- c(
  if (has_edi) "EDI" else "EDI (skipped - settings incomplete)",
  if (has_zotero) "Zotero" else "Zotero (skipped - settings incomplete)"
)

cat(
  "\n========================================\n",
  "DATASET REGISTRY COMPLETE\n",
  "========================================\n",
  "Saved: ", data_registry_file, "\n",
  "Sources: ", paste(sources_used, collapse = ", "), "\n",
  "EDI dataset rows: ", nrow(edi_registry), "\n",
  "External dataset rows: ", nrow(zotero_registry), "\n",
  "Total registry rows: ", nrow(data_registry), "\n",
  "Next step: R/02_find_dataset_citations.R\n",
  "========================================\n"
)

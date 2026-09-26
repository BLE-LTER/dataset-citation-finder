# ================================================================
# utils.R
# SHARED HELPERS FOR DATASET CITATION FINDER
# ================================================================
#
# This file contains functions used by more than one workflow script.
# It is sourced automatically by the numbered scripts; users normally
# do not run it directly.
#
# CONTENTS:
# load_citation_finder_packages() - check and attach required packages.
# ensure_output_dir()             - announce and create output_dir.
# prepare_xlsx_for_read()         - verify a workbook and read it from a
#                                   local temporary copy.
# safe(), clean_doi(), extract_dois() - small value helpers.
# get_json(), paginate_json()     - HTTP helpers with retry/backoff.
# oa_query()                     - OpenAlex requests.
# Citation helpers below normalize dataset identity, combine source
# evidence, and build catalog review tables without making API requests.
# ================================================================

citation_finder_packages <- c(
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

load_citation_finder_packages <- function() {
  installed <- rownames(installed.packages())
  missing <- setdiff(citation_finder_packages, installed)

  if (length(missing)) {
    stop(
      paste0(
        "Missing required R package(s): ",
        paste(missing, collapse = ", "),
        ".\nRun source(\"setup.R\") once from the repository root, ",
        "then restart this script."
      ),
      call. = FALSE
    )
  }

  invisible(
    lapply(
      citation_finder_packages,
      library,
      character.only = TRUE
    )
  )
}

ensure_output_dir <- function(path = output_dir) {
  if (!dir.exists(path)) {
    message("Creating output directory: ", normalizePath(path, winslash = "/", mustWork = FALSE))
    ok <- dir.create(path, recursive = TRUE, showWarnings = FALSE)
    if (!isTRUE(ok) && !dir.exists(path)) {
      stop("Could not create output directory: ", path, call. = FALSE)
    }
  }
  invisible(path)
}

# ------------------------------------------------
# SAFE EXCEL INPUT
# ------------------------------------------------
# Workbooks are read from the directory configured as output_dir in
# config.R. Files kept in cloud-synced or network folders can be locked
# or only partially downloaded when R tries to read them.
#
# This helper checks that the workbook is readable and copies it to a
# temporary local file before openxlsx opens it. Pass created_by to name
# the workflow script that recreates the file, so the error messages can
# tell the user what to rerun.

prepare_xlsx_for_read <- function(xlsx_file, created_by = NULL) {

  rerun_hint <- if (is.null(created_by)) {
    ""
  } else {
    paste0(" Rerun ", created_by, " to recreate it.")
  }

  if (!file.exists(xlsx_file)) {
    stop(
      paste0(
        "Could not find ",
        xlsx_file,
        ".",
        rerun_hint
      ),
      call. = FALSE
    )
  }

  file_size <- file.info(xlsx_file)$size

  if (is.na(file_size) || file_size <= 0) {
    stop(
      paste0(
        xlsx_file,
        " exists but is empty or unavailable. ",
        "If it is stored in a cloud-synced or network folder, make sure it ",
        "is available locally.",
        rerun_hint
      ),
      call. = FALSE
    )
  }

  valid_zip <- tryCatch(
    {
      utils::unzip(
        xlsx_file,
        list = TRUE
      )
      TRUE
    },
    warning = function(w) FALSE,
    error = function(e) FALSE
  )

  if (!valid_zip) {
    stop(
      paste0(
        xlsx_file,
        " is not currently a readable .xlsx workbook. ",
        "Close the file in Excel and allow any file synchronization to ",
        "finish, and delete the damaged copy if necessary.",
        rerun_hint
      ),
      call. = FALSE
    )
  }

  local_copy <- file.path(
    tempdir(),
    basename(xlsx_file)
  )

  copied <- file.copy(
    from = xlsx_file,
    to = local_copy,
    overwrite = TRUE
  )

  if (!isTRUE(copied)) {
    stop(
      paste0(
        "R could not make a local copy of ",
        xlsx_file,
        ". If the file is in a cloud-synced or network folder, make sure ",
        "the file is available locally, then try again."
      ),
      call. = FALSE
    )
  }

  local_copy
}

safe <- function(x, default = NA_character_) {
  if (is.null(x) || !length(x) || all(is.na(x))) {
    return(default)
  }
  as.character(x)[1]
}

clean_doi <- function(x) {
  if (is.null(x) || !length(x)) {
    return(NA_character_)
  }

  x <- tolower(trimws(as.character(x)))
  x <- stringr::str_remove(x, "^https?://(dx\\.)?doi\\.org/")
  x <- stringr::str_remove(x, "^doi:\\s*")
  x <- stringr::str_remove(x, "[\\.,;]+$")
  x[x == ""] <- NA_character_
  x
}

extract_dois <- function(x) {
  if (is.null(x) || !length(x) || all(is.na(x))) {
    return(character())
  }

  hits <- stringr::str_extract_all(
    paste(x, collapse = " "),
    stringr::regex(
      "10\\.[0-9]{4,9}/[-._;()/:A-Z0-9]+",
      ignore_case = TRUE
    )
  )[[1]]

  cleaned <- clean_doi(hits)
  unique(cleaned[!is.na(cleaned)])
}

get_json <- function(url, query = list(), attempts = 4, user_agent = "LTER-dataset-citation-finder") {
  for (i in seq_len(attempts)) {
    response <- tryCatch(
      httr::GET(
        url,
        query = query,
        httr::timeout(60),
        httr::user_agent(user_agent)
      ),
      error = function(e) NULL
    )

    if (is.null(response)) {
      Sys.sleep(min(15, 2^i))
      next
    }

    status <- httr::status_code(response)

    if (status == 200) {
      data <- tryCatch(
        jsonlite::fromJSON(
          httr::content(response, "text", encoding = "UTF-8"),
          simplifyVector = FALSE
        ),
        error = function(e) NULL
      )

      return(list(ok = !is.null(data), data = data, status = status))
    }

    if (status == 429) {
      waits <- c(10, 20, 30)
      if (i > length(waits)) break
      message("HTTP 429 - waiting ", waits[i], " seconds...")
      Sys.sleep(waits[i])
      next
    }

    if (status %in% c(500, 502, 503, 504)) {
      Sys.sleep(min(20, 2^i))
      next
    }

    return(list(ok = FALSE, data = NULL, status = status))
  }

  list(ok = FALSE, data = NULL, status = NA_integer_)
}

paginate_json <- function(url, extra = list(), user_agent = "LTER-dataset-citation-finder", strict = FALSE) {
  out <- list()
  start <- 0

  repeat {
    response <- get_json(
      url,
      c(
        list(limit = 100, start = start, v = 3),
        extra
      ),
      user_agent = user_agent
    )

    if (!response$ok || is.null(response$data)) {
      if (strict) {
        stop("Zotero retrieval failed at offset ", start,
             " (HTTP status ", response$status,
             "). No complete comparison can be produced. Try again later.",
             call. = FALSE)
      }
      break
    }

    if (!length(response$data)) {
      break
    }

    out <- append(out, response$data)

    if (length(response$data) < 100) {
      break
    }

    start <- start + 100
  }

  out
}

# Builds an address inside the configured Zotero group library, so the
# base URL is defined once instead of in every script. Pass the rest of
# the path as one or more strings, for example:
#   zotero_group_url("/items/top")
#   zotero_group_url("/collections/", collection_id, "/items/top")
zotero_group_url <- function(..., group_id = zotero_group_id) {
  paste0("https://api.zotero.org/groups/", group_id, ...)
}

oa_query <- function(q) {
  key <- get0("openalex_key", ifnotfound = NULL, inherits = TRUE)
  if (!is.null(key) && nzchar(key)) {
    q$api_key <- key
  }

  get_json(
    "https://api.openalex.org/works",
    q,
    user_agent = "LTER-dataset-citation-finder"
  )
}

# Only revisioned EDI package IDs qualify for series-based matching.
# Including scope prevents dataset 12 at two sites from being conflated.
dataset_series_id <- function(package_id) {
  if (!length(package_id)) return(character())
  parts <- stringr::str_match(as.character(package_id),
                             "^([^.]+)\\.([0-9]+)\\.([0-9]+)$")
  ifelse(is.na(parts[, 1]), NA_character_, paste(parts[, 2], parts[, 3], sep = "."))
}

prepare_citation_registry <- function(registry) {
  registry %>%
    dplyr::transmute(
      Dataset_DOI = clean_doi(Dataset_DOI),
      Dataset_Package_ID = dplyr::na_if(trimws(as.character(Package_ID)), ""),
      Dataset_Title = as.character(Dataset_Title),
      Dataset_Series_ID = dataset_series_id(Dataset_Package_ID),
      Dataset_Revision = suppressWarnings(as.integer(
        stringr::str_match(Dataset_Package_ID, "^[^.]+\\.[0-9]+\\.([0-9]+)$")[, 2]
      ))
    ) %>%
    dplyr::filter(!is.na(Dataset_DOI)) %>%
    dplyr::distinct(Dataset_DOI, .keep_all = TRUE)
}

citation_dataset_key <- function(doi, series, deduplicate_on_dataset_id) {
  if (!length(doi)) return(character())
  if (deduplicate_on_dataset_id) {
    ifelse(!is.na(series), paste0("series:", series), paste0("doi:", doi))
  } else {
    paste0("doi:", doi)
  }
}

collapse_citation_values <- function(x) {
  values <- unique(as.character(x[!is.na(x) & as.character(x) != ""]))
  if (length(values)) paste(values, collapse = "; ") else NA_character_
}

first_citation_value <- function(x) {
  dplyr::first(x[!is.na(x) & as.character(x) != ""])
}

empty_citation_evidence <- function() {
  tibble::tibble(Dataset_DOI = character(), Paper_DOI = character(),
                 Paper_Title = character(), Year = integer(),
                 Source = character(), Found_By = character())
}

# Package/series components sort numerically: scope.2 precedes scope.13,
# and scope.2.2 precedes scope.2.13. Rows without IDs follow, ordered by DOI.
sort_citation_results <- function(results, deduplicate_on_dataset_id) {
  sort_id <- if (deduplicate_on_dataset_id) {
    dplyr::coalesce(results$Dataset_Series_ID, results$Dataset_Package_ID)
  } else {
    results$Dataset_Package_ID
  }
  parts <- stringr::str_match(sort_id, "^([^.]+)\\.([0-9]+)(?:\\.([0-9]+))?$")
  results %>%
    dplyr::mutate(
      .Sort_ID = sort_id,
      .Sort_Scope = dplyr::coalesce(parts[, 2], sort_id),
      .Sort_Identifier = suppressWarnings(as.numeric(parts[, 3])),
      .Sort_Revision = suppressWarnings(as.numeric(parts[, 4])),
      .Sort_Paper = if ("Paper_DOI" %in% names(results)) results$Paper_DOI else rep("", nrow(results))
    ) %>%
    dplyr::arrange(is.na(.Sort_ID), .Sort_Scope, .Sort_Identifier, .Sort_Revision,
                   .Sort_ID, Dataset_DOI, .Sort_Paper) %>%
    dplyr::select(-dplyr::starts_with(".Sort_"))
}

# Pure transformation: no HTTP requests, workbook reads, or file writes.
combine_citation_evidence <- function(evidence, registry, deduplicate_on_dataset_id) {
  evidence %>%
    dplyr::mutate(Dataset_DOI = clean_doi(Dataset_DOI),
                  Paper_DOI = clean_doi(Paper_DOI)) %>%
    dplyr::filter(!is.na(Dataset_DOI), !is.na(Paper_DOI)) %>%
    dplyr::left_join(registry, by = "Dataset_DOI") %>%
    dplyr::mutate(
      Dataset_Key = citation_dataset_key(Dataset_DOI, Dataset_Series_ID,
                                         deduplicate_on_dataset_id),
      Source_Priority = match(Source, c("DataCite", "Zotero", "EDI", "OpenAlex", "PDF"))
    ) %>%
    # Within one source, choose the highest numeric revision, then DOI.
    # Input/API ordering therefore cannot change the selected revision.
    dplyr::arrange(Source_Priority, dplyr::desc(Dataset_Revision), Dataset_DOI,
                   Paper_DOI, Found_By) %>%
    dplyr::group_by(Paper_DOI, Dataset_Key) %>%
    dplyr::summarise(
      Observed_Dataset_DOIs = collapse_citation_values(Dataset_DOI),
      Observed_Package_IDs = collapse_citation_values(Dataset_Package_ID),
      Dataset_DOI = dplyr::first(Dataset_DOI),
      Dataset_Package_ID = dplyr::first(Dataset_Package_ID),
      Dataset_Series_ID = dplyr::first(Dataset_Series_ID),
      Dataset_Revision = dplyr::first(Dataset_Revision),
      Dataset_Title = dplyr::first(Dataset_Title),
      Paper_Title = first_citation_value(Paper_Title),
      Year = first_citation_value(Year),
      Selected_Source = dplyr::first(Source),
      Supporting_Sources = collapse_citation_values(Source),
      Found_By = collapse_citation_values(Found_By),
      .groups = "drop"
    ) %>%
    dplyr::select(-Dataset_Key) %>%
    dplyr::relocate(Dataset_Series_ID, Dataset_Package_ID, Dataset_DOI,
                    Dataset_Title, Dataset_Revision, Paper_DOI) %>%
    sort_citation_results(deduplicate_on_dataset_id)
}

# Seed from the complete registry, not just discovered citations. In series
# mode a count covers ALL registry revisions; do not imply that one revision
# was selected for the entire dataset (different papers may select different ones).
count_dataset_citations <- function(combined_results, registry, deduplicate_on_dataset_id) {
  totals <- combined_results %>%
    dplyr::filter(!is.na(Paper_DOI)) %>%
    dplyr::mutate(Dataset_Key = citation_dataset_key(
      Dataset_DOI, Dataset_Series_ID, deduplicate_on_dataset_id
    )) %>%
    dplyr::distinct(Paper_DOI, Dataset_Key) %>%
    dplyr::count(Dataset_Key, name = "Citation_Count")

  registry %>%
    dplyr::mutate(Dataset_Key = citation_dataset_key(
      Dataset_DOI, Dataset_Series_ID, deduplicate_on_dataset_id
    )) %>%
    sort_citation_results(deduplicate_on_dataset_id = FALSE) %>%
    dplyr::group_by(Dataset_Key) %>%
    dplyr::summarise(
      Registry_Dataset_DOIs = collapse_citation_values(Dataset_DOI),
      Registry_Package_IDs = collapse_citation_values(Dataset_Package_ID),
      Dataset_Series_ID = dplyr::first(Dataset_Series_ID),
      Dataset_Package_ID = if (deduplicate_on_dataset_id && !is.na(Dataset_Series_ID)) {
        NA_character_
      } else dplyr::first(Dataset_Package_ID),
      Dataset_DOI = if (deduplicate_on_dataset_id && !is.na(Dataset_Series_ID)) {
        NA_character_
      } else dplyr::first(Dataset_DOI),
      Dataset_Title = first_citation_value(Dataset_Title),
      .groups = "drop"
    ) %>%
    dplyr::left_join(totals, by = "Dataset_Key") %>%
    dplyr::mutate(Citation_Count = dplyr::coalesce(Citation_Count, 0L)) %>%
    dplyr::select(Dataset_Series_ID, Dataset_Package_ID, Dataset_DOI, Dataset_Title,
                  Citation_Count, Registry_Dataset_DOIs, Registry_Package_IDs) %>%
    sort_citation_results(deduplicate_on_dataset_id)
}

# Exact DOI tokens in Extra, not substring matches and not arbitrary URLs.
# No-paper-DOI matches remain in the source sheet for manual review.
extract_zotero_citations <- function(publications, registry) {
  publications %>%
    dplyr::mutate(Dataset_DOI = purrr::map(Zotero_Extra, extract_dois)) %>%
    tidyr::unnest_longer(Dataset_DOI, ptype = character()) %>%
    dplyr::inner_join(registry, by = "Dataset_DOI") %>%
    dplyr::distinct(Zotero_Item_Key, Dataset_DOI, .keep_all = TRUE)
}

# packageId in each EDI response is the recorded revision, not the
# representative package used to query the series with list_all = TRUE.
map_edi_citations <- function(citations, registry, query_package_id) {
  required <- c("journalCitationId", "packageId")
  if (!all(required %in% names(citations))) {
    stop("EDI citation response is missing journalCitationId or packageId.", call. = FALSE)
  }
  for (column in c("articleDoi", "articleTitle", "articleUrl")) {
    if (!column %in% names(citations)) citations[[column]] <- rep(NA_character_, nrow(citations))
  }
  citations %>%
    dplyr::transmute(
      Query_Package_ID = query_package_id,
      EDI_Package_ID = dplyr::na_if(trimws(as.character(packageId)), ""),
      Dataset_Series_ID = dplyr::coalesce(dataset_series_id(EDI_Package_ID),
                                         dataset_series_id(query_package_id)),
      EDI_Citation_ID = as.character(journalCitationId),
      Paper_DOI = clean_doi(articleDoi),
      EDI_Paper_Title = dplyr::na_if(trimws(as.character(articleTitle)), ""),
      EDI_Article_URL = dplyr::na_if(trimws(as.character(articleUrl)), "")
    ) %>%
    dplyr::left_join(
      registry %>%
        dplyr::filter(!is.na(Dataset_Package_ID)) %>%
        dplyr::select(Dataset_Package_ID, Dataset_DOI, Dataset_Title) %>%
        dplyr::distinct(Dataset_Package_ID, .keep_all = TRUE),
      by = c("EDI_Package_ID" = "Dataset_Package_ID")
    ) %>%
    dplyr::mutate(Mapping_Status = dplyr::if_else(
      is.na(Dataset_DOI), "Package not in registry", "Matched exact package revision"
    ))
}

# Observed columns: Paper_DOI, Dataset_DOI, Dataset_Package_ID,
# Dataset_Series_ID, Record_ID. Comparisons use the SAME granularity as
# Combined_Results; source rows themselves are never collapsed by series.
catalog_link_review <- function(expected, observed, deduplicate_on_dataset_id) {
  targets <- expected %>%
    dplyr::mutate(Dataset_Key = citation_dataset_key(
      Dataset_DOI, Dataset_Series_ID, deduplicate_on_dataset_id
    )) %>%
    dplyr::transmute(
      Paper_DOI, Paper_Title, Dataset_Title, Dataset_Series_ID, Dataset_Key,
      Recommended_Dataset_DOI = Dataset_DOI,
      Recommended_Package_ID = Dataset_Package_ID,
      Selected_Source, Found_By
    )

  links <- observed %>%
    dplyr::filter(!is.na(Paper_DOI)) %>%
    dplyr::mutate(Dataset_Key = citation_dataset_key(
      Dataset_DOI, Dataset_Series_ID, deduplicate_on_dataset_id
    )) %>%
    dplyr::transmute(
      Paper_DOI, Dataset_Key, Record_ID,
      Recorded_Dataset_DOI = Dataset_DOI,
      Recorded_Package_ID = Dataset_Package_ID,
      Has_Record = TRUE
    ) %>%
    dplyr::distinct()

  targets %>%
    dplyr::left_join(links, by = c("Paper_DOI", "Dataset_Key")) %>%
    dplyr::mutate(
      Exact_Link = dplyr::coalesce(Recorded_Dataset_DOI == Recommended_Dataset_DOI, FALSE) |
        dplyr::coalesce(Recorded_Package_ID == Recommended_Package_ID, FALSE),
      Review_Status = dplyr::case_when(
        is.na(Has_Record) ~ "Missing dataset link",
        Exact_Link ~ "Already linked",
        !is.na(dataset_series_id(Recorded_Package_ID)) ~ "Different dataset revision",
        TRUE ~ "Review unresolved revision"
      )
    ) %>%
    dplyr::filter(Review_Status != "Already linked") %>%
    dplyr::select(-Dataset_Key, -Has_Record, -Exact_Link) %>%
    dplyr::arrange(Paper_DOI, Dataset_Series_ID, Recorded_Package_ID)
}

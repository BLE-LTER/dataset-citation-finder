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
# oa_query(), get_openalex_citation_count() - OpenAlex helpers.
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

paginate_json <- function(url, extra = list(), user_agent = "LTER-dataset-citation-finder") {
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

    if (!response$ok || is.null(response$data) || !length(response$data)) {
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

get_openalex_citation_count <- function(paper_doi) {
  doi <- clean_doi(paper_doi)

  if (is.na(doi)) {
    return(
      tibble::tibble(
        Paper_DOI = NA_character_,
        Cited_By_Count = NA_integer_,
        OpenAlex_ID = NA_character_
      )
    )
  }

  response <- oa_query(
    list(
      filter = paste0("doi:https://doi.org/", doi),
      corpus = "all",
      per_page = 1
    )
  )

  if (!response$ok || is.null(response$data$results) || !length(response$data$results)) {
    return(
      tibble::tibble(
        Paper_DOI = doi,
        Cited_By_Count = NA_integer_,
        OpenAlex_ID = NA_character_
      )
    )
  }

  work <- response$data$results[[1]]

  tibble::tibble(
    Paper_DOI = doi,
    Cited_By_Count = suppressWarnings(as.integer(safe(work$cited_by_count))),
    OpenAlex_ID = safe(work$id)
  )
}

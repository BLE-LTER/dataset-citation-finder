# ================================================================
# utils.R
# SHARED HELPERS FOR DATASET CITATION FINDER
# ================================================================
#
# This file contains functions used by more than one workflow script.
# It is sourced automatically by the numbered scripts; users normally
# do not run it directly.
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

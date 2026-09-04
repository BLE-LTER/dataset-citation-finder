# ================================================================
# 01_Dataset_Registry.R
#
# PURPOSE
# Build the dataset registry used by the citation workflow.
#
# Sources:
#   1. EDI dataset packages and all revisions
#   2. Externally archived datasets identified by a Zotero tag
#
# OUTPUT
#   Data_Registry.xlsx
#
# Run this script before 02_Publication_Search_PDF.R.
# ================================================================


# ================================================================
# 1. PACKAGES
# ================================================================

pkgs <- c(
  "EDIutils",
  "httr",
  "jsonlite",
  "dplyr",
  "purrr",
  "stringr",
  "tibble",
  "openxlsx"
)

new <- pkgs[!pkgs %in% installed.packages()[, "Package"]]

if (length(new)) {
  install.packages(new)
}

invisible(
  lapply(
    pkgs,
    library,
    character.only = TRUE
  )
)


# ================================================================
# 2. SITE SETTINGS
# ================================================================

edi_scope <- "knb-lter-ble"

zotero_group_id <- "2211939"

external_tag <- "LTER-Funded Data at Other Archives"

# Save generated files outside the GitHub repository
output_dir <- paste0(
  "C:/Users/im23237/OneDrive - The University of Texas at Austin/",
  "Documents/Citation_finder_output"
)

if (!dir.exists(output_dir)) {
  dir.create(
    output_dir,
    recursive = TRUE
  )
}

output_file <- file.path(
  output_dir,
  "Data_Registry.xlsx"
)


# ================================================================
# 3. EDI API KEY
# ================================================================

edi_key <- Sys.getenv("EDI_API_KEY")

if (edi_key == "") {
  stop("Set EDI_API_KEY first.")
}


# ================================================================
# 4. HELPERS
# ================================================================

safe <- function(x, default = NA_character_) {
  
  if (
    is.null(x) ||
    !length(x) ||
    all(is.na(x))
  ) {
    return(default)
  }
  
  as.character(x)[1]
}


clean_doi <- function(x) {
  
  if (
    is.null(x) ||
    !length(x)
  ) {
    return(NA_character_)
  }
  
  x <- tolower(
    trimws(
      as.character(x)
    )
  )
  
  x <- stringr::str_remove(
    x,
    "^https?://(dx\\.)?doi\\.org/"
  )
  
  x <- stringr::str_remove(
    x,
    "^doi:\\s*"
  )
  
  x <- stringr::str_remove(
    x,
    "[\\.,;]+$"
  )
  
  x[x == ""] <- NA_character_
  
  x
}


extract_dois <- function(x) {
  
  z <- stringr::str_extract_all(
    paste(
      x,
      collapse = " "
    ),
    stringr::regex(
      "10\\.[0-9]{4,9}/[-._;()/:A-Z0-9]+",
      ignore_case = TRUE
    )
  )[[1]]
  
  unique(
    na.omit(
      clean_doi(z)
    )
  )
}


get_json <- function(
    url,
    query = list(),
    attempts = 4
) {
  
  for (i in seq_len(attempts)) {
    
    r <- tryCatch(
      httr::GET(
        url,
        query = query,
        httr::timeout(60),
        httr::user_agent("LTER-dataset-registry")
      ),
      error = function(e) NULL
    )
    
    if (is.null(r)) {
      Sys.sleep(min(15, 2^i))
      next
    }
    
    s <- httr::status_code(r)
    
    if (s == 200) {
      
      dat <- tryCatch(
        jsonlite::fromJSON(
          httr::content(
            r,
            "text",
            encoding = "UTF-8"
          ),
          simplifyVector = FALSE
        ),
        error = function(e) NULL
      )
      
      return(
        list(
          ok = !is.null(dat),
          data = dat
        )
      )
    }
    
    if (s == 429) {
      waits <- c(10, 20, 30)
      
      if (i > length(waits)) {
        break
      }
      
      cat(
        "HTTP 429 - waiting ",
        waits[i],
        " seconds...\n",
        sep = ""
      )
      
      Sys.sleep(waits[i])
      next
    }
    
    if (s %in% c(500, 502, 503, 504)) {
      Sys.sleep(min(20, 2^i))
      next
    }
    
    break
  }
  
  list(
    ok = FALSE,
    data = NULL
  )
}


paginate_json <- function(
    url,
    extra = list()
) {
  
  out <- list()
  start <- 0
  
  repeat {
    
    r <- get_json(
      url,
      c(
        list(
          limit = 100,
          start = start,
          v = 3
        ),
        extra
      )
    )
    
    if (
      !r$ok ||
      is.null(r$data) ||
      !length(r$data)
    ) {
      break
    }
    
    out <- append(
      out,
      r$data
    )
    
    if (length(r$data) < 100) {
      break
    }
    
    start <- start + 100
  }
  
  out
}


# ================================================================
# 5. EDI DATASET REGISTRY
# ================================================================

EDIutils::login(
  key = edi_key
)

cat(
  "\n========================================\n",
  "GETTING EDI DATASET REGISTRY\n",
  "========================================\n"
)


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
    
    packageid =
      as.character(
        packageid
      ),
    
    scope =
      stringr::str_extract(
        packageid,
        "^[^.]+"
      ),
    
    identifier =
      stringr::str_match(
        packageid,
        "^[^.]+\\.([0-9]+)\\."
      )[, 2]
  ) %>%
  
  dplyr::filter(
    !is.na(identifier)
  ) %>%
  
  dplyr::distinct(
    scope,
    identifier,
    .keep_all = TRUE
  )


revisions <- purrr::pmap_dfr(
  
  list(
    edi_series$scope,
    edi_series$identifier,
    edi_series$title
  ),
  
  function(
    scope,
    identifier,
    title
  ) {
    
    r <- tryCatch(
      
      EDIutils::list_data_package_revisions(
        scope = scope,
        identifier = as.numeric(identifier),
        env = "production"
      ),
      
      error = function(e) NULL
    )
    
    if (is.null(r)) {
      return(tibble::tibble())
    }
    
    tibble::tibble(
      Scope = scope,
      Identifier = identifier,
      Revision = as.integer(r),
      Dataset_Title = title,
      Package_ID = paste(
        scope,
        identifier,
        r,
        sep = "."
      )
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
  
  dplyr::filter(
    !is.na(Dataset_DOI)
  ) %>%
  
  dplyr::distinct(
    Dataset_DOI,
    .keep_all = TRUE
  ) %>%
  
  dplyr::mutate(
    Registry_Source = "EDI",
    Registry_Category = "Dataset Registry",
    Zotero_Item_Key = NA_character_
  )


EDIutils::logout()


# ================================================================
# 6. EXTERNALLY ARCHIVED DATASETS FROM ZOTERO
# ================================================================

cat(
  "\n========================================\n",
  "GETTING EXTERNALLY ARCHIVED DATASETS\n",
  "========================================\n"
)


external_items <- paginate_json(
  
  paste0(
    "https://api.zotero.org/groups/",
    zotero_group_id,
    "/items/top"
  ),
  
  list(
    tag = external_tag
  )
)


zotero_registry <- purrr::map_dfr(
  
  external_items,
  
  function(item) {
    
    d <- item$data
    
    direct <- clean_doi(
      safe(
        d$DOI
      )
    )
    
    possible <- extract_dois(
      paste(
        safe(
          d$DOI,
          ""
        ),
        safe(
          d$url,
          ""
        ),
        safe(
          d$extra,
          ""
        )
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
  
  dplyr::filter(
    !is.na(Dataset_DOI)
  ) %>%
  
  dplyr::distinct(
    Dataset_DOI,
    .keep_all = TRUE
  )


# ================================================================
# 7. MASTER DATA REGISTRY
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
# 8. SAVE DATA REGISTRY
# ================================================================

openxlsx::write.xlsx(
  list(
    Data_Registry = data_registry
  ),
  file = output_file,
  overwrite = TRUE
)


cat(
  "\n========================================\n",
  "DATASET REGISTRY COMPLETE\n",
  "========================================\n",
  "Saved: ", output_file, "\n",
  "EDI dataset rows: ", nrow(edi_registry), "\n",
  "External dataset rows: ", nrow(zotero_registry), "\n",
  "Total registry rows: ", nrow(data_registry), "\n",
  "========================================\n"
)

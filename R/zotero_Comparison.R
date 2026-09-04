# ================================================================
# 03_Zotero_Comparison.R
#
# PURPOSE
# Compare automated publication-dataset relationships with the
# Zotero For-Website collection and create Zotero review tabs.
#
# INPUTS
#   Data_Registry.xlsx
#   Publication_Search_Results.xlsx
#
# OUTPUT
#   Zotero_Comparison.xlsx
# ================================================================


# ================================================================
# 1. PACKAGES
# ================================================================

pkgs <- c(
  "httr",
  "jsonlite",
  "dplyr",
  "purrr",
  "stringr",
  "tibble",
  "tidyr",
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
# 2. SETTINGS
# ================================================================

zotero_group_id <- "2211939"

website_collection <- "For-Website"

# Save/read generated Excel files outside the GitHub repository
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

data_registry_file <- file.path(
  output_dir,
  "Data_Registry.xlsx"
)

publication_results_file <- file.path(
  output_dir,
  "Publication_Search_Results.xlsx"
)

output_file <- file.path(
  output_dir,
  "Zotero_Comparison.xlsx"
)

cache_file <- "openalex_cache.rds"


# ================================================================
# 3. OPENALEX KEY
# ================================================================

openalex_key <- Sys.getenv("OPENALEX_API_KEY")

if (openalex_key == "") {
  openalex_key <- NULL
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
        httr::user_agent("LTER-zotero-comparison")
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
# 5. OPENALEX CITATION COUNT CACHE
# ================================================================

if (file.exists(cache_file)) {
  
  oa_cache <- tryCatch(
    readRDS(cache_file),
    error = function(e) NULL
  )
  
} else {
  
  oa_cache <- NULL
}


if (
  is.null(oa_cache) ||
  !is.list(oa_cache)
) {
  oa_cache <- list()
}


if (is.null(oa_cache$paper_metrics)) {
  oa_cache$paper_metrics <- list()
}


oa_query <- function(q) {
  
  if (!is.null(openalex_key)) {
    q$api_key <- openalex_key
  }
  
  get_json(
    "https://api.openalex.org/works",
    q
  )
}


get_openalex_citation_count <- function(paper_doi) {
  
  doi <- clean_doi(
    paper_doi
  )
  
  if (is.na(doi)) {
    
    return(
      tibble::tibble(
        Paper_DOI = NA_character_,
        Cited_By_Count = NA_integer_,
        OpenAlex_ID = NA_character_
      )
    )
  }
  
  
  if (doi %in% names(oa_cache$paper_metrics)) {
    
    cached <- oa_cache$paper_metrics[[doi]]
    
    if (is.data.frame(cached)) {
      return(cached)
    }
  }
  
  
  r <- oa_query(
    list(
      filter =
        paste0(
          "doi:https://doi.org/",
          doi
        ),
      corpus = "all",
      per_page = 1
    )
  )
  
  
  result <- if (
    !r$ok ||
    is.null(r$data$results) ||
    !length(r$data$results)
  ) {
    
    tibble::tibble(
      Paper_DOI = doi,
      Cited_By_Count = NA_integer_,
      OpenAlex_ID = NA_character_
    )
    
  } else {
    
    w <- r$data$results[[1]]
    
    tibble::tibble(
      Paper_DOI = doi,
      Cited_By_Count =
        suppressWarnings(
          as.integer(
            safe(
              w$cited_by_count
            )
          )
        ),
      OpenAlex_ID = safe(w$id)
    )
  }
  
  
  oa_cache$paper_metrics[[doi]] <<- result
  
  saveRDS(
    oa_cache,
    cache_file
  )
  
  result
}


# ================================================================
# 6. LOAD SCRIPT 1 + SCRIPT 2 RESULTS
# ================================================================

if (!file.exists(data_registry_file)) {
  stop(
    paste0(
      "Could not find ",
      data_registry_file,
      ". Run 01_Dataset_Registry.R first."
    )
  )
}


if (!file.exists(publication_results_file)) {
  stop(
    paste0(
      "Could not find ",
      publication_results_file,
      ". Run 02_Publication_Search_PDF.R first."
    )
  )
}


master_data_registry <- openxlsx::read.xlsx(
  data_registry_file,
  sheet = "Data_Registry"
) %>%
  
  dplyr::mutate(
    Dataset_DOI =
      clean_doi(
        Dataset_DOI
      )
  )


publication_search <- openxlsx::read.xlsx(
  publication_results_file,
  sheet = "Publication_Search"
) %>%
  
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


pdf_results <- openxlsx::read.xlsx(
  publication_results_file,
  sheet = "PDF_Results"
)


final_publication_relationships <- openxlsx::read.xlsx(
  publication_results_file,
  sheet = "Final_Relationships"
) %>%
  
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


# ================================================================
# 7. GET ZOTERO FOR-WEBSITE COLLECTION
# ================================================================

cat(
  "\n========================================\n",
  "GETTING ZOTERO FOR-WEBSITE COLLECTION\n",
  "========================================\n"
)


collections <- paginate_json(
  paste0(
    "https://api.zotero.org/groups/",
    zotero_group_id,
    "/collections"
  )
)


fw <- purrr::keep(
  collections,
  ~ identical(
    safe(
      .x$data$name
    ),
    website_collection
  )
)


if (!length(fw)) {
  
  stop(
    paste0(
      'Could not find Zotero collection "',
      website_collection,
      '".'
    )
  )
}


fw_key <- safe(
  fw[[1]]$key
)


fw_items <- paginate_json(
  paste0(
    "https://api.zotero.org/groups/",
    zotero_group_id,
    "/collections/",
    fw_key,
    "/items/top"
  )
)


# ================================================================
# 8. ZOTERO PUBLICATION ITEMS
# ================================================================

pub_types <- c(
  "journalArticle",
  "conferencePaper",
  "bookSection",
  "preprint",
  "report",
  "thesis"
)


zotero_publications <- purrr::map_dfr(
  
  fw_items,
  
  function(item) {
    
    d <- item$data
    
    if (
      !safe(
        d$itemType
      ) %in%
      pub_types
    ) {
      return(tibble::tibble())
    }
    
    
    pdoi <- clean_doi(
      safe(
        d$DOI
      )
    )
    
    
    if (is.na(pdoi)) {
      
      z <- extract_dois(
        safe(
          d$url,
          ""
        )
      )
      
      if (length(z)) {
        pdoi <- z[1]
      }
    }
    
    
    tibble::tibble(
      Zotero_Item_Key = safe(item$key),
      Paper_Title = safe(d$title),
      Paper_DOI = pdoi,
      Zotero_Extra = safe(d$extra, ""),
      Zotero_Item_Type = safe(d$itemType)
    )
  }
  
) %>%
  
  dplyr::filter(
    !is.na(Paper_DOI)
  ) %>%
  
  dplyr::mutate(
    Paper_DOI =
      clean_doi(
        Paper_DOI
      )
  ) %>%
  
  dplyr::distinct(
    Paper_DOI,
    .keep_all = TRUE
  )


# ================================================================
# 9. OPENALEX CITATION COUNTS
# ================================================================

citation_count_date <- as.character(
  Sys.Date()
)


all_paper_dois <- union(
  final_publication_relationships$Paper_DOI,
  zotero_publications$Paper_DOI
) %>%
  
  clean_doi() %>%
  
  unique()


all_paper_dois <- all_paper_dois[
  !is.na(all_paper_dois)
]


paper_citation_counts <- purrr::map_dfr(
  
  all_paper_dois,
  
  function(doi) {
    
    cat(
      "OpenAlex cited-by count: ",
      doi,
      "\n",
      sep = ""
    )
    
    get_openalex_citation_count(
      doi
    )
  }
  
) %>%
  
  dplyr::distinct(
    Paper_DOI,
    .keep_all = TRUE
  ) %>%
  
  dplyr::mutate(
    Citation_Count_Date =
      citation_count_date
  )


zotero_publications <- zotero_publications %>%
  
  dplyr::left_join(
    paper_citation_counts %>%
      dplyr::select(
        Paper_DOI,
        Cited_By_Count,
        OpenAlex_ID,
        Citation_Count_Date
      ),
    by = "Paper_DOI"
  )


# ================================================================
# 10. ZOTERO FOR-WEBSITE TAB
# ================================================================

zotero_for_website <- zotero_publications %>%
  
  dplyr::rowwise() %>%
  
  dplyr::mutate(
    
    Dataset_DOIs_In_Extra = {
      
      dois <- extract_dois(
        Zotero_Extra
      )
      
      dataset_dois <- dois[
        dois %in%
          master_data_registry$Dataset_DOI
      ]
      
      if (length(dataset_dois) > 0) {
        
        paste(
          unique(
            dataset_dois
          ),
          collapse = "; "
        )
        
      } else {
        
        NA_character_
      }
    },
    
    Has_Dataset_DOI_In_Extra =
      !is.na(
        Dataset_DOIs_In_Extra
      )
  ) %>%
  
  dplyr::ungroup() %>%
  
  dplyr::select(
    Zotero_Item_Key,
    Paper_DOI,
    Paper_Title,
    Zotero_Item_Type,
    Dataset_DOIs_In_Extra,
    Has_Dataset_DOI_In_Extra,
    Cited_By_Count,
    Citation_Count_Date,
    Zotero_Extra
  ) %>%
  
  dplyr::arrange(
    Paper_Title
  )


# ================================================================
# 11. BUILD ZOTERO PAPER-DATASET RELATIONSHIPS
# ================================================================

zotero_dataset_evidence <- purrr::map_dfr(
  
  seq_len(
    nrow(
      zotero_publications
    )
  ),
  
  function(i) {
    
    extra <- tolower(
      safe(
        zotero_publications$Zotero_Extra[i],
        ""
      )
    )
    
    hits <- master_data_registry %>%
      
      dplyr::rowwise() %>%
      
      dplyr::mutate(
        
        DOI_Match =
          !is.na(Dataset_DOI) &&
          stringr::str_detect(
            extra,
            stringr::fixed(
              tolower(
                Dataset_DOI
              )
            )
          ),
        
        URL_Match =
          !is.na(Final_URL) &&
          Final_URL != "" &&
          stringr::str_detect(
            extra,
            stringr::fixed(
              tolower(
                Final_URL
              )
            )
          )
      ) %>%
      
      dplyr::ungroup() %>%
      
      dplyr::filter(
        DOI_Match |
          URL_Match
      )
    
    
    if (!nrow(hits)) {
      return(tibble::tibble())
    }
    
    
    hits %>%
      
      dplyr::transmute(
        Paper_Title =
          zotero_publications$Paper_Title[i],
        Paper_DOI =
          zotero_publications$Paper_DOI[i],
        Zotero_Item_Key =
          zotero_publications$Zotero_Item_Key[i],
        Dataset_Package_ID =
          Package_ID,
        Dataset_DOI,
        Dataset_Title,
        Zotero_Evidence =
          dplyr::case_when(
            DOI_Match &
              URL_Match ~
              "Dataset DOI + Final URL in Extra",
            DOI_Match ~
              "Dataset DOI in Extra",
            TRUE ~
              "Final URL in Extra"
          ),
        Zotero_Extra =
          zotero_publications$Zotero_Extra[i]
      )
  }
)


# ================================================================
# 12. MISSING FROM ZOTERO
#
# Publication was found by the automated workflow but the Paper DOI
# does not exist anywhere in the Zotero For-Website collection.
#
# IMPORTANT:
# Papers that already exist in Zotero but are missing a specific
# Dataset DOI are NOT included here. Those belong only in
# Zotero_Missing_Data_DOI.
# ================================================================

missing_from_zotero <- final_publication_relationships %>%
  
  dplyr::anti_join(
    zotero_publications %>%
      dplyr::distinct(
        Paper_DOI
      ),
    by = "Paper_DOI"
  ) %>%
  
  dplyr::left_join(
    paper_citation_counts %>%
      dplyr::select(
        Paper_DOI,
        Cited_By_Count,
        Citation_Count_Date
      ),
    by = "Paper_DOI"
  ) %>%
  
  dplyr::left_join(
    master_data_registry %>%
      dplyr::select(
        Dataset_DOI,
        Dataset_Package_ID = Package_ID,
        Dataset_Title
      ),
    by = "Dataset_DOI"
  ) %>%
  
  dplyr::select(
    Paper_DOI,
    Paper_Title,
    Year,
    Dataset_Package_ID,
    Dataset_DOI,
    Dataset_Title,
    Cited_By_Count,
    Citation_Count_Date,
    Found_By
  ) %>%
  
  dplyr::arrange(
    dplyr::desc(
      Year
    ),
    Paper_Title,
    Dataset_Package_ID
  )


# ================================================================
# 13. ZOTERO MISSING DATASET DOI
#
# Paper exists in Zotero, but a relationship found by the
# automated workflow is missing from Zotero Extra.
# ================================================================

zotero_missing_dataset_doi <- final_publication_relationships %>%
  
  dplyr::inner_join(
    zotero_publications %>%
      dplyr::select(
        Paper_DOI,
        Zotero_Item_Key,
        Zotero_Extra
      ),
    by = "Paper_DOI"
  ) %>%
  
  dplyr::anti_join(
    zotero_dataset_evidence %>%
      dplyr::distinct(
        Paper_DOI,
        Dataset_DOI
      ),
    by =
      c(
        "Paper_DOI",
        "Dataset_DOI"
      )
  ) %>%
  
  dplyr::left_join(
    master_data_registry %>%
      dplyr::select(
        Dataset_DOI,
        Dataset_Package_ID = Package_ID,
        Dataset_Title
      ),
    by = "Dataset_DOI"
  ) %>%
  
  dplyr::left_join(
    paper_citation_counts %>%
      dplyr::select(
        Paper_DOI,
        Cited_By_Count,
        Citation_Count_Date
      ),
    by = "Paper_DOI"
  ) %>%
  
  dplyr::mutate(
    DOI_In_Extra = FALSE
  ) %>%
  
  dplyr::select(
    Paper_DOI,
    Paper_Title,
    Year,
    Dataset_Package_ID,
    Dataset_DOI,
    Dataset_Title,
    Cited_By_Count,
    Citation_Count_Date,
    Zotero_Item_Key,
    Zotero_Extra,
    DOI_In_Extra,
    Found_By
  ) %>%
  
  dplyr::arrange(
    dplyr::desc(
      Year
    ),
    Paper_Title
  )


# ================================================================
# 14. ZOTERO NOT IN SEARCH
#
# Zotero records a specific Paper DOI + Dataset DOI relationship
# that the automated workflow did not find.
# ================================================================

zotero_not_in_search <- zotero_dataset_evidence %>%
  
  dplyr::anti_join(
    final_publication_relationships %>%
      dplyr::distinct(
        Paper_DOI,
        Dataset_DOI
      ),
    by =
      c(
        "Paper_DOI",
        "Dataset_DOI"
      )
  ) %>%
  
  dplyr::left_join(
    paper_citation_counts %>%
      dplyr::select(
        Paper_DOI,
        Cited_By_Count,
        Citation_Count_Date
      ),
    by = "Paper_DOI"
  ) %>%
  
  dplyr::arrange(
    Paper_Title,
    Dataset_Package_ID,
    Dataset_DOI
  )


# ================================================================
# 15. WRITE ZOTERO COMPARISON WORKBOOK
# ================================================================

sheets <- list(
  Zotero_For_Website =
    zotero_for_website,
  Missing_From_Zotero =
    missing_from_zotero,
  Zotero_Missing_Data_DOI =
    zotero_missing_dataset_doi,
  Zotero_Not_In_Search =
    zotero_not_in_search
)


wb <- openxlsx::createWorkbook()


header_style <- openxlsx::createStyle(
  textDecoration = "bold",
  border = "Bottom"
)


purrr::walk(
  names(
    sheets
  ),
  function(nm) {
    
    openxlsx::addWorksheet(
      wb,
      nm
    )
    
    openxlsx::writeData(
      wb,
      nm,
      sheets[[nm]]
    )
    
    if (ncol(sheets[[nm]]) > 0) {
      
      openxlsx::addStyle(
        wb,
        nm,
        header_style,
        rows = 1,
        cols =
          seq_len(
            ncol(
              sheets[[nm]]
            )
          ),
        gridExpand = TRUE
      )
      
      openxlsx::freezePane(
        wb,
        nm,
        firstRow = TRUE
      )
      
      openxlsx::setColWidths(
        wb,
        nm,
        cols =
          seq_len(
            ncol(
              sheets[[nm]]
            )
          ),
        widths = "auto"
      )
    }
  }
)


openxlsx::saveWorkbook(
  wb,
  output_file,
  overwrite = TRUE
)


cat(
  "\n========================================\n",
  "ZOTERO COMPARISON COMPLETE\n",
  "========================================\n",
  "Zotero For-Website publications: ",
  nrow(zotero_for_website),
  "\n",
  "Publications completely missing from Zotero: ",
  nrow(missing_from_zotero),
  "\n",
  "Existing Zotero publications missing dataset DOI in Extra: ",
  nrow(zotero_missing_dataset_doi),
  "\n",
  "Zotero relationships not found by automated search: ",
  nrow(zotero_not_in_search),
  "\n",
  "Saved: ",
  output_file,
  "\n",
  "========================================\n"
)

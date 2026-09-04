# ================================================================
# 04_Zotero_Comprehensive_List.R
# ZOTERO COMPREHENSIVE PUBLICATION LIST
#
# PURPOSE:
# Get publications from Zotero "For-Website"
# and extract related DOI values from the Extra field.
#
# Also extract paper authors from Zotero creators.
#
# Reuses the same helper logic/style as Citation Finder.
#
#
# COLUMNS:
# Paper_Title
# Paper_Authors
# Paper_DOI
# Dataset_DOIs
# Cited_By_Count
#
# ONE ROW PER:
# Publication
#
# Multiple related dataset DOIs are combined with "; ".
# ================================================================

packages <- c(
  "httr",
  "jsonlite",
  "dplyr",
  "purrr",
  "stringr",
  "tibble",
  "openxlsx"
)


new_packages <- packages[
  !packages %in%
    installed.packages()[, "Package"]
]


if (length(new_packages) > 0) {
  install.packages(new_packages)
}


library(httr)
library(jsonlite)
library(dplyr)
library(purrr)
library(stringr)
library(tibble)
library(openxlsx)


# ================================================================
# 1. SETTINGS
# ================================================================

zotero_group_id <- "2211939"

website_collection <- "For-Website"

# Save generated Excel files outside the GitHub repository
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
  "Zotero_Comprehensive_Publication_List.xlsx"
)


openalex_key <- Sys.getenv(
  "OPENALEX_API_KEY"
)


if (
  openalex_key == ""
) {
  openalex_key <- NULL
}


# ================================================================
# 2. HELPER FUNCTIONS
# ================================================================

safe <- function(
    x,
    default = NA_character_
) {
  
  if (
    is.null(x) ||
    length(x) == 0 ||
    all(is.na(x))
  ) {
    
    return(default)
  }
  
  as.character(x)[1]
}


clean_doi <- function(x) {
  
  if (
    is.null(x) ||
    length(x) == 0
  ) {
    
    return(NA_character_)
  }
  
  x <- as.character(x)
  
  x <- tolower(x)
  
  x <- trimws(x)
  
  x <- str_remove(
    x,
    "^https?://(dx\\.)?doi\\.org/"
  )
  
  x <- str_remove(
    x,
    "^doi:\\s*"
  )
  
  x <- str_remove(
    x,
    "[\\.,;]+$"
  )
  
  x[x == ""] <- NA_character_
  
  x
}


extract_dois <- function(x) {
  
  if (
    is.null(x) ||
    length(x) == 0 ||
    is.na(x) ||
    x == ""
  ) {
    
    return(character())
  }
  
  dois <- str_extract_all(
    
    x,
    
    regex(
      "10\\.[0-9]{4,9}/[-._;()/:A-Z0-9]+",
      ignore_case = TRUE
    )
    
  )[[1]]
  
  dois <- clean_doi(
    dois
  )
  
  unique(
    dois[
      !is.na(dois)
    ]
  )
}


# ================================================================
# 2A. EXTRACT PAPER AUTHORS
# ================================================================

extract_authors <- function(creators) {
  
  if (
    is.null(creators) ||
    length(creators) == 0
  ) {
    
    return(NA_character_)
  }
  
  
  author_names <- map_chr(
    
    creators,
    
    function(creator) {
      
      # ------------------------------------------------
      # ONLY INCLUDE AUTHORS
      #
      # Ignore editors, contributors, etc.
      # ------------------------------------------------
      
      creator_type <- safe(
        creator$creatorType,
        ""
      )
      
      
      if (
        creator_type != "author"
      ) {
        
        return("")
      }
      
      
      # ------------------------------------------------
      # INSTITUTIONAL / SINGLE-FIELD AUTHOR
      # ------------------------------------------------
      
      single_name <- safe(
        creator$name,
        ""
      )
      
      
      if (
        !is.na(single_name) &&
        single_name != ""
      ) {
        
        return(
          str_squish(
            single_name
          )
        )
      }
      
      
      # ------------------------------------------------
      # NORMAL PERSONAL AUTHOR
      # ------------------------------------------------
      
      first_name <- safe(
        creator$firstName,
        ""
      )
      
      
      last_name <- safe(
        creator$lastName,
        ""
      )
      
      
      full_name <- str_squish(
        paste(
          first_name,
          last_name
        )
      )
      
      
      if (
        full_name == ""
      ) {
        
        return("")
      }
      
      
      full_name
    }
  )
  
  
  # ------------------------------------------------
  # REMOVE EMPTY VALUES
  # ------------------------------------------------
  
  author_names <- author_names[
    !is.na(author_names) &
      author_names != ""
  ]
  
  
  # ------------------------------------------------
  # NO AUTHORS FOUND
  # ------------------------------------------------
  
  if (
    length(author_names) == 0
  ) {
    
    return(NA_character_)
  }
  
  
  # ------------------------------------------------
  # COMBINE AUTHORS INTO ONE COLUMN
  # ------------------------------------------------
  
  paste(
    author_names,
    collapse = "; "
  )
}


# ================================================================
# 3. GENERAL ZOTERO API REQUEST
# ================================================================

get_json <- function(
    url,
    query = list(),
    attempts = 4
) {
  
  for (
    i in seq_len(attempts)
  ) {
    
    response <- tryCatch(
      
      GET(
        url,
        query = query,
        timeout(60),
        user_agent(
          "BLE-LTER-Zotero-comprehensive-export"
        )
      ),
      
      error = function(e) {
        NULL
      }
    )
    
    
    if (
      is.null(response)
    ) {
      
      Sys.sleep(
        min(
          10,
          2^i
        )
      )
      
      next
    }
    
    
    status <- status_code(
      response
    )
    
    
    if (
      status == 200
    ) {
      
      result <- tryCatch(
        
        fromJSON(
          content(
            response,
            "text",
            encoding = "UTF-8"
          ),
          simplifyVector = FALSE
        ),
        
        error = function(e) {
          NULL
        }
      )
      
      
      if (
        !is.null(result)
      ) {
        
        return(result)
      }
    }
    
    
    if (
      status == 429
    ) {
      
      wait <- c(
        5,
        10,
        20,
        30
      )
      
      
      Sys.sleep(
        wait[
          min(
            i,
            length(wait)
          )
        ]
      )
      
      next
    }
    
    
    stop(
      paste(
        "Zotero API request failed. HTTP status:",
        status
      )
    )
  }
  
  
  stop(
    paste(
      "Zotero request failed after",
      attempts,
      "attempts."
    )
  )
}


# ================================================================
# 3A. OPENALEX CITED-BY COUNT
# ================================================================

get_openalex_citation_count <- function(
    paper_doi
) {
  
  doi <- clean_doi(
    paper_doi
  )
  
  if (is.na(doi)) {
    return(
      tibble(
        Paper_DOI = NA_character_,
        Cited_By_Count = NA_integer_
      )
    )
  }
  
  query <- list(
    filter = paste0(
      "doi:https://doi.org/",
      doi
    ),
    corpus = "all",
    per_page = 1
  )
  
  if (!is.null(openalex_key)) {
    query$api_key <- openalex_key
  }
  
  result <- tryCatch(
    get_json(
      "https://api.openalex.org/works",
      query
    ),
    error = function(e) NULL
  )
  
  if (
    is.null(result) ||
    is.null(result$results) ||
    !length(result$results)
  ) {
    return(
      tibble(
        Paper_DOI = doi,
        Cited_By_Count = NA_integer_
      )
    )
  }
  
  tibble(
    Paper_DOI = doi,
    Cited_By_Count = suppressWarnings(
      as.integer(
        safe(result$results[[1]]$cited_by_count)
      )
    )
  )
}


# ================================================================
# 4. ZOTERO PAGINATION
# ================================================================

paginate_zotero <- function(
    url,
    extra = list()
) {
  
  all_items <- list()
  
  start <- 0
  
  
  repeat {
    
    result <- get_json(
      
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
      is.null(result) ||
      length(result) == 0
    ) {
      
      break
    }
    
    
    all_items <- append(
      all_items,
      result
    )
    
    
    if (
      length(result) < 100
    ) {
      
      break
    }
    
    
    start <- start + 100
  }
  
  
  all_items
}


# ================================================================
# 5. GET ZOTERO COLLECTIONS
# ================================================================

cat(
  "\n========================================\n",
  "GETTING ZOTERO COLLECTIONS\n",
  "========================================\n"
)


collections <- paginate_zotero(
  
  paste0(
    "https://api.zotero.org/groups/",
    zotero_group_id,
    "/collections"
  )
)


# ================================================================
# 6. FIND FOR-WEBSITE COLLECTION
# ================================================================

collection_match <- keep(
  
  collections,
  
  ~ identical(
    safe(
      .x$data$name
    ),
    website_collection
  )
)


if (
  length(collection_match) == 0
) {
  
  stop(
    paste0(
      'Could not find Zotero collection "',
      website_collection,
      '".'
    )
  )
}


collection_key <- safe(
  collection_match[[1]]$key
)


cat(
  "For-Website collection key:",
  collection_key,
  "\n"
)


# ================================================================
# 7. GET ALL TOP-LEVEL ITEMS FROM FOR-WEBSITE
# ================================================================

cat(
  "\n========================================\n",
  "GETTING FOR-WEBSITE ITEMS\n",
  "========================================\n"
)


items <- paginate_zotero(
  
  paste0(
    "https://api.zotero.org/groups/",
    zotero_group_id,
    "/collections/",
    collection_key,
    "/items/top"
  )
)


cat(
  "Total top-level items:",
  length(items),
  "\n"
)


# ================================================================
# 8. PUBLICATION TYPES
# ================================================================

publication_types <- c(
  "journalArticle",
  "conferencePaper",
  "bookSection",
  "preprint",
  "report",
  "thesis"
)


# ================================================================
# 9. GET PUBLICATION TITLE, AUTHORS, DOI, AND EXTRA
# ================================================================

zotero_publications <- map_dfr(
  
  items,
  
  function(item) {
    
    d <- item$data
    
    
    item_type <- safe(
      d$itemType
    )
    
    
    if (
      !item_type %in%
      publication_types
    ) {
      
      return(
        tibble()
      )
    }
    
    
    # ------------------------------------------------
    # PAPER AUTHORS
    # ------------------------------------------------
    
    paper_authors <- extract_authors(
      d$creators
    )
    
    
    # ------------------------------------------------
    # PAPER DOI
    # ------------------------------------------------
    
    paper_doi <- clean_doi(
      safe(
        d$DOI
      )
    )
    
    
    # ------------------------------------------------
    # IF DOI FIELD IS EMPTY, TRY URL
    # ------------------------------------------------
    
    if (
      is.na(
        paper_doi
      )
    ) {
      
      url_dois <- extract_dois(
        safe(
          d$url,
          ""
        )
      )
      
      
      if (
        length(
          url_dois
        ) > 0
      ) {
        
        paper_doi <-
          url_dois[1]
      }
    }
    
    
    # ------------------------------------------------
    # BUILD PUBLICATION ROW
    # ------------------------------------------------
    
    tibble(
      
      Paper_Title =
        safe(
          d$title
        ),
      
      Paper_Authors =
        paper_authors,
      
      Paper_DOI =
        paper_doi,
      
      Zotero_Extra =
        safe(
          d$extra,
          ""
        )
    )
  }
)


cat(
  "Publication items:",
  nrow(
    zotero_publications
  ),
  "\n"
)


# ================================================================
# 10. EXTRACT RELATED DOI VALUES FROM ZOTERO EXTRA
#
# IMPORTANT:
# ALL publications are kept.
#
# If no related DOI is found in Extra:
# Dataset_DOI = NA
#
# If multiple related DOIs are found:
# one row per related DOI.
# ================================================================

zotero_related_dois <- map_dfr(
  
  seq_len(
    nrow(
      zotero_publications
    )
  ),
  
  function(i) {
    
    row <- zotero_publications[
      i,
    ]
    
    
    # ------------------------------------------------
    # GET EVERY DOI FROM EXTRA
    # ------------------------------------------------
    
    extra_dois <- extract_dois(
      row$Zotero_Extra
    )
    
    
    # ------------------------------------------------
    # REMOVE PAPER DOI ITSELF
    # ------------------------------------------------
    
    if (
      !is.na(
        row$Paper_DOI
      )
    ) {
      
      extra_dois <- extra_dois[
        extra_dois !=
          clean_doi(
            row$Paper_DOI
          )
      ]
    }
    
    
    # ------------------------------------------------
    # NO DATASET / RELATED DOI IN EXTRA
    #
    # KEEP THE PUBLICATION
    # ------------------------------------------------
    
    if (
      length(
        extra_dois
      ) == 0
    ) {
      
      return(
        
        tibble(
          
          Paper_Title =
            row$Paper_Title,
          
          Paper_Authors =
            row$Paper_Authors,
          
          Paper_DOI =
            clean_doi(
              row$Paper_DOI
            ),
          
          Dataset_DOI =
            NA_character_
        )
      )
    }
    
    
    # ------------------------------------------------
    # ONE ROW PER RELATED DOI
    # ------------------------------------------------
    
    tibble(
      
      Paper_Title =
        row$Paper_Title,
      
      Paper_Authors =
        row$Paper_Authors,
      
      Paper_DOI =
        clean_doi(
          row$Paper_DOI
        ),
      
      Dataset_DOI =
        extra_dois
    )
  }
)


# ================================================================
# 11. FINAL CLEAN TABLE
#
# ONE ROW PER PUBLICATION.
# Multiple related dataset DOIs are combined with "; ".
# ================================================================

zotero_citation_list <- zotero_related_dois %>%
  filter(
    !is.na(Paper_Title)
  ) %>%
  group_by(
    Paper_Title,
    Paper_Authors,
    Paper_DOI
  ) %>%
  summarise(
    Dataset_DOIs = {
      dois <- unique(
        Dataset_DOI[
          !is.na(Dataset_DOI) &
            Dataset_DOI != ""
        ]
      )
      if (length(dois) > 0) {
        paste(
          sort(dois),
          collapse = "; "
        )
      } else {
        NA_character_
      }
    },
    .groups = "drop"
  )


# ================================================================
# 11A. GET OPENALEX CITATION COUNTS
# ================================================================

cat(
  "\n========================================\n",
  "GETTING OPENALEX CITATION COUNTS\n",
  "========================================\n"
)

citation_count_date <- as.character(
  Sys.Date()
)

unique_paper_dois <- zotero_citation_list %>%
  filter(
    !is.na(Paper_DOI)
  ) %>%
  distinct(Paper_DOI)

citation_counts <- map_dfr(
  unique_paper_dois$Paper_DOI,
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
)

zotero_citation_list <- zotero_citation_list %>%
  left_join(
    citation_counts,
    by = "Paper_DOI"
  ) %>%
  mutate(
    Citation_Count_Date =
      citation_count_date
  ) %>%
  select(
    Paper_Title,
    Paper_Authors,
    Paper_DOI,
    Dataset_DOIs,
    Cited_By_Count,
    Citation_Count_Date
  ) %>%
  arrange(
    Paper_Title
  )


# ================================================================
# 12. SUMMARY
# ================================================================

cat(
  "\n========================================\n",
  "ZOTERO BLE CITATION SUMMARY\n",
  "========================================\n"
)


cat(
  "Unique publications:",
  n_distinct(
    zotero_citation_list$Paper_Title,
    na.rm = TRUE
  ),
  "\n"
)


cat(
  "Unique publications with paper DOI:",
  n_distinct(
    zotero_citation_list$Paper_DOI,
    na.rm = TRUE
  ),
  "\n"
)


cat(
  "Publications with one or more related dataset DOIs:",
  sum(
    !is.na(
      zotero_citation_list$Dataset_DOIs
    )
  ),
  "\n"
)


cat(
  "Publications with OpenAlex citation count:",
  sum(
    !is.na(
      zotero_citation_list$Cited_By_Count
    )
  ),
  "\n"
)


cat(
  "Citation count date:",
  citation_count_date,
  "\n"
)


cat(
  "Total output rows:",
  nrow(
    zotero_citation_list
  ),
  "\n"
)


# ================================================================
# 13. CREATE EXCEL
# ================================================================

wb <- createWorkbook()


addWorksheet(
  wb,
  "Zotero_Publications"
)


writeData(
  wb,
  "Zotero_Publications",
  zotero_citation_list
)


# ================================================================
# 14. FORMAT EXCEL
# ================================================================

header_style <- createStyle(
  textDecoration = "bold",
  border = "Bottom"
)


if (
  ncol(
    zotero_citation_list
  ) > 0
) {
  
  addStyle(
    
    wb,
    
    sheet =
      "Zotero_Publications",
    
    style =
      header_style,
    
    rows =
      1,
    
    cols =
      seq_len(
        ncol(
          zotero_citation_list
        )
      ),
    
    gridExpand =
      TRUE
  )
  
  
  freezePane(
    
    wb,
    
    sheet =
      "Zotero_Publications",
    
    firstRow =
      TRUE
  )
  
  
  setColWidths(
    
    wb,
    
    sheet =
      "Zotero_Publications",
    
    cols =
      seq_len(
        ncol(
          zotero_citation_list
        )
      ),
    
    widths =
      "auto"
  )
}


# ================================================================
# 15. SAVE
# ================================================================

saveWorkbook(
  
  wb,
  
  output_file,
  
  overwrite =
    TRUE
)


# ================================================================
# 16. FINAL MESSAGE
# ================================================================

cat(
  "\n========================================\n",
  "EXPORT COMPLETE\n",
  "========================================\n",
  "Saved as:\n",
  normalizePath(
    output_file,
    winslash = "/",
    mustWork = FALSE
  ),
  "\n",
  "========================================\n"
)
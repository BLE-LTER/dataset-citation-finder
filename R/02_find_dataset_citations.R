# ================================================================
# 02_find_dataset_citations.R
# PUBLICATION DISCOVERY AND PDF VERIFICATION
# ================================================================
#
# PURPOSE:
# Discover publications associated with dataset DOIs in Data_Registry.xlsx
# using DataCite and OpenAlex, then use site-specific keyword searches to
# find additional candidate papers and verify dataset references in PDFs
# when an OpenAlex PDF URL is available.
#
# INPUT:
# Citation_finder_output/Data_Registry.xlsx, created by
# R/01_get_dataset_dois.R.
#
# OPENALEX API KEY:
# OPENALEX_API_KEY is used for OpenAlex citation-graph, text, keyword,
# requests. This workflow makes many API requests;
# a free OpenAlex key provides a larger request budget and helps avoid
# rate-limit failures. Store the key in .Renviron, not in this script.
# The script can attempt keyless requests when no key is available, but
# results may be incomplete if OpenAlex rate limits are reached.
#
# OUTPUTS:
# Citation_finder_output/Publication_Search_Results.xlsx
#   Publication_Search  - metadata/API-discovered paper-dataset pairs.
#   PDF_Results         - papers discovered by site-keyword searches that
#                         were checked for an available PDF/full text.
#   Final_Relationships - union of Publication_Search relationships and
#                         additional exact dataset references confirmed
#                         during PDF verification.
#
# Citation_finder_output/openalex_cache.rds
#   Reused to reduce repeated OpenAlex requests on later runs.
#
# IMPORTANT COLUMN MEANINGS:
# Search_Source identifies the service that supplied relationship evidence
# (DataCite and/or OpenAlex). Search_Method describes the evidence method:
# Citation relationship, Exact relatedIdentifier, Citation graph,
# Dataset DOI text, or Final URL text.
#
# Discovery_Keyword is the configured site term that caused OpenAlex to
# return a paper as a PDF candidate. Matched_Site_Keyword is a configured
# site term actually found in the extracted PDF text. These can differ.
#
# WHY FINAL_RELATIONSHIPS CAN HAVE MORE ROWS:
# Publication_Search contains API/metadata discoveries. PDF verification
# can confirm an exact paper-dataset relationship that those API searches
# did not return, so Final_Relationships may legitimately contain more rows.
# The script reports how many relationships were added only by PDF checking.
#
# FILE BEHAVIOR:
# The output directory is defined in config.R. If it does not exist,
# this script announces and creates it. Existing output/cache files may be
# overwritten or updated. A completion message prints counts and file paths.
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

if (is.null(openalex_key)) {
  warning(
    paste0(
      "OPENALEX_API_KEY is not set. OpenAlex requests will be attempted without a key, ",
      "but this workflow makes many requests and may be rate limited. See README.md."
    ),
    call. = FALSE
  )
}


# ================================================================
# 1. SAFE EXCEL INPUT HELPER
# ================================================================
# SAFE EXCEL INPUT HELPER
# ================================================================
#
# Excel outputs are stored in Citation_finder_output. Files stored in
# cloud-synced or network folders can occasionally be locked or only
# partially available.
#
# This helper checks the workbook and creates a temporary local copy
# before openxlsx reads it.
# ================================================================
#

prepare_xlsx_for_read <- function(xlsx_file) {
  
  if (!file.exists(xlsx_file)) {
    stop(
      paste0(
        "Could not find ",
        xlsx_file,
        ". Run R/01_get_dataset_dois.R first. Expected file: ",
        xlsx_file
      )
    )
  }
  
  file_size <- file.info(xlsx_file)$size
  
  if (is.na(file_size) || file_size <= 0) {
    stop(
      paste0(
        xlsx_file,
        " exists but is empty or unavailable. ",
        "If it is stored in a cloud-synced or network folder, make sure it is available locally, ",
        "then rerun R/01_get_dataset_dois.R."
      )
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
        "Close the file in Excel and allow any file synchronization to finish, ",
        "delete the damaged copy if necessary, and rerun ",
        "R/01_get_dataset_dois.R to recreate it."
      )
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
      )
    )
  }
  
  local_copy
}


# ================================================================
# LOCAL HELPERS
# Functions shared across scripts are in R/utils.R.
# ================================================================

first_text <- function(x) {
  
  x <- x[
    !is.na(x) &
      x != ""
  ]
  
  if (
    length(x)
  ) {
    
    x[1]
    
  } else {
    
    NA_character_
  }
}


first_int <- function(x) {
  
  x <- x[
    !is.na(x)
  ]
  
  if (
    length(x)
  ) {
    
    as.integer(
      x[1]
    )
    
  } else {
    
    NA_integer_
  }
}


is_pub <- function(type) {
  
  type %in%
    c(
      "article",
      "review",
      "preprint",
      "book-chapter",
      "proceedings-article",
      "report"
    )
}


empty_search <- function() {
  
  tibble(
    
    Dataset_DOI =
      character(),
    
    Paper_DOI =
      character(),
    
    Paper_Title =
      character(),
    
    Year =
      integer(),
    
    Search_Source =
      character(),
    
    Search_Method =
      character()
  )
}


empty_candidate <- function() {
  
  tibble(
    
    Paper_Title =
      character(),
    
    Paper_DOI =
      character(),
    
    Year =
      integer(),
    
    Discovery_Keyword =
      character(),
    
    PDF_URL =
      character()
  )
}


# ================================================================
# 2. OPENALEX CACHE
# ================================================================

if (
  file.exists(
    cache_file
  )
) {
  
  oa_cache <- tryCatch(
    
    readRDS(
      cache_file
    ),
    
    error = function(e) {
      
      NULL
    }
  )
  
} else {
  
  oa_cache <- NULL
}


if (
  is.null(
    oa_cache
  ) ||
  !is.list(
    oa_cache
  )
) {
  
  oa_cache <- list(
    
    citation =
      list(),
    
    text =
      list(),
    
    keyword =
      list(),
    
    paper_metrics =
      list()
  )
}


for (
  x in c(
    "citation",
    "text",
    "keyword",
    "paper_metrics"
  )
) {
  
  if (
    is.null(
      oa_cache[[x]]
    )
  ) {
    
    oa_cache[[x]] <-
      list()
  }
}


oa_cached <- function(
    section,
    key,
    fun
) {
  
  if (
    key %in%
    names(
      oa_cache[[section]]
    )
  ) {
    
    cat(
      "OpenAlex CACHE: ",
      key,
      "\n",
      sep = ""
    )
    
    
    return(
      oa_cache[[section]][[key]]
    )
  }
  
  
  ans <- fun()
  
  
  if (
    isTRUE(
      ans$ok
    )
  ) {
    
    oa_cache[[section]][[key]] <<-
      ans$result
    
    
    saveRDS(
      oa_cache,
      cache_file
    )
  }
  
  
  ans$result
}


# OpenAlex request helpers shared across scripts are defined in R/utils.R.

oa_to_search <- function(
    results,
    dataset_doi,
    source,
    method
) {
  
  if (
    is.null(
      results
    ) ||
    !length(
      results
    )
  ) {
    
    return(
      empty_search()
    )
  }
  
  
  map_dfr(
    
    results,
    
    function(w) {
      
      if (
        !is_pub(
          safe(
            w$type
          )
        )
      ) {
        
        return(
          empty_search()
        )
      }
      
      
      pdoi <- clean_doi(
        safe(
          w$doi
        )
      )
      
      
      if (
        is.na(
          pdoi
        ) ||
        pdoi %in%
        master_data_registry$Dataset_DOI
      ) {
        
        return(
          empty_search()
        )
      }
      
      
      tibble(
        
        Dataset_DOI =
          dataset_doi,
        
        Paper_DOI =
          pdoi,
        
        Paper_Title =
          safe(
            w$title
          ),
        
        Year =
          suppressWarnings(
            as.integer(
              safe(
                w$publication_year
              )
            )
          ),
        
        Search_Source =
          source,
        
        Search_Method =
          method
      )
    }
  )
}


# ================================================================
# LOAD DATA REGISTRY CREATED BY:
# R/01_get_dataset_dois.R
# ================================================================

cat(
  "\n========================================\n",
  "LOADING DATA REGISTRY\n",
  "========================================\n"
)

data_registry_local <- prepare_xlsx_for_read(
  data_registry_file
)

cat(
  "Registry source: ",
  normalizePath(
    data_registry_file,
    winslash = "/",
    mustWork = TRUE
  ),
  "\n",
  sep = ""
)

cat(
  "Reading local copy: ",
  normalizePath(
    data_registry_local,
    winslash = "/",
    mustWork = TRUE
  ),
  "\n",
  sep = ""
)

registry_sheets <- tryCatch(
  openxlsx::getSheetNames(
    data_registry_local
  ),
  error = function(e) {
    stop(
      paste0(
        "The workbook could not be opened by openxlsx. ",
        "Rerun R/01_get_dataset_dois.R to recreate Data_Registry.xlsx.\n",
        "Original error: ",
        conditionMessage(e)
      )
    )
  }
)

if (!"Data_Registry" %in% registry_sheets) {
  stop(
    paste0(
      'The workbook does not contain a sheet named "Data_Registry". ',
      "Available sheets: ",
      paste(
        registry_sheets,
        collapse = ", "
      )
    )
  )
}

master_data_registry <- tryCatch(
  openxlsx::read.xlsx(
    data_registry_local,
    sheet = "Data_Registry"
  ),
  error = function(e) {
    stop(
      paste0(
        "Could not read the Data_Registry sheet. ",
        "Close the workbook in Excel and rerun R/01_get_dataset_dois.R if needed.\n",
        "Original error: ",
        conditionMessage(e)
      )
    )
  }
) %>%
  
  mutate(
    
    Scope = as.character(Scope),
    
    Identifier = as.character(Identifier),
    
    Revision =
      suppressWarnings(
        as.integer(
          Revision
        )
      ),
    
    Dataset_Title = as.character(Dataset_Title),
    
    Package_ID = as.character(Package_ID),
    
    Dataset_DOI =
      clean_doi(
        Dataset_DOI
      ),
    
    Registry_Source = as.character(Registry_Source),
    
    Registry_Category = as.character(Registry_Category),
    
    Zotero_Item_Key = as.character(Zotero_Item_Key),
    
    Final_URL = as.character(Final_URL)
  ) %>%
  
  filter(
    !is.na(Dataset_DOI)
  ) %>%
  
  distinct(
    Dataset_DOI,
    .keep_all = TRUE
  )


# ================================================================
# PUBLICATION DISCOVERY
# DATACITE AND OPENALEX METADATA SEARCH
# ================================================================

cat(
  "\n========================================\n",
  "PUBLICATION DISCOVERY - DATACITE + OPENALEX\n",
  "========================================\n"
)


# ================================================================
# DATACITE CITATION RELATIONSHIPS
# ================================================================

datacite_citations <- map_dfr(
  
  master_data_registry$Dataset_DOI,
  
  function(doi) {
    
    cat(
      "DataCite citation: ",
      doi,
      "\n",
      sep = ""
    )
    
    
    r <- get_json(
      
      paste0(
        
        "https://api.datacite.org/dois/",
        
        URLencode(
          doi,
          reserved = TRUE
        )
      )
    )
    
    
    if (
      !r$ok
    ) {
      
      return(
        empty_search()
      )
    }
    
    
    cites <- tryCatch(
      
      r$data$data$
        relationships$
        citations$
        data,
      
      error = function(e) {
        
        NULL
      }
    )
    
    
    if (
      is.null(
        cites
      )
    ) {
      
      return(
        empty_search()
      )
    }
    
    
    map_dfr(
      
      cites,
      
      function(x) {
        
        pdoi <- clean_doi(
          safe(
            x$id
          )
        )
        
        
        if (
          is.na(
            pdoi
          ) ||
          pdoi %in%
          master_data_registry$Dataset_DOI
        ) {
          
          return(
            empty_search()
          )
        }
        
        
        tibble(
          
          Dataset_DOI =
            doi,
          
          Paper_DOI =
            pdoi,
          
          Paper_Title =
            NA_character_,
          
          Year =
            NA_integer_,
          
          Search_Source =
            "DataCite",
          
          Search_Method =
            "Citation relationship"
        )
      }
    )
  }
)


# ================================================================
# DATACITE RELATED IDENTIFIER
# ================================================================

datacite_related <- map_dfr(
  
  master_data_registry$Dataset_DOI,
  
  function(doi) {
    
    cat(
      "DataCite relatedIdentifier: ",
      doi,
      "\n",
      sep = ""
    )
    
    
    r <- get_json(
      
      "https://api.datacite.org/dois",
      
      list(
        
        query =
          paste0(
            'relatedIdentifiers.relatedIdentifier:"',
            doi,
            '"'
          ),
        
        `page[size]` =
          100
      )
    )
    
    
    if (
      !r$ok ||
      is.null(
        r$data$data
      )
    ) {
      
      return(
        empty_search()
      )
    }
    
    
    map_dfr(
      
      r$data$data,
      
      function(x) {
        
        a <- x$attributes
        
        
        pdoi <- clean_doi(
          safe(
            a$doi
          )
        )
        
        
        type <- tolower(
          safe(
            a$types$resourceTypeGeneral,
            ""
          )
        )
        
        
        if (
          is.na(
            pdoi
          ) ||
          pdoi %in%
          master_data_registry$Dataset_DOI ||
          type %in%
          c(
            "dataset",
            "software",
            "collection",
            "workflow",
            "physicalobject",
            "model"
          )
        ) {
          
          return(
            empty_search()
          )
        }
        
        
        tibble(
          
          Dataset_DOI =
            doi,
          
          Paper_DOI =
            pdoi,
          
          Paper_Title =
            tryCatch(
              
              safe(
                a$titles[[1]]$title
              ),
              
              error = function(e) {
                
                NA_character_
              }
            ),
          
          Year =
            suppressWarnings(
              as.integer(
                safe(
                  a$publicationYear
                )
              )
            ),
          
          Search_Source =
            "DataCite",
          
          Search_Method =
            "Exact relatedIdentifier"
        )
      }
    )
  }
)


# ================================================================
# OPENALEX CITATION GRAPH
# ================================================================

openalex_citations <- map_dfr(
  
  master_data_registry$Dataset_DOI,
  
  function(doi) {
    
    cat(
      "OpenAlex citation graph: ",
      doi,
      "\n",
      sep = ""
    )
    
    
    oa_cached(
      
      "citation",
      
      doi,
      
      function() {
        
        lookup <- oa_query(
          
          list(
            
            filter =
              paste0(
                "doi:https://doi.org/",
                doi
              ),
            
            corpus =
              "all",
            
            per_page =
              1
          )
        )
        
        
        if (
          !lookup$ok
        ) {
          
          return(
            
            list(
              
              ok =
                FALSE,
              
              result =
                empty_search()
            )
          )
        }
        
        
        if (
          is.null(
            lookup$data$results
          ) ||
          !length(
            lookup$data$results
          )
        ) {
          
          return(
            
            list(
              
              ok =
                TRUE,
              
              result =
                empty_search()
            )
          )
        }
        
        
        oa_id <- basename(
          safe(
            lookup$data$results[[1]]$id
          )
        )
        
        
        cites <- oa_query(
          
          list(
            
            filter =
              paste0(
                "cites:",
                oa_id
              ),
            
            corpus =
              "all",
            
            per_page =
              100
          )
        )
        
        
        if (
          !cites$ok
        ) {
          
          return(
            
            list(
              
              ok =
                FALSE,
              
              result =
                empty_search()
            )
          )
        }
        
        
        list(
          
          ok =
            TRUE,
          
          result =
            oa_to_search(
              
              cites$data$results,
              
              doi,
              
              "OpenAlex",
              
              "Citation graph"
            )
        )
      }
    )
  }
)


# ================================================================
# OPENALEX DOI + DOI URL TEXT SEARCH
# ================================================================

openalex_text <- pmap_dfr(
  
  list(
    
    master_data_registry$Dataset_DOI,
    
    master_data_registry$Final_URL
  ),
  
  function(
    doi,
    url
  ) {
    
    searches <- tibble(
      
      Search_Method =
        c(
          "Dataset DOI text",
          "Final URL text"
        ),
      
      Search_Value =
        c(
          doi,
          url
        )
    ) %>%
      
      filter(
        !is.na(
          Search_Value
        ),
        Search_Value != ""
      )
    
    
    map_dfr(
      
      seq_len(
        nrow(
          searches
        )
      ),
      
      function(i) {
        
        method <-
          searches$Search_Method[i]
        
        value <-
          searches$Search_Value[i]
        
        
        key <- paste(
          
          doi,
          
          method,
          
          tolower(
            value
          ),
          
          sep = "||"
        )
        
        
        oa_cached(
          
          "text",
          
          key,
          
          function() {
            
            r <- oa_query(
              
              list(
                
                search =
                  paste0(
                    '"',
                    value,
                    '"'
                  ),
                
                corpus =
                  "all",
                
                per_page =
                  100
              )
            )
            
            
            if (
              !r$ok
            ) {
              
              return(
                
                list(
                  
                  ok =
                    FALSE,
                  
                  result =
                    empty_search()
                )
              )
            }
            
            
            list(
              
              ok =
                TRUE,
              
              result =
                oa_to_search(
                  
                  r$data$results,
                  
                  doi,
                  
                  "OpenAlex",
                  
                  method
                )
            )
          }
        )
      }
    )
  }
)


# ================================================================
# INTERNAL API/METADATA RELATIONSHIPS
# ================================================================

api_relationships <- bind_rows(
  
  datacite_citations,
  
  datacite_related,
  
  openalex_citations,
  
  openalex_text
  
) %>%
  
  mutate(
    
    Dataset_DOI =
      clean_doi(
        Dataset_DOI
      ),
    
    Paper_DOI =
      clean_doi(
        Paper_DOI
      )
  ) %>%
  
  filter(
    
    !is.na(
      Paper_DOI
    ),
    
    !is.na(
      Dataset_DOI
    ),
    
    !Paper_DOI %in%
      master_data_registry$Dataset_DOI
  ) %>%
  
  distinct(
    
    Dataset_DOI,
    
    Paper_DOI,
    
    Search_Source,
    
    Search_Method,
    
    .keep_all =
      TRUE
  )


# ================================================================
# FILL TITLE / YEAR FROM DUPLICATE RESULTS
# ================================================================

api_relationships <- api_relationships %>%
  
  group_by(
    Paper_DOI
  ) %>%
  
  mutate(
    
    Paper_Title =
      first_text(
        Paper_Title
      ),
    
    Year =
      first_int(
        Year
      )
  ) %>%
  
  ungroup()


# ================================================================
# CROSSREF FALLBACK FOR MISSING PAPER METADATA
# ================================================================

missing_meta <- api_relationships %>%
  
  filter(
    
    is.na(
      Paper_Title
    ) |
      is.na(
        Year
      )
  ) %>%
  
  distinct(
    Paper_DOI
  ) %>%
  
  pull(
    Paper_DOI
  )


if (
  length(
    missing_meta
  )
) {
  
  meta <- map_dfr(
    
    missing_meta,
    
    function(doi) {
      
      r <- get_json(
        
        paste0(
          
          "https://api.crossref.org/works/",
          
          URLencode(
            doi,
            reserved = TRUE
          )
        )
      )
      
      
      if (
        !r$ok
      ) {
        
        return(
          
          tibble(
            
            Paper_DOI =
              doi,
            
            Lookup_Title =
              NA_character_,
            
            Lookup_Year =
              NA_integer_
          )
        )
      }
      
      
      tibble(
        
        Paper_DOI =
          doi,
        
        Lookup_Title =
          tryCatch(
            
            safe(
              r$data$message$title[[1]]
            ),
            
            error = function(e) {
              
              NA_character_
            }
          ),
        
        Lookup_Year =
          tryCatch(
            
            as.integer(
              r$data$message$
                published$
                `date-parts`[[1]][1]
            ),
            
            error = function(e) {
              
              NA_integer_
            }
          )
      )
    }
  )
  
  
  api_relationships <- api_relationships %>%
    
    left_join(
      
      meta,
      
      by =
        "Paper_DOI"
    ) %>%
    
    mutate(
      
      Paper_Title =
        coalesce(
          Paper_Title,
          Lookup_Title
        ),
      
      Year =
        coalesce(
          Year,
          Lookup_Year
        )
    ) %>%
    
    select(
      -Lookup_Title,
      -Lookup_Year
    )
}


# ================================================================
# ADD DATASET INFORMATION
# ================================================================

api_relationships <- api_relationships %>%
  
  left_join(
    
    master_data_registry %>%
      
      select(
        
        Dataset_DOI,
        
        Dataset_Title,
        
        Package_ID,
        
        Final_URL,
        
        Registry_Source
      ),
    
    by =
      "Dataset_DOI"
  )


# ================================================================
# TAB 2
# PUBLICATION SEARCH
#
# ONE ROW PER:
# PAPER DOI + DATASET DOI
# ================================================================

publication_search <- api_relationships %>%
  
  group_by(
    Paper_DOI,
    Dataset_DOI
  ) %>%
  
  summarise(
    
    Paper_Title =
      first_text(
        Paper_Title
      ),
    
    Year =
      first_int(
        Year
      ),
    
    Dataset_Package_ID =
      first_text(
        Package_ID
      ),
    
    Dataset_Title =
      first_text(
        Dataset_Title
      ),
    
    Search_Source = {
      
      sources <- unique(
        
        Search_Source[
          !is.na(
            Search_Source
          ) &
            Search_Source != ""
        ]
      )
      
      
      preferred_order <- c(
        "DataCite",
        "OpenAlex"
      )
      
      
      sources <- preferred_order[
        preferred_order %in%
          sources
      ]
      
      
      paste(
        sources,
        collapse = " + "
      )
    },
    
    
    Search_Method = {
      
      methods <- unique(
        
        Search_Method[
          !is.na(
            Search_Method
          ) &
            Search_Method != ""
        ]
      )
      
      
      paste(
        sort(
          methods
        ),
        collapse = "; "
      )
    },
    
    
    .groups =
      "drop"
  ) %>%
  
  select(
    
    Paper_DOI,
    
    Paper_Title,
    
    Year,
    
    Dataset_Package_ID,
    
    Dataset_DOI,
    
    Dataset_Title,
    
    Search_Source,
    
    Search_Method
  ) %>%
  
  arrange(
    
    desc(
      Year
    ),
    
    Paper_Title,
    
    Dataset_Package_ID,
    
    Dataset_DOI
  )


# ================================================================
# INTERNAL UNIQUE PAPER-DATASET RELATIONSHIPS
# ================================================================

api_unique <- api_relationships %>%
  
  group_by(
    Dataset_DOI,
    Paper_DOI
  ) %>%
  
  summarise(
    
    Paper_Title =
      first_text(
        Paper_Title
      ),
    
    Year =
      first_int(
        Year
      ),
    
    Found_By =
      paste(
        
        unique(
          
          paste(
            Search_Source,
            Search_Method,
            sep = ": "
          )
        ),
        
        collapse = " + "
      ),
    
    .groups =
      "drop"
  )


# ================================================================
# KEYWORD DISCOVERY + PDF FULL-TEXT VERIFICATION
# ================================================================

cat(
  "\n========================================\n",
  "KEYWORD + PDF FULL-TEXT VERIFICATION\n",
  "========================================\n"
)


keyword_raw <- map_dfr(
  
  site_keywords,
  
  function(keyword) {
    
    cat(
      "OpenAlex keyword: ",
      keyword,
      "\n",
      sep = ""
    )
    
    
    key <- paste0(
      "pdf_discovery||",
      tolower(
        keyword
      )
    )
    
    
    oa_cached(
      
      "keyword",
      
      key,
      
      function() {
        
        r <- oa_query(
          
          list(
            
            search =
              paste0(
                '"',
                keyword,
                '"'
              ),
            
            per_page =
              100
          )
        )
        
        
        if (
          !r$ok
        ) {
          
          return(
            
            list(
              
              ok =
                FALSE,
              
              result =
                empty_candidate()
            )
          )
        }
        
        
        out <- map_dfr(
          
          r$data$results,
          
          function(w) {
            
            if (
              !is_pub(
                safe(
                  w$type
                )
              )
            ) {
              
              return(
                empty_candidate()
              )
            }
            
            
            pdoi <- clean_doi(
              safe(
                w$doi
              )
            )
            
            
            if (
              is.na(
                pdoi
              ) ||
              pdoi %in%
              master_data_registry$Dataset_DOI
            ) {
              
              return(
                empty_candidate()
              )
            }
            
            
            pdf <- tryCatch(
              
              safe(
                w$best_oa_location$pdf_url
              ),
              
              error = function(e) {
                
                NA_character_
              }
            )
            
            
            if (
              is.na(
                pdf
              )
            ) {
              
              pdf <- tryCatch(
                
                safe(
                  w$primary_location$pdf_url
                ),
                
                error = function(e) {
                  
                  NA_character_
                }
              )
            }
            
            
            tibble(
              
              Paper_Title =
                safe(
                  w$title
                ),
              
              Paper_DOI =
                pdoi,
              
              Year =
                suppressWarnings(
                  as.integer(
                    safe(
                      w$publication_year
                    )
                  )
                ),
              
              Discovery_Keyword =
                keyword,
              
              PDF_URL =
                pdf
            )
          }
        )
        
        
        list(
          
          ok =
            TRUE,
          
          result =
            out
        )
      }
    )
  }
)


# ================================================================
# ONE KEYWORD CANDIDATE PER PAPER
#
# IMPORTANT:
# We keep papers even if they already appear in Publication_Search.
# This allows PDF verification to act independently.
# ================================================================

keyword_candidates <- keyword_raw %>%
  
  group_by(
    Paper_DOI
  ) %>%
  
  summarise(
    
    Paper_Title =
      first_text(
        Paper_Title
      ),
    
    Year =
      first_int(
        Year
      ),
    
    Discovery_Keyword =
      paste(
        
        unique(
          Discovery_Keyword
        ),
        
        collapse = "; "
      ),
    
    PDF_URL =
      first_text(
        PDF_URL
      ),
    
    .groups =
      "drop"
  )


# ================================================================
# PDF TO MARKDOWN-LIKE TEXT
# ================================================================

pdf_to_markdown <- function(
    pdf,
    md
) {
  
  pages <- tryCatch(
    
    pdftools::pdf_text(
      pdf
    ),
    
    error = function(e) {
      
      NULL
    }
  )
  
  
  if (
    is.null(
      pages
    ) ||
    !length(
      pages
    )
  ) {
    
    return(
      FALSE
    )
  }
  
  
  writeLines(
    
    map_chr(
      
      seq_along(
        pages
      ),
      
      ~ paste0(
        
        "\n# Page ",
        .x,
        "\n\n",
        
        pages[[.x]],
        
        "\n"
      )
    ),
    
    md
  )
  
  
  TRUE
}


# ================================================================
# SEARCH COMPLETE EXTRACTED PDF TEXT
# ================================================================

search_pdf_text <- function(md) {
  
  txt <- tolower(
    
    paste(
      
      readLines(
        md,
        warn = FALSE
      ),
      
      collapse = "\n"
    )
  )
  
  
  # Remove spaces/newlines for DOI matching
  compact <- str_replace_all(
    txt,
    "\\s+",
    ""
  )
  
  
  # ------------------------------------------------
  # WHICH SITE KEYWORDS APPEAR IN THE ACTUAL PDF?
  # ------------------------------------------------
  
  matched_keywords <- site_keywords[
    
    map_lgl(
      
      site_keywords,
      
      ~ str_detect(
        
        txt,
        
        fixed(
          tolower(
            .x
          )
        )
      )
    )
  ]
  
  
  keyword_match <- if (
    length(
      matched_keywords
    )
  ) {
    
    paste(
      
      unique(
        matched_keywords
      ),
      
      collapse = "; "
    )
    
  } else {
    
    NA_character_
  }
  
  
  # ------------------------------------------------
  # SEARCH EVERY DATASET DOI / DOI URL
  # ------------------------------------------------
  
  hits <- map_dfr(
    
    seq_len(
      nrow(
        master_data_registry
      )
    ),
    
    function(i) {
      
      doi <-
        master_data_registry$
        Dataset_DOI[i]
      
      
      url <- safe(
        master_data_registry$
          Final_URL[i]
      )
      
      
      doi_hit <-
        !is.na(
          doi
        ) &&
        doi != "" &&
        str_detect(
          
          compact,
          
          fixed(
            
            str_replace_all(
              
              tolower(
                doi
              ),
              
              "\\s+",
              
              ""
            )
          )
        )
      
      
      url_hit <-
        !is.na(
          url
        ) &&
        url != "" &&
        str_detect(
          
          compact,
          
          fixed(
            
            str_replace_all(
              
              tolower(
                url
              ),
              
              "\\s+",
              
              ""
            )
          )
        )
      
      
      if (
        !doi_hit &&
        !url_hit
      ) {
        
        return(
          tibble()
        )
      }
      
      
      tibble(
        
        Dataset_DOI =
          doi,
        
        Dataset_Title =
          master_data_registry$
          Dataset_Title[i],
        
        Matched_Dataset_Reference =
          case_when(
            
            doi_hit &
              url_hit ~
              "Dataset DOI + Final URL",
            
            doi_hit ~
              "Dataset DOI",
            
            TRUE ~
              "Final URL"
          )
      )
    }
  )
  
  
  list(
    
    keyword_match =
      keyword_match,
    
    hits =
      hits
  )
}


# ================================================================
# VERIFY ONE PDF
# ================================================================

verify_pdf <- function(
    title,
    pdoi,
    year,
    discovery_keyword,
    pdf_url
) {
  
  base_row <- function(
    status,
    keyword = NA_character_,
    dataset_doi = NA_character_,
    dataset_title = NA_character_,
    ref = NA_character_
  ) {
    
    tibble(
      
      Paper_Title =
        title,
      
      Paper_DOI =
        clean_doi(
          pdoi
        ),
      
      Year =
        suppressWarnings(
          as.integer(
            year
          )
        ),
      
      Discovery_Keyword =
        discovery_keyword,
      
      Matched_Site_Keyword =
        keyword,
      
      Dataset_DOI =
        dataset_doi,
      
      Dataset_Title =
        dataset_title,
      
      Matched_Dataset_Reference =
        ref,
      
      PDF_URL =
        pdf_url,
      
      PDF_Status =
        status
    )
  }
  
  
  # ------------------------------------------------
  # NO PDF URL
  # ------------------------------------------------
  
  if (
    is.na(
      pdf_url
    ) ||
    pdf_url == ""
  ) {
    
    return(
      
      base_row(
        "No direct OA PDF URL"
      )
    )
  }
  
  
  id <- paste0(
    
    "citation_",
    
    format(
      Sys.time(),
      "%Y%m%d%H%M%S"
    ),
    
    "_",
    
    sample(
      100000:999999,
      1
    )
  )
  
  
  pdf <- file.path(
    tempdir(),
    paste0(
      id,
      ".pdf"
    )
  )
  
  
  md <- file.path(
    tempdir(),
    paste0(
      id,
      ".md"
    )
  )
  
  
  # ------------------------------------------------
  # DELETE TEMP FILES AFTER CHECK
  # ------------------------------------------------
  
  on.exit(
    {
      
      if (
        file.exists(
          pdf
        )
      ) {
        
        file.remove(
          pdf
        )
      }
      
      
      if (
        file.exists(
          md
        )
      ) {
        
        file.remove(
          md
        )
      }
      
    },
    
    add =
      TRUE
  )
  
  
  # ------------------------------------------------
  # DOWNLOAD PDF
  # ------------------------------------------------
  
  download_info <- tryCatch(
    
    {
      
      r <- GET(
        
        pdf_url,
        
        write_disk(
          pdf,
          overwrite = TRUE
        ),
        
        timeout(
          120
        ),
        
        user_agent(
          "LTER-dataset-citation-verification"
        )
      )
      
      
      content_type <-
        headers(
          r
        )[["content-type"]]
      
      
      list(
        
        success =
          status_code(
            r
          ) == 200,
        
        content_type =
          safe(
            content_type,
            ""
          )
      )
      
    },
    
    error = function(e) {
      
      list(
        
        success =
          FALSE,
        
        content_type =
          ""
      )
    }
  )
  
  
  if (
    !download_info$success ||
    !file.exists(
      pdf
    )
  ) {
    
    return(
      
      base_row(
        "PDF download failed"
      )
    )
  }
  
  
  # ------------------------------------------------
  # CHECK IF SERVER CLEARLY RETURNED HTML
  # ------------------------------------------------
  
  if (
    str_detect(
      tolower(
        download_info$content_type
      ),
      "text/html"
    )
  ) {
    
    return(
      
      base_row(
        "PDF URL returned HTML, not PDF"
      )
    )
  }
  
  
  # ------------------------------------------------
  # CHECK PDF VALIDITY
  # ------------------------------------------------
  
  valid <- tryCatch(
    
    {
      
      suppressMessages(
        pdftools::pdf_info(
          pdf
        )
      )
      
      TRUE
    },
    
    error = function(e) {
      
      FALSE
    }
  )
  
  
  if (
    !valid
  ) {
    
    return(
      
      base_row(
        "Downloaded URL is not a readable PDF"
      )
    )
  }
  
  
  # ------------------------------------------------
  # EXTRACT FULL PDF TEXT
  # ------------------------------------------------
  
  if (
    !pdf_to_markdown(
      pdf,
      md
    )
  ) {
    
    return(
      
      base_row(
        "PDF text extraction failed"
      )
    )
  }
  
  
  # ------------------------------------------------
  # SEARCH COMPLETE EXTRACTED TEXT
  # ------------------------------------------------
  
  m <- search_pdf_text(
    md
  )
  
  
  # ------------------------------------------------
  # KEYWORD MAY MATCH BUT NO DATASET DOI
  # ------------------------------------------------
  
  if (
    !nrow(
      m$hits
    )
  ) {
    
    return(
      
      base_row(
        
        "PDF searched: keyword may match, but no exact dataset DOI/final URL",
        
        keyword =
          m$keyword_match
      )
    )
  }
  
  
  # ------------------------------------------------
  # CONFIRMED DATASET MATCH
  # ------------------------------------------------
  
  m$hits %>%
    
    transmute(
      
      Paper_Title =
        title,
      
      Paper_DOI =
        clean_doi(
          pdoi
        ),
      
      Year =
        suppressWarnings(
          as.integer(
            year
          )
        ),
      
      Discovery_Keyword =
        discovery_keyword,
      
      Matched_Site_Keyword =
        m$keyword_match,
      
      Dataset_DOI,
      
      Dataset_Title,
      
      Matched_Dataset_Reference,
      
      PDF_URL =
        pdf_url,
      
      PDF_Status =
        "Confirmed: exact dataset DOI/final URL found"
    )
}


# ================================================================
# RUN PDF CHECK
# ================================================================

pdf_results <- if (
  nrow(
    keyword_candidates
  )
) {
  
  pmap_dfr(
    
    list(
      
      keyword_candidates$
        Paper_Title,
      
      keyword_candidates$
        Paper_DOI,
      
      keyword_candidates$
        Year,
      
      keyword_candidates$
        Discovery_Keyword,
      
      keyword_candidates$
        PDF_URL
    ),
    
    verify_pdf
  )
  
} else {
  
  tibble(
    
    Paper_Title =
      character(),
    
    Paper_DOI =
      character(),
    
    Year =
      integer(),
    
    Discovery_Keyword =
      character(),
    
    Matched_Site_Keyword =
      character(),
    
    Dataset_DOI =
      character(),
    
    Dataset_Title =
      character(),
    
    Matched_Dataset_Reference =
      character(),
    
    PDF_URL =
      character(),
    
    PDF_Status =
      character()
  )
}


# ================================================================
# PDF CONFIRMED RELATIONSHIPS
# ================================================================

pdf_confirmed <- pdf_results %>%
  
  filter(
    !is.na(
      Dataset_DOI
    )
  ) %>%
  
  transmute(
    
    Dataset_DOI =
      clean_doi(
        Dataset_DOI
      ),
    
    Paper_DOI =
      clean_doi(
        Paper_DOI
      ),
    
    Paper_Title,
    
    Year,
    
    Found_By =
      paste0(
        "PDF: ",
        Matched_Dataset_Reference
      )
  )


# ================================================================
# FINAL INTERNAL PAPER-DATASET RELATIONSHIPS
# ================================================================

final_publication_relationships <- bind_rows(
  
  api_unique,
  
  pdf_confirmed
  
) %>%
  
  mutate(
    
    Dataset_DOI =
      clean_doi(
        Dataset_DOI
      ),
    
    Paper_DOI =
      clean_doi(
        Paper_DOI
      )
  ) %>%
  
  filter(
    
    !is.na(
      Paper_DOI
    ),
    
    !is.na(
      Dataset_DOI
    )
  ) %>%
  
  group_by(
    Dataset_DOI,
    Paper_DOI
  ) %>%
  
  summarise(
    
    Paper_Title =
      first_text(
        Paper_Title
      ),
    
    Year =
      first_int(
        Year
      ),
    
    Found_By =
      paste(
        
        unique(
          Found_By
        ),
        
        collapse =
          " + "
      ),
    
    .groups =
      "drop"
  )

# ================================================================
# RELATIONSHIPS ADDED ONLY BY PDF VERIFICATION
# ================================================================

pdf_only_relationships <- final_publication_relationships %>%
  dplyr::anti_join(
    publication_search %>%
      dplyr::distinct(Paper_DOI, Dataset_DOI),
    by = c("Paper_DOI", "Dataset_DOI")
  )


if (nrow(pdf_only_relationships) > 0) {
  cat(
    "\nRelationships added only by PDF verification:\n"
  )
  print(
    pdf_only_relationships %>%
      dplyr::select(Paper_DOI, Dataset_DOI, Paper_Title, Found_By)
  )
}


# ================================================================
# SAVE PUBLICATION SEARCH RESULTS
# ================================================================

openxlsx::write.xlsx(
  list(
    Publication_Search = publication_search,
    PDF_Results = pdf_results,
    Final_Relationships = final_publication_relationships
  ),
  file = publication_results_file,
  overwrite = TRUE
)

cat(
  "\n========================================\n",
  "PUBLICATION SEARCH + PDF CHECK COMPLETE\n",
  "========================================\n",
  "Saved results: ", publication_results_file, "\n",
  "Publication-search relationships: ", nrow(publication_search), "\n",
  "PDF candidates checked: ", n_distinct(pdf_results$Paper_DOI), "\n",
  "Relationships added only by PDF verification: ", nrow(pdf_only_relationships), "\n",
  "Final paper-dataset relationships: ", nrow(final_publication_relationships), "\n",
  "========================================\n"
)

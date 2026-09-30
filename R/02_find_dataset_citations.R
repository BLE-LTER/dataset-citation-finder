# ================================================================
# 02_find_dataset_citations.R
# DATASET CITATION DISCOVERY, CONSOLIDATION, AND CURATION REPORTS
# ================================================================
#
# Read Data_Registry.xlsx from output_dir (config.R). Search DataCite and
# OpenAlex and verify exact dataset references in keyword-discovered PDFs.
# Optionally retrieve EDI journal citations and dataset DOIs recorded in
# the Extra field of publications in the configured Zotero collection.
#
# OUTPUT: Publication_Search_Results.xlsx
#   DataCite_Citations          - DataCite/OpenAlex DOI relationships.
#   PDF_Citations               - keyword candidates and PDF check outcomes.
#   EDI_Citations               - optional EDI records, including unresolved
#                                 packages and records without a paper DOI.
#   Zotero_Citations            - optional Extra-field dataset DOI matches.
#   Combined_Results            - one publication-dataset citation per row.
#   Result_Counts               - citations per registry dataset/series,
#                                 including datasets with zero citations.
#   Missing_From_Zotero         - optional papers absent from the collection.
#   Zotero_Missing_Data_DOI     - optional missing Extra-field dataset links.
#   EDI_Missing_Links           - optional missing EDI journal citations.
#   Zotero_Revision_Mismatches / EDI_Revision_Mismatches
#                               - optional revision review, in series mode.
#
# deduplicate_on_dataset_id = TRUE groups each paper's EDI dataset links
# by scope + identifier. Select a revision from DataCite, then Zotero, then
# EDI; fall back to OpenAlex, then PDF. FALSE groups by exact dataset DOI.
# Source sheets retain revision-level evidence in both modes. Non-EDI
# datasets always match by DOI. Review sheets include the recommended
# dataset DOI and package ID; no EDI or Zotero records are changed.
#
# EDI requires edi_scope and EDI_API_KEY. Zotero retrieval requires both
# zotero_group_id and zotero_publication_collection_id and a public group.
# OPENALEX_API_KEY is recommended. Store keys in .Renviron. No publication
# citation counts or standalone publication-list reports are generated.
#
# OpenAlex responses are cached in openalex_cache.rds, subject to
# cache_max_age_days. EDI and Zotero are retrieved afresh on each run.
# Existing output/cache files may be overwritten. See README.md for the
# worksheet columns, matching rules, limitations, and setup instructions.
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

is_configured <- function(x) {
  length(x) == 1L && !is.na(x) && nzchar(trimws(as.character(x)))
}
if (!is.logical(deduplicate_on_dataset_id) || length(deduplicate_on_dataset_id) != 1L ||
    is.na(deduplicate_on_dataset_id)) {
  stop("deduplicate_on_dataset_id in config.R must be TRUE or FALSE.", call. = FALSE)
}
has_edi <- is_configured(edi_scope)
has_zotero <- is_configured(zotero_group_id) && is_configured(zotero_publication_collection_id)
if (has_edi && !is_configured(edi_key)) {
  stop("edi_scope is set, but EDI_API_KEY is missing. Add it to .Renviron, or clear edi_scope to skip EDI.",
       call. = FALSE)
}
if (!has_edi) message("EDI citations and EDI review sheets are disabled (edi_scope is blank).")
if (!has_zotero) {
  message("Zotero citations and Zotero review sheets are disabled: set both zotero_group_id and zotero_publication_collection_id to enable them.")
}

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
# LOCAL HELPERS
# Functions shared across scripts, including prepare_xlsx_for_read(),
# are in R/utils.R.
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
get_publication_type <- function(paper_doi) {
  
  if (is.na(paper_doi) || paper_doi == "") {
    return(NA_character_)
  }
  
  r <- get_json(
    paste0(
      "https://api.crossref.org/works/",
      URLencode(
        paper_doi,
        reserved = TRUE
      )
    )
  )
  
  # Crossref request failed
  if (!r$ok) {
    return(NA_character_)
  }
  
  # Safely retrieve publication type
  publication_type <- tryCatch(
    r$data$message$type,
    error = function(e) NA_character_
  )
  
  # Handle missing type
  if (
    is.null(publication_type) ||
    length(publication_type) == 0 ||
    is.na(publication_type[1]) ||
    publication_type[1] == ""
  ) {
    return(NA_character_)
  }
  
  publication_type <- publication_type[1]
  
  # Convert Crossref type to readable label
  dplyr::case_when(
    
    publication_type == "journal-article" ~
      "Journal Article",
    
    publication_type == "posted-content" ~
      "Preprint",
    
    publication_type == "proceedings-article" ~
      "Conference Paper",
    
    publication_type == "book-chapter" ~
      "Book Chapter",
    
    publication_type == "book" ~
      "Book",
    
    publication_type == "dissertation" ~
      "Dissertation",
    
    TRUE ~
      publication_type
  )
}

# ================================================================
# 1. OPENALEX CACHE
# ================================================================
#
# OpenAlex responses are saved to the cache file set in config.R and
# reused on later runs, so repeating the workflow does not repeat every
# request. Each entry records when it was fetched, and oa_cached() below
# reuses an entry only while it is younger than cache_max_age_days
# (config.R). Older entries are requested again, because OpenAlex keeps
# indexing new papers and a cached answer goes out of date.
#
# Only successful responses are cached, so a rate-limited or failed
# request is never stored as an empty answer. If a re-fetch fails, the
# expired copy is reused and a warning is issued.
#
# A cache file written before entries carried a fetch time still loads;
# its entries count as expired and are refreshed once, after which they
# are stored in the current format. Deleting the cache file forces a
# complete re-fetch.
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
  
  entry <- oa_cache[[section]][[key]]
  
  
  # cache_max_age_days is set in config.R. The default covers an older
  # config.R that predates this setting.
  max_age_days <- get0(
    "cache_max_age_days",
    ifnotfound = 60,
    inherits = TRUE
  )
  
  
  # Entries are stored as list(fetched = <time>, value = <result>).
  # Anything else came from a cache file written before expiry existed,
  # has no fetch time, and is therefore treated as expired.
  timestamped <- is.list(entry) &&
    !is.data.frame(entry) &&
    all(
      c("fetched", "value") %in% names(entry)
    )
  
  
  fresh <- timestamped &&
    as.numeric(
      difftime(
        Sys.time(),
        entry$fetched,
        units = "days"
      )
    ) < max_age_days
  
  
  if (fresh) {
    
    cat(
      "OpenAlex CACHE: ",
      key,
      "\n",
      sep = ""
    )
    
    
    return(
      entry$value
    )
  }
  
  
  if (
    !is.null(entry)
  ) {
    
    cat(
      "OpenAlex CACHE EXPIRED, re-fetching: ",
      key,
      "\n",
      sep = ""
    )
  }
  
  
  ans <- fun()
  
  
  if (
    isTRUE(
      ans$ok
    )
  ) {
    
    oa_cache[[section]][[key]] <<- list(
      fetched = Sys.time(),
      value = ans$result
    )
    
    
    saveRDS(
      oa_cache,
      cache_file
    )
    
    
    return(
      ans$result
    )
  }
  
  
  # The request failed. An out-of-date answer is more useful than an
  # empty one, so reuse the expired copy and say so.
  if (
    !is.null(entry)
  ) {
    
    warning(
      "OpenAlex request failed for ",
      key,
      ". Using the expired cached copy.",
      call. = FALSE
    )
    
    
    return(
      if (timestamped) entry$value else entry
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
# 2. LOAD DATA REGISTRY CREATED BY:
# R/01_get_dataset_dois.R
# ================================================================

cat(
  "\n========================================\n",
  "LOADING DATA REGISTRY\n",
  "========================================\n"
)

data_registry_local <- prepare_xlsx_for_read(
  data_registry_file,
  created_by = "R/01_get_dataset_dois.R"
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
# 3. PUBLICATION DISCOVERY
# DATACITE AND OPENALEX METADATA SEARCH
# ================================================================

cat(
  "\n========================================\n",
  "PUBLICATION DISCOVERY - DATACITE + OPENALEX\n",
  "========================================\n"
)


# ================================================================
# 4. DATACITE CITATION RELATIONSHIPS
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
# 5. DATACITE RELATED IDENTIFIER
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
# 6. OPENALEX CITATION GRAPH
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
# 7. OPENALEX DOI + DOI URL TEXT SEARCH
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
# 8. INTERNAL API/METADATA RELATIONSHIPS
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
# 9. FILL TITLE / YEAR FROM DUPLICATE RESULTS
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
# 10. CROSSREF FALLBACK FOR MISSING PAPER METADATA
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
# 11. ADD DATASET INFORMATION
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
# 12. OUTPUT SHEET: DATACITE_CITATIONS
# ================================================================
#
# One row per Paper_DOI + Dataset_DOI found by the DataCite and OpenAlex
# searches above. This table is written to the DataCite_Citations
# worksheet of Publication_Search_Results.xlsx.
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
# 13. INTERNAL UNIQUE PAPER-DATASET RELATIONSHIPS
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
# 14. KEYWORD DISCOVERY + PDF FULL-TEXT VERIFICATION
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
# 15. ONE KEYWORD CANDIDATE PER PAPER
#
# IMPORTANT:
# We keep papers even if they already appear in DataCite_Citations.
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
# 16. PDF TO MARKDOWN-LIKE TEXT
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
# 17. SEARCH COMPLETE EXTRACTED PDF TEXT
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
# 18. VERIFY ONE PDF
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
# 19. OUTPUT SHEET: PDF_CITATIONS
# ================================================================
#
# Checks each keyword-discovered candidate paper. Every candidate gets a
# row, including candidates with no reachable PDF, so PDF_Status explains
# what happened. This is written to the PDF_Citations worksheet.
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
# 20. PDF CONFIRMED RELATIONSHIPS
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
# 21. EDI JOURNAL CITATIONS (OPTIONAL)
# ================================================================

citation_registry <- prepare_citation_registry(master_data_registry)
edi_registry <- citation_registry %>%
  filter(!is.na(Dataset_Series_ID),
         startsWith(Dataset_Series_ID, paste0(edi_scope, ".")))

empty_edi_citations <- function() {
  tibble(Query_Package_ID = character(), EDI_Package_ID = character(),
         Dataset_Series_ID = character(), EDI_Citation_ID = character(),
         Paper_DOI = character(), EDI_Paper_Title = character(),
         EDI_Article_URL = character(), Dataset_DOI = character(),
         Dataset_Title = character(), Mapping_Status = character())
}

get_edi_citations <- function() {
  # Keep typed columns even when the configured scope has no registry rows.
  if (!nrow(edi_registry)) return(empty_edi_citations())
  series <- edi_registry %>%
    arrange(Dataset_Package_ID) %>%
    distinct(Dataset_Series_ID, .keep_all = TRUE)

  EDIutils::login(key = edi_key)
  on.exit(try(EDIutils::logout(), silent = TRUE), add = TRUE)
  rows <- map(seq_len(nrow(series)), function(i) {
    query_package <- series$Dataset_Package_ID[i]
    cat("EDI citations: ", query_package, " (", i, "/", nrow(series), ")\n", sep = "")
    citations <- tryCatch(
      EDIutils::list_data_package_citations(
        packageId = query_package, as = "data.frame", list_all = TRUE,
        env = "production"
      ),
      error = function(e) stop(
        "EDI retrieval failed for ", query_package, ": ", conditionMessage(e),
        "\nCannot produce a complete EDI comparison. Retry Step 02 later.", call. = FALSE
      )
    )
    if (is.null(citations) || !nrow(citations)) return(empty_edi_citations())
    map_edi_citations(citations, citation_registry, query_package)
  })
  bind_rows(empty_edi_citations(), bind_rows(rows)) %>%
    distinct(EDI_Citation_ID, EDI_Package_ID, Paper_DOI, .keep_all = TRUE)
}

edi_citations <- if (has_edi) get_edi_citations() else empty_edi_citations()

# ================================================================
# 22. ZOTERO EXTRA-FIELD DATASET CITATIONS (OPTIONAL)
# ================================================================

empty_zotero_publications <- function() {
  tibble(Zotero_Item_Key = character(), Paper_DOI = character(),
         Paper_Title = character(), Year = integer(), Zotero_Extra = character(),
         Zotero_Item_Type = character(), Zotero_Item_URL = character())
}

get_zotero_publications <- function() {
  collection_url <- zotero_group_url("/collections/", zotero_publication_collection_id)
  collection <- get_json(collection_url)
  if (!collection$ok) {
    stop("Cannot read the configured Zotero publication collection (HTTP status ",
         collection$status, "). Check its group ID, collection key, and public access.",
         call. = FALSE)
  }
  # Strict pagination distinguishes an empty collection from a failed or
  # incomplete response; otherwise failures could look like missing papers.
  items <- paginate_json(paste0(collection_url, "/items/top"), strict = TRUE)
  rows <- map(items, function(item) {
    d <- item$data
    if (safe(d$itemType) %in% c("note", "attachment")) return(empty_zotero_publications())
    paper_doi <- clean_doi(safe(d$DOI))
    if (is.na(paper_doi)) paper_doi <- first_text(extract_dois(safe(d$url, "")))
    tibble(
      Zotero_Item_Key = safe(item$key), Paper_DOI = paper_doi,
      Paper_Title = safe(d$title),
      Year = suppressWarnings(as.integer(str_extract(safe(d$date), "\\b[12][0-9]{3}\\b"))),
      Zotero_Extra = safe(d$extra, ""), Zotero_Item_Type = safe(d$itemType),
      Zotero_Item_URL = safe(item$links$alternate$href)
    )
  })
  bind_rows(empty_zotero_publications(), bind_rows(rows)) %>%
    distinct(Zotero_Item_Key, .keep_all = TRUE)
}

zotero_publications <- if (has_zotero) get_zotero_publications() else empty_zotero_publications()
zotero_citations <- extract_zotero_citations(zotero_publications, citation_registry)

# ================================================================
# 23. COMBINE ALL SOURCE EVIDENCE
# ================================================================
# Source sheets retain their original revision-level evidence. Only this
# combined view uses the configured series/DOI grouping and source priority.
# EDI records without a paper DOI or an exact registry package mapping stay
# visible in EDI_Citations but cannot supply a combined DOI relationship.

api_evidence <- api_relationships %>%
  transmute(Dataset_DOI, Paper_DOI, Paper_Title, Year,
            Source = Search_Source, Found_By = paste(Search_Source, Search_Method, sep = ": "))
pdf_evidence <- pdf_confirmed %>% mutate(Source = "PDF")
edi_evidence <- edi_citations %>%
  transmute(Dataset_DOI, Paper_DOI, Paper_Title = EDI_Paper_Title,
            Year = NA_integer_, Source = "EDI", Found_By = "EDI: Journal citation")
zotero_evidence <- zotero_citations %>%
  transmute(Dataset_DOI, Paper_DOI, Paper_Title, Year,
            Source = "Zotero", Found_By = "Zotero: Dataset DOI in Extra")

all_evidence <- bind_rows(empty_citation_evidence(), api_evidence, pdf_evidence,
                          edi_evidence, zotero_evidence)
combined_results <- combine_citation_evidence(
  all_evidence, citation_registry, deduplicate_on_dataset_id
)

# This maps over zero DOIs safely when discovery produces no relationships.
publication_types <- combined_results %>%
  distinct(Paper_DOI) %>%
  mutate(Publication_Type = purrr::map_chr(Paper_DOI, get_publication_type))
combined_results <- combined_results %>% left_join(publication_types, by = "Paper_DOI")

# ================================================================
# 24. ZOTERO CURATION SHEETS (ONLY WHEN ZOTERO IS CONFIGURED)
# ================================================================

if (has_zotero) {
  known_papers <- zotero_publications %>%
    filter(!is.na(Paper_DOI)) %>% distinct(Paper_DOI)

  missing_from_zotero <- combined_results %>%
    anti_join(known_papers, by = "Paper_DOI") %>%
    transmute(Paper_DOI, Paper_Title, Year, Dataset_Title, Dataset_Series_ID,
              Recommended_Package_ID = Dataset_Package_ID,
              Recommended_Dataset_DOI = Dataset_DOI, Selected_Source, Found_By)

  zotero_links <- zotero_citations %>%
    transmute(Paper_DOI, Dataset_DOI, Dataset_Package_ID, Dataset_Series_ID,
              Record_ID = Zotero_Item_Key)
  zotero_review <- catalog_link_review(
    semi_join(combined_results, known_papers, by = "Paper_DOI"),
    zotero_links, deduplicate_on_dataset_id
  ) %>% rename(Zotero_Item_Key = Record_ID)

  # Missing-link rows have no matched record. Supply the existing publication
  # item(s) so the reviewer can locate the Extra field that needs the DOI.
  publication_items <- zotero_publications %>%
    filter(!is.na(Paper_DOI)) %>%
    group_by(Paper_DOI) %>%
    summarise(Publication_Item_Keys = collapse_citation_values(Zotero_Item_Key),
              .groups = "drop")
  zotero_review <- zotero_review %>%
    left_join(publication_items, by = "Paper_DOI") %>%
    mutate(Zotero_Item_Key = coalesce(Zotero_Item_Key, Publication_Item_Keys)) %>%
    select(-Publication_Item_Keys)
  zotero_missing_links <- zotero_review %>% filter(Review_Status == "Missing dataset link")
  zotero_revision_review <- zotero_review %>% filter(Review_Status != "Missing dataset link")
}

# ================================================================
# 25. EDI CURATION SHEETS (ONLY WHEN EDI IS CONFIGURED)
# ================================================================

if (has_edi) {
  edi_links <- edi_citations %>%
    transmute(Paper_DOI, Dataset_DOI, Dataset_Package_ID = EDI_Package_ID,
              Dataset_Series_ID, Record_ID = EDI_Citation_ID)
  edi_expected <- combined_results %>%
    filter(Dataset_Series_ID %in% edi_registry$Dataset_Series_ID)
  edi_review <- catalog_link_review(edi_expected, edi_links, deduplicate_on_dataset_id) %>%
    rename(EDI_Citation_ID = Record_ID)
  edi_missing_links <- edi_review %>% filter(Review_Status == "Missing dataset link")
  edi_revision_review <- edi_review %>% filter(Review_Status != "Missing dataset link")
}

# ================================================================
# 26. SAVE ONE WORKBOOK WITH SOURCE, COMBINED, AND CURATION SHEETS
# ================================================================

result_counts <- count_dataset_citations(
  combined_results, citation_registry, deduplicate_on_dataset_id
)
sheets <- list(DataCite_Citations = publication_search, PDF_Citations = pdf_results)
if (has_edi) sheets$EDI_Citations <- edi_citations
if (has_zotero) sheets$Zotero_Citations <- zotero_citations
sheets$Combined_Results <- combined_results
sheets$Result_Counts <- result_counts
if (has_zotero) {
  sheets$Missing_From_Zotero <- missing_from_zotero
  sheets$Zotero_Missing_Data_DOI <- zotero_missing_links
  if (deduplicate_on_dataset_id) sheets$Zotero_Revision_Mismatches <- zotero_revision_review
}
if (has_edi) {
  sheets$EDI_Missing_Links <- edi_missing_links
  if (deduplicate_on_dataset_id) sheets$EDI_Revision_Mismatches <- edi_revision_review
}

openxlsx::write.xlsx(sheets, file = publication_results_file, overwrite = TRUE)

# Discovery counts use exact DOI pairs, independent of the combined mode.
# Count PDF-confirmed additions before EDI/Zotero so EDI-only evidence can
# never be reported as a PDF discovery.
pdf_only_relationships <- pdf_evidence %>%
  filter(!is.na(Paper_DOI), !is.na(Dataset_DOI)) %>%
  distinct(Paper_DOI, Dataset_DOI) %>%
  anti_join(distinct(api_evidence, Paper_DOI, Dataset_DOI), by = c("Paper_DOI", "Dataset_DOI"))
cat("\nSaved results: ", publication_results_file,
    "\nDataCite/OpenAlex relationships: ", nrow(publication_search),
    "\nAdditional PDF-confirmed DOI pairs: ", nrow(pdf_only_relationships),
    "\nEDI: ", if (has_edi) paste(nrow(edi_citations), "citation records") else "disabled",
    "\nZotero: ", if (has_zotero) paste(nrow(zotero_citations), "dataset links") else "disabled",
    "\nCombined relationships: ", nrow(combined_results),
    "\nDeduplication: ", if (deduplicate_on_dataset_id) "dataset series" else "dataset DOI",
    "\n", sep = "")

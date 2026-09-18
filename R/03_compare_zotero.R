# ================================================================
# 03_compare_zotero.R
# COMPARE CITATION FINDER RESULTS WITH ZOTERO
# ================================================================
#
# PURPOSE:
# Compare paper-dataset relationships discovered by
# R/02_find_dataset_citations.R with the configured Zotero publication
# collection. This produces review lists for publications or dataset DOI
# relationships that may need curation in Zotero.
#
# INPUTS:
# Citation_finder_output/Data_Registry.xlsx
# Citation_finder_output/Publication_Search_Results.xlsx
# A Zotero group and collection configured in config.R.
#
# ZOTERO ACCESS:
# The configured Zotero group must be readable through the Zotero API.
# This workflow currently uses public/readable group requests and does not
# store a Zotero API key.
#
# OPENALEX API KEY:
# OPENALEX_API_KEY is used to retrieve cited-by counts for publication
# DOIs. A key is recommended because the workflow can make many OpenAlex
# requests. Store it in .Renviron, not in this script.
#
# OUTPUT:
# Citation_finder_output/Zotero_Comparison.xlsx
#   Zotero_For_Website       - publications currently in the configured
#                              Zotero collection.
#   Missing_From_Zotero      - papers found by Citation Finder whose paper
#                              DOI is not in the Zotero collection.
#   Zotero_Missing_Data_DOI  - paper exists in Zotero, but a specific
#                              paper-dataset relationship is absent from
#                              the Zotero Extra field.
#   Zotero_Not_In_Search     - relationship recorded in Zotero Extra but
#                              not found by the automated citation search.
#
# FILE BEHAVIOR:
# The output directory is defined in config.R. If it does not exist,
# this script announces and creates it. An existing Zotero_Comparison.xlsx
# is overwritten. A completion message prints counts and the saved path.
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

if (is.null(zotero_group_id) || !nzchar(trimws(zotero_group_id))) {
  stop("zotero_group_id is required for this script. Set it in config.R.", call. = FALSE)
}

if (is.null(website_collection) || !nzchar(trimws(website_collection))) {
  stop("website_collection is required for this script. Set it in config.R.", call. = FALSE)
}

if (is.null(openalex_key)) {
  warning(
    paste0(
      "OPENALEX_API_KEY is not set. Citation-count requests will be attempted without a key, ",
      "but may be rate limited. See README.md."
    ),
    call. = FALSE
  )
}


# ================================================================
# 1. LOAD DATA REGISTRY AND PUBLICATION SEARCH RESULTS
# ================================================================

if (!file.exists(data_registry_file)) {
  stop(
    paste0(
      "Could not find ",
      data_registry_file,
      ". Run R/01_get_dataset_dois.R first."
    )
  )
}


if (!file.exists(publication_results_file)) {
  stop(
    paste0(
      "Could not find ",
      publication_results_file,
      ". Run R/02_find_dataset_citations.R first."
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
# 5. GET ZOTERO FOR-WEBSITE COLLECTION
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
# 6. ZOTERO PUBLICATION ITEMS
# ================================================================

# Publication types are defined in config.R.

zotero_publications <- purrr::map_dfr(
  
  fw_items,
  
  function(item) {
    
    d <- item$data
    
    if (
      !safe(
        d$itemType
      ) %in%
      publication_types
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
  
  dplyr::mutate(
    Paper_DOI =
      clean_doi(
        Paper_DOI
      )
  ) %>%
  
  distinct(
    Zotero_Item_Key,
    .keep_all = TRUE
  )


# ================================================================
# 7. OPENALEX CITATION COUNTS
# ================================================================



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
  )
  


zotero_publications <- zotero_publications %>%
  
  dplyr::left_join(
    paper_citation_counts %>%
      dplyr::select(
        Paper_DOI,
        Cited_By_Count
      ),
    by = "Paper_DOI"
  )


# ================================================================
# 8. ZOTERO FOR-WEBSITE TAB
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
    Zotero_Extra
  ) %>%
  
  dplyr::arrange(
    Paper_Title
  )


# ================================================================
# 9. BUILD ZOTERO PAPER-DATASET RELATIONSHIPS
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
# 10. MISSING FROM ZOTERO
#
# Publication was found by the automated workflow but the Paper DOI
# does not exist anywhere in the configured Zotero collection.
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
        Cited_By_Count
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
# 11. ZOTERO MISSING DATASET DOI
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
        Cited_By_Count
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
# 12. ZOTERO NOT IN SEARCH
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
        Cited_By_Count
      ),
    by = "Paper_DOI"
  ) %>%
  
  dplyr::arrange(
    Paper_Title,
    Dataset_Package_ID,
    Dataset_DOI
  )


# ================================================================
# 13. WRITE ZOTERO COMPARISON WORKBOOK
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
  zotero_comparison_file,
  overwrite = TRUE
)


cat(
  "\n========================================\n",
  "ZOTERO COMPARISON COMPLETE\n",
  "========================================\n",
  "Configured Zotero publications: ",
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
  zotero_comparison_file,
  "\n",
  "========================================\n"
)

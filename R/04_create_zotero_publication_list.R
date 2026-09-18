# ================================================================
# 04_create_zotero_publication_list.R
# CREATE A COMPREHENSIVE ZOTERO PUBLICATION LIST
# ================================================================
#
# PURPOSE:
# Export one row per publication from the configured Zotero collection,
# including authors, paper DOI, selected publication-category tags,
# dataset DOIs recorded in Zotero Extra, and an OpenAlex cited-by count.
# Publications are retained even when a paper DOI or dataset DOI is absent.
#
# INPUT:
# A Zotero group and collection configured in config.R. The group must be
# readable through the Zotero API.
#
# OPENALEX API KEY:
# OPENALEX_API_KEY is used to retrieve cited-by counts for publication
# DOIs. A key is recommended because many requests may be made. Store it
# in .Renviron, not in this script.
#
# OUTPUT:
# Citation_finder_output/Zotero_Comprehensive_Publication_List.xlsx
#   Sheet: Zotero_Publications
#
# OUTPUT COLUMNS:
# Paper_Title             - Zotero publication title.
# Paper_Authors           - authors combined with semicolons.
# Paper_DOI               - normalized publication DOI, when available.
# Publication_Category    - Foundational and/or Supported Zotero tag.
# Dataset_DOIs            - dataset DOIs found in Zotero Extra, combined
#                           with semicolons when more than one is present.
# Cited_By_Count          - OpenAlex cited_by_count for Paper_DOI.
#
# FILE BEHAVIOR:
# The output directory is defined in config.R. If it does not exist,
# this script announces and creates it. An existing workbook with the
# same name is overwritten. A completion message prints the saved path.
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
# LOCAL HELPERS
# Shared helpers such as safe(), clean_doi(), extract_dois(),
# get_json(), and OpenAlex helpers are defined in R/utils.R.
# ================================================================

# ================================================================
# EXTRACT PAPER AUTHORS
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
# EXTRACT FOUNDATIONAL / SUPPORTED CATEGORY FROM ZOTERO TAGS
# ================================================================

extract_publication_category <- function(tags) {
  
  if (
    is.null(tags) ||
    length(tags) == 0
  ) {
    return(NA_character_)
  }
  
  tag_values <- map_chr(
    tags,
    function(tag) {
      safe(
        tag$tag,
        ""
      )
    }
  )
  
  tag_values <- tag_values[
    !is.na(tag_values) &
      tag_values != ""
  ]
  
  category_tags <- tag_values[
    tolower(tag_values) %in%
      c(
        "foundational",
        "supported"
      )
  ]
  
  if (length(category_tags) == 0) {
    return(NA_character_)
  }
  
  category_tags <- dplyr::case_when(
    tolower(category_tags) == "foundational" ~ "Foundational",
    tolower(category_tags) == "supported" ~ "Supported",
    TRUE ~ category_tags
  )
  
  paste(
    unique(category_tags),
    collapse = "; "
  )
}


# ================================================================
# 1. GET ZOTERO COLLECTIONS
# ================================================================

cat(
  "\n========================================\n",
  "GETTING ZOTERO COLLECTIONS\n",
  "========================================\n"
)


collections <- paginate_json(
  
  paste0(
    "https://api.zotero.org/groups/",
    zotero_group_id,
    "/collections"
  )
)


# ================================================================
# 2. FIND CONFIGURED WEBSITE COLLECTION
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
  "Configured collection key:",
  collection_key,
  "\n"
)


# ================================================================
# 3. GET TOP-LEVEL ITEMS FROM CONFIGURED COLLECTION
# ================================================================

cat(
  "\n========================================\n",
  "GETTING CONFIGURED COLLECTION ITEMS\n",
  "========================================\n"
)


items <- paginate_json(
  
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
# 4. PUBLICATION TYPES
# ================================================================

# Publication types are defined in config.R.

# ================================================================
# 5. EXTRACT PUBLICATION FIELDS
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
      
      Publication_Category =
        extract_publication_category(
          d$tags
        ),
      
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
# 6. EXTRACT RELATED DATASET DOIS FROM ZOTERO EXTRA
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
          
          Publication_Category =
            row$Publication_Category,
          
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
      
      Publication_Category =
        row$Publication_Category,
      
      Dataset_DOI =
        extra_dois
    )
  }
)


# ================================================================
# 7. BUILD FINAL CLEAN TABLE
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
    Paper_DOI,
    Publication_Category
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
# 8. GET OPENALEX CITATION COUNTS
# ================================================================

cat(
  "\n========================================\n",
  "GETTING OPENALEX CITATION COUNTS\n",
  "========================================\n"
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
  select(
    Paper_Title,
    Paper_Authors,
    Paper_DOI,
    Publication_Category,
    Dataset_DOIs,
    Cited_By_Count
  ) %>%
  arrange(
    Paper_Title
  )


# ================================================================
# 9. SUMMARY
# ================================================================

cat(
  "\n========================================\n",
  "ZOTERO PUBLICATION SUMMARY\n",
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
  "Total output rows:",
  nrow(
    zotero_citation_list
  ),
  "\n"
)


# ================================================================
# 10. CREATE EXCEL
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
# 11. FORMAT EXCEL
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
# 12. SAVE
# ================================================================

saveWorkbook(
  
  wb,
  
  zotero_comprehensive_file,
  
  overwrite =
    TRUE
)


# ================================================================
# 13. FINAL MESSAGE
# ================================================================

cat(
  "\n========================================\n",
  "EXPORT COMPLETE\n",
  "========================================\n",
  "Saved as:\n",
  normalizePath(
    zotero_comprehensive_file,
    winslash = "/",
    mustWork = FALSE
  ),
  "\n",
  "========================================\n"
)
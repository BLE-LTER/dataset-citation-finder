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
# INPUTS:
# A Zotero group and publication collection configured in config.R. The
# group must be readable through the Zotero API.
#
# Zotero_Comparison.xlsx, created by R/03_compare_zotero.R, is used when
# it exists. Its Zotero_For_Website sheet already holds an OpenAlex
# cited-by count for each publication DOI, so those values are reused and
# only the missing ones are requested again. The file is optional; if it
# is absent, every count is retrieved from OpenAlex here instead. Running
# R/03_compare_zotero.R first therefore avoids duplicate API requests.
#
# Those saved counts are only reused while Zotero_Comparison.xlsx is
# younger than zotero_comparison_cache_max_age_days (config.R). Once
# the file is older than that, this script treats it as stale and
# re-fetches every citation count from OpenAlex instead.
#
# OPENALEX API KEY:
# OPENALEX_API_KEY is used to retrieve any cited-by counts that could not
# be reused. A key is recommended because many requests may be made.
# Store it in .Renviron, not in this script.
#
# OUTPUT:
# Zotero_Comprehensive_Publication_List.xlsx, written to the directory set
# by output_dir in config.R (by default Citation_finder_output in the
# repository root).
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

# This publication list is built from Zotero. A site that does not track
# its publications in a Zotero group should skip this script.
# See README.md.

if (is.null(zotero_group_id) || !nzchar(trimws(zotero_group_id))) {
  stop(
    paste0(
      "zotero_group_id is required for this script. Set it in config.R, or ",
      "skip this script if your site does not use Zotero."
    ),
    call. = FALSE
  )
}

if (is.null(zotero_publication_collection_id) ||
    !nzchar(trimws(zotero_publication_collection_id))) {
  stop(
    paste0(
      "zotero_publication_collection_id is required for this script. Set it ",
      "in config.R to the ID of the Zotero collection that holds your ",
      "publications. config.R explains where to find that ID."
    ),
    call. = FALSE
  )
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
# 1. GET TOP-LEVEL ITEMS FROM THE CONFIGURED COLLECTION
# ================================================================
#
# The collection is requested by ID, so there is no need to list every
# collection in the group and match one by name.
# ================================================================

cat(
  "\n========================================\n",
  "GETTING CONFIGURED COLLECTION ITEMS\n",
  "========================================\n",
  "Collection ID: ", zotero_publication_collection_id, "\n",
  sep = ""
)


items <- paginate_json(
  zotero_group_url(
    "/collections/",
    zotero_publication_collection_id,
    "/items/top"
  )
)


# An unknown collection ID returns nothing rather than an error, so say
# so here instead of writing an empty publication list.
if (!length(items)) {
  stop(
    paste0(
      'The Zotero collection "',
      zotero_publication_collection_id,
      '" returned no items. Check zotero_publication_collection_id in ',
      "config.R, and that the group is readable through the Zotero API."
    ),
    call. = FALSE
  )
}


cat(
  "Total top-level items:",
  length(items),
  "\n"
)


# ================================================================
# 2. PUBLICATION TYPES
# ================================================================

# Publication types are defined in config.R.

# ================================================================
# 3. EXTRACT PUBLICATION FIELDS
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
# 4. EXTRACT RELATED DATASET DOIS FROM ZOTERO EXTRA
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
# 5. BUILD FINAL CLEAN TABLE
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
# 6. GET OPENALEX CITATION COUNTS
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


# ------------------------------------------------
# REUSE COUNTS ALREADY RETRIEVED BY 03_compare_zotero.R
# ------------------------------------------------
# 03_compare_zotero.R asks OpenAlex for a cited-by count for every
# publication DOI and saves the answers in the Zotero_For_Website sheet
# of Zotero_Comparison.xlsx. Reading those values back means this script
# only has to ask OpenAlex about DOIs that report is missing.
#
# The file is optional. If it has not been created yet, every count is
# retrieved here instead. The file is also ignored, and every count is
# retrieved here instead, once it is older than
# zotero_comparison_cache_max_age_days (config.R) - an old report can
# be missing cited-by counts for papers OpenAlex has indexed since, or
# hold counts that have since gone up.

existing_counts <- tibble(
  Paper_DOI = character(),
  Cited_By_Count = integer()
)

# zotero_comparison_cache_max_age_days is set in config.R. The default
# covers an older config.R that predates this setting.
max_comparison_age_days <- get0(
  "zotero_comparison_cache_max_age_days",
  ifnotfound = 30,
  inherits = TRUE
)

if (file.exists(zotero_comparison_file)) {

  comparison_age_days <- as.numeric(
    difftime(
      Sys.time(),
      file.info(zotero_comparison_file)$mtime,
      units = "days"
    )
  )

  comparison_is_fresh <- is.infinite(max_comparison_age_days) ||
    comparison_age_days < max_comparison_age_days

  if (comparison_is_fresh) {

    existing_counts <- tryCatch(
      {
        previous <- openxlsx::read.xlsx(
          zotero_comparison_file,
          sheet = "Zotero_For_Website"
        )

        if (all(c("Paper_DOI", "Cited_By_Count") %in% names(previous))) {

          previous %>%
            transmute(
              Paper_DOI = clean_doi(Paper_DOI),
              Cited_By_Count = suppressWarnings(
                as.integer(Cited_By_Count)
              )
            ) %>%
            filter(
              !is.na(Paper_DOI),
              !is.na(Cited_By_Count)
            ) %>%
            distinct(
              Paper_DOI,
              .keep_all = TRUE
            )

        } else {
          existing_counts
        }
      },
      error = function(e) {
        message(
          "Could not reuse counts from ",
          basename(zotero_comparison_file),
          "; they will be retrieved from OpenAlex. Reason: ",
          conditionMessage(e)
        )
        existing_counts
      }
    )

    cat(
      "Reusing ",
      nrow(existing_counts),
      " cited-by count(s) from ",
      basename(zotero_comparison_file),
      " (",
      round(comparison_age_days, 1),
      " day(s) old)\n",
      sep = ""
    )

  } else {

    cat(
      basename(zotero_comparison_file),
      " is ",
      round(comparison_age_days, 1),
      " day(s) old, which is older than zotero_comparison_cache_max_age_days (",
      max_comparison_age_days,
      "). Re-fetching every citation count from OpenAlex instead of reusing it.\n",
      sep = ""
    )
  }

} else {
  cat(
    "No ",
    basename(zotero_comparison_file),
    " found. Run R/03_compare_zotero.R first to avoid repeating these ",
    "OpenAlex requests.\n",
    sep = ""
  )
}


# ------------------------------------------------
# RETRIEVE ONLY THE MISSING COUNTS
# ------------------------------------------------

dois_to_fetch <- setdiff(
  unique_paper_dois$Paper_DOI,
  existing_counts$Paper_DOI
)

cat(
  "Cited-by counts to retrieve from OpenAlex: ",
  length(dois_to_fetch),
  " of ",
  nrow(unique_paper_dois),
  "\n",
  sep = ""
)

fetched_counts <- if (length(dois_to_fetch)) {

  map_dfr(
    dois_to_fetch,
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
    select(
      Paper_DOI,
      Cited_By_Count
    )

} else {

  tibble(
    Paper_DOI = character(),
    Cited_By_Count = integer()
  )
}

citation_counts <- bind_rows(
  existing_counts,
  fetched_counts
) %>%
  filter(
    !is.na(Paper_DOI)
  ) %>%
  distinct(
    Paper_DOI,
    .keep_all = TRUE
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
# 7. SUMMARY
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
# 8. CREATE EXCEL
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
# 9. FORMAT EXCEL
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
# 10. SAVE
# ================================================================

saveWorkbook(
  
  wb,
  
  zotero_comprehensive_file,
  
  overwrite =
    TRUE
)


# ================================================================
# 11. FINAL MESSAGE
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
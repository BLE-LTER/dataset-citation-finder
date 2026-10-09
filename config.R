# ================================================================
# config.R
# SHARED CONFIGURATION FOR DATASET CITATION FINDER
# ================================================================
#
# Edit site-specific settings here instead of changing each workflow
# script. The numbered scripts source this file automatically.
#
# API keys are not stored here. Put them in a local .Renviron file in the
# repository root:
#
#   EDI_API_KEY=your_key
#   OPENALEX_API_KEY=your_key
#
# Do not commit .Renviron to GitHub; .gitignore already excludes it.
# This file reads that .Renviron itself (see API KEYS below), so every
# workflow script sees the keys even when the R session was started
# outside the repository root.
#
# OUTPUT BEHAVIOR:
# The numbered scripts write their generated files to output_dir below.
# The output directory is created only when a workflow script calls
# ensure_output_dir(); config.R itself does not create files or folders.
# Existing output files with the same names are overwritten.
# ================================================================


# ------------------------------------------------
# LTER / EDI SETTINGS
# ------------------------------------------------
# Set edi_scope to your EDI scope, for example "knb-lter-ble".
# Set it to "" to skip EDI registry harvesting in 01 and EDI citations in 02.

edi_scope <- "knb-lter-ble"


# ------------------------------------------------
# ZOTERO SETTINGS
# ------------------------------------------------
# zotero_group_id must refer to a Zotero group that can be read through
# the Zotero API. Set it to "" if your site does not use Zotero for this
# workflow.

zotero_group_id <- "2211939"

# ID of the Zotero collection holding the site's publications, used by
# 02_find_dataset_citations.R. Zotero's
# API calls this the collection "key"; it is an eight-character code.
#
# To find it, open the collection in your Zotero group on the web. The ID
# is the last part of the address:
#
#   https://www.zotero.org/groups/lter-ble/collections/KHTHLKB5
#                                                      ^^^^^^^^
#
# Supplying the ID lets the scripts request the collection directly,
# instead of listing every collection in the group to match one by name.
#
# The value below is the BLE "For-Website" collection. Another site
# should replace it with the ID of its own publication collection.

zotero_publication_collection_id <- "KHTHLKB5"

# Tag used by 01_get_dataset_dois.R to identify datasets archived outside
# EDI. BLE uses this tag in its Zotero group; other sites may use a
# different tag or may leave it blank to skip this Zotero registry source.
zotero_dataset_tag <- "LTER-Funded Data at Other Archives"


# ------------------------------------------------
# COMBINED RESULTS: DATASET REVISION DEDUPLICATION
# ------------------------------------------------
# TRUE: one row per paper DOI + EDI dataset series (scope + identifier).
# Select the dataset DOI/revision from DataCite first, then Zotero, then EDI.
# OpenAlex and PDF provide fallback revisions, in that order. Ties within
# one source use the highest numeric revision, then the dataset DOI.
# FALSE: one row per paper DOI + dataset DOI; distinct revisions remain.
# Non-EDI datasets always use DOI matching. Source worksheets keep all
# their revision-level evidence in either mode. Revision-mismatch review
# sheets are produced only in TRUE mode.

deduplicate_on_dataset_id <- TRUE

# ------------------------------------------------
# PREPRINT SETTINGS
# ------------------------------------------------
# TRUE: Include preprints in citation results.
# FALSE: Exclude preprints from citation results.

include_preprints <- FALSE


# ------------------------------------------------
# SITE-SPECIFIC SEARCH TERMS
# ------------------------------------------------
# These terms are used by 02_find_dataset_citations.R for OpenAlex
# keyword discovery and full-text verification. Replace them with terms
# appropriate for your LTER site.

site_keywords <- c(
  "Beaufort Lagoon Ecosystems",
  "Beaufort Lagoon Ecosystems LTER",
  "BLE LTER",
  "BLE-LTER",
  "Beaufort Lagoon",
  "knb-lter-ble",
  "Arctic Lagoon",
  "Beaufort Sea Coastal Lagoons",
  "Arctic Coastal"
)


# ------------------------------------------------
# OUTPUT LOCATION
# ------------------------------------------------
# By default, results are written to a Citation_finder_output folder in
# the repository root, so that nothing is written outside the project.
# Change output_dir below if you want results stored somewhere else.
#
# The numbered scripts announce this directory before creating it, and
# they overwrite an output file that already has the same name.

# project_root is normally set by the workflow script that sources this
# file. The fallback covers sourcing config.R on its own.
if (!exists("project_root", inherits = TRUE)) {
  project_root <- normalizePath(".", winslash = "/", mustWork = FALSE)
}

output_dir <- file.path(
  project_root,
  "Citation_finder_output"
)


# ------------------------------------------------
# SHARED INPUT / OUTPUT FILES
# ------------------------------------------------

data_registry_file <- file.path(
  output_dir,
  "Data_Registry.xlsx"
)

publication_results_file <- file.path(
  output_dir,
  "Publication_Search_Results.xlsx"
)

cache_file <- file.path(
  output_dir,
  "openalex_cache.rds"
)


# ------------------------------------------------
# OPENALEX CACHE EXPIRY
# ------------------------------------------------
# 02_find_dataset_citations.R saves each OpenAlex response in the cache
# file above and reuses it on later runs. A cached response is reused
# only while it is younger than the number of days below; after that it
# is requested again.
#
# OpenAlex keeps indexing new papers, so a cached answer goes out of
# date as new work cites a dataset. Lower this number to pick up new
# citations sooner, raise it to make fewer API requests. Set it to Inf
# to keep cached responses forever.

cache_max_age_days <- 10


# ------------------------------------------------
# API KEYS FROM THE R ENVIRONMENT
# ------------------------------------------------
# R loads variables from ~/.Renviron or a project .Renviron when the R
# session starts, which only happens if R started in the repository root.
# Reading the project .Renviron here means every workflow script finds
# the keys no matter where the session was started from. Keys set as
# operating-system environment variables keep working as well.
#
# See README.md for how to create .Renviron.

renviron_file <- file.path(project_root, ".Renviron")

if (file.exists(renviron_file)) {
  readRenviron(renviron_file)
}

# Missing keys are not an error here. Each workflow script reports the
# keys it actually needs, because the scripts need different ones.

edi_key <- Sys.getenv("EDI_API_KEY")

openalex_key <- Sys.getenv("OPENALEX_API_KEY")

if (!nzchar(openalex_key)) {
  openalex_key <- NULL
}

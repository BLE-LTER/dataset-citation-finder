# ================================================================
# config.R
# SHARED CONFIGURATION FOR DATASET CITATION FINDER
# ================================================================
#
# Edit site-specific settings here instead of changing each workflow
# script. The numbered scripts source this file automatically.
#
# API keys are not stored here. Put them in a local .Renviron file:
#
#   EDI_API_KEY=your_key
#   OPENALEX_API_KEY=your_key
#
# Do not commit .Renviron to GitHub.
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
# Set it to "" if you do not want 01_get_dataset_dois.R to harvest EDI.

edi_scope <- "knb-lter-ble"


# ------------------------------------------------
# ZOTERO SETTINGS
# ------------------------------------------------
# zotero_group_id must refer to a Zotero group that can be read through
# the Zotero API. Set it to "" if your site does not use Zotero for this
# workflow.

zotero_group_id <- "2211939"

# Collection used by the Zotero comparison/publication-list scripts.
website_collection <- "For-Website"

# Tag used by 01_get_dataset_dois.R to identify datasets archived outside
# EDI. BLE uses this tag in its Zotero group; other sites may use a
# different tag or may leave it blank to skip this Zotero registry source.
external_tag <- "LTER-Funded Data at Other Archives"


# ------------------------------------------------
# PUBLICATION TYPES INCLUDED FROM ZOTERO
# ------------------------------------------------

publication_types <- c(
  "journalArticle",
  "conferencePaper",
  "bookSection",
  "preprint",
  "report",
  "thesis",
  "patent",
  "book"
)


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
# By default, results are written to Citation_finder_output in the
# repository root.
# provider or on a particular user's home directory.
#
# The numbered scripts announce the directory before creating it.
# Change this value if you want results stored somewhere else.

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

zotero_comparison_file <- file.path(
  output_dir,
  "Zotero_Comparison.xlsx"
)

zotero_comprehensive_file <- file.path(
  output_dir,
  "Zotero_Comprehensive_Publication_List.xlsx"
)

edi_journal_citation_file <- file.path(
  output_dir,
  "EDI_Journal_Citation_Comparison.xlsx"
)

cache_file <- file.path(
  output_dir,
  "openalex_cache.rds"
)


# ------------------------------------------------
# API KEYS FROM THE R ENVIRONMENT
# ------------------------------------------------
# R normally loads variables from ~/.Renviron or a project .Renviron
# when the R session starts. See README.md for setup instructions.

edi_key <- Sys.getenv("EDI_API_KEY")

openalex_key <- Sys.getenv("OPENALEX_API_KEY")

if (!nzchar(openalex_key)) {
  openalex_key <- NULL
}

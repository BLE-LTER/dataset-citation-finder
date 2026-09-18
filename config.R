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

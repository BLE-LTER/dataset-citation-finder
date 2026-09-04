# Dataset Citation Finder

## Overview

Dataset Citation Finder is an R workflow for identifying publications that
cite, reference, or are associated with Long Term Ecological Research (LTER)
datasets.

The workflow combines dataset information from EDI and Zotero with publication
information from DataCite, OpenAlex, and Crossref. When full text is available,
publication PDFs are also searched for dataset references.

The workflow can be adapted for use by different LTER sites by changing the
site-specific settings in the R scripts.

## Workflow

The repository contains five main scripts:

1. `01_Dataset_Registry.R`  
   Creates the dataset registry from EDI and externally archived datasets
   documented in Zotero.

2. `02_Publication_Search_PDF.R`  
   Searches for publications associated with the datasets and checks available
   publication full text.

3. `03_Zotero_Comparison.R`  
   Compares discovered publication-dataset relationships with existing Zotero
   records.

4. `04_Zotero_Comprehensive_List.R`  
   Creates a comprehensive Zotero publication list with available OpenAlex
   citation counts.

5. `05_EDI_Journal_Citations.R`  
   Retrieves and compares journal citations recorded in EDI.

## Setup

Before running the workflow, update the site-specific settings in the R scripts,
including:

- EDI scope
- Zotero group and collection
- Site-specific search terms

API keys should be stored as environment variables:

`EDI_API_KEY`  
`OPENALEX_API_KEY`

API keys should **not** be committed to GitHub.

## Running the Workflow

For the main workflow, run:

`01_Dataset_Registry.R` → `02_Publication_Search_PDF.R` → `03_Zotero_Comparison.R`

The other scripts provide additional Zotero and EDI citation reports.

## Note

The workflow is intended to support dataset citation discovery and review.
Results should be manually verified before updating Zotero, EDI, or other
publication records.

See the individual R scripts for details about each step of the workflow.

## Contributing

When updating the workflow:

-   Update the date at the top of the README when appropriate.
-   Update the documentation if search methods or outputs change.
-   Do not commit API keys or credentials.
-   Test the workflow before merging changes into the `main` branch.

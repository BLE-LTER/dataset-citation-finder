# Dataset Citation Finder

## Orientation

**BLE Citation Finder** is an R workflow for identifying publications
that cite, reference, or are associated with **Beaufort Lagoon
Ecosystems Long Term Ecological Research (BLE LTER)** datasets.

The workflow builds a registry of BLE datasets from the **Environmental
Data Initiative (EDI)** and BLE-funded datasets documented in
**Zotero**. It then searches multiple scholarly sources for related
publications.

Search results are compared with the BLE Zotero bibliography to identify
potentially missing publications and dataset citation information.

> **Important:** The workflow is intended as a citation discovery and
> review tool. Results should be manually verified before updating
> Zotero or EDI.

## Features

The workflow:

-   Builds a registry of BLE datasets from EDI and Zotero.
-   Searches DataCite for dataset citation relationships.
-   Searches OpenAlex for citations and dataset DOI references.
-   Uses Crossref to retrieve missing publication metadata.
-   Searches available publication PDFs for BLE keywords, dataset DOIs,
    and dataset URLs.
-   Links publications to individual BLE datasets.
-   Combines results found through multiple search methods.
-   Compares results with the BLE Zotero bibliography.
-   Identifies potentially missing publication-dataset relationships.
-   Produces an Excel workbook for manual review.

## API Keys

API credentials should be stored as environment variables and **must not
be committed to GitHub**.

For example, the workflow uses the following environment variables:

-   `EDI_API_KEY`
-   `OPENALEX_API_KEY`

## Usage

Run the main citation-finder R script.

The workflow first retrieves BLE datasets from the EDI scope
`knb-lter-ble` and adds BLE-funded datasets archived elsewhere and
documented in Zotero.

It then searches DataCite and OpenAlex for publications associated with
each dataset. Crossref is used to complete missing publication metadata.

When publication PDFs are available, the workflow searches the full text
for:

-   BLE keywords
-   Dataset DOIs
-   Dataset URLs

The discovered publication-dataset relationships are then compared with
Zotero, and an Excel workbook is created for review.

A publication may be associated with multiple BLE datasets. Therefore,
comparisons are made using the combination of **Paper DOI + Dataset
DOI**, rather than only the publication DOI.

## Output

The workflow produces an Excel workbook containing the following tabs:

- **`BLE_Data_Registry`**  
  Contains the BLE datasets included in the search.

- **`Publication_Search`**  
  Contains publication-dataset relationships identified through DataCite, OpenAlex, and other searches.

- **`PDF_Results`**  
  Contains BLE keywords, dataset DOIs, and dataset URLs found in available publication full text.

- **`Zotero_For_Website`**  
  Contains existing publications and BLE dataset DOI information retrieved from Zotero.

- **`Missing_From_Zotero`**  
  Contains publication-dataset relationships found by the search that may not yet be represented in Zotero.

- **`Zotero_Missing_Data_DOI`**  
  Contains publications already in Zotero that may be missing an associated BLE dataset DOI.

- **`Zotero_Not_In_Search`**  
  Contains known Zotero publication-dataset relationships that were not recovered by the automated search.
  
## Interpreting Results

Different search methods provide different levels of evidence.

For example, a **DataCite Citation** relationship means that DataCite
contains a structured relationship between the publication and dataset.
It does not necessarily mean that the dataset DOI appears directly in
the publication PDF.

Finding an exact dataset DOI or dataset URL in the publication full text
provides stronger evidence of a dataset reference.

BLE keyword matches are useful for discovering candidate publications
but do not by themselves confirm that a BLE dataset was used.

For this reason, records in `Missing_From_Zotero` should be manually
reviewed before being added to Zotero.

## Zotero Review

For each candidate in `Missing_From_Zotero`:

1.  Open the publication using the paper DOI.
2.  Check for the associated BLE dataset DOI or dataset information.
3.  Review the **Data Availability**, **Methods**, **References**, and
    **Acknowledgements** sections when appropriate.
4.  Review the `Search_Source`, `Search_Method`, and PDF search results.
5.  If the publication-dataset relationship is confirmed, add or update
    the publication in Zotero.
6.  Add the associated BLE dataset DOI to the Zotero `Extra` field when
    appropriate.

> The script does **not** automatically modify Zotero or EDI records.

## Limitations

The workflow may not find every publication using BLE data. Publications
may omit dataset DOIs, PDFs may not be openly accessible, and external
citation metadata may be incomplete.

For this reason, the workflow combines multiple search methods and uses
manual verification as the final step.

## Contributing

When updating the workflow:

-   Update the date at the top of the README when appropriate.
-   Update the documentation if search methods or outputs change.
-   Do not commit API keys or credentials.
-   Test the workflow before merging changes into the `main` branch.

## Adapting the Workflow

The workflow was developed for **BLE LTER** but may be adapted by other
LTER sites by changing:

-   The EDI scope
-   Zotero information
-   Site-specific search terms

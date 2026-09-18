# Dataset Citation Finder

## Overview

Dataset Citation Finder is an R workflow for identifying publications that cite,
reference, or are associated with Long Term Ecological Research (LTER) datasets.
It combines dataset information from the Environmental Data Initiative (EDI) and,
optionally, Zotero with publication evidence from DataCite and OpenAlex. When an
OpenAlex keyword search returns a paper with an accessible PDF, the workflow can
also search the extracted PDF text for site terms and exact dataset references.

## Repository structure

The repository contains configuration files, shared utilities, and five workflow scripts.

### Configuration and setup

- `config.R` contains site-specific settings such as the EDI scope, Zotero settings, search terms, and output location.
- `setup.R` installs the R packages required by the workflow. It only needs to be run during initial setup.
- `R/utils.R` contains functions shared by multiple scripts and is loaded automatically by the workflow scripts. It should not be run separately.

### Workflow scripts

The main scripts are located in the `R/` folder and are numbered in their usual order of execution:

1. `01_get_dataset_dois.R` retrieves dataset DOIs from EDI and Zotero.
2. `02_find_dataset_citations.R` searches for publications associated with the datasets and checks available publication full text.
3. `03_compare_zotero.R` compares the discovered relationships with publication information in Zotero.
4. `04_create_zotero_publication_list.R` creates a comprehensive Zotero publication list with available citation counts.
5. `05_compare_edi_citations.R` compares the discovered relationships with journal citations recorded in EDI.

### Output files

Workflow results are written to the `Citation_finder_output` folder. This folder is created automatically when a script first needs to save an output file.
The output location can be changed in `config.R`.

## What is the dataset registry?

The dataset registry is the master list of dataset DOIs that the citation workflow
will search for. `R/01_get_dataset_dois.R` currently knows how to discover dataset
DOIs from two sources:

1. **EDI** - all DOI-bearing revisions in the EDI scope configured as `edi_scope`.
2. **Zotero** - datasets archived outside EDI that are represented in the configured

Zotero group and tagged with `external_tag`.
The Zotero approach is a BLE convention, not an LTER-wide requirement. BLE uses a
readable Zotero group and the tag `LTER-Funded Data at Other Archives` to identify
externally archived datasets. Another LTER site can change that tag in `config.R`,
or leave the Zotero settings blank and build the registry from EDI only.
The Zotero group must be readable through the Zotero API for the current
unauthenticated requests to work.

## Dataset sources for sites that do not use EDI

Not every LTER site archives its datasets in EDI. The citation-search portion of this workflow can still be used as long as a dataset registry is provided.

### If your site uses EDI

Run `R/01_get_dataset_dois.R` to build `Data_Registry.xlsx` automatically from the EDI scope configured in `config.R`. If Zotero is also configured, the script can add externally archived datasets identified through the configured Zotero tag.

### If your site does not use EDI

Create `Data_Registry.xlsx` manually and save it in the directory specified by `output_dir` in `config.R`. The workbook must contain a worksheet named `Data_Registry`.
Use the same column names produced by `R/01_get_dataset_dois.R`:

- `Scope`
- `Identifier`
- `Revision`
- `Dataset_Title`
- `Package_ID`
- `Dataset_DOI`
- `Registry_Source`
- `Registry_Category`
- `Zotero_Item_Key`
- `Final_URL`

For datasets that are not in EDI, the EDI-specific fields (`Scope`, `Identifier`, `Revision`, and `Package_ID`) can be left blank. `Zotero_Item_Key` can also be left blank when Zotero is not being used.
At minimum, each dataset that should be searched must have a `Dataset_Title` and `Dataset_DOI`. Set `Registry_Source` to a value such as `Manual` or the name of the repository where the dataset is archived. `Final_URL` should be the canonical DOI URL, for example `https://doi.org/10.xxxx/example`.
Once the manually created `Data_Registry.xlsx` is in the configured output directory, start the citation-search workflow with:

```r

source("R/02_find_dataset_citations.R")

```

Sites that do not use EDI should skip `R/05_compare_edi_citations.R`, because that report specifically compares Citation Finder results with journal citations recorded in EDI.

## Before running the workflow

### 1. Clone or download the repository

Open the **repository root** in RStudio. If you cloned this version, you can open
`dataset-citation-finder.Rproj` directly. Alternatively use:
`File > New Project > Existing Directory`
Choose the `dataset-citation-finder` directory, not the `R/` subfolder. Keeping the
repository root as the R working directory makes the relative paths in the workflow
predictable.

### 2. Install the required R packages once

From the repository root, run:

```r

source("setup.R")

```

`setup.R` installs missing packages into your local R package library. It does not
create citation-result files. The numbered workflow scripts load the packages but
do not install them automatically.

### 3. Edit `config.R`

Review the site-specific settings before running any workflow script:

- `edi_scope` - the site's EDI scope, such as `knb-lter-ble`.
- `zotero_group_id` - Zotero group ID, or `""` if Zotero is not used for the dataset-registry step.
- `website_collection` - Zotero collection used for publication comparison.
- `external_tag` - Zotero tag used to identify datasets archived outside EDI.
- `publication_types` - Zotero item types treated as publications.
- `site_keywords` - site-specific terms used for OpenAlex keyword discovery and PDF full-text searching.
- `output_dir` - where generated files are written.

By default, `output_dir` is `Citation_finder_output` in the repository root. The folder is created only when a workflow script needs it;
the script prints a message before creating it.
Existing output files with the same names are overwritten, so move or rename an old
report first if you need to keep it.

## API keys and `.Renviron`

API keys are not stored in the code and should never be committed to GitHub.
`.gitignore` excludes `.Renviron`.

### EDI API key

`EDI_API_KEY` is used by `EDIutils` to authenticate requests that require an EDI
identity, including the EDI registry harvest and EDI journal-citation comparison.
EDI registered users can create access keys from the EDI Identity and Access Manager;
the EDI documentation describes them under **Profile Menu > Access Keys**:
https://edirepository.org/resources/iam

### OpenAlex API key

`OPENALEX_API_KEY` is used for OpenAlex work searches, citation-graph queries, keyword
searches, and cited-by counts. The workflow can attempt limited keyless requests, but
it makes enough requests that a key is strongly recommended to increase the available
request budget and reduce rate-limit failures. OpenAlex documents free API keys here:
https://help.openalex.org/api/authentication/
After creating an OpenAlex account, the key is available at:
https://openalex.org/settings/api

### Create the environment variables

From the repository root in RStudio, run:

```r

file.edit(".Renviron")

```

Add your own values:

```text

EDI_API_KEY=your_edi_key
OPENALEX_API_KEY=your_openalex_key

```

Save the file and restart R so the variables are loaded. Confirm without printing the
secret values:

```r

nzchar(Sys.getenv("EDI_API_KEY"))
nzchar(Sys.getenv("OPENALEX_API_KEY"))

```

Each should return `TRUE` when configured.
For `R/01_get_dataset_dois.R`, EDI and Zotero are independent sources. If the EDI
scope or EDI key is missing, the script warns and continues with Zotero when Zotero is
configured. If the Zotero group/tag is missing, it skips Zotero and continues with
EDI. If neither source is configured, the script stops and explains what settings are
needed.

## Workflow

The main scripts are in the `R/` folder.

### 1. `R/01_get_dataset_dois.R`

Builds the dataset registry from EDI and/or the configured Zotero external-dataset
tag.

**Output:** `Citation_finder_output/Data_Registry.xlsx`
**Sheet: `Data_Registry`**

- `Scope` - EDI scope; blank for non-EDI datasets.
- `Identifier` - EDI package identifier; blank for non-EDI datasets.
- `Revision` - EDI package revision; blank for non-EDI datasets.
- `Dataset_Title` - dataset title.
- `Package_ID` - revisioned EDI package ID when applicable.
- `Dataset_DOI` - normalized dataset DOI.
- `Registry_Source` - `EDI` or `Zotero`.
- `Registry_Category` - registry/source category; Zotero rows use the configured

external tag.

- `Zotero_Item_Key` - Zotero item key for externally archived datasets.
- `Final_URL` -  canonical `https://doi.org/<Dataset_DOI>` URL.

### 2. `R/02_find_dataset_citations.R`

Uses the dataset registry to discover paper-dataset relationships with DataCite and
OpenAlex. It separately performs site-keyword searches in OpenAlex and checks PDF text
when OpenAlex supplies a PDF URL.
**Outputs:**

- `Citation_finder_output/Publication_Search_Results.xlsx`
- `Citation_finder_output/openalex_cache.rds`

The cache is reused to reduce repeated OpenAlex requests.

#### Sheet: `Publication_Search`

One row per unique `Paper_DOI + Dataset_DOI` discovered from API/metadata searches.
Columns are:

- `Paper_DOI` - normalized publication DOI.
- `Paper_Title` - publication title when available.
- `Year` - publication year when available.
- `Dataset_Package_ID` - package ID from the registry.
- `Dataset_DOI` - dataset DOI associated with the publication.
- `Dataset_Title` - dataset title from the registry.
- `Search_Source` - service(s) that supplied evidence. Possible components are

`DataCite` and `OpenAlex`; multiple sources can be combined as `DataCite + OpenAlex`.

- `Search_Method` - one or more evidence methods, separated by semicolons when the
same relationship was found in more than one way.
`Search_Method` values mean:
- `Citation relationship` - DataCite returned a structured citation relationship.
- `Exact relatedIdentifier` - DataCite returned a work whose related identifier
exactly matches the dataset DOI.
- `Citation graph` - OpenAlex reports that the publication cites the OpenAlex work
associated with the dataset DOI.
- `Dataset DOI text` - an OpenAlex search for the exact dataset DOI returned the work.
- `Final URL text` - an OpenAlex search for the canonical dataset DOI URL returned
the work.
These are discovery/evidence signals and should still be manually reviewed before
curating EDI or Zotero records.

#### Sheet: `PDF_Results`

This sheet contains \*\*only papers discovered through the configured site-keyword
searches in OpenAlex\*\*. It is not a list of every PDF for every relationship in
`Publication_Search`, and it does not automatically PDF-check every paper found from
DataCite dataset-DOI searches.
Key columns are:

- `Paper_Title`, `Paper_DOI`, `Year` - candidate publication metadata.
- `Discovery_Keyword` - site keyword(s) used in the OpenAlex search that caused the
paper to be returned as a candidate.
- `Matched_Site_Keyword` - site keyword(s) actually found in the extracted PDF text.

Therefore, `Discovery_Keyword` and `Matched_Site_Keyword` are not the same thing:
the first records how the candidate was discovered; the second records what the
workflow actually found in the PDF text.

- `Dataset_DOI`, `Dataset_Title` - populated when an exact registered dataset
reference is confirmed in the PDF text.

- `Matched_Dataset_Reference` - whether the PDF contained the dataset DOI, canonical
final URL, or both.

- `PDF_URL` - OpenAlex PDF URL used for the check.
- `PDF_Status` - result of the PDF check. Possible values include:

`No direct OA PDF URL`, `PDF download failed`, `PDF URL returned HTML, not PDF`,
`Downloaded URL is not a readable PDF`, `PDF text extraction failed`,
`PDF searched: keyword may match, but no exact dataset DOI/final URL`, and
`Confirmed: exact dataset DOI/final URL found`.

#### Sheet: `Final_Relationships`

This is the combined, deduplicated paper-dataset relationship table used by downstream
comparison scripts. It contains API/metadata relationships plus any additional exact
relationships confirmed through PDF verification.
Columns are `Dataset_DOI`, `Paper_DOI`, `Paper_Title`, `Year`, and `Found_By`.
`Found_By` records the evidence contributing to the relationship.
`Final_Relationships` can have more rows than `Publication_Search`. For example, if
`Publication_Search` has 56 rows and `Final_Relationships` has 57, the extra row is a
paper-dataset pair that was confirmed from PDF text but was not returned by the
DataCite/OpenAlex metadata searches. The script now prints the PDF-only relationship(s)
to the R console so this difference can be reviewed directly.

### 3. `R/03_compare_zotero.R`

Compares `Final_Relationships` with the configured Zotero website/publication
collection and adds OpenAlex cited-by counts where a paper DOI is available.
**Output:** `Citation_finder_output/Zotero_Comparison.xlsx`
The workbook contains:

- `Zotero_For_Website` - current publications from the configured Zotero collection,
including item key, paper DOI/title/type, dataset DOI evidence from Extra, cited-by
count, and the Extra field.

- `Missing_From_Zotero` - a publication DOI found by Citation Finder is not present
in the Zotero collection at all.

- `Zotero_Missing_Data_DOI` - the publication exists in Zotero, but the specific

`Paper_DOI + Dataset_DOI` relationship found by Citation Finder is missing from
Zotero Extra.

- `Zotero_Not_In_Search` - Zotero Extra records a specific paper-dataset relationship
that the automated Citation Finder did not find.
These three review categories are intentionally different. A paper that already
exists in Zotero but is missing one dataset relationship belongs in
`Zotero_Missing_Data_DOI`, not `Missing_From_Zotero`.

### 4. `R/04_create_zotero_publication_list.R`

Creates a human-readable publication list from the configured Zotero collection.

**Output:** `Citation_finder_output/Zotero_Comprehensive_Publication_List.xlsx`
**Sheet: `Zotero_Publications`**

- `Paper_Title` - Zotero title.
- `Paper_Authors` - authors separated by semicolons.
- `Paper_DOI` - publication DOI when present.
- `Publication_Category` - `Foundational`, `Supported`, or both when those Zotero
tags are present.

- `Dataset_DOIs` - dataset DOIs found in Extra; multiple values are separated by
semicolons.

- `Cited_By_Count` - OpenAlex citation count for the publication DOI; blank when a
DOI or OpenAlex match is unavailable.

### 5. `R/05_compare_edi_citations.R`

Retrieves journal citations recorded in EDI and compares exact
`dataset series + paper DOI` relationships with Citation Finder results. It does not
automatically create or modify EDI journal citations.
**Output:** `Citation_finder_output/EDI_Journal_Citation_Comparison.xlsx`
**Sheet: `EDI_Citation_Comparison`**
Columns are:

- `Dataset_Package_ID` - dataset series identifier used for comparison.
- `Dataset_DOI` - DOI associated with the EDI package/revision when available.
- `Dataset_Title` - dataset title.
- `Paper_DOI` - publication DOI; can be blank for an EDI citation that has no DOI.
- `Paper_Title` - publication title.
- `Year` - publication year when available from Citation Finder.
- `EDI_Citation_ID` - EDI journal citation identifier when present.
- `EDI_Status` - comparison result.

`EDI_Status` values are:

- `Already in EDI` - the exact dataset-series + paper DOI relationship occurs in
both Citation Finder and EDI.

- `Missing from EDI` - Citation Finder found the relationship but EDI did not contain
that exact pair. Manually verify before adding anything to EDI.

- `In EDI - Not in Citation Finder` - EDI contains a citation for the dataset,
 but Citation Finder did not find the same dataset paper DOI relationship. 
 EDI citations without a paper DOI are also assigned this status because they cannot be matched automatically using DOI-based comparison.

## Recommended run order

For the main discovery and Zotero-comparison workflow:

```r

source("R/01_get_dataset_dois.R")
source("R/02_find_dataset_citations.R")
source("R/03_compare_zotero.R")

```

Then run either or both additional reports as needed:

```r

source("R/04_create_zotero_publication_list.R")
source("R/05_compare_edi_citations.R")

```

`R/05_compare_edi_citations.R` depends on the outputs from steps 1 and 2.

## Review before curation

The workflow is designed to support citation discovery and review, not to make
unattended changes to Zotero or EDI. DataCite/OpenAlex metadata relationships,
keyword matches, and PDF matches are evidence with different strengths. Review the
results before adding, removing, or modifying citation records in another system.

## Contributing
when updating the code and publishing a new release, be sure to also:

1. Update the date at the top of this readme.
2. Update the version in the DESCRIPTION file.
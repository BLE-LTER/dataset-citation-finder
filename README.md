# Dataset Citation Finder

Last updated: 2026-09-18

## Overview

Dataset Citation Finder is an R workflow for identifying publications that cite,
reference, or are otherwise associated with Long Term Ecological Research (LTER)
datasets. It combines dataset information from the Environmental Data Initiative
(EDI) and, optionally, Zotero with publication evidence from DataCite and
OpenAlex. When an OpenAlex keyword search returns a paper with an accessible PDF,
the workflow can also search the extracted PDF text for site terms and for exact
dataset references.

Everything the workflow produces is evidence for a person to review. The scripts
never add, change, or delete records in EDI or Zotero.

## Repository structure

The repository contains configuration files, shared utilities, and five numbered
workflow scripts.

### Configuration and setup

- `config.R` holds all site-specific settings: the EDI scope, the Zotero
  settings, the site search terms, and the output location. It also reads the
  project `.Renviron` so that API keys are available to every script.
- `setup.R` installs the R packages the workflow needs. It only has to be run
  once, during initial setup.
- `R/utils.R` holds the functions shared by more than one script, such as
  `safe()`, `clean_doi()`, and the OpenAlex request helpers. The numbered scripts
  source it automatically, so it is never run on its own.
- `dataset-citation-finder.Rproj` is an RStudio project file. Opening it makes
  the repository root the R working directory, which is what the scripts expect.

### Workflow scripts

The workflow scripts are in the `R/` folder and are numbered in their usual order
of execution:

1. `01_get_dataset_dois.R` builds the dataset registry by retrieving dataset DOIs
   from EDI and Zotero.
2. `02_find_dataset_citations.R` searches for publications associated with those
   datasets and checks available publication full text.
3. `03_compare_zotero.R` compares the discovered relationships with the
   publication information already recorded in Zotero.
4. `04_create_zotero_publication_list.R` creates a comprehensive Zotero
   publication list with available citation counts.
5. `05_compare_edi_citations.R` compares the discovered relationships with the
   journal citations recorded in EDI.

### Output files

Results are written to the `Citation_finder_output` folder in the repository
root. The folder is created the first time a script needs to save a file, and
each script prints a message before creating it. Existing output files with the
same names are overwritten, so move or rename an old report first if you need to
keep it. The output location can be changed with `output_dir` in `config.R`.

## What is the dataset registry?

The dataset registry is the master list of dataset DOIs that the rest of the
workflow searches for. It is a single worksheet, `Data_Registry`, inside
`Data_Registry.xlsx`. `R/01_get_dataset_dois.R` knows how to discover dataset
DOIs from exactly two sources:

1. **EDI.** Every DOI-bearing revision in the EDI scope configured as
   `edi_scope`.
2. **Zotero.** Datasets that the site funded or used but that are archived
   somewhere other than EDI, found by looking for the Zotero tag configured as
   `external_tag`.

Datasets archived anywhere else are not discovered automatically and have to be
added to the registry by hand.

### How the Zotero source works

Using Zotero this way is a BLE convention rather than an LTER-wide requirement,
and BLE may be the only site that does it. BLE keeps a Zotero **group** whose
items include the datasets it has funded, and tags the ones archived outside EDI
with `LTER-Funded Data at Other Archives`. `R/01_get_dataset_dois.R` asks the
Zotero API for the top-level items in that group carrying that tag, and takes the
DOI from each item's DOI, URL, or Extra field.

Two details matter for another site trying this:

- The setting is a **group ID** (`zotero_group_id`), not a personal library or a
  collection. The separate `website_collection` setting is a collection name, and
  it is used only by the publication-comparison scripts, 03 and 04.
- The requests are unauthenticated, so the group has to be readable through the
  Zotero API. A private group will not work without adding authentication.

Another site can point `external_tag` at whatever tag it uses, or leave the
Zotero settings blank and build the registry from EDI alone.

### When a source is not configured

EDI and Zotero are independent of each other in `R/01_get_dataset_dois.R`:

- If the EDI settings are incomplete, meaning `edi_scope` in `config.R` or
  `EDI_API_KEY` in `.Renviron` is missing, the script says which one is missing,
  warns, skips EDI, and builds the registry from Zotero.
- If the Zotero settings are incomplete, meaning `zotero_group_id` or
  `external_tag` is missing, the script warns, skips Zotero, and builds the
  registry from EDI.
- If both are incomplete, the script stops and lists the settings it needs. It
  does not write an output file in that case.

The completion message reports which sources were actually used, so the row
counts are not mistaken for a complete picture of the site's datasets.

## Sites that do not use EDI or do not use Zotero

The citation search itself does not depend on EDI or Zotero. It only needs a
dataset registry.

### If your site does not use EDI

Create `Data_Registry.xlsx` by hand, save it in the directory set by `output_dir`
in `config.R`, and make sure the workbook contains a worksheet named
`Data_Registry` with the same column names that `R/01_get_dataset_dois.R`
produces:

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

The EDI-specific fields (`Scope`, `Identifier`, `Revision`, and `Package_ID`) can
be left blank, and so can `Zotero_Item_Key`. At minimum every dataset needs a
`Dataset_Title` and a `Dataset_DOI`. Set `Registry_Source` to something like
`Manual` or the name of the repository holding the dataset, and set `Final_URL`
to the canonical DOI URL, for example `https://doi.org/10.xxxx/example`.

With that file in place, start the workflow at the second script:

```r
source("R/02_find_dataset_citations.R")
```

Skip `R/05_compare_edi_citations.R`, because that report compares results with
journal citations recorded in EDI.

### If your site does not use Zotero

Leave `zotero_group_id` and `external_tag` blank in `config.R`. Script 01 will
build the registry from EDI only, and script 02 will run normally.

Skip `R/03_compare_zotero.R` and `R/04_create_zotero_publication_list.R`, since
both read publications from a Zotero collection. Both scripts stop with an
explanatory message if they are run without Zotero settings.

## Before running the workflow

### 1. Clone or download the repository, then open the project

Open the **repository root** in RStudio, not the `R/` subfolder. Either
double-click `dataset-citation-finder.Rproj`, or use
`File > New Project > Existing Directory` and choose the `dataset-citation-finder`
directory. Opening the project makes the repository root the working directory,
which keeps the relative paths in the scripts predictable.

### 2. Install the required R packages once

From the repository root, run:

```r
source("setup.R")
```

`setup.R` installs missing packages into your local R package library. It does
not create any citation results. The workflow scripts load the packages they need
but do not install them; if something is missing they stop and tell you to run
`setup.R`.

### 3. Edit `config.R`

Review the site-specific settings before running any workflow script:

- `edi_scope` - the site's EDI scope, such as `knb-lter-ble`. Leave it blank to
  skip EDI.
- `zotero_group_id` - the Zotero group ID, or `""` if Zotero is not used.
- `website_collection` - the Zotero collection holding publications, used by
  scripts 03 and 04.
- `external_tag` - the Zotero tag marking datasets archived outside EDI, used by
  script 01.
- `publication_types` - the Zotero item types treated as publications.
- `site_keywords` - site-specific terms used for OpenAlex keyword discovery and
  for searching PDF text.
- `output_dir` - where generated files are written.

## API keys and `.Renviron`

The workflow uses two API keys. Neither is stored in the code, and neither should
ever be committed to GitHub; `.gitignore` already excludes `.Renviron`.

### EDI API key

`EDI_API_KEY` is used by `EDIutils` to authenticate requests that need an EDI
identity: the EDI registry harvest in script 01 and the journal-citation
comparison in script 05. Registered EDI users can create access keys in the EDI
Identity and Access Manager, documented under **Profile Menu > Access Keys**:

<https://edirepository.org/resources/iam>

### OpenAlex API key

`OPENALEX_API_KEY` is used for the OpenAlex work searches, citation-graph
queries, keyword searches, and cited-by counts in scripts 02, 03, and 04. The
workflow can attempt requests without a key, but it makes enough requests that a
key is strongly recommended: it raises the available request budget and reduces
rate-limit failures. Scripts warn when the key is absent. OpenAlex documents free
API keys here:

<https://help.openalex.org/api/authentication/>

After creating an OpenAlex account, the key is available at:

<https://openalex.org/settings/api>

### Create the environment variables

Because `.Renviron` is not committed, each user has to create their own. From the
repository root in RStudio, run:

```r
file.edit(".Renviron")
```

Add your own values, one per line:

```text
EDI_API_KEY=your_edi_key
OPENALEX_API_KEY=your_openalex_key
```

Save the file and restart R. `config.R` reads the project `.Renviron` itself, so
the keys are picked up even if the R session was started somewhere other than the
repository root. Keys set as operating-system environment variables also work.

Confirm the values are loaded without printing the secrets themselves:

```r
nzchar(Sys.getenv("EDI_API_KEY"))
nzchar(Sys.getenv("OPENALEX_API_KEY"))
```

Each should return `TRUE` when configured.

## Workflow

### 1. `R/01_get_dataset_dois.R`

Builds the dataset registry from EDI and from the configured Zotero
external-dataset tag. See "When a source is not configured" above for what
happens if one of the two sources is unavailable.

**Output:** `Citation_finder_output/Data_Registry.xlsx`

Sheet `Data_Registry`, sorted by scope, identifier, revision, and dataset title:

- `Scope` - EDI scope; blank for non-EDI datasets.
- `Identifier` - EDI package identifier; blank for non-EDI datasets.
- `Revision` - EDI package revision; blank for non-EDI datasets.
- `Dataset_Title` - dataset title.
- `Package_ID` - revisioned EDI package ID, where applicable.
- `Dataset_DOI` - normalized dataset DOI.
- `Registry_Source` - `EDI` or `Zotero`.
- `Registry_Category` - source category; Zotero rows carry the configured
  external tag.
- `Zotero_Item_Key` - Zotero item key for externally archived datasets.
- `Final_URL` - canonical `https://doi.org/<Dataset_DOI>` URL.

### 2. `R/02_find_dataset_citations.R`

Uses the dataset registry to discover paper-dataset relationships through
DataCite and OpenAlex. Separately, it runs site-keyword searches in OpenAlex and
checks PDF text whenever OpenAlex supplies a PDF URL.

**Outputs:**

- `Citation_finder_output/Publication_Search_Results.xlsx`
- `Citation_finder_output/openalex_cache.rds`, reused on later runs to reduce
  repeated OpenAlex requests.

#### Sheet: `Publication_Search`

One row per unique `Paper_DOI` + `Dataset_DOI` discovered through API and
metadata searches:

- `Paper_DOI` - normalized publication DOI.
- `Paper_Title` - publication title, when available.
- `Year` - publication year, when available.
- `Dataset_Package_ID` - package ID from the registry.
- `Dataset_DOI` - dataset DOI associated with the publication.
- `Dataset_Title` - dataset title from the registry.
- `Search_Source` - which service supplied the evidence. The possible components
  are `DataCite` and `OpenAlex`, and both can appear as `DataCite + OpenAlex`.
- `Search_Method` - how the relationship was found. Multiple values are separated
  by semicolons when the same relationship was found more than one way.

The `Search_Method` values mean:

- `Citation relationship` - DataCite returned a structured citation relationship.
- `Exact relatedIdentifier` - DataCite returned a work whose related identifier
  exactly matches the dataset DOI.
- `Citation graph` - OpenAlex reports that the publication cites the OpenAlex work
  associated with the dataset DOI.
- `Dataset DOI text` - an OpenAlex search for the exact dataset DOI returned the
  work.
- `Final URL text` - an OpenAlex search for the canonical dataset DOI URL
  returned the work.

These are discovery signals of differing strength, and all of them should be
reviewed by a person before anything is curated in EDI or Zotero.

#### Sheet: `PDF_Results`

This sheet contains **only papers discovered through the configured site-keyword
searches in OpenAlex**. It is not a list of every PDF for every relationship in
`Publication_Search`, and it does not PDF-check the papers found through the
DataCite dataset-DOI searches. Every keyword candidate gets a row, including
candidates whose PDF could not be read, so that `PDF_Status` explains what
happened.

- `Paper_Title`, `Paper_DOI`, `Year` - candidate publication metadata.
- `Discovery_Keyword` - the site keyword or keywords whose OpenAlex search
  returned this paper as a candidate.
- `Matched_Site_Keyword` - the site keyword or keywords actually found in the
  extracted PDF text.
- `Dataset_DOI`, `Dataset_Title` - filled in only when an exact registered
  dataset reference is confirmed in the PDF text.
- `Matched_Dataset_Reference` - whether the PDF contained the dataset DOI, the
  canonical final URL, or both.
- `PDF_URL` - the OpenAlex PDF URL used for the check.
- `PDF_Status` - the result of the check.

`Discovery_Keyword` and `Matched_Site_Keyword` are therefore two different
things: the first records how the candidate was discovered, and the second
records what the workflow actually found inside the PDF. A paper can be
discovered by one keyword and contain a different one, or contain none at all if
the PDF text could not be searched.

The possible `PDF_Status` values are `No direct OA PDF URL`,
`PDF download failed`, `PDF URL returned HTML, not PDF`,
`Downloaded URL is not a readable PDF`, `PDF text extraction failed`,
`PDF searched: keyword may match, but no exact dataset DOI/final URL`, and
`Confirmed: exact dataset DOI/final URL found`.

#### Sheet: `Final_Relationships`

The combined, deduplicated paper-dataset relationship table used by the
comparison scripts, 03 and 05. It contains the API and metadata relationships
plus any additional exact relationships confirmed through PDF verification. Its
columns are `Dataset_DOI`, `Paper_DOI`, `Paper_Title`, `Year`, and `Found_By`,
where `Found_By` records the evidence behind the relationship.

`Final_Relationships` can legitimately have more rows than `Publication_Search`.
If `Publication_Search` has 56 rows and `Final_Relationships` has 57, the extra
row is a paper-dataset pair that was confirmed from PDF text but was not returned
by the DataCite or OpenAlex metadata searches. The script prints the count of
PDF-only relationships and lists them in the R console, so the difference can be
checked on any given run.

### 3. `R/03_compare_zotero.R`

Compares `Final_Relationships` with the configured Zotero publication collection
and adds OpenAlex cited-by counts where a paper DOI is available.

**Output:** `Citation_finder_output/Zotero_Comparison.xlsx`

- `Zotero_For_Website` - the publications currently in the configured Zotero
  collection, with item key, paper DOI, title and type, the dataset DOI evidence
  found in the Extra field, and the cited-by count.
- `Missing_From_Zotero` - a publication DOI that Citation Finder found and that is
  not in the Zotero collection at all.
- `Zotero_Missing_Data_DOI` - the publication is in Zotero, but the specific
  `Paper_DOI` + `Dataset_DOI` relationship Citation Finder found is missing from
  the Zotero Extra field.
- `Zotero_Not_In_Search` - Zotero Extra records a paper-dataset relationship that
  the automated search did not find.

Those three review categories are deliberately separate. A paper already in
Zotero that is missing one dataset relationship belongs in
`Zotero_Missing_Data_DOI`, not in `Missing_From_Zotero`.

### 4. `R/04_create_zotero_publication_list.R`

Creates a human-readable publication list from the configured Zotero collection.

**Output:** `Citation_finder_output/Zotero_Comprehensive_Publication_List.xlsx`

Sheet `Zotero_Publications`:

- `Paper_Title` - the Zotero title.
- `Paper_Authors` - authors separated by semicolons.
- `Paper_DOI` - publication DOI, when present.
- `Publication_Category` - `Foundational`, `Supported`, or both, based on those
  Zotero tags.
- `Dataset_DOIs` - dataset DOIs found in the Extra field, separated by semicolons
  when there is more than one.
- `Cited_By_Count` - the OpenAlex citation count for the publication DOI; blank
  when no DOI or no OpenAlex match is available.

### 5. `R/05_compare_edi_citations.R`

Retrieves the journal citations recorded in EDI and compares exact
`dataset series + paper DOI` relationships with Citation Finder results. It does
not create or modify EDI journal citations.

**Output:** `Citation_finder_output/EDI_Journal_Citation_Comparison.xlsx`

Sheet `EDI_Citation_Comparison`:

- `Dataset_Package_ID` - the dataset series identifier used for the comparison.
- `Dataset_DOI` - the DOI of the EDI package or revision, when available.
- `Dataset_Title` - dataset title.
- `Paper_DOI` - publication DOI; can be blank for an EDI citation that has none.
- `Paper_Title` - publication title.
- `Year` - publication year, when Citation Finder supplied one.
- `EDI_Citation_ID` - the EDI journal citation identifier, when present.
- `EDI_Status` - the comparison result.

The `EDI_Status` values are:

- `Already in EDI` - the exact dataset series and paper DOI pair appears in both
  Citation Finder and EDI.
- `Missing from EDI` - Citation Finder found the relationship but EDI does not
  contain that exact pair. Verify it manually before adding anything to EDI.
- `In EDI - Not in Citation Finder` - EDI contains a citation for the dataset, but
  Citation Finder did not find the same dataset and paper DOI relationship. EDI
  citations with no paper DOI also get this status, because they cannot be matched
  automatically by DOI.

## Recommended run order

For the main discovery and Zotero-comparison workflow:

```r
source("R/01_get_dataset_dois.R")
source("R/02_find_dataset_citations.R")
source("R/03_compare_zotero.R")
```

Then run either or both of the additional reports as needed:

```r
source("R/04_create_zotero_publication_list.R")
source("R/05_compare_edi_citations.R")
```

Scripts 03, 04, and 05 all depend on output from the earlier steps, so run 01 and
02 first.

## Review before curation

The workflow is designed to support citation discovery and review, not to make
unattended changes to Zotero or EDI. DataCite and OpenAlex metadata
relationships, keyword matches, and PDF matches are evidence of different
strengths. Review the results before adding, removing, or modifying citation
records in another system.

## Contributing

When updating the code and publishing a new release, also update the
"Last updated" date at the top of this README.

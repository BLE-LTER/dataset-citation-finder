# Dataset Citation Finder

An R workflow for finding publications associated with each LTER dataset.

Last updated: 2026-09-30

Originally created by the Beaufort Lagoon Ecosystems (BLE) LTER.

## What the workflow does

The workflow has two steps:

1. **Build the dataset registry.** Script 01 collects DOI-bearing revisions of
   EDI datasets and, optionally, datasets cataloged in Zotero with a dataset tag.
2. **Find and reconcile dataset citations.** Script 02 searches DataCite and
   OpenAlex, checks available PDFs from site-keyword searches, and optionally
   retrieves EDI journal citations and Zotero publication Extra-field links.
   It writes source evidence, combined results, and curation reports to one
   Excel workbook.

Everything is evidence for a person to review. The scripts never add, change,
or delete records in EDI or Zotero. The workflow does not create a general
publication list or retrieve publication citation counts.

## First run at your site

You need R installed; RStudio is optional but provides a convenient way to open
and run the project. Enter the commands shown in this guide in the **R console**.
The "repository root" means the folder containing `config.R` and `setup.R`.

1. Clone or download this repository and open `dataset-citation-finder.Rproj`
   in RStudio. Without RStudio, set R's working directory to the repository root.
2. Follow [Setup](#setup) to install packages, replace the BLE example settings
   with your site's settings, and add your API keys. **Do this before running
   either workflow script**; the supplied settings point to BLE's datasets and
   publication collection.
3. Run `source("R/01_get_dataset_dois.R")`. Open `Data_Registry.xlsx` in the
   output folder and check that it includes the datasets and revisions you
   expect. If you maintain the registry yourself, use the
   [manual-registry instructions](#using-a-manually-maintained-registry) instead.
4. Close the workbooks in Excel, then run `source("R/02_find_dataset_citations.R")`.
   Wait for the R console to print `Saved results:` and the output path. Step 02
   makes many requests and PDF checks, so completion time depends on your registry,
   keywords, and available services.
5. Open `Publication_Search_Results.xlsx`. Start with `Result_Counts` for an
   overview, then `Combined_Results` for individual dataset citations. Use
   [Reviewing the workbook](#reviewing-the-workbook) to follow up on the evidence
   and suggested catalog changes.

The default output folder is `Citation_finder_output` inside the repository.
There is no need to run the helpers or tests for ordinary use.

## Setup

Open `dataset-citation-finder.Rproj` in RStudio, or set the R working directory
to the repository root. Install the required packages once:

```r
source("setup.R")
```

Scripts load packages but do not install them. Edit `config.R` before running
any workflow script; its defaults describe BLE and should be changed for
another site.

### Choose the sources your site uses

The dataset registry tells Step 02 **which datasets to search for**. It is
separate from the publication collection that Step 02 searches for existing
Zotero links. You can use EDI, Zotero, both, or a manually maintained registry.

| What you want to do | Settings to provide | How to skip it |
| --- | --- | --- |
| Get dataset DOIs from EDI in Step 01 and existing journal links in Step 02 | Your `edi_scope` and `EDI_API_KEY` | Set `edi_scope <- ""`. |
| Add non-EDI datasets cataloged in Zotero to the Step 01 registry | `zotero_group_id` and `zotero_dataset_tag` | Set `zotero_dataset_tag <- ""`. |
| Read dataset links from Zotero publications in Step 02 and produce Zotero review sheets | `zotero_group_id` and `zotero_publication_collection_id` | Set `zotero_publication_collection_id <- ""`. |

For example, a site using EDI but no Zotero should set its own `edi_scope` and
clear all three Zotero settings. A site using Zotero only for publications can
set the group and publication collection while leaving `zotero_dataset_tag`
blank. Setting `zotero_group_id <- ""` disables both Zotero uses.

DataCite/OpenAlex discovery and PDF checking remain available regardless of
these optional catalog integrations. If neither source will build your dataset
registry, provide one manually and start at Step 02.

### API keys

Store keys in a local `.Renviron` file in the repository root, not in scripts.
`.gitignore` excludes `.Renviron`. From RStudio:

```r
file.edit(".Renviron")
```

Add the keys you use, then save:

```text
EDI_API_KEY="your_edi_key"
OPENALEX_API_KEY="your_openalex_key"
```

Restart R after editing. `config.R` also reads the project `.Renviron` itself,
so keys are available when R started elsewhere. Operating-system environment
variables also work. To check that a key is present without printing it:

```r
nzchar(Sys.getenv("EDI_API_KEY"))
nzchar(Sys.getenv("OPENALEX_API_KEY"))
```

- **EDI:** `EDI_API_KEY` authenticates the EDI requests in scripts 01 and 02.
  Registered EDI users can create access keys through the Identity and Access
  Manager; see [EDI access-key instructions](https://edirepository.org/resources/iam).
  Step 02 requires this key whenever `edi_scope` is configured.
- **OpenAlex:** `OPENALEX_API_KEY` is recommended for the many discovery requests
  in Step 02. Without it, the script attempts keyless requests and warns that
  results may be incomplete because of rate limits. See
  [OpenAlex authentication](https://help.openalex.org/api/authentication/) and
  [account settings](https://openalex.org/settings/api).
- **Zotero:** the current implementation uses unauthenticated group requests.
  The configured group and publication collection must be publicly readable
  through the Zotero API. Private-group authentication is not implemented.

### Site settings

| Setting | Purpose |
| --- | --- |
| `edi_scope` | EDI scope, such as `knb-lter-ble`. Set to `""` to skip EDI in both steps. |
| `zotero_group_id` | Numeric Zotero group ID as a string; set to `""` to disable Zotero. |
| `zotero_dataset_tag` | Tag identifying externally archived datasets for Step 01. Independent of the publication collection. |
| `zotero_publication_collection_id` | Collection key identifying publications for Step 02. |
| `deduplicate_on_dataset_id` | `TRUE` (default) merges dataset revisions per publication; `FALSE` matches exact dataset DOIs. |
| `site_keywords` | Terms used for OpenAlex keyword discovery and PDF text searches. |
| `output_dir` | Folder containing the input registry and generated results. |
| `cache_max_age_days` | Maximum age of reusable OpenAlex search responses. |

Find the group ID in the group's web address. For example,
`https://www.zotero.org/groups/2211939/ble_lter` has group ID `2211939`.
Find the publication collection key by opening that collection on the web:
`https://www.zotero.org/groups/lter-ble/collections/KHTHLKB5` has collection key
`KHTHLKB5`. Use the key, not the collection's display name.

BLE uses Zotero in two independent ways: a tag identifies datasets archived
outside EDI, and a publication collection contains items whose Extra fields
record dataset DOIs. You may configure either or both uses. Both use the same
`zotero_group_id`.

Replace the BLE `site_keywords` with your site's name, acronym, EDI scope,
and other distinctive terms used in publications. These terms control the
additional keyword/PDF search, not which datasets are in the registry.

Leave `deduplicate_on_dataset_id <- TRUE` if you want a dataset-level view
across EDI revisions. Use `FALSE` if you need a separate result and count for
each dataset DOI. [The worked example](#choosing-a-deduplication-mode)
shows how this choice affects both the combined results and revision review.

### How to record dataset links in Zotero

Step 02 reads the **Extra field of publication items** in the configured
collection. Put the publication's own DOI in its DOI field. Put the DOIs of
its cited datasets in Extra, for example:

```text
Dataset DOI: 10.1234/example-dataset-a
Dataset DOI: https://doi.org/10.1234/example-dataset-b
```

These are illustrative DOIs; use the actual dataset DOIs from your registry.
Several dataset DOIs can appear in one Extra field. The text label is optional,
and existing unrelated Extra text can remain. Dataset links recorded only in
Zotero tags, notes, or Related items are not searched by this workflow.

## Step 01: build the dataset registry

```r
source("R/01_get_dataset_dois.R")
```

**Output:** `Citation_finder_output/Data_Registry.xlsx`, sheet `Data_Registry`.
The default output folder is in the repository root.

EDI harvesting includes every DOI-bearing revision in `edi_scope`. Zotero
harvesting reads group items bearing `zotero_dataset_tag` and takes the dataset
DOI from each item's DOI or URL field. This tagged-dataset convention is used
by BLE; it is not required of other LTER sites.

The registry columns are:

- `Scope`, `Identifier`, `Revision`: EDI package components, when applicable.
- `Package_ID`: full revisioned EDI ID, such as `knb-lter-ble.12.7`.
- `Dataset_DOI`, `Dataset_Title`: normalized DOI and dataset title.
- `Registry_Source`, `Registry_Category`: where the registry row came from.
- `Zotero_Item_Key`: Zotero dataset item key, when applicable.
- `Final_URL`: canonical dataset DOI URL.

Step 01 treats its sources independently. If EDI scope/key settings are
incomplete, it warns and skips EDI. If Zotero group/tag settings are incomplete,
it warns and skips Zotero. If neither source is configured, it stops without
writing a registry.

### Using a manually maintained registry

Datasets in other repositories can be added manually. You can also skip Step 01
entirely and create `Data_Registry.xlsx` in `output_dir`. Include a sheet named
`Data_Registry` with these exact ten column headers (one column per name):

```text
Scope, Identifier, Revision, Dataset_Title, Package_ID, Dataset_DOI,
Registry_Source, Registry_Category, Zotero_Item_Key, Final_URL
```

Each row needs a dataset DOI and title. Set `Registry_Source` to `Manual` or
the repository name and `Final_URL` to the canonical `https://doi.org/<DOI>`
address. EDI-specific fields and
`Zotero_Item_Key` can be blank for externally archived datasets.

For EDI datasets, provide each revision's actual package ID and DOI. The full
`Package_ID` supplies the scope, dataset identifier, and revision used for
series matching and revision recommendations. Datasets without a valid
revisioned package ID are matched by DOI.

Rerunning Step 01 replaces `Data_Registry.xlsx`, including manual additions.
Keep a separate copy of your manually maintained data. If you refresh the
registry with Step 01, reapply any manual additions before running Step 02.

## Step 02: discover and reconcile citations

```r
source("R/02_find_dataset_citations.R")
```

**Output:** `Citation_finder_output/Publication_Search_Results.xlsx`.
This is the complete citation and curation report; there are no subsequent
comparison scripts to run.

The DataCite/OpenAlex searches and keyword/PDF checks run for the dataset
registry. Optional sources are controlled independently:

- When `edi_scope` is set, retrieve EDI journal citations for registry dataset
  series in that scope. A missing EDI key stops Step 02 before discovery.
- When **both** `zotero_group_id` and `zotero_publication_collection_id` are set,
  retrieve top-level items in that publication collection. Notes and attachments
  are excluded. No dataset tag is required for this publication search.
- When a service is disabled, its source and curation sheets are omitted.
  A configured source with no records produces empty sheets with headers.

A failed EDI request, inaccessible Zotero collection, or failed Zotero page
request stops the run instead of producing a misleading missing-link report
from incomplete catalog data. An existing results workbook is not replaced by
that failed run; it still contains the previous results. Retry Step 02 after
resolving the problem. PDF errors are recorded per candidate and discovery
continues.

### Reviewing the workbook

| Start here | What to look for | Next action |
| --- | --- | --- |
| `Result_Counts` | How many publications were found for each dataset or series, including zeros | Check that the dataset coverage and chosen deduplication mode suit your reporting purpose. |
| `Combined_Results` | Which publication cites which dataset, with supporting evidence | Filter by dataset, then inspect `Supporting_Sources` and `Found_By`. |
| `DataCite_Citations`, `PDF_Citations`, and any EDI/Zotero source sheets | The original source evidence and dataset revision | Check the actual publication or catalog record before acting on a proposed link. |
| The curation sheets | Publications, dataset links, or revisions that may need attention | Review and make any agreed changes manually in Zotero or EDI; rerun Step 02 to check the updated records. |

A missing optional source sheet means that integration was disabled. Revision
mismatch sheets also require series mode (`deduplicate_on_dataset_id <- TRUE`).
An empty sheet for an enabled integration means no matching records or review
items were found in that run. `PDF_Citations` also includes unsuccessful PDF
checks; not every row in that source sheet is a confirmed citation.

### Source sheets

Source worksheets preserve revision-level evidence regardless of the
`deduplicate_on_dataset_id` setting. Combining results never rewrites these
sheets to the selected revision.

#### `DataCite_Citations`

This sheet includes both DataCite and OpenAlex evidence; `Search_Source`
identifies which service found each relationship.
One row per paper DOI + dataset DOI discovered through those services:

- `Paper_DOI`, `Paper_Title`, `Year`: publication metadata.
- `Dataset_Package_ID`, `Dataset_DOI`, `Dataset_Title`: dataset registry metadata.
- `Search_Source`: `DataCite`, `OpenAlex`, or both.
- `Search_Method`: the evidence method or methods.

Methods are `Citation relationship` and `Exact relatedIdentifier` from DataCite,
and `Citation graph`, `Dataset DOI text`, and `Final URL text` from OpenAlex.
These methods supply different strengths of evidence and require review.

#### `PDF_Citations`

These are papers discovered by **site-keyword searches** in OpenAlex. This is
not a PDF check of every paper found by the dataset-DOI searches. Every keyword
candidate is retained, including candidates with no accessible or readable PDF.

- `Paper_Title`, `Paper_DOI`, `Year`: candidate metadata.
- `Discovery_Keyword`: configured terms that caused the candidate to be found.
- `Matched_Site_Keyword`: site terms actually present in extracted PDF text.
- `Dataset_DOI`, `Dataset_Title`: populated for exact registered dataset matches.
- `Matched_Dataset_Reference`: dataset DOI, canonical final URL, or both.
- `PDF_URL`, `PDF_Status`: the attempted PDF and check outcome.

`PDF_Status` distinguishes no direct OA URL, failed downloads, HTML responses,
unreadable PDFs, extraction failures, no exact dataset match, and a confirmed
exact dataset DOI/final URL. A site keyword alone does not create a combined
dataset relationship. The console count of additional PDF-confirmed pairs
excludes API-discovered pairs and never includes EDI-only or Zotero-only links.

#### `EDI_Citations` (optional)

Journal citations recorded in EDI, including links to different revisions of
the same dataset. Each link is matched to its **exact** package ID in the
registry. The revision shown is the one recorded in EDI, rather than an
arbitrarily chosen revision of the dataset.

Columns include `Query_Package_ID`, `EDI_Package_ID`, `Dataset_Series_ID`,
`Dataset_DOI`, `Dataset_Title`, `EDI_Citation_ID`, `Paper_DOI`,
`EDI_Paper_Title`, `EDI_Article_URL`, and `Mapping_Status`.

All returned records are retained, including citations without a paper DOI.
An unrecognized package is labeled `Package not in registry`; its dataset DOI
is left blank rather than replaced with a different revision's DOI. Such a
record cannot add a DOI pair to the combined sheet, but can still support
series-level revision review when another source supplies the relationship.
Update the registry and rerun when necessary.

#### `Zotero_Citations` (optional)

One row per publication item + registered dataset DOI found in that item's
**Extra** field. Matching uses extracted DOI tokens, normalized for case and
DOI URL prefixes. A dataset DOI appearing only in another field does not count.
The paper DOI comes from the item's DOI field, with its URL as a fallback.

Columns include `Zotero_Item_Key`, `Zotero_Item_URL`, `Zotero_Item_Type`,
`Zotero_Extra`, `Paper_DOI`, `Paper_Title`, `Year`, `Dataset_DOI`,
`Dataset_Package_ID`, `Dataset_Series_ID`, `Dataset_Revision`, and
`Dataset_Title`.

Matches without a paper DOI remain visible for manual review. They cannot
participate in automatic publication matching or add a combined DOI pair.
A publication without a matching dataset DOI in Extra is not listed here,
but its existence is still considered when finding missing publications and
missing links. This is a dataset-link evidence sheet, not a full publication list.

### `Combined_Results`

Each row represents **one dataset citation within one publication**, identified
by paper DOI plus the dataset key for the selected deduplication mode. A paper
citing several datasets therefore has several rows. Multiple sources confirming
the same citation contribute provenance to one row rather than additional rows.
This sheet combines DOI-bearing relationships from all enabled sources,
including exact PDF-confirmed matches. Dataset columns appear first. It includes:

- `Paper_DOI`, `Paper_Title`, `Year`, `Publication_Type`: publication metadata.
  Type is looked up through Crossref once per unique DOI per run and is blank
  when unavailable. It is not a citation count.
- `Dataset_DOI`, `Dataset_Package_ID`, `Dataset_Series_ID`, `Dataset_Revision`,
  `Dataset_Title`: the selected dataset identity.
- `Selected_Source`: the source that determines the chosen DOI/revision.
- `Supporting_Sources`, `Found_By`: all contributing sources and evidence methods.
- `Observed_Dataset_DOIs`, `Observed_Package_IDs`: the distinct identities present
  in the grouped source evidence. Consult the source sheets for their exact
  source-to-revision associations.

### Choosing a deduplication mode

#### Series mode: `deduplicate_on_dataset_id <- TRUE` (default)

Keep one row per **paper DOI + dataset series**. For EDI package
`knb-lter-ble.12.7`, the series is `knb-lter-ble.12`. Scope is part of the key;
dataset 12 at another site is a different dataset. In this example,
`knb-lter-ble` is the scope, `12` is the dataset identifier, and `7` is the
revision. Non-EDI datasets continue to match by dataset DOI.

Choose the revision in this order: **DataCite, Zotero, EDI, OpenAlex, PDF**.
OpenAlex/PDF supply the selected revision only when none of the first three
sources supplies that paper-series relationship. Within a single source,
choose the highest numeric revision, then use DOI ordering to break any tie.
This rule chooses a preferred reported revision, not necessarily the newest
revision in the registry or the revision the authors actually used.

For example, suppose Publication A links to these revisions:

| Source | Package ID |
| --- | --- |
| DataCite | `knb-lter-ble.12.6` |
| EDI | `knb-lter-ble.12.7` |
| Zotero | `knb-lter-ble.12.8` |

The combined sheet has one row for Publication A and dataset 12, using the
**DOI and package ID of revision 6**. All three sources remain in the provenance,
and their individual worksheets still show revisions 6, 7, and 8. The review
sheets recommend checking the EDI and Zotero links against revision 6.

#### DOI mode: `deduplicate_on_dataset_id <- FALSE`

Keep one row per **paper DOI + dataset DOI**. Repeated evidence for the same
exact pair is combined, while different revision DOIs remain separate.
The example above produces three rows, one for each revision's DOI.

Curation reports use exact DOI matching too: a revision-8 Zotero link does not
satisfy the revision-6 relationship. Missing exact links are reported, and
revision-mismatch sheets are omitted because no single preferred revision is
being imposed across those rows.

### `Result_Counts`

This sheet appears immediately after `Combined_Results`. It includes every
dataset or series in the registry, even when its `Citation_Count` is **zero**.
A zero means the workflow found no DOI-bearing publication relationship in the
sources searched during this run. It does not establish that the dataset has
never been cited; missing metadata, inaccessible PDFs, and publications without
DOIs can leave gaps.

- In series mode (`TRUE`), count one citation per distinct publication DOI and
  dataset series, using the dataset DOI instead when no valid package ID exists.
- In DOI mode (`FALSE`), count one citation per distinct publication DOI and
  dataset DOI. Different revision DOIs are counted separately.
- Repeated mentions within a publication or evidence from multiple sources do
  not increase a dataset's count. A publication citing two different datasets
  contributes one citation to each dataset.

**Do not sum this column to obtain the number of unique publications.** The same
publication can contribute to several datasets, and in DOI mode it can also
contribute to several revisions of one dataset.

Columns are `Dataset_Series_ID`, `Dataset_Package_ID`, `Dataset_DOI`,
`Dataset_Title`, `Citation_Count`, `Registry_Dataset_DOIs`, and
`Registry_Package_IDs`. The last two columns list all registry identities covered
by the row. For a series-level count, the singular `Dataset_DOI` and
`Dataset_Package_ID` fields are blank: different publications may have different
preferred revisions, so the count belongs to the entire series. DOI-level rows
show their individual DOI and package ID, if available.

Both `Combined_Results` and `Result_Counts` are sorted by package ID in DOI mode
or series ID in series mode. Scope is sorted alphabetically, then the dataset
identifier and applicable revision are sorted numerically: `knb-lter-ble.2`
comes before `knb-lter-ble.13`, and revision 2 comes before revision 13.
Datasets without package IDs follow, sorted by DOI.

### Curation sheets

These are review lists for changes you may want to make in your catalogs.
They use the same EDI and Zotero records as the source sheets from this run.
Reports are produced only for enabled services, and EDI reports are limited to
datasets in the configured EDI scope.

| Sheet | What it means | What to do after checking the evidence |
| --- | --- | --- |
| `Missing_From_Zotero` | The publication DOI was not found in the configured collection. A paper can have several rows if it cites several datasets. | Check for an existing item elsewhere in your group or an item lacking its DOI before creating a duplicate. Add the paper to the collection and record its dataset links as appropriate. |
| `Zotero_Missing_Data_DOI` | The publication is in the collection, but its Extra field does not contain the expected dataset link. | Locate the listed item and add the recommended dataset DOI if the relationship is supported. |
| `Zotero_Revision_Mismatches` | Series mode only: a Zotero link differs from the revision selected by source priority. | Compare recorded and recommended DOIs with the publication before changing the Extra field. |
| `EDI_Missing_Links` | No EDI journal citation matches the expected relationship at the selected dataset/series level. | Check the publication, then add the appropriate journal citation through your normal EDI curation process. |
| `EDI_Revision_Mismatches` | Series mode only: an EDI link has a different or unresolved revision. | Check the recorded package and recommended package against the publication before revising the EDI link. |

Reports include `Recommended_Package_ID` and `Recommended_Dataset_DOI`, plus
the publication and dataset metadata and evidence supporting the recommendation.
Link review sheets also provide `Recorded_Package_ID`, `Recorded_Dataset_DOI`,
`Review_Status`, and the relevant `Zotero_Item_Key` or `EDI_Citation_ID`.
Missing-link Zotero rows provide existing publication item keys to help locate
the Extra field; there may be several keys if the collection duplicates a paper.

In series mode, a known different revision appears in the mismatch sheet rather
than the missing-link sheet. A different-revision link is still reported if
the selected revision is also linked, so all links that need review remain
visible. Unknown EDI revisions are labeled `Review unresolved revision`
instead of guessed.

Matching publications requires a paper DOI. No title-only matching is attempted;
items lacking a DOI can therefore require manual reconciliation even when a
similar title appears in a report. Recommended revisions reflect the configured
source priority and should be checked before changing catalog records.
A revision mismatch is not proof that a catalog entry is wrong: a publication
may legitimately cite an older revision or more than one revision. Keep a
supported link even if another source supplies the workflow's preferred DOI.

## Run order and output handling

From the repository root:

```r
source("R/01_get_dataset_dois.R")
source("R/02_find_dataset_citations.R")
```

With a manually maintained registry, run only Step 02. Clear `edi_scope` to
skip EDI, and clear the Zotero publication settings to skip Zotero. DataCite,
OpenAlex, and PDF discovery remain available without those catalog integrations.

The output directory is created as needed. Existing output files with the same
names are overwritten after a successful run, so copy reports you need to keep
before rerunning. Existing comparison workbooks from the old workflow are not
updated by Step 02. Generated files are specific to the site's configuration
and should not be committed. The repository's `.gitignore` excludes the default
`Citation_finder_output` folder and everything inside it. If you change
`output_dir` to another folder inside the repository, add that folder to
`.gitignore` as well.

OpenAlex responses are reused until `cache_max_age_days` expires. Lower that
value to refresh searches sooner, or use `Inf` to keep cached responses
indefinitely. EDI and Zotero are refreshed on every Step 02 run. API discovery,
keyword matches, and exact catalog/PDF evidence differ in strength; review the
source sheets before curating any external records.

## Common questions and troubleshooting

| Situation | What to check |
| --- | --- |
| R cannot find `config.R` or a script | Open the project and run commands from the repository root. |
| R reports a missing package | Run `source("setup.R")`, then retry. |
| Step 02 cannot find `Data_Registry.xlsx` | Run Step 01 or put the manually maintained registry in the configured `output_dir`. |
| Step 01 skipped EDI, but Step 02 stops for a missing EDI key | Step 01 can continue with another registry source. Step 02 requires `EDI_API_KEY` whenever `edi_scope` is set; provide the key or clear the scope. |
| Zotero retrieval fails | Check the group ID, collection key, and whether the group is publicly readable through the API. |
| An optional source or curation sheet is absent | Check the source settings. Revision-mismatch sheets also require `deduplicate_on_dataset_id <- TRUE`. |
| An EDI row says `Package not in registry` | Refresh the registry, preserving any manual additions, then rerun Step 02. The report does not substitute another revision's DOI. |
| A PDF could not be downloaded or read | Inspect `PDF_Status`. Other candidates are still processed; the publication may need manual checking. |
| A new publication does not appear | Check that the cited dataset DOI is in the registry, review the OpenAlex cache age, and consider gaps in source metadata or PDF access. |
| The workbook still shows an earlier run | Confirm that Step 02 finished with `Saved results:`. A failed catalog retrieval leaves the previous workbook in place. Close the file in Excel before rerunning. |

## Repository structure

- `config.R` contains site settings, matching options, output paths, and API-key
  loading. Edit this file for your site.
- `setup.R` installs the required R packages once.
- `R/01_get_dataset_dois.R` creates `Data_Registry.xlsx`.
- `R/02_find_dataset_citations.R` creates `Publication_Search_Results.xlsx`
  and maintains `openalex_cache.rds`.
- `R/utils.R` contains shared request, normalization, evidence-merging, and
  comparison helpers. The scripts source it automatically.
- `dataset-citation-finder.Rproj` opens the repository as an RStudio project.
- `tests/2026-09-25_citation-results.R` contains offline regression checks for
  citation matching and review reports.

The former scripts 03 and 05 have been incorporated into Step 02. Script 04,
which produced a publication list with citation counts, has been removed.
The separate Zotero and EDI comparison workbooks are no longer generated.
Older output files are not deleted automatically; regenerate Step 02 and use
its workbook for current results. `Combined_Results` replaces `Full_Results`
(previously named `Final_Relationships`).

## Offline regression checks (for maintainers)

When R and the project packages are available, run from the repository root:

```r
source("tests/2026-09-25_citation-results.R")
```

These fixtures exercise both deduplication modes, source precedence,
revision-specific EDI mapping, Zotero Extra matching, empty results, and
missing/mismatched link reports, citation counts including zeros, numeric
dataset ordering, and workbook sheet order without API requests or workbook writes.

## Contributing

When updating the code and publishing a new release, update the "Last updated"
date at the top of this README.

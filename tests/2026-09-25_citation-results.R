# Run from the repository root. No network requests or file writes.
library(dplyr)
source("R/utils.R")

registry <- prepare_citation_registry(tibble::tibble(
  Dataset_DOI = c("10.1234/ble6", "10.1234/ble7", "10.1234/ble8",
                  "10.1234/other", "10.1234/external1", "10.1234/external2"),
  Package_ID = c("knb-lter-ble.12.6", "knb-lter-ble.12.7", "knb-lter-ble.12.8",
                 "knb-lter-other.12.1", NA_character_, NA_character_),
  Dataset_Title = c(rep("BLE dataset", 3), "Other site", "External A", "External B")
))
paper <- "10.5678/paper-a"
evidence <- tibble::tibble(
  Dataset_DOI = c("10.1234/ble6", "10.1234/ble7", "10.1234/ble8",
                  "10.1234/ble8", "10.1234/ble7", "10.1234/ble7"),
  Paper_DOI = paper, Paper_Title = "Publication A", Year = 2025L,
  Source = c("DataCite", "EDI", "Zotero", "OpenAlex", "PDF", "PDF"),
  Found_By = c("DataCite: Citation relationship", "EDI: Journal citation",
               "Zotero: Dataset DOI in Extra", "OpenAlex: Citation graph",
               "PDF: DOI", "PDF: Final URL")
)
series <- combine_citation_evidence(evidence, registry, TRUE)
exact <- combine_citation_evidence(evidence, registry, FALSE)
stopifnot(nrow(series) == 1L, nrow(exact) == 3L,
          series$Dataset_DOI == "10.1234/ble6",
          series$Dataset_Package_ID == "knb-lter-ble.12.6",
          series$Selected_Source == "DataCite",
          setequal(strsplit(series$Observed_Dataset_DOIs, "; ", fixed = TRUE)[[1]],
                   c("10.1234/ble6", "10.1234/ble7", "10.1234/ble8")),
          length(strsplit(series$Observed_Package_IDs, "; ", fixed = TRUE)[[1]]) == 3L,
          length(strsplit(series$Supporting_Sources, "; ", fixed = TRUE)[[1]]) == 5L,
          nrow(evidence) == 6L,
          identical(series, combine_citation_evidence(evidence[6:1, ], registry, TRUE)))

for (source in c("Zotero", "EDI", "OpenAlex", "PDF")) {
  priority <- c("DataCite", "Zotero", "EDI", "OpenAlex", "PDF")
  remaining <- priority[seq.int(match(source, priority), length(priority))]
  result <- combine_citation_evidence(filter(evidence, Source %in% remaining), registry, TRUE)
  stopifnot(result$Selected_Source == source)
}
newer <- evidence[1, ] %>% mutate(Dataset_DOI = "10.1234/ble8")
stopifnot(combine_citation_evidence(bind_rows(evidence, newer), registry, TRUE)$Dataset_DOI ==
            "10.1234/ble8")

# Scope separates sites; absent package IDs must not merge external datasets.
others <- evidence[rep(1, 3), ] %>%
  mutate(Dataset_DOI = c("10.1234/other", "10.1234/external1", "10.1234/external2"))
stopifnot(nrow(combine_citation_evidence(bind_rows(evidence, others), registry, TRUE)) == 4L,
          nrow(combine_citation_evidence(bind_rows(evidence, others), registry, FALSE)) == 6L)

# Each publication-dataset citation is a row, not each publication. Counts
# include all registry datasets, even those absent from combined results.
series_counts <- count_dataset_citations(series, registry, TRUE)
exact_counts <- count_dataset_citations(exact, registry, FALSE)
stopifnot(nrow(series_counts) == 4L, nrow(exact_counts) == 6L,
          sum(series_counts$Citation_Count) == 1L,
          sum(exact_counts$Citation_Count) == 3L,
          sum(series_counts$Citation_Count == 0L) == 3L,
          sum(exact_counts$Citation_Count == 0L) == 3L,
          is.na(series_counts$Dataset_DOI[series_counts$Dataset_Series_ID %in% "knb-lter-ble.12"]),
          all(exact_counts$Citation_Count[exact_counts$Dataset_DOI %in%
                                          c("10.1234/ble6", "10.1234/ble7", "10.1234/ble8")] == 1L))
two_papers <- bind_rows(evidence, others, mutate(evidence, Paper_DOI = "10.5678/paper-b"))
two_paper_results <- combine_citation_evidence(two_papers, registry, TRUE)
two_paper_counts <- count_dataset_citations(two_paper_results, registry, TRUE)
stopifnot(nrow(two_paper_results) == 5L,
          sum(two_paper_counts$Citation_Count) == nrow(two_paper_results),
          two_paper_counts$Citation_Count[two_paper_counts$Dataset_Series_ID %in% "knb-lter-ble.12"] == 2L)
for (mode in c(TRUE, FALSE)) {
  zero_counts <- count_dataset_citations(series[0, ], registry, mode)
  stopifnot(nrow(zero_counts) == if (mode) 4L else 6L,
            all(zero_counts$Citation_Count == 0L),
            nrow(count_dataset_citations(series[0, ], registry[0, ], mode)) == 0L)
}

# Natural package ordering handles identifiers, revisions, and DOI-only rows.
sort_registry <- prepare_citation_registry(tibble::tibble(
  Dataset_DOI = c("10.1234/id13", "10.1234/id2-r13", "10.1234/id2-r2",
                  "10.1234/z-external", "10.1234/a-external"),
  Package_ID = c("knb-lter-ble.13.1", "knb-lter-ble.2.13", "knb-lter-ble.2.2",
                 NA_character_, NA_character_),
  Dataset_Title = "Sorting fixture"
))
sort_evidence <- evidence[rep(1, 5), ] %>% mutate(Dataset_DOI = sort_registry$Dataset_DOI)
for (mode in c(TRUE, FALSE)) {
  sorted <- combine_citation_evidence(sort_evidence, sort_registry, mode)
  counted <- count_dataset_citations(sorted, sort_registry, mode)
  if (mode) {
    stopifnot(identical(sorted$Dataset_Series_ID[1:2], c("knb-lter-ble.2", "knb-lter-ble.13")),
              identical(counted$Dataset_Series_ID[1:2], c("knb-lter-ble.2", "knb-lter-ble.13")))
  } else {
    expected_order <- c("knb-lter-ble.2.2", "knb-lter-ble.2.13", "knb-lter-ble.13.1")
    stopifnot(identical(sorted$Dataset_Package_ID[1:3], expected_order),
              identical(counted$Dataset_Package_ID[1:3], expected_order))
  }
  stopifnot(identical(tail(sorted$Dataset_DOI, 2), c("10.1234/a-external", "10.1234/z-external")),
            identical(tail(counted$Dataset_DOI, 2), c("10.1234/a-external", "10.1234/z-external")))
}

# EDI response revisions must not be replaced by the query package revision.
edi_raw <- data.frame(journalCitationId = c("7", "8", "9"),
                      packageId = c("knb-lter-ble.12.7", "knb-lter-ble.12.8", "knb-lter-ble.12.9"),
                      articleDoi = c(paper, NA_character_, paper))
edi <- map_edi_citations(edi_raw, registry, "knb-lter-ble.12.6")
stopifnot(edi$Dataset_DOI[1] == "10.1234/ble7",
          edi$Dataset_DOI[2] == "10.1234/ble8", is.na(edi$Paper_DOI[2]),
          is.na(edi$Dataset_DOI[3]), edi$Mapping_Status[3] == "Package not in registry")

# Exact Extra-field DOI tokens, including URL/case normalization and no-DOI papers.
publications <- tibble::tibble(
  Zotero_Item_Key = c("ITEM1", "ITEM2", "ITEM3"),
  Paper_DOI = c(paper, NA_character_, paper), Paper_Title = "Publication A", Year = 2025L,
  Zotero_Extra = c("Dataset: https://doi.org/10.1234/BLE8; doi:10.1234/ble7",
                   "10.1234/ble6", "10.1234/ble60")
)
zotero <- extract_zotero_citations(publications, registry)
stopifnot(nrow(zotero) == 3L, !"ITEM3" %in% zotero$Zotero_Item_Key,
          sum(is.na(zotero$Paper_DOI)) == 1L,
          nrow(extract_zotero_citations(publications[0, ], registry)) == 0L)

links <- edi %>% filter(!is.na(Paper_DOI)) %>%
  transmute(Paper_DOI, Dataset_DOI, Dataset_Package_ID = EDI_Package_ID,
            Dataset_Series_ID, Record_ID = EDI_Citation_ID)
review <- catalog_link_review(series, links, TRUE)
stopifnot(nrow(review) == 2L, all(review$Review_Status == "Different dataset revision"),
          all(review$Recommended_Dataset_DOI == "10.1234/ble6"),
          all(review$Recommended_Package_ID == "knb-lter-ble.12.6"))

# A correct link does not hide an obsolete duplicate link.
preferred <- links[1, ] %>% mutate(Dataset_DOI = "10.1234/ble6",
                                  Dataset_Package_ID = "knb-lter-ble.12.6", Record_ID = "6")
stopifnot(nrow(catalog_link_review(series, bind_rows(links, preferred), TRUE)) == 2L,
          nrow(catalog_link_review(series, preferred, TRUE)) == 0L)
exact_review <- catalog_link_review(exact, links, FALSE)
stopifnot(nrow(exact_review) == 2L,
          all(exact_review$Review_Status == "Missing dataset link"),
          setequal(exact_review$Recommended_Dataset_DOI, c("10.1234/ble6", "10.1234/ble8")))
unresolved <- links[1, ] %>% mutate(Dataset_DOI = NA_character_, Dataset_Package_ID = NA_character_)
stopifnot(catalog_link_review(series, unresolved, TRUE)$Review_Status == "Review unresolved revision")
other_paper <- preferred %>% mutate(Paper_DOI = "10.5678/paper-b")
stopifnot(catalog_link_review(series, other_paper, TRUE)$Review_Status == "Missing dataset link")

# Empty catalogs and evidence must preserve usable zero-row tables.
stopifnot(nrow(combine_citation_evidence(empty_citation_evidence(), registry, TRUE)) == 0L,
          nrow(combine_citation_evidence(empty_citation_evidence(), registry, FALSE)) == 0L,
          catalog_link_review(series, links[0, ], TRUE)$Review_Status == "Missing dataset link",
          nrow(catalog_link_review(series[0, ], links, TRUE)) == 0L)

# Evaluate only the real script's type-lookup assignment; never source the workflow.
expressions <- as.list(parse("R/02_find_dataset_citations.R"))
type_assignment <- Filter(function(x) {
  is.call(x) && identical(x[[1]], as.name("<-")) &&
    identical(x[[2]], as.name("publication_types"))
}, expressions)
stopifnot(length(type_assignment) == 1L)
fixture <- new.env(parent = globalenv())
fixture$combined_results <- series[0, ]
fixture$get_publication_type <- function(...) stop("Empty results must not call Crossref")
eval(type_assignment[[1]], fixture)
stopifnot(nrow(fixture$publication_types) == 0L,
          is.character(fixture$publication_types$Publication_Type))

# Evaluate the actual in-memory report/sheet assembly for all source/mode
# combinations. Stop before write.xlsx; these checks never write workbooks.
script_lines <- readLines("R/02_find_dataset_citations.R")
report_start <- grep("^# 24\\. ZOTERO CURATION", script_lines)
report_end <- grep("^openxlsx::write.xlsx\\(sheets", script_lines)
stopifnot(length(report_start) == 1L, length(report_end) == 1L)
report_code <- parse(text = script_lines[seq.int(report_start, report_end - 1L)])
for (mode in c(TRUE, FALSE)) {
  for (edi_enabled in c(TRUE, FALSE)) {
    for (zotero_enabled in c(TRUE, FALSE)) {
      reports <- new.env(parent = globalenv())
      reports$deduplicate_on_dataset_id <- mode
      reports$has_edi <- edi_enabled
      reports$has_zotero <- zotero_enabled
      # Paper B is absent from Zotero; it belongs only in Missing_From_Zotero.
      paper_b <- evidence[1, ] %>% mutate(Paper_DOI = "10.5678/paper-b")
      reports$combined_results <- combine_citation_evidence(bind_rows(evidence, paper_b), registry, mode)
      reports$publication_search <- evidence
      reports$pdf_results <- evidence[0, ]
      reports$citation_registry <- registry
      reports$edi_citations <- edi
      reports$edi_registry <- filter(registry, Dataset_Series_ID == "knb-lter-ble.12")
      reports$zotero_publications <- publications
      reports$zotero_citations <- zotero
      eval(report_code, reports)
      tabs <- names(reports$sheets)
      stopifnot("Combined_Results" %in% tabs,
                identical(tabs[1:2], c("DataCite_Citations", "PDF_Citations")),
                tabs[match("Combined_Results", tabs) + 1L] == "Result_Counts",
                sum(reports$sheets$Result_Counts$Citation_Count) == nrow(reports$combined_results),
                identical("EDI_Citations" %in% tabs, edi_enabled),
                identical("Zotero_Citations" %in% tabs, zotero_enabled),
                identical("EDI_Revision_Mismatches" %in% tabs, edi_enabled && mode),
                identical("Zotero_Revision_Mismatches" %in% tabs, zotero_enabled && mode))
      if (zotero_enabled) {
        stopifnot(nrow(reports$sheets$Missing_From_Zotero) == 1L,
                  reports$sheets$Missing_From_Zotero$Paper_DOI == "10.5678/paper-b",
                  !"10.5678/paper-b" %in% reports$sheets$Zotero_Missing_Data_DOI$Paper_DOI)
        if (!mode) {
          stopifnot(reports$sheets$Zotero_Missing_Data_DOI$Recommended_Dataset_DOI == "10.1234/ble6",
                    !is.na(reports$sheets$Zotero_Missing_Data_DOI$Zotero_Item_Key))
        }
      }
    }
  }
}
message("Offline citation-result regression checks passed.")

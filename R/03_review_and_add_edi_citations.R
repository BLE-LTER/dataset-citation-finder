# 03_review_and_add_edi_citations.R
# First create a review workbook; upload only citations you approve.
# Run this script from the project folder (or the R folder).
# Usage:
#   source('R/03_review_and_add_edi_citations.R')   
#   Sys.setenv(EDI_CITATION_MODE='upload')
#   source('R/03_review_and_add_edi_citations.R')
#   upload_approved()  # type the confirmation phrase when prompted
#   Sys.unsetenv('EDI_CITATION_MODE')
# Requires: EDIutils, openxlsx, httr, jsonlite
# EDI upload key: uses EDI_PERSONAL_API_KEY from .Renviron (not the group key)

root <- if (file.exists('config.R')) '.' else if (file.exists('../config.R')) '..' else stop('Cannot find config.R')
root <- normalizePath(root)
source(file.path(root, 'config.R'))
mode <- tolower(Sys.getenv('EDI_CITATION_MODE', 'review'))
if (!mode %in% c('review','upload')) stop('EDI_CITATION_MODE must be review or upload')
output <- if (exists('output_dir') && length(output_dir)==1 && nzchar(output_dir)) output_dir else file.path(root,'Citation_finder_output')
if (!grepl('^(/|[A-Za-z]:[/\\\\])', output)) output <- file.path(root,output)
dir.create(output, recursive=TRUE, showWarnings=FALSE)
input_file <- file.path(output, 'Publication_Search_Results.xlsx')
review_file <- file.path(output, 'EDI_Citation_Review.xlsx')
log_file <- file.path(output, 'EDI_Citation_Upload_Log.csv')

normalize_doi <- function(x) {
  x <- trimws(tolower(as.character(x)))
  x <- sub('^https?://(dx\\.)?doi\\.org/', '', x)
  x <- sub('^doi:', '', x)
  x[is.na(x) | x %in% c('', 'na')] <- NA_character_
  x
}
normalize_package <- function(x) trimws(as.character(x))
get_column <- function(df, col) if (col %in% names(df)) as.character(df[[col]]) else rep(NA_character_, nrow(df))
get_meta <- function(doi) {
  result <- tryCatch({
    url <- paste0('https://api.crossref.org/works/', utils::URLencode(doi, reserved=TRUE))
    response <- httr::GET(url, httr::timeout(20), httr::user_agent('BLE-citation-review/1.0'))
    if (httr::http_error(response)) stop('Crossref HTTP error')
    m <- jsonlite::fromJSON(httr::content(response, 'text', encoding='UTF-8'), simplifyVector=FALSE)$message
    list(title=if(length(m$title)) as.character(m$title[[1]]) else NA_character_,
         journal=if(length(m$`container-title`)) as.character(m$`container-title`[[1]]) else NA_character_)
  }, error=function(e) list(title=NA_character_, journal=NA_character_))
  result
}

# Read existing citations. Stop if EDI returns an unexpected format,
# so we do not accidentally upload a duplicate.
existing_dois <- function(package_id, env) {
  x <- EDIutils::list_data_package_citations(packageId=package_id, as='data.frame', list_all=TRUE, env=env)
  if (is.null(x) || NROW(x)==0) return(character())
  if (!is.data.frame(x)) stop('Unexpected EDI citation response for ',package_id)
  nm <- names(x)
  candidates <- grep('doi|articleurl|article_url', nm, ignore.case=TRUE, value=TRUE)
  if (!length(candidates)) stop('Cannot identify DOI/URL columns returned by EDI for ',package_id, ': ',paste(nm,collapse=', '))
  vals <- unlist(x[candidates], use.names=FALSE)
  unique(stats::na.omit(normalize_doi(vals)))
}

if (mode=='review') {
  if (!file.exists(input_file)) stop('Missing ',input_file,'; run 02_find_dataset_citations.R first.')
  d <- openxlsx::read.xlsx(input_file, sheet='EDI_Missing_Links')
  required <- c('Paper_DOI','Recommended_Package_ID')
  if (!all(required %in% names(d))) stop('Missing required columns: ',paste(setdiff(required,names(d)),collapse=', '))
  if (!nrow(d)) stop('No EDI missing links found.')
  doi <- normalize_doi(d$Paper_DOI)
  pkg <- normalize_package(d$Recommended_Package_ID)
  if (anyNA(doi) || anyNA(pkg) || any(!nzchar(pkg))) stop('Missing DOI or recommended package ID; review source output.')
  if (anyDuplicated(paste(pkg,doi))) stop('Duplicate DOI/package pairs in source output; review first.')
  unique_dois <- unique(doi)
  message('Fetching Crossref journal metadata for ',length(unique_dois),' unique publications...')
  metadata <- setNames(lapply(unique_dois, get_meta), unique_dois)
  journal <- vapply(doi, function(z) metadata[[z]]$journal, character(1))
  title <- get_column(d,'Paper_Title')
  for (i in seq_along(title)) if (is.na(title[i]) || !nzchar(trimws(title[i]))) title[i] <- metadata[[doi[i]]]$title
  # Check PDF matches yourself before approving them.
  review <- data.frame(
    Paper_DOI=doi, Paper_Title=title, Journal_Title=journal,
    Dataset_Title=get_column(d,'Dataset_Title'),
    Recommended_Package_ID=pkg,
    Recommended_Dataset_DOI=get_column(d,'Recommended_Dataset_DOI'),
    Selected_Source=get_column(d,'Selected_Source'),
    Found_By=get_column(d,'Found_By'),
    Relation_Type=rep('IsCitedBy',nrow(d)),
    Approved=rep('No',nrow(d)),
    Reviewer_Notes=rep('',nrow(d)), stringsAsFactors=FALSE
  )
  instructions <- data.frame(Instructions=c(
    'Review the article and verify that it relates to the exact recommended dataset/package.',
    'Relation_Type is fixed to IsCitedBy for this workflow.',
    'Approve only when the article explicitly cites the corresponding dataset.',
    'Set Approved to Yes only after verification; all rows start as No.',
    'Close the Excel file before running upload mode.',
    'Upload mode writes to PRODUCTION; requires typing the confirmation phrase.',
    'Review mode does not contact EDI or change repository records.'
  ))
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb,'Review')
  openxlsx::writeData(wb,'Review',review,withFilter=TRUE)
  openxlsx::freezePane(wb,'Review',firstRow=TRUE)
  openxlsx::setColWidths(wb,'Review',cols=1:ncol(review),widths='auto')
  openxlsx::dataValidation(wb,'Review',cols=10,rows=2:(nrow(review)+1),type='list',value='"No,Yes"')
  openxlsx::addWorksheet(wb,'Instructions')
  openxlsx::writeData(wb,'Instructions',instructions)
  openxlsx::setColWidths(wb,'Instructions',cols=1,widths=110)
  if (file.exists(review_file)) stop('Review workbook already exists; move or rename it before generating a new one: ', review_file)
  openxlsx::saveWorkbook(wb,review_file,overwrite=FALSE)
  message('Review workbook created: ',review_file,'\nNo EDI changes made.')
} else {
  if (!file.exists(review_file)) stop('Review workbook not found: ',review_file)
  review <- openxlsx::read.xlsx(review_file,sheet='Review',detectDates=FALSE)
  required <- c('Paper_DOI','Recommended_Package_ID','Relation_Type','Approved','Paper_Title','Journal_Title')
  if (!all(required %in% names(review))) stop('Review file missing columns: ',paste(setdiff(required,names(review)),collapse=', '))
  approved <- review[!is.na(review$Approved) & tolower(trimws(as.character(review$Approved)))=='yes',,drop=FALSE]
  if (!nrow(approved)) stop('No approved citations. Nothing uploaded.')
  approved$Paper_DOI <- normalize_doi(approved$Paper_DOI)
  approved$Recommended_Package_ID <- normalize_package(approved$Recommended_Package_ID)
  valid_relations <- 'IsCitedBy'
  if (anyNA(approved$Paper_DOI) || any(!grepl('^10\\.[0-9]{4,9}/\\S+$',approved$Paper_DOI)) ||
      any(!grepl('^[^.]+\\.[0-9]+\\.[0-9]+$',approved$Recommended_Package_ID)) ||
      anyNA(approved$Relation_Type) || any(!approved$Relation_Type %in% valid_relations)) {
    stop('Approved rows have invalid DOI, package ID, or Relation_Type. No upload attempted.')
  }
  keys <- paste(approved$Recommended_Package_ID,approved$Paper_DOI)
  if (anyDuplicated(keys)) stop('Duplicate approved DOI/package pairs. No upload attempted.')
  # Use your personal key for uploading citations to EDI.
  key <- Sys.getenv('EDI_PERSONAL_API_KEY', '')
  if (!nzchar(trimws(key))) {
    stop('Personal EDI API key missing. Add EDI_PERSONAL_API_KEY to .Renviron and restart R.')
  }
  cat('Approved rows: ',nrow(approved),'\nProduction environment: YES\n',sep='')
  if (file.exists(log_file)) stop('Existing upload log found. Archive it before another upload: ',log_file)
  upload_approved <- function() {
    # Call upload_approved() directly in the Console so readline waits for input.
    confirmation <- readline('Type UPLOAD TO EDI PRODUCTION to continue: ')
    if (!identical(confirmation, 'UPLOAD TO EDI PRODUCTION')) stop('Cancelled. No changes made.')
    if (file.exists(log_file)) stop('Existing upload log found. Archive it before another upload: ',log_file)
    EDIutils::login(key=key)
    on.exit(EDIutils::logout(), add=TRUE)
    log <- data.frame(Package_ID=character(),Paper_DOI=character(),Relation_Type=character(),Status=character(),EDI_Citation_ID=character(),Details=character(),stringsAsFactors=FALSE)
    append_log <- function(pkg,doi,rel,status,id='',details='') {
      log <<- rbind(log,data.frame(Package_ID=pkg,Paper_DOI=doi,Relation_Type=rel,Status=status,EDI_Citation_ID=as.character(id),Details=details))
      utils::write.csv(log,log_file,row.names=FALSE,na='')
    }
    for (i in seq_len(nrow(approved))) {
      r <- approved[i,,drop=FALSE]
      pkg <- r$Recommended_Package_ID[[1]]; doi <- r$Paper_DOI[[1]]; rel <- r$Relation_Type[[1]]
      message('[',i,'/',nrow(approved),'] ',pkg,' <- ',doi)
      current <- tryCatch(existing_dois(pkg,'production'),error=function(e)e)
      if (inherits(current,'error')) {
        append_log(pkg,doi,rel,'CHECK_FAILED',details=conditionMessage(current)); next
      }
      if (doi %in% current) {
        append_log(pkg,doi,rel,'SKIPPED_ALREADY_EXISTS'); next
      }
      clean_optional <- function(x) if (length(x)==0 || is.na(x) || !nzchar(trimws(as.character(x)))) NULL else as.character(x)
      result <- tryCatch(EDIutils::create_journal_citation(
        packageId=pkg,articleDoi=doi,
        articleTitle=clean_optional(r$Paper_Title[[1]]),
        journalTitle=clean_optional(r$Journal_Title[[1]]),
        relationType='IsCitedBy',env='production'
      ),error=function(e)e)
      if (inherits(result,'error')) append_log(pkg,doi,rel,'UPLOAD_FAILED',details=conditionMessage(result))
      else append_log(pkg,doi,rel,'UPLOADED',id=paste(result,collapse=';'))
    }
    message('Finished. Audit log: ',log_file)
  }
  message('Ready to upload. In the RStudio Console, run: upload_approved()')
}

# Pseudobulk differential expression between two conditions (CAIBI convention).
#
# Template: copy this file into the project, fill in the SETTINGS block,
# then run it with: Rscript pseudobulk_de.R
#
# Steps: sum raw counts per donor x condition x cell type with
# Seurat::AggregateExpression, then test each cell type with DESeq2,
# using the donor as the replicate.
#
# Outputs (in OUTDIR):
#   summary.csv            cell types ranked by number of significant genes
#   de_<cell type>.csv     DESeq2 results table of each cell type
#   deseq2_results.rds     all DESeq2 runs (named list by cell type), each with
#                          $dds (fitted DESeqDataSet), $results, $design, $n_donors.
#                          Load it with readRDS() for follow-up work instead of re-running.

suppressPackageStartupMessages({
  library(Seurat)
  library(DESeq2)
  library(dplyr)
  library(purrr)
  library(readr)
  library(tibble)
})

# ---- SETTINGS: fill these in after looking at obj[[]] (the meta.data) ------
DATA_FILE  <- ""   # .rds file holding a Seurat object with raw counts
DONOR      <- ""   # meta.data column with the donor / biological sample
CONDITION  <- ""   # meta.data column with the condition
CELL_TYPE  <- ""   # meta.data column with the cell type annotation
REF        <- ""   # reference condition level (e.g. the control)
ALT        <- ""   # tested condition level
MIN_CELLS  <- 10   # minimum cells for one donor x condition x cell type profile
MIN_DONORS <- 3    # minimum donors per condition to test a cell type
OUTDIR     <- "results/pseudobulk"
# -----------------------------------------------------------------------------

if (any(c(DATA_FILE, DONOR, CONDITION, CELL_TYPE, REF, ALT) == "")) {
  stop("Fill in every value of the SETTINGS block before running.")
}
dir.create(OUTDIR, recursive = TRUE, showWarnings = FALSE)

obj <- readRDS(DATA_FILE)
missing <- setdiff(c(DONOR, CONDITION, CELL_TYPE), colnames(obj[[]]))
if (length(missing) > 0) stop("Column(s) not found in meta.data: ", paste(missing, collapse = ", "))
missing <- setdiff(c(REF, ALT), obj[[]][[CONDITION]])
if (length(missing) > 0) stop("Level(s) not found in column ", CONDITION, ": ", paste(missing, collapse = ", "))

# One row per kept cell: the two conditions, a cell type label, and only
# donor x condition x cell type groups with enough cells. Each group gets a
# simple ID ("pb1", "pb2", ...) so Seurat cannot rewrite the labels.
cells <- obj[[]] |>
  as_tibble(rownames = "cell_id") |>
  transmute(cell_id,
            donor     = as.character(.data[[DONOR]]),
            condition = as.character(.data[[CONDITION]]),
            cell_type = as.character(.data[[CELL_TYPE]])) |>
  filter(condition %in% c(REF, ALT), !is.na(cell_type)) |>
  group_by(donor, condition, cell_type) |>
  filter(n() >= MIN_CELLS) |>
  mutate(profile = paste0("pb", cur_group_id())) |>
  ungroup()

obj <- subset(obj, cells = cells$cell_id)
obj$profile <- cells$profile[match(colnames(obj), cells$cell_id)]

# 1. Pseudobulk: sum raw counts for each donor x condition x cell type.
assay <- DefaultAssay(obj)
if (inherits(obj[[assay]], "Assay5")) obj[[assay]] <- JoinLayers(obj[[assay]])  # needed after IntegrateLayers
counts <- AggregateExpression(obj, assays = assay, group.by = "profile")[[assay]]
if (any(counts < 0) || any(counts != round(counts))) {
  stop("The counts layer does not hold raw integer counts. Use the raw counts, not normalised data.")
}

pb_meta <- cells |> distinct(profile, donor, condition, cell_type)

# 2. Show the design: number of donors per cell type and condition.
pb_meta |> count(cell_type, condition, name = "n_donors") |> print(n = Inf)

# 3. Test one cell type with DESeq2, donors as replicates.
test_cell_type <- function(ct) {
  info <- pb_meta |>
    filter(cell_type == ct) |>
    mutate(donor     = factor(donor),   # factor, even if donors look like numbers
           condition = factor(condition, levels = c(REF, ALT)))

  n_donors <- min(table(info$condition))
  if (n_donors < MIN_DONORS) {
    message(ct, ": skipped, fewer than ", MIN_DONORS, " donors in a condition")
    return(NULL)
  }

  # Paired design when every donor is seen in both conditions.
  paired <- all(table(info$donor) == 2)
  design <- if (paired) ~ donor + condition else ~ condition

  dds <- DESeqDataSetFromMatrix(as.matrix(counts[, info$profile]),
                                column_to_rownames(info, "profile"), design)
  dds <- dds[rowSums(counts(dds)) >= 10, ]   # drop genes with almost no counts
  dds <- DESeq(dds, quiet = TRUE)

  res <- results(dds, contrast = c("condition", ALT, REF), alpha = 0.05) |>
    as_tibble(rownames = "gene") |>
    arrange(padj)

  list(cell_type = ct,
       design    = paste(deparse(design), collapse = ""),
       n_donors  = n_donors,
       dds       = dds,
       results   = res)
}

# 4. Run every cell type (skipped cell types are dropped) and save all runs.
runs <- sort(unique(pb_meta$cell_type)) |>
  set_names() |>
  map(test_cell_type) |>
  compact()
saveRDS(runs, file.path(OUTDIR, "deseq2_results.rds"))

walk(runs, \(run) write_csv(run$results,
                            file.path(OUTDIR, paste0("de_", gsub("[^A-Za-z0-9]+", "_", run$cell_type), ".csv"))))

# 5. Rank cell types by number of significant genes (FDR 0.05).
summary <- runs |>
  map(\(run) {
    significant <- run$results |> filter(padj < 0.05)
    tibble(cell_type     = run$cell_type,
           design        = run$design,
           n_donors      = run$n_donors,
           n_significant = nrow(significant),
           top_up        = significant |>
                             filter(log2FoldChange > 0) |>
                             slice_head(n = 10) |>
                             pull(gene) |>
                             paste(collapse = ", "))
  }) |>
  bind_rows() |>
  arrange(desc(n_significant))

write_csv(summary, file.path(OUTDIR, "summary.csv"))
print(summary, width = Inf)

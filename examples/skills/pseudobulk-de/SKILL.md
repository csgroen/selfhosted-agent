---
name: pseudobulk-de
description: Differential expression between conditions (treated vs control, disease vs healthy, stimulated vs unstimulated) in single-cell RNA-seq data with several donors or samples, in R, following CAIBI conventions. Use this skill whenever the user asks which genes or cell types change between conditions, which cell types respond to a treatment, or for any condition comparison on a Seurat object, even if they don't mention pseudobulk.
license: MIT
compatibility: opencode
metadata:
  author: CAIBI, Centre de Recherche des Cordeliers
  requires: R>=4.3, Seurat>=5, DESeq2 (Bioconductor), tidyverse (dplyr, purrr, readr, tibble, tidyr, ggplot2)
---

# Pseudobulk differential expression in R (CAIBI convention)

## The rule

The replicate is the **donor** (or biological sample), not the cell. Cells from one donor are
not independent, so cell-level tests between conditions (`FindMarkers` on cells, Wilcoxon on
cells) give p-values that are far too small.

- Do NOT use `FindMarkers` or any cell-level test to compare conditions (it is fine for cluster markers).
- DO sum raw counts per donor x condition x cell type (pseudobulk) and test with DESeq2.
  The template script below does this for you.

## Steps

1. **Find the settings.** Load the object and print the metadata:
   ```r
   obj <- readRDS("path/to/object.rds")
   head(obj[[]])
   ```
   Then print `unique()` of the candidate columns. You need:
   - `DONOR`: the column with the donor / sample ID
   - `CONDITION`: the column with the condition
   - `CELL_TYPE`: the column with the cell type annotation
   - `REF` and `ALT`: the two condition values to compare (`REF` = control)

   If any of these is unclear, **ask the user. Do not guess.**
   If the data is a SingleCellExperiment, first make a Seurat object from its raw counts:
   `obj <- CreateSeuratObject(counts = counts(sce), meta.data = as.data.frame(colData(sce)))`, then `saveRDS(obj, ...)`.

2. **Run the DE script.** Copy `scripts/pseudobulk_de.R` from this skill into the project.
   Edit only its SETTINGS block, then run `Rscript pseudobulk_de.R`.
   Do not rewrite the method. The script already:
   - checks the columns, the condition values and that the counts are raw integers;
   - drops groups with fewer than 10 cells and cell types with fewer than 3 donors per condition;
   - uses a paired design (`~ donor + condition`) when every donor is in both conditions;
   - prints the number of donors per cell type and condition.

   If it stops with an error, read the message, fix the setting or the data, and run it again.

3. **Plot.** Copy `scripts/plot_log2fc_dotplot.R` into the project and run it
   (`Rscript plot_log2fc_dotplot.R`). It makes a dotplot of log2 fold changes of the top genes per
   cell type from the saved results, without re-running DESeq2.

4. **Report**, in this order:
   - the design used and the number of donors per condition for each cell type;
   - cell types ranked by number of significant genes (FDR 0.05), from `summary.csv`;
   - the top up-regulated genes of the 2-3 most responsive cell types;
   - any cell type that was skipped and why;
   - the caveats below.

## Output files (in `results/pseudobulk/`)

| File | Content |
|---|---|
| `summary.csv` | one row per tested cell type: design, donors, number of significant genes, top up genes |
| `de_<cell type>.csv` | full DESeq2 results of one cell type (gene, log2FoldChange, pvalue, padj, ...) |
| `deseq2_results.rds` | all DESeq2 runs, a list named by cell type; each has `$dds`, `$results`, `$design`, `$n_donors` |
| `dotplot_log2fc.pdf` | dotplot from step 3 |

For follow-up questions or extra plots, **load the saved results instead of re-running the script**:
```r
runs <- readRDS("results/pseudobulk/deseq2_results.rds")
runs[["B cells"]]$results    # results table of one cell type
runs[["B cells"]]$dds        # fitted DESeq2 object, e.g. for vst() or plotCounts()
```
Extra code follows tidyverse style: native pipe `|>`, dplyr verbs, `purrr::map()` + `bind_rows()`, `readr::write_csv()`.

## Caveats to state in the report

- The number of significant genes depends on the number of cells per donor, so compare cell types with care.
- Results are only as good as the cell type annotation.
- Check the top genes against known biology before interpreting.

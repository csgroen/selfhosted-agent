# Dotplot of log2 fold changes per cell type from a saved pseudobulk DE run.
#
# Run pseudobulk_de.R first, then this script (Rscript plot_log2fc_dotplot.R).
# It only reads the saved OUTDIR/deseq2_results.rds, so nothing is recomputed.
# Colour = log2 fold change (ALT vs REF), size = -log10(adjusted p-value).

suppressPackageStartupMessages({
  library(dplyr)
  library(purrr)
  library(ggplot2)
})

# ---- SETTINGS ---------------------------------------------------------------
OUTDIR <- "results/pseudobulk"   # same OUTDIR as in pseudobulk_de.R
TOP_N  <- 5                      # top significant genes per cell type (by padj)
# -----------------------------------------------------------------------------

runs <- readRDS(file.path(OUTDIR, "deseq2_results.rds"))

de <- runs |>
  map(\(run) run$results |> mutate(cell_type = run$cell_type)) |>
  bind_rows() |>
  filter(!is.na(padj))

top_genes <- de |>
  filter(padj < 0.05) |>
  group_by(cell_type) |>
  slice_min(padj, n = TOP_N, with_ties = FALSE) |>
  pull(gene) |>
  unique()
if (length(top_genes) < 2) stop("Fewer than 2 significant genes (FDR 0.05): nothing to plot.")

# Order genes by clustering their log2FC across cell types (co-regulated genes together).
lfc <- de |>
  filter(gene %in% top_genes) |>
  tidyr::pivot_wider(id_cols = gene, names_from = cell_type,
                     values_from = log2FoldChange, values_fill = 0) |>
  tibble::column_to_rownames("gene")
gene_order <- rownames(lfc)[hclust(dist(lfc))$order]

p <- de |>
  filter(gene %in% top_genes) |>
  mutate(gene = factor(gene, levels = gene_order)) |>
  ggplot(aes(x = cell_type, y = gene, colour = log2FoldChange, size = -log10(padj))) +
  geom_point() +
  scale_colour_gradient2(low = "#2166ac", mid = "grey85", high = "#b2182b", midpoint = 0) +
  labs(x = NULL, y = NULL, colour = "log2FC") +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

ggsave(file.path(OUTDIR, "dotplot_log2fc.pdf"), p, width = 7, height = 2 + 0.18 * length(top_genes))

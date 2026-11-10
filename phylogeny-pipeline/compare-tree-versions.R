# Compare reference-tree versions: which taxonomic groups each tree recovers, what
# intrudes into the groups it breaks, how far apart the topologies are, and the
# longest terminal branches. See "Interpreting the reference trees" in README.md.
#
# Usage (on Grace):
#   module load GCC/13.3.0 OpenMPI/5.0.3 R-bundle-CRAN/2024.11
#   Rscript compare-tree-versions.R <out_dir> <label>=<treefile> [<label>=<treefile> ...]
#
# Taxonomy comes from 02-references/pr2-euk-tax.tsv (all PR2 eukaryotes), so trees
# built from different reference sets can be compared. Comparisons use only the
# references present in every tree. The trees are treated as unrooted: a group counts
# as recovered when one branch separates it from every other reference.

suppressPackageStartupMessages({ library(ape); library(phangorn) })

TAX_FILE <- "/scratch/group/hu-lab/deepsea-18S-merged-outputs/phylo-placement/02-references/pr2-euk-tax.tsv"
RANKS <- c("domain", "supergroup", "division", "subdivision", "class", "order",
           "family", "genus", "species")
CHECK_RANKS <- c("supergroup", "division", "subdivision", "class", "order")
N_LONG <- 25   # longest terminal branches listed per tree

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) stop("usage: Rscript compare-tree-versions.R <out_dir> <label>=<treefile> ...")
out_dir <- args[1]
specs <- strsplit(args[-1], "=", fixed = TRUE)
labels <- vapply(specs, `[`, "", 1)
files <- vapply(specs, `[`, "", 2)
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

trees <- lapply(files, read.tree)
names(trees) <- labels
for (i in seq_along(trees)) cat(labels[i], ":", Ntip(trees[[i]]), "tips,", files[i], "\n")

shared <- Reduce(intersect, lapply(trees, function(t) t$tip.label))
cat("References in every tree:", length(shared), "\n")
trees <- lapply(trees, function(t) unroot(keep.tip(t, shared)))

tax <- read.delim(TAX_FILE, header = FALSE, col.names = c("id", "taxonomy"))
tax <- tax[tax$id %in% shared, ]
lin <- do.call(rbind, strsplit(tax$taxonomy, ";", fixed = TRUE))
colnames(lin) <- RANKS
rownames(lin) <- tax$id
missing <- setdiff(shared, rownames(lin))
if (length(missing) > 0) stop(length(missing), " tips have no PR2 taxonomy, e.g. ", missing[1])
lin <- lin[shared, ]

# Every bipartition of a tree as a logical matrix (bipartitions x tips, in `shared` order)
bipartitions <- function(t) {
  parts <- prop.part(t)
  idx <- match(attr(parts, "labels"), shared)
  m <- matrix(FALSE, length(parts), length(shared))
  for (k in seq_along(parts)) m[k, idx[parts[[k]]]] <- TRUE
  m
}
splits <- lapply(trees, bipartitions)

# Two views of how well a tree recovers a group:
#   intruders: references in the smallest clade that holds every group member but are
#     not in the group. One stray member can make this huge, so read it with `outside`.
#   outside: group members not in the largest clade made only of group members.
# A recovered group has 0 of both. Clades are sides of bipartitions (unrooted).
group_fit <- function(m, members) {
  g <- length(members)
  n <- ncol(m)
  inside <- rowSums(m[, members, drop = FALSE])
  size <- rowSums(m)
  side_size <- ifelse(inside == g, size, ifelse(inside == 0, n - size, NA))
  k <- which.min(side_size)
  side <- if (inside[k] == g) m[k, ] else !m[k, ]
  intruders <- setdiff(which(side), members)
  pure <- c(ifelse(inside == size, inside, 0), ifelse(g - inside == n - size, g - inside, 0))
  list(n_intruders = length(intruders), intruders = intruders,
       n_outside = g - max(1, pure))
}

describe_intruders <- function(intruders, rank_col) {
  if (length(intruders) == 0) return("")
  groups <- sort(table(lin[intruders, rank_col]), decreasing = TRUE)
  paste0(names(groups), " (", groups, ")", collapse = "; ")
}

rows <- list()
for (rank in CHECK_RANKS) {
  for (g in sort(unique(lin[, rank]))) {
    members <- which(lin[, rank] == g)
    if (length(members) < 2 || length(members) > length(shared) - 2) next
    row <- data.frame(rank = rank, group = g, n_refs = length(members))
    for (lab in labels) {
      fit <- group_fit(splits[[lab]], members)
      row[[paste0(lab, "_intruders")]] <- fit$n_intruders
      row[[paste0(lab, "_outside")]] <- fit$n_outside
      row[[paste0(lab, "_intruded_by")]] <- describe_intruders(fit$intruders, rank)
    }
    rows[[length(rows) + 1]] <- row
  }
}
groups <- do.call(rbind, rows)
counts <- as.matrix(groups[, paste0(labels, "_intruders"), drop = FALSE])
groups$recovered_in <- rowSums(counts == 0)
groups$differs <- apply(counts == 0, 1, function(x) length(unique(x)) > 1)
write.table(groups, file.path(out_dir, "group-monophyly.tsv"), sep = "\t", quote = FALSE, row.names = FALSE)

cat("\n=== GROUPS RECOVERED (no intruders), out of", nrow(groups), "\n")
print(sapply(labels, function(lab) tapply(groups[[paste0(lab, "_intruders")]] == 0, groups$rank, sum))[CHECK_RANKS, , drop = FALSE])

cat("\n=== GROUPS RECOVERED IN SOME TREES BUT NOT OTHERS (supergroup to class)\n")
cat("Each tree: intruders/outside (0/0 = recovered); intruder lineages in group-monophyly.tsv\n")
sel <- groups$differs & groups$rank %in% c("supergroup", "division", "subdivision", "class")
changed <- groups[sel, c("rank", "group", "n_refs")]
for (lab in labels) {
  changed[[lab]] <- paste(groups[sel, paste0(lab, "_intruders")], groups[sel, paste0(lab, "_outside")], sep = "/")
}
if (nrow(changed) == 0) cat("none\n") else print(changed, row.names = FALSE)

if (length(trees) > 1) {
  class(trees) <- "multiPhylo"
  rf <- as.matrix(RF.dist(trees, normalize = TRUE))
  dimnames(rf) <- list(labels, labels)
  write.table(round(rf, 4), file.path(out_dir, "rf-normalized.tsv"), sep = "\t", quote = FALSE)
  cat("\n=== NORMALIZED RF DISTANCE on the", length(shared), "shared references (0 = identical, 1 = no bipartitions shared)\n")
  print(round(rf, 3))
}

long <- do.call(rbind, lapply(labels, function(lab) {
  t <- trees[[lab]]
  term <- t$edge[, 2] <= Ntip(t)
  bl <- data.frame(tree = lab, id = t$tip.label[t$edge[term, 2]], length = t$edge.length[term])
  bl$times_median <- bl$length / median(bl$length)
  bl <- head(bl[order(-bl$length), ], N_LONG)
  bl$division <- lin[bl$id, "division"]
  bl$lineage <- paste(lin[bl$id, "class"], lin[bl$id, "genus"], sep = ";")
  bl
}))
write.table(long, file.path(out_dir, "longest-branches.tsv"), sep = "\t", quote = FALSE, row.names = FALSE)
cat("\n=== LONGEST TERMINAL BRANCHES (top 10 per tree; all", N_LONG, "in longest-branches.tsv)\n")
print(do.call(rbind, lapply(split(long, long$tree), head, 10))[, c("tree", "id", "length", "times_median", "division", "lineage")], row.names = FALSE)

cat("\nWrote group-monophyly.tsv, rf-normalized.tsv, longest-branches.tsv to", out_dir, "\n")

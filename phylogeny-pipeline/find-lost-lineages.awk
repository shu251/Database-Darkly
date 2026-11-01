# Lists PR2 lineages with no selected reference, at the highest rank each was lost.
# Inputs, in order: reference taxonomy, ids that passed the filters, id <tab> length, full taxonomy.
BEGIN {
  FS = OFS = "\t"
  split("domain supergroup division subdivision class order family", rank_name, " ")
  print "rank", "lineage", "n_seqs", "n_passed_filters", "longest_id", "longest_bp", "longest_passing_id", "longest_passing_bp"
}
FNR == 1 { file++ }
file == 1 {
  split($2, r, ";")
  path = r[1]
  for (k = 2; k <= 7; k++) { path = path ";" r[k]; in_ref[path] }
  next
}
file == 2 { passed[$1]; next }
file == 3 { len[$1] = $2; next }
{
  split($2, r, ";")
  path = r[1]
  for (k = 2; k <= 7; k++) {
    up = path
    path = path ";" r[k]
    parent[path] = up
    rank[path] = k
    n[path]++
    if (len[$1] + 0 > best_bp[path] + 0) { best_bp[path] = len[$1]; best_id[path] = $1 }
    if ($1 in passed) {
      n_pass[path]++
      if (len[$1] + 0 > pass_bp[path] + 0) { pass_bp[path] = len[$1]; pass_id[path] = $1 }
    }
  }
}
END {
  for (p in n) {
    if (p in in_ref) continue
    if (rank[p] > 2 && !(parent[p] in in_ref)) continue
    print rank_name[rank[p]], p, n[p], n_pass[p] + 0, best_id[p], best_bp[p], (p in pass_id ? pass_id[p] : "-"), pass_bp[p] + 0
  }
}

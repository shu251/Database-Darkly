# Caps the number of reference sequences per taxonomic group.
# Input 1: id <tab> 9-rank taxonomy. Input 2: id <tab> length, sorted longest first,
# so the longest sequences in each group are the ones kept.
# Prints the selected ids.
BEGIN { FS = "\t" }
FNR == NR { tax[$1] = $2; next }
{
  if (!($1 in tax)) { missing++; next }
  n = split(tax[$1], r, ";")
  if (n != 9) { bad_ranks++; next }

  coarse = (r[4] == "Metazoa" || r[4] == "Fungi" || r[3] == "Streptophyta")
  key = r[1]
  last = coarse ? 7 : 8
  for (i = 2; i <= last; i++) key = key ";" r[i]

  if (coarse) cap = cap_coarse
  else if (r[8] ~ /_X+$/) cap = cap_x
  else cap = cap_named

  if (++seen[key] <= cap) print $1
}
END {
  if (missing + 0 > 0 || bad_ranks + 0 > 0)
    printf "select-references: skipped %d ids without taxonomy, %d without 9 ranks\n", missing, bad_ranks > "/dev/stderr"
}

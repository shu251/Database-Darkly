# Bases kept per sequence after trimming.
# Inputs: unwrapped unaligned FASTA, then unwrapped trimmed alignment.
# Prints id <tab> original length <tab> bases kept <tab> fraction kept.
FNR == 1 { file++ }
/^>/ { id = substr($1, 2); next }
file == 1 { len[id] = length($0); next }
id in len {
  s = $0
  kept = gsub(/[^-.]/, "", s)
  printf "%s\t%d\t%d\t%.3f\n", id, len[id], kept, kept / len[id]
}

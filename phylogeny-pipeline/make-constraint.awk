# Writes an IQ-TREE backbone constraint tree (-g) from reference-taxonomy.tsv.
# Only groups with strong phylogenomic support are enforced. Relationships inside each
# group, and the placement of every other reference, are left to the data.
#   Amorphea (Obazoa + Amoebozoa)
#     Opisthokonta
#       Metazoa
#       Fungi
#     Amoebozoa
#   Rhizaria, Alveolata, Stramenopiles, Discoba
# Usage: awk -f make-constraint.awk reference-taxonomy.tsv > constraint.tree
BEGIN { FS = "\t" }
{
  split($2, r, ";")
  if      (r[4] == "Metazoa")      g = "metazoa"
  else if (r[4] == "Fungi")        g = "fungi"
  else if (r[3] == "Opisthokonta") g = "opisthokonta"
  else if (r[2] == "Amoebozoa")    g = "amoebozoa"
  else if (r[2] == "Obazoa")       g = "amorphea"
  else if (r[3] == "Rhizaria")     g = "rhizaria"
  else if (r[3] == "Alveolata")    g = "alveolata"
  else if (r[3] == "Stramenopiles") g = "stramenopiles"
  else if (r[3] == "Discoba")      g = "discoba"
  else                             g = "free"
  tips[g] = (g in tips ? tips[g] "," : "") $1
  n[g]++
}
function grp(name) { return "(" tips[name] ")" }
END {
  for (k in n) if (n[k] < 2 && k != "free") { print "ERROR: group " k " has fewer than 2 references" > "/dev/stderr"; exit 1 }
  for (k in n) print k "\t" n[k] > "/dev/stderr"
  opis = "(" grp("metazoa") "," grp("fungi") "," tips["opisthokonta"] ")"
  amor = "(" opis "," grp("amoebozoa") "," tips["amorphea"] ")"
  print "(" amor "," grp("rhizaria") "," grp("alveolata") "," grp("stramenopiles") "," grp("discoba") "," tips["free"] ");"
}

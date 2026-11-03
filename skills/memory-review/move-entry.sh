#!/bin/bash
# Moves one entry, verbatim, from memory/inbox.md to the end of memory/archive.md.
# Usage (from the project root): move-entry.sh "<exact heading line of the entry>"
# The entry is the heading plus every line up to the next "## " heading.
# Refuses to act unless the heading occurs exactly once in the inbox.
h="$1"
inbox="memory/inbox.md"
archive="memory/archive.md"
if [ -z "$h" ] || [ ! -f "$inbox" ] || [ ! -f "$archive" ]; then
  echo "usage: move-entry.sh \"<heading line>\" (run from the project root; needs $inbox and $archive)"
  exit 1
fi
n=$(grep -cFx -- "$h" "$inbox")
if [ "$n" != "1" ]; then
  echo "heading found $n times in $inbox; nothing moved"
  exit 1
fi
H="$h" awk -v out="$archive.add" '
  $0 == ENVIRON["H"] { m = 1; print > out; next }
  m && /^## / { m = 0 }
  m { print > out; next }
  { print }
' "$inbox" > "$inbox.new"
if [ ! -s "$archive.add" ] || [ ! -s "$inbox.new" ]; then
  rm -f "$archive.add" "$inbox.new"
  echo "move failed; nothing changed"
  exit 1
fi
{ echo; cat "$archive.add"; } >> "$archive"
mv "$inbox.new" "$inbox"
rm -f "$archive.add"
echo "moved to archive: $h"

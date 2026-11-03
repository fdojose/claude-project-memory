#!/bin/bash
# Project memory hooks. Usage: project-memory.sh start|sync|prompt|guard|index
#   start  prints the session id into context, rebuilds the index, prints a
#          reminder when a memory review is due and the open lines of the board,
#          and records what this session has seen of the shared memory
#   sync   copies this project's transcripts into memory/sessions/, rebuilds the index
#   prompt checks the developer's message for a correction, a re-explanation or a
#          standing instruction (memory-signal.py); on a match, logs a row to
#          memory/signals.tsv and prints a note into context. Also prints inbox
#          entries and board lines that other sessions added or changed since
#          this session last looked
#   guard  stops a subagent from writing to memory/inbox.md (PreToolUse on Edit|Write)
#   index  rebuilds memory/index.md from memory/inbox.md
# The index lists the current entries (date, type, title, status), leaves out
# superseded ones, and ends with the most recent lines of the inbox's Misses
# section, followed by the shared entries that apply to this project's scope.
# Safe to run by hand. Only guard can block, and only a subagent's inbox write.
# Only hooks send JSON on stdin. "index" never reads it, so it cannot hang when run
# from a tool whose stdin stays open.
input=""
case "$1" in index) ;; *) [ -t 0 ] || input=$(cat) ;; esac
project="${CLAUDE_PROJECT_DIR:-$(pwd)}"
get() {
  [ -z "$input" ] && return
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$input" | jq -r --arg k "$1" '.[$k] // empty' 2>/dev/null
  else
    printf '%s' "$input" | python3 -c 'import json,sys; print(json.load(sys.stdin).get(sys.argv[1],""))' "$1" 2>/dev/null
  fi
}
MISSES_MAX=10           # most recent Misses lines copied into the index
TITLE_MAX="${MEMORY_TITLE_MAX:-120}"  # characters of an entry heading shown in the index
# Entries that hold beyond one project live in a shared inbox. The index lists
# those whose Scope is "all", this project's scope (first line of memory/scope),
# or a parent of it: scope home/solar sees home and home/solar, not home/river.
SHARED_INBOX="${CLAUDE_SHARED_MEMORY:-$HOME/.claude/shared-memory/inbox.md}"
shared_index() {
  [ -f "$SHARED_INBOX" ] || return 0
  scope=""
  [ -f "$project/memory/scope" ] && scope=$(sed -n 's/[[:space:]]//g; /^[^#]/{p;q;}' "$project/memory/scope")
  LC_ALL=C awk -v p="$scope" -v tm="$TITLE_MAX" '
    function cut(x) { if (length(x) > tm) { x = substr(x, 1, tm); sub(/ [^ ]*$/, "", x); x = x "..." } return x }
    function applies(sc) { return sc == "all" || (p != "" && (sc == p || index(p, sc "/") == 1)) }
    function flush() {
      if (!t) return
      if (s !~ /^superseded/ && applies(sc)) {
        st = s; sub(/ · .*/, "", st); st = substr(st, 1, 40)
        line[++n] = "- " cut(t) " [" (st ? st : "status?") "] (scope " sc ")"
      }
      t = ""
    }
    /^## [0-9][0-9][0-9][0-9]-/ { flush(); t = substr($0, 4); s = ""; sc = ""; next }
    /^## / { flush(); next }
    /^- Scope:/ && t { sc = $0; sub(/^- Scope: */, "", sc); gsub(/[[:space:]]/, "", sc) }
    /^- Status:/ && t { s = $0; sub(/^- Status: */, "", s) }
    END {
      flush()
      if (n) {
        print ""
        print "Shared entries that apply here (scope " (p != "" ? p : "not set") "). Read them in ~/.claude/shared-memory/inbox.md:"
        for (i = 1; i <= n; i++) print line[i]
      }
    }
  ' "$SHARED_INBOX"
}
build_index() {
  inbox="$project/memory/inbox.md"
  index="$project/memory/index.md"
  [ -f "$inbox" ] || return 0
  {
    echo "# Memory index"
    echo "Generated from memory/inbox.md. One line per current entry: date, type, title, status."
    echo "Entries are written by Claude and not reviewed. Read the full entry in"
    echo "memory/inbox.md before relying on one, and check it against what it cites."
    echo "A heading ending in ... is cut here; search the inbox for its first words."
    echo
    # LC_ALL=C: cutting a heading inside an accented letter must not stop macOS awk.
    LC_ALL=C awk -v max="$MISSES_MAX" -v tm="$TITLE_MAX" '
      function cut(x) { if (length(x) > tm) { x = substr(x, 1, tm); sub(/ [^ ]*$/, "", x); x = x "..." } return x }
      # Superseded entries are left out. The status is cut at its first " · ",
      # so "resolved by 2026-10-08 · <title>" shows as "resolved by 2026-10-08".
      function flush() {
        if (!t) return
        if (s ~ /^superseded/) { hidden++; t = ""; return }
        st = s; sub(/ · .*/, "", st); st = substr(st, 1, 40)
        print "- " cut(t) " [" (st ? st : "status?") "]"
        t = ""
      }
      /^## [0-9][0-9][0-9][0-9]-/ { flush(); t = substr($0, 4); s = ""; inmiss = 0; next }
      /^## Misses/ { flush(); inmiss = 1; next }
      /^## / { flush(); inmiss = 0; next }
      inmiss && /^- / { m[++n] = $0; next }
      /^- Status:/ && t { s = $0; sub(/^- Status: */, "", s) }
      END {
        flush()
        if (hidden) {
          print ""
          print hidden " superseded " (hidden == 1 ? "entry is" : "entries are") " not shown; see memory/inbox.md."
        }
        if (n) {
          print ""
          print "Misses: times the developer had to re-explain something, or a settled point was reopened."
          print "Showing the last " (n > max ? max : n) " of " n ". Do not repeat these."
          for (i = (n > max ? n - max + 1 : 1); i <= n; i++) print m[i]
        }
      }
    ' "$inbox"
    ok=$?
    shared_index
  } > "$index.tmp"
  # A failed awk leaves a partial file: keep the old index instead of replacing it.
  if [ "$ok" = 0 ]; then mv "$index.tmp" "$index"; else rm -f "$index.tmp"; fi
}
# Thresholds for the review reminder printed at session start.
REVIEW_MAX_ENTRIES=60   # entries in the inbox (one index line each)
REVIEW_MAX_LINES=400    # lines in the inbox
REVIEW_MAX_DAYS=14      # days since the last review...
REVIEW_MIN_NEW=10       # ...with at least this many entries added since
review_due() {
  inbox="$project/memory/inbox.md"
  [ -f "$inbox" ] || return 0
  entries=$(grep -c '^## [0-9][0-9][0-9][0-9]-' "$inbox")
  lines=$(wc -l < "$inbox" | tr -d ' ')
  last=$(ls "$project"/memory/review-[0-9]*.md 2>/dev/null | sort | tail -1)
  if [ -n "$last" ]; then
    since=${last##*review-}; since=${since%.md}
    fresh=$(awk -v d="$since" '/^## [0-9][0-9][0-9][0-9]-/ && substr($0, 4, 10) > d { n++ } END { print n + 0 }' "$inbox")
    label="last review $since"
  else
    since=$(awk '/^## [0-9][0-9][0-9][0-9]-/ { d = substr($0, 4, 10); if (m == "" || d < m) m = d } END { print m }' "$inbox")
    fresh=$entries
    label="never reviewed"
  fi
  cutoff=$(date -v-"$REVIEW_MAX_DAYS"d +%Y-%m-%d 2>/dev/null || date -d "$REVIEW_MAX_DAYS days ago" +%Y-%m-%d 2>/dev/null)
  reason=""
  if [ -n "$last" ] && [ "$fresh" -lt "$REVIEW_MIN_NEW" ]; then
    : # reviewed, and little added since: size alone does not ask again
  elif [ "$entries" -gt "$REVIEW_MAX_ENTRIES" ]; then
    reason="$entries entries in the index"
  elif [ "$lines" -gt "$REVIEW_MAX_LINES" ]; then
    reason="$lines lines in the inbox"
  elif [ -n "$since" ] && [ -n "$cutoff" ] && [ "$since" \< "$cutoff" ] && [ "$fresh" -ge "$REVIEW_MIN_NEW" ]; then
    reason="$fresh entries added since $since"
  fi
  [ -n "$reason" ] && echo "Memory review due ($label): $reason. Tell the developer once, at a natural point, that /memory-review is suggested. Do not run it yourself."
  return 0
}
# Inbox entries (as index lines) and board lines that do not mention the given
# session id: what that session could have missed. Session ids are matched on
# their first 8 characters, which is what board lines carry.
SEEN_MAX_DAYS=14        # per-session "seen" files older than this are removed
BOARD_MAX_LINES=20      # open board lines printed at session start
shared_lines() {
  me=$(printf '%s' "$1" | cut -c1-8)
  [ -n "$me" ] || return 0
  inbox="$project/memory/inbox.md"
  board="$project/memory/board.md"
  [ -f "$inbox" ] && awk -v me="$me" '
    function flush() { if (t && !mine) print "- " t " [" (s ? s : "status?") "]" }
    /^## [0-9][0-9][0-9][0-9]-/ { flush(); t = substr($0, 4); s = ""; mine = 0; next }
    /^## / { flush(); t = ""; next }
    t && index($0, me) { mine = 1 }
    /^- Status:/ && t { s = $0; sub(/^- Status: */, "", s); sub(/ · .*/, "", s); s = substr(s, 1, 40) }
    END { flush() }
  ' "$inbox"
  [ -f "$board" ] && grep '^- ' "$board" | grep -Fv "$me" | sed 's/^- /- board: /'
  return 0
}
board_open() {
  board="$project/memory/board.md"
  [ -f "$board" ] || return 0
  open=$(grep '^- ' "$board" | head -"$BOARD_MAX_LINES")
  [ -n "$open" ] && printf 'Open lines on memory/board.md (claims and handoffs between sessions; see the project-memory rules):\n%s\n' "$open"
  return 0
}
case "$1" in
  start)
    session=$(get session_id)
    [ -n "$session" ] && echo "Session id: $session (use it in the Refs line of inbox entries)"
    build_index
    review_due
    board_open
    if [ -n "$session" ] && [ -d "$project/memory" ]; then
      mkdir -p "$project/memory/.state"
      find "$project/memory/.state" -name '*.seen' -mtime +"$SEEN_MAX_DAYS" -delete 2>/dev/null
      shared_lines "$session" > "$project/memory/.state/$session.seen"
    fi
    ;;
  sync)
    transcript=$(get transcript_path)
    transcript="${transcript/#\~/$HOME}"
    if [ -n "$transcript" ] && [ -f "$transcript" ]; then
      from=$(dirname "$transcript")
    else
      from="$HOME/.claude/projects/$(printf '%s' "$project" | sed 's/[^A-Za-z0-9]/-/g')"
    fi
    dest="$project/memory/sessions"
    if [ -d "$from" ]; then
      mkdir -p "$dest"
      for f in "$from"/*.jsonl; do
        [ -f "$f" ] || continue
        [ "$f" -nt "$dest/$(basename "$f")" ] && cp -p "$f" "$dest/"
      done
    fi
    build_index
    ;;
  prompt)
    printf '%s' "$input" | python3 "$(dirname "$0")/memory-signal.py" 2>/dev/null
    # Trial: per-prompt search runs only where memory/search-on exists.
    if [ -f "$project/memory/search-on" ] && [ -f "$(dirname "$0")/memory-search.py" ]; then
      printf '%s' "$input" | python3 "$(dirname "$0")/memory-search.py" --hook 2>/dev/null
    fi
    session=$(get session_id)
    if [ -n "$session" ] && [ -d "$project/memory" ]; then
      seen="$project/memory/.state/$session.seen"
      if [ -f "$seen" ]; then
        new=$(shared_lines "$session" | grep -Fxv -f "$seen")
        if [ -n "$new" ]; then
          printf 'Memory update: added or changed by other sessions since this one last looked:\n%s\nRead the full entry in memory/inbox.md, or the line in memory/board.md, before relying on it.\n' "$new"
          printf '%s\n' "$new" >> "$seen"
        fi
      else
        mkdir -p "$project/memory/.state"
        shared_lines "$session" > "$seen"
      fi
    fi
    ;;
  guard)
    agent=$(get agent_id)
    [ -n "$agent" ] || exit 0
    path=$(printf '%s' "$input" | python3 -c 'import json,sys; print((json.load(sys.stdin).get("tool_input") or {}).get("file_path",""))' 2>/dev/null)
    case "$path" in
      */memory/inbox.md)
        echo "Subagents do not write to memory/inbox.md. Put what you would have recorded under a 'Memory candidates' heading at the end of your report; the session that launched you writes it once." >&2
        exit 2
        ;;
      */shared-memory/inbox.md)
        echo "Subagents do not write to the shared inbox. Put what you would have recorded under a 'Memory candidates' heading at the end of your report; the session that launched you writes it once." >&2
        exit 2
        ;;
    esac
    ;;
  index)
    build_index
    ;;
esac
exit 0

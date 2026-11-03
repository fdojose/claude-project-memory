#!/bin/bash
# Exercises the coordination features of project-memory.sh in a scratch folder.
# Usage: coord_test.sh <path to project-memory.sh under test> <path to memory-signal.py>
# Hook inputs are built into variables first: bash 3.2 (macOS) mishandles
# escaped quotes inside $(...) inside double quotes.
set -u
src="$1"; sig="$2"
t=$(mktemp -d)
mkdir -p "$t/.claude/hooks" "$t/memory"
cp "$src" "$t/.claude/hooks/project-memory.sh"
cp "$sig" "$t/.claude/hooks/memory-signal.py"
export CLAUDE_PROJECT_DIR="$t"
H="$t/.claude/hooks/project-memory.sh"
A=aaaaaaaa-1111-1111-1111-111111111111
B=bbbbbbbb-2222-2222-2222-222222222222
pass=0; fail=0
check() { # name, expected substring ("" = expect empty), actual
  if { [ -z "$2" ] && [ -z "$3" ]; } || { [ -n "$2" ] && printf '%s' "$3" | grep -Fq -- "$2"; }; then
    pass=$((pass+1)); echo "ok    $1"
  else
    fail=$((fail+1)); echo "FAIL  $1"; echo "      wanted: ${2:-<empty>}"; echo "      got:    $3"
  fi
}
run() { printf '%s' "$2" | bash "$H" "$1" 2>&1; }
js() { printf '{"session_id":"%s","prompt":"%s"}' "$1" "${2:-commit and push}"; }
gj() { printf '{%s"tool_input":{"%s":"%s"}}' "$1" "$2" "$3"; }
guard() { printf '%s' "$1" | bash "$H" guard 2>&1; echo "exit=$?"; }

cat > "$t/memory/inbox.md" <<EOF
# Inbox
## 2026-09-01 · constraint · Entry that was replaced
- Refs: session old
- Status: superseded by 2026-10-01 · Entry that exists before both sessions

## 2026-10-01 · decision · Entry that exists before both sessions
- Refs: session old
- Status: active

## Misses
One line per time the developer had to re-explain something.
EOF
for i in 01 02 03 04 05 06 07 08 09 10 11 12; do echo "- 2026-10-02 miss-$i" >> "$t/memory/inbox.md"; done
printf '# Board\nLine format: `- date · id · claim | handoff · what · files`\n' > "$t/memory/board.md"

out=$(bash -n "$H" 2>&1); check "syntax" "" "$out"
in=$(js "$A"); out=$(run start "$in"); check "start A prints session id" "Session id: $A" "$out"
out=$(printf '%s' "$out" | grep 'Open lines'); check "start with empty board prints no board lines" "" "$out"
idx=$(cat "$t/memory/index.md")
check "index lists the entry with its status" "- 2026-10-01 · decision · Entry that exists before both sessions [active]" "$idx"
body=$(printf '%s' "$idx" | grep 'Refs: session old'); check "index has no entry bodies" "" "$body"
gone=$(printf '%s' "$idx" | grep 'Entry that was replaced'); check "index leaves out the superseded entry" "" "$gone"
check "index says how many superseded entries are hidden" "1 superseded entry is not shown" "$idx"
check "index has a Misses block with the count" "Showing the last 10 of 12" "$idx"
check "index shows the newest miss" "miss-12" "$idx"
check "index shows the tenth newest miss" "miss-03" "$idx"
old=$(printf '%s' "$idx" | grep 'miss-02'); check "index leaves out misses beyond the cap" "" "$old"
hdr=$(printf '%s' "$idx" | grep 'One line per time'); check "index does not copy the Misses explanation text" "" "$hdr"
in=$(js "$B"); run start "$in" >/dev/null
in=$(js "$A"); out=$(run prompt "$in"); check "prompt A, nothing new" "" "$out"

# B writes an entry
python3 - "$t/memory/inbox.md" "$B" <<'EOF'
import sys
p, b = sys.argv[1], sys.argv[2]
s = open(p).read()
new = "## 2026-10-09 · constraint · Entry written by session B\n- Refs: session %s\n- Status: active\n\n" % b
open(p, "w").write(s.replace("## Misses", new + "## Misses"))
EOF
in=$(js "$A"); out=$(run prompt "$in")
check "prompt A sees B's entry" "Entry written by session B [active]" "$out"
old=$(printf '%s' "$out" | grep 'exists before'); check "prompt A does not re-list the old entry" "" "$old"
out=$(run prompt "$in"); check "prompt A again is quiet" "" "$out"
in=$(js "$B"); out=$(run prompt "$in"); check "prompt B does not see its own entry" "" "$out"

# B claims work on the board
echo "- 2026-10-09 20:00 · bbbbbbbb · claim · refactor the hook · .claude/hooks/" >> "$t/memory/board.md"
in=$(js "$A"); out=$(run prompt "$in")
check "prompt A sees B's claim" "board: 2026-10-09 20:00 · bbbbbbbb · claim" "$out"
in=$(js "$B"); out=$(run prompt "$in"); check "prompt B does not see its own claim" "" "$out"
in=$(js "cccccccc-3333"); out=$(run start "$in")
check "new session C is shown the open claim at start" "bbbbbbbb · claim · refactor the hook" "$out"
fmt=$(printf '%s' "$out" | grep 'Line format'); check "the board's format line is not listed as open" "" "$fmt"

# status change on B's entry by a third party is visible to A
sed -i.bak 's/^- Status: active$/- Status: resolved by test/' "$t/memory/inbox.md"
in=$(js "$A"); out=$(run prompt "$in")
check "prompt A sees the status change" "Entry written by session B [resolved by test]" "$out"
sed -i.bak 's/^- Status: resolved by test$/- Status: resolved by 2026-10-09 · Some later entry title/' "$t/memory/inbox.md"
in=$(js "$A"); out=$(run prompt "$in")
check "a status pointer is cut at its date" "Entry written by session B [resolved by 2026-10-09]" "$out"

# correction note and update note together
echo "- 2026-10-09 20:05 · bbbbbbbb · handoff · tests left to write · calibration/" >> "$t/memory/board.md"
in=$(js "$A" "no, that is wrong"); out=$(run prompt "$in")
check "correction note still printed" "Memory signal (correction)" "$out"
check "update note printed alongside" "handoff · tests left to write" "$out"

# a session with no seen file (hook installed mid-session) starts quiet
in=$(js "dddddddd-4444"); out=$(run prompt "$in")
check "prompt from unknown session is quiet the first time" "" "$out"

# malformed input never prints noise
out=$(run prompt 'not json'); check "malformed input is silent" "" "$out"

# guard
sub='"agent_id":"x1",'
in=$(gj "$sub" file_path "$t/memory/inbox.md"); out=$(guard "$in")
check "guard blocks a subagent inbox write" "exit=2" "$out"
check "guard explains itself" "Memory candidates" "$out"
in=$(gj "" file_path "$t/memory/inbox.md"); out=$(guard "$in"); check "guard allows the main session" "exit=0" "$out"
quiet=$(printf '%s' "$out" | grep -v '^exit='); check "guard is silent for the main session" "" "$quiet"
in=$(gj "$sub" file_path "$t/memory/board.md"); out=$(guard "$in"); check "guard allows a subagent on the board" "exit=0" "$out"
in=$(gj "$sub" file_path "$t/notes/inbox.md"); out=$(guard "$in"); check "guard allows a subagent on other files" "exit=0" "$out"
in=$(gj "$sub" command "ls"); out=$(guard "$in"); check "guard allows a subagent tool with no file path" "exit=0" "$out"

echo "$pass passed, $fail failed"
rm -rf "$t"
[ "$fail" -eq 0 ]

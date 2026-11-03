---
name: memory-update-scheme
description: Upgrade a project memory that was installed earlier (by memory-setup or
  the older pasted prompts) to the current scheme - hook script, rules, settings,
  scope and shared inbox - offer to migrate existing entries to it, and import
  Claude Code's built-in auto memory before switching it off. Use when the
  user asks to update, upgrade or adopt the new memory scheme in a project.
---

# Memory scheme update

Bring the project memory in the current folder up to the current scheme, without
losing anything it holds. The current scheme is defined by the `memory-setup`
skill: its `SKILL.md`, `project-memory.sh` and `memory-signal.py`, in
`~/.claude/skills/memory-setup/`. Read those files first and treat them as the
source of truth; this skill only says how to move an existing install onto them.

## Rules

- Never delete an entry, a file in `memory/`, or a setting. Replace a file only
  where a step below says so.
- Change entry text only in phase 3, only with the developer's approval for each
  change, and only the words the change names.
- Before starting, read `memory/board.md` if it exists. If another session has a
  claim on `.claude/` or `memory/`, stop and tell the developer. Otherwise add a
  claim line for this update, and delete it at the end.
- If an edit to `.claude/settings.json` is refused (for example as
  self-modification), do not look for another way to make it. Collect the exact
  lines and give them to the developer in the report.

## Phase 0: check what is installed

- If `memory/inbox.md` is missing, or does not begin with the `# Inbox` header,
  stop: this is not an install of this memory. Suggest `/memory-setup`.
- Inventory, and show it to the developer before changing anything:
  - hook scripts in `.claude/hooks/`: `project-memory.sh`, `memory-signal.py`,
    and the older `session-memory.sh` and `memory-index.sh`
  - which of those the hooks in `.claude/settings.json` call, per event
  - which bullets of the current rules template (memory-setup step 3) are
    missing from `.claude/rules/project-memory.md`, and which bullets there are
    not in the template
  - which permission entries from memory-setup step 6 are missing
  - which files from memory-setup step 1 are missing (`memory/board.md`,
    `memory/scope`, `memory/sessions/README.md`), and whether
    `~/.claude/shared-memory/inbox.md` exists
  - whether the folder is a git repository, and whether `.gitignore` has the two
    lines from memory-setup step 5
  - whether shell access is available (phase 1 needs it for checks)
  - Claude Code's built-in auto memory: whether `autoMemoryEnabled` is false in
    `.claude/settings.json`, and the auto memory directory with its topic-file
    count, `MEMORY.md` line count and newest date (phase 4, step 1)

## Phase 1: mechanics

1. Hook scripts. Apply memory-setup steps 2 and 2b, including their rule for an
   existing copy: replace a file only if every difference is something the
   skill's file adds; otherwise stop and show the differences.
2. Older two-script installs. If hooks call `session-memory.sh` or
   `memory-index.sh`, they are replaced by `project-memory.sh`, which does both
   jobs: in step 4 below, point those hook events at `project-memory.sh` instead.
   Leave the old script files in place and tell the developer they can be
   deleted once the new hooks have run.
3. Missing files from memory-setup step 1: create them as that step says,
   including asking the developer for the scope path for `memory/scope`, and
   creating the shared inbox only if it does not exist.
4. Settings. Merge memory-setup step 6 into `.claude/settings.json`, keeping every
   existing key, rule and hook. Each hook event must call `project-memory.sh`
   exactly once with the mode the template gives; remove only hook commands that
   call the two older scripts, and only when the same event now calls
   `project-memory.sh`. If the edit is refused, see the rules above.
5. Rules. Add the template bullets that are missing. Where a bullet exists in an
   older wording, show both versions and replace it only if the developer agrees.
   Keep every bullet that is not in the template; it is a local rule.
6. `.gitignore`, as memory-setup step 5 says.
7. Checks, if shell access is available:
   `bash -n .claude/hooks/project-memory.sh` must print nothing;
   `python3 .claude/hooks/memory-signal.py --selftest` must end by saying every
   sample matched; `bash .claude/hooks/project-memory.sh index` must rebuild
   `memory/index.md` (show its last lines). Without shell access, give the
   developer these three commands.

Step 4 also sets `"autoMemoryEnabled": false`. If the auto memory directory
holds topic files, phase 4 has to import them, because once the setting is off
their facts no longer reach sessions. Say this when showing the inventory.

## Phase 2: offer the migration

Tell the developer the mechanics are done, and ask whether to review the existing
entries for the new scheme now (phase 3), and, if auto memory holds topic files,
whether to import them (phase 4). If neither, go to the report.
Large inboxes: work in batches of about 20 entries and stop after each batch.

## Phase 3: migrate entries (each change approved by the developer)

Read the active entries of `memory/inbox.md` (Status not "superseded").

1. Shared candidates. List the entries that hold beyond this project: shared
   equipment or services, Claude Code behaviour, how the developer works. For
   each, propose the narrowest scope that covers every project it applies to, or
   `all`, and say why. Leave project-specific entries alone, and if unsure, leave
   the entry in the project.
   For each approved one:
   - append a copy to `~/.claude/shared-memory/inbox.md`, with a `- Scope:` line
     inserted directly under the heading and the Refs line extended with this
     project's folder name; every other line exactly as in the project inbox
   - set the project entry's Status to
     `superseded by <date · title> (moved to the shared inbox)`, changing
     nothing else in it
   - read both entries back and confirm the copy matches line for line
2. Self-containment. List the active entries that use relative time ("yesterday",
   "today", "this morning", "last week", "tonight") or point at something outside
   the entry ("it", "this", "that one", "the earlier fix", "as above") where the
   meaning is not clear from the entry itself. For each, propose the replacement
   words: a date derived from the entry's own heading date, or the name of the
   thing. Propose a replacement only when the entry itself, or a source it cites,
   makes it certain; otherwise list the entry as unclear. Apply only the
   approved replacements, changing only those words.
3. Rebuild the index (`bash .claude/hooks/project-memory.sh index`), or say that
   it will rebuild at the end of the next turn.

## Phase 4: import Claude Code's auto memory (each entry approved by the developer)

Claude Code's auto memory is a second store that Claude writes on its own: a
`MEMORY.md` index (its first 200 lines or 25 KB load every session) and one topic
file per memory. This phase moves its facts into the inbox so one store is left.

1. Find the directory. If `autoMemoryDirectory` is set in any settings file, use
   it. Otherwise it is `~/.claude/projects/<key>/memory/`, where `<key>` is the
   absolute path of the git repository root (or of the project folder outside
   git) with every `/`, space and `_` replaced by `-`. List the directories in
   `~/.claude/projects/` whose name starts with that key, and show them: subfolder
   or worktree sessions outside git can have their own. Read every topic file and
   `MEMORY.md` before proposing anything.
2. Compare each topic with the active entries of `memory/inbox.md` and the shared
   inbox, and with the project's own docs (README files, `docs/`, CLAUDE.md):
   grep each fact's distinctive terms (numbers, register names, file names)
   before proposing it. Also read any `memory/backfill-*.md` staging file: its
   "left out" notes say which facts an earlier pass judged to be in the docs.
   Sort each fact into:
   - in the docs: the repository already records it. Nothing to import; name the
     file. The rules file forbids recording what the docs already say.
   - covered: an entry already states the same fact. Nothing to import.
   - conflicting: an entry states the same subject with different details.
     Show both; the developer says which holds, and the result goes in as a new
     entry that supersedes the old one, or not at all.
   - not covered: propose a new entry in the inbox template.
   A topic that mixes several facts is split into one entry per fact; a topic
   that is only a pointer (a URL, a file location) can stay one entry.
3. Writing an imported entry:
   - heading date: the date the topic gives for the fact; if it gives none, the
     topic file's modification date, and say so in the entry
   - type: decision, failure, constraint or open, from what the topic says;
     preferences and ways of working ("user" and "feedback" topics) are
     candidates for the shared inbox under the scope rule
   - keep the topic's figures and names exactly; do not add anything it does
     not say, and keep every rule of the rules file (dates, no relative time,
     named things)
   - Refs: the topic file's full path, "imported from auto memory, not
     re-verified", and this session's id
   - where a topic gives several dated states of one thing ("was .113 until
     2026-09-23, .103 since"), write the current state, with the dates
4. Work in batches of about 10 topics. Show each batch as a table (topic, verdict,
   proposed heading) with the proposed entries below it, append only what the
   developer approves, and stop after each batch.
5. Never edit, move or delete the auto memory files. They stay as the record of
   what was imported.
6. When every topic is covered or imported, check that `"autoMemoryEnabled":
   false` is in `.claude/settings.json` (step 4 of phase 1). Rebuild the index.
7. Check, if shell access is available: from the project root run
   `claude -p "Is an auto memory MEMORY.md index part of your context? Answer yes or no, then quote its first line if yes." </dev/null`
   and show the answer; it must say no. Without shell access, give the developer
   that command.

## Report

- what was installed before, and what was changed, added or left as it was
- the scope written to `memory/scope`, or that none was set
- settings lines the developer still has to add by hand, as exact JSON
- old script files that can now be deleted
- the check results, or the commands to run them
- for phase 3: entries moved to the shared inbox (with scopes), entries
  reworded (with the words changed), entries listed as unclear
- for phase 4: the auto memory directory, topics found covered, conflicting
  (with the developer's choice) and imported, topics left out and why, and
  the check result
- to restart open sessions in this folder so the rules, imports and hooks load
- that the board claim was removed

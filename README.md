# claude-project-memory

A file-based project memory for [Claude Code](https://claude.com/claude-code), built as four skills.

Claude Code already has a context window, a `CLAUDE.md` it reads at every start, and its own "auto memory". This is a different take: a memory that keeps **what only the memory knows** — decisions with their reasons, approaches that failed, constraints measured in the real world — and lets the rest go.

It is the memory behind the article [It's the Memory, Stupid!](https://medium.com/@fernando.dougnac).

## What it does

- **An inbox of short entries.** Each one is a decision, a failure, a constraint or an open question, with what, why, what was rejected and a pointer to the evidence. Claude writes them when a task ends, and only when a test, a command result or the developer confirmed the fact.
- **A generated index** that loads into every session: one line per current entry, so every session sees the titles and reads the full entry only when the topic comes up.
- **A session archive.** Transcripts are copied into `memory/sessions/` automatically. They are not loaded and not turned into entries on their own.
- **A prompt hook** that flags messages that look like a correction, a re-explanation or a standing instruction, so Claude checks whether something should have been in memory.
- **Coordination between sessions** working in the same project at the same time: a board for short-lived claims and handoffs, and a note when another session added entries.
- **A shared inbox** (`~/.claude/shared-memory/inbox.md`) for facts that hold beyond one project, listed in each project by scope.
- **Review, like sleep.** `/memory-review` cleans stale and duplicate entries, groups related ones, compacts old ones and moves superseded entries to an archive, with a snapshot first.

Everything is plain Markdown. No database.

## The skills

| Skill | What it does |
| --- | --- |
| `memory-setup` | Installs the memory in the current project: files, rules, hooks and settings. |
| `memory-review` | Consolidates the memory: stale, duplicate, superseded and old entries. |
| `memory-backfill` | Builds entries from archived session transcripts, with quoted evidence and an audit, when you ask for it. |
| `memory-update-scheme` | Upgrades an earlier install to the current scheme and imports Claude Code's auto memory before switching it off. |

## Install

Requirements: Claude Code, `bash`, and `python3` for the prompt hook. Tested on macOS.

```bash
git clone https://github.com/fdojose/claude-project-memory.git
```

```bash
cp -R claude-project-memory/skills/memory-* ~/.claude/skills/
```

Then open Claude Code in your project and run:

```
/memory-setup
```

It creates `memory/`, `.claude/hooks/`, `.claude/rules/project-memory.md`, adds two imports to `CLAUDE.md` and merges the hooks and permissions into `.claude/settings.json`, keeping what is already there. Restart the session so the hooks load.

Notes:
- Transcripts are copied into `memory/sessions/`. If your project folder syncs to a cloud service, they go with it. In a git repository they are added to `.gitignore`.
- Setup sets `"autoMemoryEnabled": false`, so Claude Code's built-in auto memory does not keep a second store. If you already have auto memory, run `/memory-update-scheme` to import it first.

## Does it work?

Small tests, honestly reported, in [RESULTS.md](RESULTS.md). Short version: with the memory, sessions answered more questions right in half the steps and stopped giving confidently wrong answers. About half of what was saved was already in the code or docs; the entries that mattered were observations about the world that nothing else records.

## License

MIT

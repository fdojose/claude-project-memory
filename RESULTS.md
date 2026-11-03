# Results

Small evaluations run with `claude -p` in fresh sessions, 2026-10 to 2026-11, on two real projects (a home solar and automation project, "project A", and a second project, "project B"). Answers graded by Claude Haiku. Brackets are Wilson 95% intervals. These are small samples, mostly one run each: read them as a direction, not a benchmark.

## Recall with and without the memory (project A, 40 questions)

One question per saved entry, asked in fresh sessions. Same code and docs in both arms; the memory arm also had the project memory. Both arms graded together, blind to the arm.

| | Fully correct | Correct or partial | Wrong | Mean turns | Mean cost |
| --- | --- | --- | --- | --- | --- |
| No memory | 21 of 40 (37–67%) | 32 | 5 | 5.7 | $0.175 |
| Memory | 34 of 40 (71–93%) | 40 | 0 | 2.7 | $0.290 |

Paired: the memory fixed 13 answers and broke none. The gain was mostly in observations (17 of 21 correct with memory against 7 of 21 without); on decisions and rules, 17 of 19 against 14 of 19. Cost per question was higher with the memory, most likely because the index loads in full at the start of every session (not measured by tokens).

## What the memory held that nothing else did (projects A and B, 100 entries)

For every saved entry, a session with the code and docs but no memory was asked a question the entry answers.

- 53 of 100 were answered fully right without memory (43–62%); 78 at least partly right (69–85%). About half of what was saved was already within reach.
- Entries recording an **observation** (a measurement, a usage figure, a cause found, an outside limit, a running system's behaviour) were answered right without memory 12 times in 36 (33%), against 41 of 64 for the rest (64%). Mean impact 0.50 against 0.23.
- Entries with **"never" or "rejected"** in them were *less* often needed: 37 of 53 answered right without memory (70%), against 16 of 47 without that wording (34%). A rejected option usually ends in a choice the code shows.
- A keyword check ("are the entry's numbers and names already in the files?") matched impact on project A (AUC 0.80) but not on project B (0.53, chance). It is kept for information only.

## Earlier small runs

- Fixture project, 6 recall cases: 2 of 6 with no memory, 5 of 6 with the same facts as plain notes in `CLAUDE.md`, 6 of 6 with the memory. The one difference from plain notes was a stale entry: the notes arm trusted it, the memory arm checked it against the code.

## Caveats

One grader (a regrade moved 4 of 40 verdicts), one run for most cells, observation labels set by Claude and checked against a blind second labeller (91 of 100 agree), two projects for the impact figures and one for the recall run.

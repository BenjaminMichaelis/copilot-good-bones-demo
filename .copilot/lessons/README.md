# Lessons

What this repository has taught the agents that work in it: root causes,
gotchas, and "we tried that" findings, each with evidence. The agent writes
entries when asked; people review them in pull requests like any other change.

- `index.md` — the catalog. Agents read it before changing code in an area.
- `log.md` — the entries themselves, newest first.
- The format is enforced by `.github/instructions/lessons.instructions.md`.

Why a folder in the repo rather than a memory service: it's diffable,
reviewable, and revertible; everyone on the team gets the same lessons on
their next `git pull`; and it works on every surface that reads repository
files.

The pattern is adapted from Lab 10 ("Agent Memory") of
[ms-mfg-community/day-in-the-life-copilot-lab](https://github.com/ms-mfg-community/day-in-the-life-copilot-lab).

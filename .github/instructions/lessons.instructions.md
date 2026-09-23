---
applyTo: ".copilot/lessons/**"
---

# Lessons schema

`.copilot/lessons/` is this repo's memory: plain markdown the agent writes and
people review in pull requests, like any other change. Two files:

- `log.md` — append-only journal, **newest entry first**.
- `index.md` — one line per lesson, grouped by area, pointing into `log.md`.

## Writing an entry in `log.md`

Use exactly this shape:

```markdown
## YYYY-MM-DD — <short title>

- **Area:** <folder, file, or endpoint this applies to>
- **Lesson:** <one or two sentences: what is true about this repo>
- **Evidence:** <where it was observed: file:line, a log or trace, a command and its output>
- **Next time:** <what a future session should do differently because of it>
```

Rules:

- Evidence is required. Cite something a reviewer can check — a `file:line`,
  an Aspire log or trace, a failing test, a command's output. If you can't
  cite evidence, it isn't a lesson yet; don't write it.
- One lesson per entry. Specific beats general: "`buckets` in
  `ratings/average` is sized for scores 1–4" beats "watch for off-by-one
  errors".
- Don't restate the house rules in `.github/copilot-instructions.md`. Lessons
  are what those rules don't already say.
- Never record secrets, tokens, personal data, or anything from outside this
  repository.

## Updating `index.md`

Add one line under the right area heading (create the heading if needed):

```markdown
- <short title> — <YYYY-MM-DD> — see log.md
```

# .review-memory

Per-repo memory for the automated review skills (`/review-pr`,
`/review-pr-slack`, etc.). Committed to the repo so the whole team
shares it and it is reviewed via PR.

- `decisions.jsonl` — append-only log of past findings + developer
  responses (resolved / deferred / disputed / clarified). Source of truth.
- `rules.md` — human-curated rules distilled from that log. Loaded as
  reviewer context. **CLAUDE.md / ADRs always outrank it.**
- `graphify-out/` — queryable graph built from the log (gitignored).

This memory only *calibrates* reviews (cuts repeat-noise, honors prior
deferrals). It never overrides CLAUDE.md or ADRs. Recurring confirmed
lessons get promoted by a human into CLAUDE.md / a new ADR.

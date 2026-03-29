# Review Loop Design

## Summary

- Designed a strict `review -> fix -> verify` loop for `ralph-codex`
- Kept the existing PRD-based `run` flow unchanged and proposed a separate
  `review-loop` command family
- Captured full-repository review scope, finding categories, verification gate,
  Hurl orchestration, artifact layout, and failure policy
- Ran a spec review pass and tightened bootstrap, blocker handling, Hurl
  triggering, zero-finding verification failure, and managed server cleanup
- Ran a second spec review pass and clarified profile-vs-core scope,
  cumulative Hurl triggering, `review-reset --artifacts`, and `--dry-run`

## Changed Files

- `docs/superpowers/specs/2026-03-29-strict-review-loop-design.md`

## Verification

- Reviewed existing `ralph-codex` command structure and target repository
  verification commands before writing the spec
- Performed local spec self-review against the approved design decisions
- Ran a Codex spec review pass and updated the document to resolve the reported
  ambiguities

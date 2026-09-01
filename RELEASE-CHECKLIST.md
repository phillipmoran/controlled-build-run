# Release checklist — the go-public gate

This repo is PRIVATE until every box is checked and the operator explicitly
says "go public." Making the repo public is the operator's action, never an
agent's.

## Before flipping public

- [x] **License approved by the operator.** A draft MIT `LICENSE` ships in
      this repo with the operator's name — the license choice and the
      copyright line are the operator's call; replace or ratify before
      release.
- [x] **De-personalization sweep is clean.** No personal names, emails,
      machine paths, or private project names:
      `grep -rniE 'phill|freebird|/Users/|@gmail|claw clans|cbr-cockpit' .`
      must return nothing (the word "operator" replaced the person).
- [x] **Secrets scan is clean.** `gitleaks detect --source . --no-git` and
      `gitleaks detect --source .` (history) both pass.
- [x] **Manifest verifies.** `./verify-manifest.sh` passes at HEAD.
- [x] **Verify suite passes.** Every `verify/*.test.sh` green on a clean
      checkout.
- [x] **Core snapshots identical.** `verify/core-mirrors.test.sh` (also
      covered by the suite).
- [x] **Credits complete.** `THIRD-PARTY.md` names every tool CBR drives and
      every vendored skill with its origin and license; each vendored skill
      carries its upstream license file beside it.
- [ ] **Install walked once per harness** on a scratch repo by an agent with
      no other context — Claude Code (plugin path) AND Codex. Setup arms one
      harness at a time; a pass on one proves nothing about the other.
      *2026-09-01: Codex walked and PASSED; Claude Code plugin walk still
      owed — released without it by operator decision.*
- [x] **Operator has read the repo end-to-end** and says, in so many words,
      "looks good, let's go public."

## After flipping public

- [x] Tag `VERSION` as the first release (v0.12.0, 2026-09-01).
- [x] Turn on issues; decide whether PRs require operator review (they
      should). Issues on; main requires 1 approving review + green CI for
      non-admins.

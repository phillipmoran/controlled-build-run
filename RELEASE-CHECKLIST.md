# Release checklist — the go-public gate

This repo is PRIVATE until every box is checked and the operator explicitly
says "go public." Making the repo public is the operator's action, never an
agent's.

## Before flipping public

- [ ] **License approved by the operator.** A draft MIT `LICENSE` ships in
      this repo with the operator's name — the license choice and the
      copyright line are the operator's call; replace or ratify before
      release.
- [ ] **De-personalization sweep is clean.** No personal names, emails,
      machine paths, or private project names:
      `grep -rniE 'phill|freebird|/Users/|@gmail|claw clans|cbr-cockpit' .`
      must return nothing (the word "operator" replaced the person).
- [ ] **Secrets scan is clean.** `gitleaks detect --source . --no-git` and
      `gitleaks detect --source .` (history) both pass.
- [ ] **Manifest verifies.** `./verify-manifest.sh` passes at HEAD.
- [ ] **Verify suite passes.** Every `verify/*.test.sh` green on a clean
      checkout.
- [ ] **Core snapshots identical.** `verify/core-mirrors.test.sh` (also
      covered by the suite).
- [ ] **Credits complete.** `THIRD-PARTY.md` names every tool CBR drives and
      every vendored skill with its origin and license; each vendored skill
      carries its upstream license file beside it.
- [ ] **Install walked once per harness** on a scratch repo by an agent with
      no other context — Claude Code (plugin path) AND Codex. Setup arms one
      harness at a time; a pass on one proves nothing about the other.
- [ ] **Operator has read the repo end-to-end** and says, in so many words,
      "looks good, let's go public."

## After flipping public

- [ ] Tag `VERSION` as the first release.
- [ ] Turn on issues; decide whether PRs require operator review (they
      should).

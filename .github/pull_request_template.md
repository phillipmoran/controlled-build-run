## What and why

<!-- One paragraph. If this changes a guard, name the failure it prevents. -->

## Checklist

- [ ] If this touches package content (`skill/`, `sibling-skills/`,
      `control-plane/`, `verify/`, `SETUP.md`, `MANIFEST.md`): I read the
      canonical-source note in CONTRIBUTING.md and this is meant as an
      upstream fix.
- [ ] Core snapshots edited in BOTH mirrors, `verify/core-mirrors.test.sh`
      passes (skip if core untouched).
- [ ] Changed guards ship a `verify/` fixture proving they fire and can fail.
- [ ] `MANIFEST.sha256` matches (pre-commit hook, or `./generate-manifest.sh`)
      if package content changed.
- [ ] Full suite green: `for t in verify/*.test.sh; do bash "$t" || exit 1; done`
- [ ] Person-neutral: no personal names, machine paths, or private project
      names; the human is the operator.

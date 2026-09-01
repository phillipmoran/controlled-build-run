# Third-party components

CBR is a control plane over other people's tools. What it uses, what it
vendors, and the license each one carries.

## Tools CBR drives (installed by the target repo, not vendored here)

| Tool | What CBR uses it for | License |
|---|---|---|
| [Probity](https://github.com/nizos/probity) (`@nizos/probity`) | Write-time TDD judge: blocks untested production code at the moment of writing; runs the prove-NO / prove-YES probes | MIT |
| [RoboRev](https://github.com/kenn-io/roborev) | Per-commit advisory AI review and the merge-boundary branch review | MIT |
| [gitleaks](https://github.com/gitleaks/gitleaks) | Secrets scan in the pre-commit wall and in CI | MIT |
| [pre-commit](https://github.com/pre-commit/pre-commit) | Runs the commit-time gate wall (format, lint, types, tests, secrets) | MIT |

## Skills vendored under `sibling-skills/`

Each vendored skill keeps its upstream license file beside it.

| Skill | Origin | License | Notes |
|---|---|---|---|
| `test-driven-development` | [obra/superpowers](https://github.com/obra/superpowers) — Jesse Vincent | MIT (`sibling-skills/test-driven-development/LICENSE`) | Vendored as-is |
| `cyclomatic-complexity` | [saurabhkumar8112/cyclomatic-complexity-skill](https://github.com/saurabhkumar8112/cyclomatic-complexity-skill) | Apache-2.0 (`sibling-skills/cyclomatic-complexity/LICENSE`) | Vendored as-is |
| `planning-with-files` | [OthmanAdi/planning-with-files](https://github.com/OthmanAdi/planning-with-files) — Ahmad Adi; Manus-style file planning | MIT (`sibling-skills/planning-with-files/LICENSE`) | Vendored; CBR's own plan templates now carry most of this role (see ROADMAP) |
| `fusion` | adapted from [duolahypercho/fusion-fable](https://github.com/duolahypercho/fusion-fable) | MIT (`sibling-skills/fusion/LICENSE-upstream`) | Substantially modified for CBR's panel review |
| `stage-review`, `closeout` | this project | MIT (repo `LICENSE`) | Original |

Missing or wrong attribution is a bug — open an issue.

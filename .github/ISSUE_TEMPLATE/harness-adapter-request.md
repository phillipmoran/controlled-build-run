---
name: Request a harness adapter
about: Ask for CBR support in another agent runtime (Cursor, Gemini CLI, ...)
title: "adapter request: <harness name>"
labels: adapter
---

## Which harness?

Name and link the agent runtime you want CBR to plug into.

## What does it expose?

An adapter needs hook points. What does this harness offer for each? Leave
blank what you don't know — partial answers still help.

- **Lifecycle hooks** (pre-tool-use / stop / session-start equivalents):
- **Skill or instruction loading** (how does it read a SKILL.md-like file):
- **Settings file** (where per-repo config lives):
- **Subagent behavior** (do child sessions inherit hooks):

## Would you use it or build it?

An adapter is about 30 files, and the porting docs
(`skill/claude-controlled-build-run/PORTING.md`) walk the structure. If you
want to build it yourself, say so — PRs for adapters are the contribution
this repo most wants.

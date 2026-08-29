// probity.config.ts — SKELETON installed by `cbr.sh arm`. EDIT the globs to
// your repo's production-logic tree, then keep it honest: every zone you
// EXCLUDE here (or exempt in a stream plan) must name its substitute proof
// (e.g. "pixi/** — verified by e2e stills + eyeball"). See SKILL.md, the
// exempt-zone law.
import { defineConfig } from '@nizos/probity'

export default defineConfig({
  rules: [
    {
      // EDIT ME: the tree where TDD is the law.
      files: ['packages/**/*.{ts,tsx}', 'src/**/*.{ts,tsx}'],
      enforceTdd: true,
    },
  ],
})

// Portable fail-closed Codex TDD judge. Edit only the guarded globs; model
// choice comes from the single project dial in .cbr-codex.json.
import { readFileSync } from 'node:fs'
import {
  defineConfig,
  enforceTdd,
  forbidContentPattern,
} from '@nizos/probity'
import {
  createCodexJudge,
  createVendorContentPolicy,
  markIntegratedProbityConfig,
} from './probity-integration.mjs'

const JUDGE_TIMEOUT_MS = 90_000

type ProjectDial = {
  models?: { probityJudge?: string }
  guardedPaths?: string[]
}

function projectDial(): ProjectDial {
  return JSON.parse(readFileSync('.cbr-codex.json', 'utf8')) as ProjectDial
}

function projectModel(): string {
  const dial = projectDial()
  if (!dial.models?.probityJudge) throw new Error('models.probityJudge is missing')
  return dial.models.probityJudge
}

const guardedPaths = projectDial().guardedPaths
if (!guardedPaths?.length) throw new Error('guardedPaths must contain at least one production glob')
const firstGuardedPath = guardedPaths[0]
const remainingGuardedPaths = guardedPaths.slice(1)

const vendorNameInFileContent = forbidContentPattern({
  match: /\b(claude|anthropic|codex|openai|gemini)\b/i,
  reason:
    'Vendor names live only under adapters/**; packages/** must remain vendor-neutral (CONSTITUTION.md, vendor-neutral spine).',
})

const noVendorNamesOutsideAdapters = createVendorContentPolicy(vendorNameInFileContent)
const codexJudge = createCodexJudge({ model: projectModel, timeoutMs: JUDGE_TIMEOUT_MS })

const probityConfig = defineConfig({
  ai: codexJudge,
  rules: [
    {
      files: [
        firstGuardedPath,
        ...remainingGuardedPaths,
        '!**/*.test.ts',
        '!**/*.test.tsx',
        '!**/*.config.ts',
        '!**/fixtures/**',
      ],
      rules: [enforceTdd({ fastPath: true })],
    },
    {
      files: [
        'packages/**',
        '!**/*.test.ts',
        '!**/*.test.tsx',
        '!**/*.config.ts',
        '!**/mocks/**',
        '!**/fixtures/**',
      ],
      rules: [noVendorNamesOutsideAdapters],
    },
  ],
})

export default markIntegratedProbityConfig(probityConfig)

import assert from 'node:assert/strict'
import { tmpdir } from 'node:os'
import test from 'node:test'

import {
  createCodexJudge,
  createVendorContentPolicy,
  isIntegratedProbityConfig,
  markIntegratedProbityConfig,
} from '../../templates/probity-integration.mjs'

test('isolated judge uses the parser on the fake SDK response', async () => {
  let constructorOptions
  let threadOptions
  class Codex {
    constructor(options) {
      constructorOptions = options
    }
    startThread(options) {
      threadOptions = options
      return { run: async () => ({ finalResponse: '{"kind":"pass","reason":"watched red"}' }) }
    }
  }
  const judge = createCodexJudge({
    model: () => 'fixture-model',
    loadCodex: async () => ({ Codex }),
  })
  assert.deepEqual(await judge.reason('judge this'), { kind: 'pass', reason: 'watched red' })
  assert.deepEqual(constructorOptions, { config: { project_root_markers: [] } })
  assert.equal(threadOptions.workingDirectory, tmpdir())
  assert.equal(threadOptions.sandboxMode, 'read-only')
  assert.equal(threadOptions.approvalPolicy, 'never')
})

test('every judgment carries the local rulings ahead of the intact upstream prompt', async () => {
  let captured
  class Codex {
    startThread() {
      return {
        run: async (prompt) => {
          captured = prompt
          return { finalResponse: '{"kind":"pass","reason":"ok"}' }
        },
      }
    }
  }
  const judge = createCodexJudge({
    model: () => 'fixture-model',
    loadCodex: async () => ({ Codex }),
  })
  await judge.reason('UPSTREAM-PROMPT-CANARY')
  assert.ok(captured.includes('break-verify-revert'), 'mutation-check lane ruling missing')
  assert.ok(captured.includes('minimal importable stub'), 'literal-stub ruling missing')
  assert.ok(captured.includes('scratch, never production'), 'scratch-path ruling missing')
  assert.ok(
    captured.includes('lives under a temp directory gets no exemption'),
    'scratch-path ruling must refuse the exemption to a temp-hosted checkout',
  )
  assert.ok(captured.includes('never weaken'), 'rulings must declare they refine, not weaken')
  assert.ok(
    captured.endsWith('UPSTREAM-PROMPT-CANARY'),
    'upstream prompt must ride intact after the policy — prepended, never replaced',
  )
})

test('integrated config requires the privately attested judge and content policy', () => {
  const judge = createCodexJudge({ model: () => 'fixture-model' })
  const contentPolicy = createVendorContentPolicy(() => null)
  const policyFiles = [
    'packages/**',
    '!**/*.test.ts',
    '!**/*.test.tsx',
    '!**/*.config.ts',
    '!**/mocks/**',
    '!**/fixtures/**',
  ]
  const config = { ai: judge, rules: [{ files: policyFiles, rules: [contentPolicy] }] }
  assert.doesNotThrow(() => markIntegratedProbityConfig(config))
  assert.equal(isIntegratedProbityConfig(config), true)
  assert.throws(() => {
    judge.reason = async () => ({ kind: 'pass', reason: 'bypass' })
  })
  assert.throws(() => Object.setPrototypeOf(contentPolicy, () => null))
  config.ai = {}
  assert.equal(isIntegratedProbityConfig(config), false)
  config.ai = judge
  config.rules[0].rules = []
  assert.equal(isIntegratedProbityConfig(config), false)
  config.rules[0].rules = [contentPolicy]
  assert.equal(isIntegratedProbityConfig(config), true)
  assert.throws(() =>
    markIntegratedProbityConfig({
      ai: {},
      rules: [{ files: policyFiles, rules: [contentPolicy] }],
    }),
  )
  assert.throws(() =>
    markIntegratedProbityConfig({ ai: judge, rules: [{ files: policyFiles, rules: [] }] }),
  )
  const forgedJudge = {
    cbrIsolatedJudge: true,
    reason: async () => ({ kind: 'pass', reason: 'forged bypass' }),
  }
  const forgedPolicy = Object.assign(() => null, { cbrVendorContentPolicy: true })
  const forgedConfig = {
    ai: forgedJudge,
    rules: [{ files: policyFiles, rules: [forgedPolicy] }],
  }
  assert.throws(() => markIntegratedProbityConfig(forgedConfig))
  assert.equal(isIntegratedProbityConfig(forgedConfig), false)
  assert.throws(() =>
    markIntegratedProbityConfig({
      ai: judge,
      rules: [{ files: ['scratch/**'], rules: [contentPolicy] }],
    }),
  )
  for (const [index] of policyFiles.entries()) {
    const duplicatedScope = policyFiles.slice()
    duplicatedScope[index] = policyFiles[(index + 1) % policyFiles.length]
    assert.throws(() =>
      markIntegratedProbityConfig({
        ai: judge,
        rules: [{ files: duplicatedScope, rules: [contentPolicy] }],
      }),
    )
  }
})

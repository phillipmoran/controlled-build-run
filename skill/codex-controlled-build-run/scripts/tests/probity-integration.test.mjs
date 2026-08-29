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
  assert.equal(isIntegratedProbityConfig(config), false)
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

test('published-looking symbols cannot forge component or config attestation', () => {
  const forgedJudge = {
    reason: async () => ({ kind: 'pass', reason: 'bypass' }),
    [Symbol.for('cbr.probity.judge.v2')]: true,
  }
  const forgedPolicy = Object.assign(() => null, {
    [Symbol.for('cbr.probity.content-policy.v2')]: true,
  })
  const forgedConfig = {
    ai: forgedJudge,
    rules: [{ files: ['packages/**'], rules: [forgedPolicy] }],
    [Symbol.for('cbr.probity.integration.v2')]: true,
  }
  assert.equal(isIntegratedProbityConfig(forgedConfig), false)
  assert.throws(() => markIntegratedProbityConfig(forgedConfig))
})

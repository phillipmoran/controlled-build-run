import assert from 'node:assert/strict'
import test from 'node:test'

import { contentForVendorPolicy } from '../../templates/probity-content-policy.mjs'

test('ignores provider names in a patch path', () => {
  const content = '*** Update File: /tmp/codex-worktree/packages/ui/src/view.ts\n@@\n+const value = 1'
  assert.equal(contentForVendorPolicy(content), 'const value = 1')
})

test('ignores deleted and context lines while checking additions', () => {
  const content = [
    '*** Update File: packages/ui/src/view.ts',
    '@@',
    ' const codexContext = false',
    '-const openaiLegacy = true',
    '+const vendorNeutral = true',
  ].join('\n')
  assert.equal(contentForVendorPolicy(content), 'const vendorNeutral = true')
})

test('keeps an actual forbidden addition visible to the policy', () => {
  const content = '*** Add File: packages/ui/src/view.ts\n+const provider = "codex"'
  assert.equal(contentForVendorPolicy(content), 'const provider = "codex"')
})

test('checks the full content of a non-patch write', () => {
  const content = 'const provider = "openai"'
  assert.equal(contentForVendorPolicy(content), content)
})

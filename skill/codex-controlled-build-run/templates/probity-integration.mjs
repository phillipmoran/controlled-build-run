import { tmpdir } from 'node:os'

import { contentForVendorPolicy } from './probity-content-policy.mjs'
import { parseVerdict } from './probity-verdict-parser.mjs'

const integratedConfigs = new WeakSet()
const isolatedJudges = new WeakSet()
const contentPolicies = new WeakSet()
const requiredContentPolicyFiles = new Set([
  'packages/**',
  '!**/*.test.ts',
  '!**/*.test.tsx',
  '!**/*.config.ts',
  '!**/mocks/**',
  '!**/fixtures/**',
])

function isRequiredContentPolicyScope(files) {
  const uniqueFiles = Array.isArray(files) ? new Set(files) : null
  return (
    uniqueFiles !== null &&
    files.length === requiredContentPolicyFiles.size &&
    uniqueFiles.size === requiredContentPolicyFiles.size &&
    [...requiredContentPolicyFiles].every((file) => uniqueFiles.has(file))
  )
}

function hasActiveSafeguards(config) {
  if (!isolatedJudges.has(config?.ai)) return false
  return (
    Array.isArray(config.rules) &&
    config.rules.some(
      (entry) =>
        isRequiredContentPolicyScope(entry.files) &&
        Array.isArray(entry.rules) &&
        entry.rules.some((rule) => contentPolicies.has(rule)),
    )
  )
}

export function createVendorContentPolicy(contentRule) {
  const policy = (action) =>
    contentRule(
      action.kind === 'write'
        ? { ...action, content: contentForVendorPolicy(action.content) }
        : action,
    )
  contentPolicies.add(policy)
  return Object.freeze(policy)
}

export function createCodexJudge({ model, timeoutMs = 90_000, loadCodex }) {
  const judge = {
    reason: async (prompt) => {
      const controller = new AbortController()
      let timer
      const deadline = new Promise((_, reject) => {
        timer = setTimeout(() => {
          controller.abort()
          reject(new Error(`judge timed out after ${timeoutMs}ms`))
        }, timeoutMs)
        timer.unref?.()
      })
      try {
        const { Codex } = await (loadCodex?.() ?? import('@openai/codex-sdk'))
        const codex = new Codex({ config: { project_root_markers: [] } })
        const thread = codex.startThread({
          model: model(),
          workingDirectory: tmpdir(),
          skipGitRepoCheck: true,
          sandboxMode: 'read-only',
          approvalPolicy: 'never',
          networkAccessEnabled: false,
          webSearchEnabled: false,
        })
        const turn = await Promise.race([
          thread.run(prompt, { signal: controller.signal }),
          deadline,
        ])
        return parseVerdict(turn.finalResponse)
      } catch (error) {
        return {
          kind: 'violation',
          reason: `Codex TDD judge unavailable; fix the judge, never bypass it: ${
            controller.signal.aborted
              ? `timed out after ${timeoutMs}ms`
              : error instanceof Error
                ? error.message
                : String(error)
          }`,
        }
      } finally {
        clearTimeout(timer)
      }
    },
  }
  isolatedJudges.add(judge)
  return Object.freeze(judge)
}

export function markIntegratedProbityConfig(config) {
  if (!isolatedJudges.has(config?.ai)) {
    throw new Error('active Probity config does not use the current isolated Codex judge')
  }
  if (!hasActiveSafeguards(config)) {
    throw new Error('active Probity config does not use the current patch content policy')
  }
  integratedConfigs.add(config)
  return config
}

export function isIntegratedProbityConfig(config) {
  return (
    (typeof config === 'object' || typeof config === 'function') &&
    config !== null &&
    integratedConfigs.has(config) &&
    hasActiveSafeguards(config)
  )
}

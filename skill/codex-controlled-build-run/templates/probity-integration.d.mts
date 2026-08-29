import type { Action, Agent } from '@nizos/probity'

export function createVendorContentPolicy<T>(
  contentRule: (action: Action) => T,
): (action: Action) => T
export function createCodexJudge(options: {
  model: () => string
  timeoutMs?: number
  loadCodex?: () => Promise<{ Codex: new (options: unknown) => unknown }>
}): Agent
export function markIntegratedProbityConfig<T>(config: T): T
export function isIntegratedProbityConfig(config: unknown): boolean

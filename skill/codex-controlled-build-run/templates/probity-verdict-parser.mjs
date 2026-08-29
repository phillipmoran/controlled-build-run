export function parseVerdict(text) {
  const candidates = [
    text.trim(),
    text.trim().replace(/^```(?:json)?\s*/u, '').replace(/\s*```$/u, ''),
  ]
  const close = text.lastIndexOf('}')
  for (let start = text.lastIndexOf('{', close); start >= 0; ) {
    candidates.push(text.slice(start, close + 1))
    if (start === 0) break
    start = text.lastIndexOf('{', start - 1)
  }
  for (const candidate of candidates) {
    try {
      const value = JSON.parse(candidate)
      if (
        (value.kind === 'pass' || value.kind === 'violation') &&
        typeof value.reason === 'string'
      ) {
        return value
      }
    } catch {
      // Try the next candidate.
    }
  }
  return { kind: 'violation', reason: `Unparseable Codex TDD verdict: ${text.slice(0, 1000)}` }
}

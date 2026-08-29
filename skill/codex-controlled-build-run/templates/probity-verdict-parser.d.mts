export type ParsedVerdict = {
  kind: 'pass' | 'violation'
  reason: string
  [key: string]: unknown
}

export function parseVerdict(text: string): ParsedVerdict

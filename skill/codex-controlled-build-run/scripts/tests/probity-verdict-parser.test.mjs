import assert from 'node:assert/strict'
import test from 'node:test'

import { parseVerdict } from '../../templates/probity-verdict-parser.mjs'

test('parses a verdict whose JSON starts at offset zero', () => {
  assert.deepEqual(parseVerdict('{"kind":"pass","reason":"watched red"}'), {
    kind: 'pass',
    reason: 'watched red',
  })
})

test('parses a fenced verdict', () => {
  assert.deepEqual(parseVerdict('```json\n{"kind":"pass","reason":"ok"}\n```'), {
    kind: 'pass',
    reason: 'ok',
  })
})

test('parses a prose-prefixed verdict', () => {
  assert.deepEqual(
    parseVerdict('Judge result: {"kind":"violation","reason":"test did not fail"} done.'),
    { kind: 'violation', reason: 'test did not fail' },
  )
})

test('parses an outer verdict containing nested JSON', () => {
  assert.deepEqual(
    parseVerdict(
      'Result {"kind":"pass","reason":"ok","evidence":{"baseline":"green"}} complete',
    ),
    { kind: 'pass', reason: 'ok', evidence: { baseline: 'green' } },
  )
})

test('fails closed for a malformed verdict', () => {
  const result = parseVerdict('{"kind":"pass"}')
  assert.equal(result.kind, 'violation')
  assert.match(result.reason, /^Unparseable Codex TDD verdict:/)
})

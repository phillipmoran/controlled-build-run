import {
  defineConfig,
  enforceTdd,
  forbidContentPattern,
} from '@nizos/probity'

const noProjectPrefix = forbidContentPattern({
  match: /\b(from|import)\s+myproj_\w+/,
  reason:
    'Project-prefixed module names ("myproj_X") are forbidden. Drop the prefix — see AGENTS.md <naming>.',
})

const noJargonModuleNames = forbidContentPattern({
  match: /\b(from|import)\s+(engine|agent)\b/,
  reason:
    'Use domain vocabulary from GLOSSARY. "world" not "engine"; "hero" not "agent". See AGENTS.md <naming>.',
})

const noClockInEnvelope = forbidContentPattern({
  match: /\b(from|import)\s+(time|datetime|uuid|random)\b/,
  reason:
    'The envelope stays clock-free: an event id derives from its turn and order, never the clock, a uuid, or randomness (player-view.md Rule 12). A replayed turn must reproduce the same wire.',
})

export default defineConfig({
  rules: [
    {
      files: ['packages/**/*.py'],
      rules: [noProjectPrefix, noJargonModuleNames, enforceTdd()],
    },
    {
      files: ['packages/player-view/src/player_view/envelope/**/*.py'],
      rules: [noClockInEnvelope],
    },
    {
      // Logic dirs only, enumerated — a catch-all glob would recreate the
      // junk-drawer incentive the lib/ dissolution removed. A new logic dir
      // extends this list in the same commit that creates it. Pure-visual
      // components stay ungated (UI ground rule 6: visuals are verified by
      // eyeball vs the mocks + the animation coverage test).
      files: [
        'packages/player-view-web/src/wire/**/*.ts',
        'packages/player-view-web/src/wire/**/*.tsx',
        'packages/player-view-web/src/hp-bar/**/*.ts',
        'packages/player-view-web/src/hp-bar/**/*.tsx',
        'packages/player-view-web/src/signin/**/*.ts',
        'packages/player-view-web/src/signin/**/*.tsx',
        'packages/player-view-web/src/api-client/**/*.ts',
        'packages/player-view-web/src/api-client/**/*.tsx',
        'packages/player-view-web/src/hero-name/**/*.ts',
        'packages/player-view-web/src/hero-name/**/*.tsx',
        'packages/player-view-web/src/creation/**/*.ts',
        'packages/player-view-web/src/creation/**/*.tsx',
        'packages/player-view-web/src/music/**/*.ts',
        'packages/player-view-web/src/music/**/*.tsx',
        'packages/player-view-web/src/replay/**/*.ts',
        'packages/player-view-web/src/replay/**/*.tsx',
        'packages/player-view-web/src/watch/**/*.ts',
        'packages/player-view-web/src/watch/**/*.tsx',
      ],
      rules: [enforceTdd()],
    },
  ],
})

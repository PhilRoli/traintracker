import type { EngineInterface, Register } from 'claude-code'

// TrainTracker writes ~/.traintracker/arrival.json: { "arrival": <epoch seconds, delay included> }
const WRAP_UP_MINUTES = 10
const POLL_MS = 30_000

export const minutesLeft = (raw: string, nowMs: number): number | undefined => {
  try {
    const arrival = JSON.parse(raw).arrival
    return typeof arrival === 'number' ? (arrival * 1000 - nowMs) / 60_000 : undefined
  } catch {
    return undefined
  }
}

async function check($: EngineInterface) {
  try {
    const home = await $.env.get('HOME')
    const raw = await $.fs.read(`${home}/.traintracker/arrival.json`)
    const left = minutesLeft(raw, await $.clock.now())
    return left !== undefined && left > -5 && left <= WRAP_UP_MINUTES ? Math.max(0, Math.ceil(left)) : undefined
  } catch {
    return undefined
  }
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    $.clock.every(POLL_MS, async () => {
      const left = await check($)
      $.ui.status(left === undefined ? undefined : `🚆 arrives in ${left} min — wrap up`)
    })
    return next(e)
  })

  on('prompt.compose', async ($, e, next) => {
    const res = await next(e)
    const left = await check($)
    if (left === undefined) return res
    return {
      sections: [
        ...res.sections,
        {
          id: `${$.plugin.name}:wrap-up`,
          scope: 'session',
          text:
            `The user's train arrives in about ${left} minute(s) and they will lose their connection and must stop. ` +
            `Do not start new work. Finish the current step only if it can be done in a minute or two, leave the code in a ` +
            `consistent, working state (no half-applied edits), commit or note progress if appropriate, then stop and tell ` +
            `the user briefly what is done and what remains so they can resume later.`,
        },
      ],
    }
  })
}

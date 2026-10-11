import { test, expect } from 'claude-code/testing'
import { minutesLeft } from './register'

test('minutesLeft reads the arrival file', () => {
  expect(minutesLeft('{"arrival":600}', 0)).toBe(10)
  expect(minutesLeft('nope', 0)).toBeUndefined()
})

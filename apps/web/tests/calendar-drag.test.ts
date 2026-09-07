import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { calendarMinute, calendarRange } from '../src/calendar-drag.ts';
test('dragging downward selects the entire half-hour range', () => {
  assert.deepEqual(calendarRange(540, 630), { start: 540, duration: 120 });
});
test('dragging upward produces the same positive duration', () => {
  assert.deepEqual(calendarRange(630, 540), { start: 540, duration: 120 });
});
test('a click defaults to an hour and the day boundary is respected', () => {
  assert.deepEqual(calendarRange(540, 540), { start: 540, duration: 60 });
  assert.deepEqual(calendarRange(1410, 1410), { start: 1410, duration: 30 });
  assert.equal(calendarMinute(-20, 0, 48), 0);
  assert.equal(calendarMinute(2000, 0, 48), 1410);
});

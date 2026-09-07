import test from 'node:test';
import assert from 'node:assert/strict';
import { seedMail, defaultPreferences } from '../src/data.ts';
import { selectMailView } from '../src/mail-view.ts';
import { inFolder } from '../src/mail-model.ts';
test('the personal inbox includes Important and other splits without pulling in archived mail', () => {
  const sample = seedMail();
  const account = sample[0].account;
  const mail = sample.filter(m => m.account === account);
  const view = selectMailView(mail, account, 'Inbox', 'All', defaultPreferences, false, '', null);
  assert.deepEqual(view.visibleMail.map(m => m.id), mail.filter(m => inFolder(m, 'Inbox')).map(m => m.id));
  assert.equal(view.inboxCount, view.visibleMail.length);
});
test('Starred remains an independent saved-message view', () => {
  const sample = seedMail();
  const account = sample[0].account;
  const mail = sample.filter(m => m.account === account);
  const view = selectMailView(mail, account, 'Starred', 'All', defaultPreferences, false, '', null);
  assert.deepEqual(view.visibleMail.map(m => m.id), mail.filter(m => inFolder(m, 'Starred')).map(m => m.id));
});

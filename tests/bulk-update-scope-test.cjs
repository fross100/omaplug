const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const context = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname, '../panel/Presentation.js'), 'utf8')
  .replace(/^\.pragma library\s*/, ''), context);
const rows = ['verified', 'pending', 'unverified', 'unknown', 'current'].map(id => ({ id, sourceKey: id }));
const states = Object.fromEntries(rows.map(row => [row.id, row.id === 'current' ? 'CURRENT' : 'UPDATE']));
const catalog = {
  verified: { verified: true, snapshotCommit: 'a'.repeat(40) },
  pending: { verified: false, snapshotStatus: 'update-unverified', snapshotCommit: 'a'.repeat(40) },
  unverified: { verified: false },
  current: { verified: true },
};
const keys = (scope, sourceRows = rows, entries = catalog) =>
  Array.from(context.bulkUpdateKeys(sourceRows, states, entries, scope, incoming));
const incoming = { verified: 'a'.repeat(40), pending: 'b'.repeat(40) };
assert.deepEqual(keys('verified'), ['verified']);
assert.deepEqual(keys('pending'), ['verified', 'pending']);
assert.deepEqual(keys('all'), ['verified', 'pending', 'unverified', 'unknown']);
assert.deepEqual(keys('verified', rows, {}), []);
assert.deepEqual(keys('pending', rows, {}), []);
const shared = [...rows, { id: 'unverified', sourceKey: 'verified' }];
assert.deepEqual(keys('verified', shared), []);
assert.deepEqual(keys('pending', shared), ['pending']);
assert.deepEqual(keys('all', shared), ['verified', 'pending', 'unverified', 'unknown']);
catalog.pending = { verified: true, snapshotCommit: 'b'.repeat(40) };
assert.deepEqual(keys('verified'), ['verified', 'pending']);
incoming.verified = 'c'.repeat(40);
assert.deepEqual(keys('verified'), ['pending']);
assert.deepEqual(keys('pending'), ['verified', 'pending']);
delete incoming.verified;
assert.deepEqual(keys('pending'), ['pending']);
console.log('bulk-update-scope-test: ok');

// Exercise the real launcher, not a copy of its commit propagation logic.
const panel = fs.readFileSync(path.join(__dirname, '../Panel.qml'), 'utf8');
const launcher = panel.slice(panel.indexOf('  function startDetachedUpdates(ids)'), panel.indexOf('  function applyUpdateJobStatus()'));
let launched;
const root = { checkingUpdates: false, updateDetachedRunning: false, updateRunnerPath: '/helper', updateStatusPath: '/status',
  incomingCommits: { verified: 'a'.repeat(40) }, markUpdateInterrupted(message) { this.error = message; this.updateDetachedRunning = false; } };
const launchContext = vm.createContext({ root, Quickshell: { execDetached(argv) { launched = Array.from(argv); } },
  updateStartTimer: { restart() {} }, updateStatusPoll: { restart() {} } });
vm.runInContext(launcher, launchContext);
launchContext.startDetachedUpdates(['verified']);
assert.equal(launched[3], 'verified@' + 'a'.repeat(40));
root.updateDetachedRunning = false;
launched = null;
launchContext.startDetachedUpdates(['missing']);
assert.equal(launched, null);
assert.match(root.error, /Check for updates again/);

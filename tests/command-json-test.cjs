const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const panel = fs.readFileSync(require('node:path').join(__dirname, '../Panel.qml'), 'utf8');
const start = panel.indexOf('  function parseCommandJson(text)');
const end = panel.indexOf('\n  function applyPluginConfig', start);
assert.notEqual(start, -1);
assert.notEqual(end, -1);
const context = vm.createContext({ JSON });
vm.runInContext(panel.slice(start, end), context);

assert.deepEqual(JSON.parse(JSON.stringify(context.parseCommandJson('[{"id":"omaplug"}]'))), [{ id: 'omaplug' }]);
assert.deepEqual(JSON.parse(JSON.stringify(context.parseCommandJson('WARN: Qt switched locale\n[{"id":"omaplug"}]'))), [{ id: 'omaplug' }]);
assert.deepEqual(JSON.parse(JSON.stringify(context.parseCommandJson('WARN: Qt diagnostic\n{\n  "bar": {}\n}'))), { bar: {} });
assert.throws(() => context.parseCommandJson('WARN: still no JSON'));
console.log('command-json-test: ok');

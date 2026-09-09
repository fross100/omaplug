const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const { execFileSync } = require('node:child_process');

const source = fs.readFileSync(path.join(__dirname, '../Panel.qml'), 'utf8');
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'omaplug-metadata-'));
try {
  const context = vm.createContext({
    console, pluginRows: [], marketplaceMap: {},
    pluginManifestProcess: {}, scanPluginRepos() {},
    Quickshell: { env: () => temporary }
  });
  context.root = context;
  for (const name of ['applyPluginList', 'applyPluginMetadata', 'mergeMarketplaceMetadata', 'applyMarketplaceCatalog']) {
    const start = source.indexOf('  function ' + name + '(');
    assert.notEqual(start, -1);
    const end = source.indexOf('\n  }', start) + 4;
    vm.runInContext(source.slice(start, end), context);
  }

  const manifests = [
    ['shell/plugins/panels/clock/clock.manifest.json', 'omarchy.clock'],
    ['.config/omarchy/plugins/test plugin/manifest.json', 'test.plugin']
  ];
  for (const [relative, id] of manifests) {
    const file = path.join(temporary, relative);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, JSON.stringify({ id, description: 'Installed ' + id }));
  }
  const catalog = JSON.stringify([
    { id: 'omarchy.clock', firstParty: true, enabled: true, kinds: ['bar-widget'] },
    { id: 'test.plugin', enabled: false, kinds: ['panel'] },
    { id: 'catalog.only', enabled: true, kinds: ['panel'] }
  ]);
  context.marketplaceMap = {
    'test.plugin': { description: 'Marketplace description' },
    'catalog.only': { description: 'Cached description' }
  };

  // Repeat to cover a refresh after the marketplace has already loaded.
  for (let refresh = 0; refresh < 2; refresh++) {
    context.applyPluginList(catalog);
    const [command, ...args] = context.pluginManifestProcess.command;
    const output = execFileSync(command, args, {
      env: { ...process.env, HOME: temporary }, encoding: 'utf8'
    });
    context.applyPluginMetadata(output);
    const rows = Object.fromEntries(context.pluginRows.map(row => [row.id, row]));
    assert.equal(rows['omarchy.clock'].description, 'Installed omarchy.clock');
    assert.equal(rows['test.plugin'].description, 'Installed test.plugin');
    assert.equal(rows['catalog.only'].description, 'Cached description');
    assert.equal(rows['test.plugin'].enabled, false);
    assert.equal(rows['omarchy.clock'].enabled, true);
    // A later marketplace response must not replace installed metadata.
    context.mergeMarketplaceMetadata(context.marketplaceMap);
    assert.equal(context.pluginRows.find(row => row.id === 'test.plugin').description,
      'Installed test.plugin');
  }
  console.log('plugin-metadata-test: ok');
  const page = fs.readFileSync(path.join(__dirname, '../panel/updates/Page.qml'), 'utf8');
  const start = page.indexOf('  function verificationText(');
  vm.runInContext(page.slice(start, page.indexOf('\n  }', start) + 4), context);
  context.applyMarketplaceCatalog(JSON.stringify({ plugins: [{
    id: 'listed', verificationStatus: 'unverified',
    verificationSnapshotStatus: 'verified', verificationCoverage: 'update-unverified'
  }] }));
  assert.equal(context.marketplaceMap.listed.snapshotStatus, 'update-unverified');
  context.updateStates = { folder: 'UPDATE' };
  context.marketplaceFetching = false;
  context.marketplaceFetchFailed = false;
  assert.equal(context.verificationText('listed', 'folder'), 'Update Unverified');
  assert.equal(context.verificationText('unlisted', 'folder'), 'Not listed');
  context.updateStates.folder = 'CURRENT';
  assert.equal(context.verificationText('listed', 'folder'), 'Update Unverified');
  context.marketplaceMap.listed.verified = true;
  assert.equal(context.verificationText('listed', 'folder'), 'Verified');
  context.marketplaceMap.listed.verified = false;
  context.marketplaceMap.listed.snapshotStatus = '';
  assert.equal(context.verificationText('listed', 'folder'), 'Unverified');
  context.updateStates.folder = 'UPDATE';
  assert.equal(context.verificationText('listed', 'folder'), 'Unverified');
  console.log('update-verification-test: ok');
} finally {
  fs.rmSync(temporary, { recursive: true, force: true });
}

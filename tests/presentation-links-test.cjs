const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const source = fs.readFileSync(require('node:path').join(__dirname, '../panel/Presentation.js'), 'utf8')
  .replace('.pragma library', '');
const context = vm.createContext({});
vm.runInContext(source, context);

for (const input of [
  'https://github.com/owner/repo',
  'https://github.com/owner/repo.git',
  'git@github.com:owner/repo.git',
  'ssh://git@github.com/owner/repo.git'
]) {
  assert.equal(context.normalizedGitHubUrl(input), 'https://github.com/owner/repo');
}
for (const input of [
  'file:///tmp/repo',
  'git@gitlab.com:owner/repo.git',
  'https://github.com/owner/../repo',
  'https://github.com/owner/repo?command=bad'
]) {
  assert.equal(context.normalizedGitHubUrl(input), '');
}
for (const input of [
  'https://github.com/owner/repo/releases/tag/v1.0.0',
  'https://github.com/owner/repo/tree/v0.1.0-beta.5'
]) {
  assert.equal(context.releaseUrl(input), input);
}
for (const input of [
  'file:///etc/passwd',
  'javascript:alert(1)',
  'https://evil.example/owner/repo/releases/tag/v1',
  'https://github.com.evil.example/owner/repo/releases/tag/v1',
  'https://github.com/owner/repo',
  'https://github.com/owner/repo/releases/tag/v1\n--help',
  'https://github.com/owner/repo/' + 'x'.repeat(600)
]) {
  assert.equal(context.releaseUrl(input), '');
}

// ToolTip.text is AutoText: manifest text must never contain markup, because an
// <img> tag there makes the shell fetch a remote URL on hover.
assert.equal(context.tooltipText('Plugin Manager'), 'Plugin Manager');
assert.equal(context.tooltipText('<img src="https://evil.example/p.png">'), '');
assert.equal(context.tooltipText('Hello <img src=x> world'), 'Hello  world');
assert.equal(context.tooltipText('a\nb\tc'), 'a b c');
assert.equal(context.tooltipText(null), '');
assert.equal(context.tooltipText(undefined), '');
assert.equal(context.tooltipText('x'.repeat(600)).length, 512);
for (const input of ['<b', 'a > b', '<img src=x>plain', '<a href="x">link</a>']) {
  const out = context.tooltipText(input);
  assert.ok(!/[<>]/.test(out), `tooltipText left markup in ${JSON.stringify(input)}`);
}
console.log('presentation-links-test: ok');

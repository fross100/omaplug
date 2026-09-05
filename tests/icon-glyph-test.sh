#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PANEL="$ROOT/Panel.qml"

node - "$PANEL" <<'NODE'
const assert = require("node:assert/strict")
const fs = require("node:fs")

const panel = fs.readFileSync(process.argv[2], "utf8")
const start = panel.indexOf("  function isStandaloneGlyph(text) {")
const end = panel.indexOf("\n  function iconFor(id) {", start)
assert.ok(start >= 0 && end > start, "isStandaloneGlyph must be present in Panel.qml")
assert.ok(panel.includes("if (live && root.isStandaloneGlyph(live)) return live"),
  "iconFor must guard live labels with isStandaloneGlyph")

const source = panel.slice(start, end).replace(/^  /gm, "")
const isStandaloneGlyph = new Function(`${source}\nreturn isStandaloneGlyph`)()

assert.equal(isStandaloneGlyph("\uf0f3"), true)
assert.equal(isStandaloneGlyph("\udb85\udcd9"), true)
assert.equal(isStandaloneGlyph("\uf0f3 1h 58m"), false)
assert.equal(isStandaloneGlyph("1h 58m"), false)
assert.equal(isStandaloneGlyph("12345"), false)

console.log("icon-glyph-test: ok")
NODE

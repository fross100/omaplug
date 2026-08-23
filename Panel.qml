import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Plugin manager popup: lists every discovered plugin (first-party omarchy +
// third-party) with an enable/disable switch. The list is read from the
// shell's PluginRegistry, which already scans manifests, so there is no
// duplicate file IO — toggling routes through registry.setEnabled, the same
// path `omarchy plugin enable/disable` uses.
Panel {
  id: root
  moduleName: "omaplug"
  ipcTarget: "omaplug"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  // Overlays cover the popup's own card, so they match the popup background.
  readonly property color panelBackground: Color.popups.background

  // ------------------------------------------------------------------ plugins

  property var pluginRows: []

  // The shell injects the PluginRegistry into the bar's `shell` (the built-in
  // Bar.qml exposes no `pluginRegistry` property itself), so resolve it there
  // with a fallback for custom bars that do carry the registry directly.
  readonly property var registry: root.bar && root.bar.shell
    ? root.bar.shell.pluginRegistry
    : (root.bar ? root.bar.pluginRegistry : null)

  // Git remote URLs for updatable plugins, keyed by sourceKey. Filled by a
  // background `git remote get-url` scan so each row can offer a repo link.
  property var pluginRepos: ({})
  property bool reposScanning: false

  // Marketplace listing info keyed by plugin id: { verified: bool }. Fetched
  // from the public catalog so rows can show a verification badge and a
  // "View on marketplace" link for listed plugins.
  property var marketplaceMap: ({})
  property bool marketplaceFetching: false
  property string marketplaceFetchedAt: ""

  function marketplaceEntry(id) {
    if (modelData_firstParty(id)) return null
    return root.marketplaceMap[String(id)] || null
  }
  function modelData_firstParty(id) {
    var reg = root.registry
    var m = reg && reg.installedPlugins ? reg.installedPlugins[id] : null
    return m ? m.__isFirstParty === true : false
  }
  function marketplaceUrlFor(id) {
    return "https://omarchyplugins.com/plugin.html?id=" + encodeURIComponent(String(id))
  }
  function openMarketplacePage(id) {
    var e = root.marketplaceEntry(id)
    if (e) Qt.openUrlExternally(root.marketplaceUrlFor(id))
  }

  property string searchText: ""
  property int filterMode: 0 // 0 all, 1 omarchy, 2 third-party, 4 adna
  property string filterKind: "" // "" all types, else a kind like bar-widget

  // Kind choices derived from what is actually installed, so the dropdown
  // only offers types the user can really filter by.
  // Canonical Omarchy plugin kinds (Quattro contract). Anything outside this
  // list is grouped under "Other".
  // Canonical Omarchy plugin kinds (Quattro contract) with display labels,
  // in fixed dropdown order. Anything outside this list groups under Other.
  readonly property var knownKinds: [
    { value: "bar-widget", label: "Bar Widget" },
    { value: "panel", label: "Panel" },
    { value: "overlay", label: "Overlay" },
    { value: "menu", label: "Menu" },
    { value: "service", label: "Service" },
    { value: "bar", label: "Bar" }
  ]

  readonly property var kindOptions: {
    var installed = {}
    var hasOther = false
    for (var i = 0; i < root.pluginRows.length; i++) {
      var parts = String(root.pluginRows[i].kinds || "").split(", ")
      for (var j = 0; j < parts.length; j++) {
        var k = parts[j].trim()
        if (k === "") continue
        var canonical = false
        for (var n = 0; n < root.knownKinds.length; n++) {
          if (root.knownKinds[n].value === k) { canonical = true; break }
        }
        if (canonical) installed[k] = true
        else hasOther = true
      }
    }
    var opts = [{ value: "", label: "All types" }]
    for (var m = 0; m < root.knownKinds.length; m++) {
      if (installed[root.knownKinds[m].value] === true)
        opts.push({ value: root.knownKinds[m].value, label: root.knownKinds[m].label })
    }
    if (hasOther) opts.push({ value: "_other", label: "Other" })
    return opts
  }

  function rowMatchesKind(p) {
    if (root.filterKind === "") return true
    var kinds = String(p.kinds || "").split(", ")
    if (root.filterKind === "_other") {
      for (var i = 0; i < kinds.length; i++) {
        var k = kinds[i].trim()
        if (k === "") continue
        var canonical = false
        for (var n = 0; n < root.knownKinds.length; n++) {
          if (root.knownKinds[n].value === k) { canonical = true; break }
        }
        if (!canonical) return true
      }
      return false
    }
    return kinds.indexOf(root.filterKind) !== -1
  }

  // Update checking state, keyed by the plugin folder name (sourceKey).
  property var updateStates: ({})
  property bool checkingUpdates: false
  property bool updatingAll: false
  property string updateSummary: ""
  property string updatingId: ""
  // Full-page "check for updates" view (replaces the header inline progress).
  property bool updatesPageOpen: false
  // Streaming parse state for per-plugin progress.
  property string updateCheckLineBuf: ""
  property int updateCheckProcessed: 0

  property bool installDialogOpen: false
  property bool installRunning: false
  property bool installFailed: false
  property string installResult: ""
  // Confirm popup shown before running install: ask whether to enable the
  // freshly installed plugin. installPendingUrl carries the extracted URL.
  property bool installConfirmOpen: false
  property string installPendingUrl: ""
  // Status file for the detached installer. The file is created securely
  // via mktemp (XDG_RUNTIME_DIR) so the helper can truncate it without
  // following an attacker-controlled symlink. The plugin is installed but
  // not enabled by default — user must enable manually after reviewing.
  property string installStatusPath: ""
  property bool installDetachedRunning: false

  // Plugin removal state. Each row gets a trash button for a single remove, and
  // a select mode (check list) removes several at once via a sequential queue.
  property var removeSelection: ({})
  property bool removeSelectMode: false
  property string removeSummary: ""
  property var removeQueue: []
  property bool removingPlugin: false
  property bool removeConfirmOpen: false
  property var removePending: []
  // Confirmation before restarting the shell: clears the QML compile cache and
  // relaunches the shell so plugins reload from source (fixes stale compiled
  // plugin QML that a live rescan would keep serving).
  property bool restartConfirmOpen: false
  // Right-click context menu on a main-page row.
  property bool rowMenuOpen: false
  property string rowMenuId: ""
  property var rowMenuPos: ({ x: 0, y: 0 })
  onInstallDialogOpenChanged: {
    if (root.installDialogOpen) {
      root.installRunning = false
      root.installFailed = false
      root.installResult = ""
      Qt.callLater(function() { installUrlField.forceActiveFocus() })
    } else {
      root.installConfirmOpen = false
      root.installPendingUrl = ""
    }
  }

  property Timer checkWatchdog: Timer {
    interval: 45000
    repeat: false
    onTriggered: {
      console.log("checkWatchdog timeout, process running=", updateCheckProcess.running)
      if (!root.checkingUpdates) return
      if (updateCheckProcess.running)
        updateCheckProcess.signal(9)
      root.checkingUpdates = false
      root.updateSummary = "Check timed out — a repository may be unreachable"
    }
  }

  // Detached install helpers have no live process handle here (setsid/nohup
  // survives the plugin reload that unloads this panel), so a helper that
  // dies mid-install would otherwise leave the dialog stuck on "Installing…"
  // forever. Bound the wait; git clones can be slow, so allow three minutes.
  property Timer installWatchdog: Timer {
    interval: 180000
    repeat: false
    onTriggered: {
      if (!root.installDetachedRunning && !root.installRunning) return
      root.installDetachedRunning = false
      root.installRunning = false
      root.installFailed = true
      root.installResult = "Install timed out"
      root.installStatusPath = ""
    }
  }

  function iconColorFor(name) {
    var hash = 0
    for (var i = 0; i < name.length; i++) hash = (hash * 31 + name.charCodeAt(i)) | 0
    var palette = [
      "#c0392b", "#2980b9", "#27ae60", "#d35400", "#8e44ad",
      "#16a085", "#e67e22", "#2c3e50", "#c0272f", "#21618c",
      "#1e8449", "#b9770e", "#7d3c98", "#117a65", "#ca6f1e"
    ]
    return palette[Math.abs(hash) % palette.length]
  }

  // Pull the icon glyph straight from the plugin's live bar widget. Each
  // module slot on the bar holds the instantiated BarWidget, whose button
  // carries the author's `text` glyph. This stays in sync with what the bar
  // actually renders (no hardcoded copy to drift).
  property var _glyphCache: ({})
  function invalidateGlyphCache() { root._glyphCache = {} }

  function liveGlyphFor(id) {
    if (root._glyphCache[id] !== undefined) return root._glyphCache[id]
    var glyph = liveGlyphForUncached(id)
    root._glyphCache[id] = glyph
    return glyph
  }

  function liveGlyphForUncached(id) {
    var bar = root.bar
    if (!bar || !bar.moduleSlots) return ""
    var slots = bar.moduleSlots
    for (var i = 0; i < slots.length; i++) {
      var slot = slots[i]
      if (!slot || slot.moduleName !== id) continue
      var item = slot.activeItem
      if (!item) continue
      var glyph = buttonGlyphIn(item)
      if (glyph) return glyph
    }
    return ""
  }

  // Depth-first walk of a widget's children looking for a bar button
  // (WidgetButton or its BarIconButton subclass, both exposing `text` and
  // `labelVisible`); returns its rendered text glyph.
  function buttonGlyphIn(item) {
    var stack = [item]
    while (stack.length > 0) {
      var node = stack.pop()
      if (!node) continue
      if (typeof node.text === "string" && node.text !== ""
          && (typeof node.slotSize === "number" || typeof node.labelVisible === "boolean")) {
        return node.text
      }
      var data = node.data
      if (data) {
        for (var j = 0; j < data.length; j++) stack.push(data[j])
      }
    }
    return ""
  }

  function iconFor(id) {
    // The clock widget's live button text is the current time, which reads
    // like noise as a row icon — always show the clock glyph for it instead.
    if (/clock/i.test(String(id))) return "\uf017"
    var live = root.liveGlyphFor(id)
    if (live) return live
    var map = {
      "omaplug":            "\udb85\udcd9",
      "adna.bar":            "\uf2f2",
      "adna.bar-switch":     "\uf2f2",
      "adna.clock":          "\uf017",
      "adna.dynamic.island": "\uf5bb",
      "adna.menu":           "\ue900",
      "adna.notifications":  "\uf0f3",
      "adna.weather":        "\uf6c3",
      "hark":                "\uf130",
      "omaconnect":          "\uf1eb",
      "hl.peripheral_battery": "\uf241",
      "io.weirdware.blueferry": "\uf56f",
      "com.aktivesolutions.bw-vault": "\uf3ed",
      "io.github.bmontythe3rd.display-manager": "\uf108",
      "io.github.sirjul1337.lock-explorer": "\uf023",
      "io.github.thisisgm.cliampui": "\uf026",
      "markbusai.opencode-usage": "\uf11b",
      "stappmus.activity-monitor": "\uf080",
      "syntaxboybe.fluxcast": "\uf043",
      "omarchy.agents":      "\uf544",
      "omarchy.background":  "\uf03e",
      "omarchy.bar":         "\uf0c9",
      "omarchy.clipboard":   "\uf328",
      "omarchy.dev-gallery": "\uf121",
      "omarchy.emojis":      "\uf118",
      "omarchy.image-picker": "\uf030",
      "omarchy.lock":        "\uf023",
      "omarchy.notifications": "\uf0f3",
      "omarchy.osd":         "\uf163",
      "omarchy.polkit":      "\uf3ed",
      "omarchy.reminders":   "\uf017"
    }
    return map[id] || ""
  }

  readonly property var visibleRows: root.pluginRows.filter(function(p) {
    if (root.removeSelectMode && p.firstParty) return false
    if (root.filterMode === 1 && !p.firstParty) return false
    if (root.filterMode === 2 && p.firstParty) return false
    if (root.filterMode === 4 && String(p.id).indexOf("adna.") !== 0) return false
    if (!root.rowMatchesKind(p)) return false
    var q = root.searchText.trim().toLowerCase()
    if (q === "") return true
    return String(p.name || "").toLowerCase().indexOf(q) !== -1
      || String(p.description || "").toLowerCase().indexOf(q) !== -1
      || String(p.id || "").toLowerCase().indexOf(q) !== -1
      || String(p.author || "").toLowerCase().indexOf(q) !== -1
      || String(p.kinds || "").toLowerCase().indexOf(q) !== -1
  })

  // Plugins that are git-managed (updatable) — what the check actually scans.
  readonly property var updateCheckRows: root.pluginRows.filter(function(p) { return p.updatable })

  function updateStatusText(key) {
    var st = root.updateStates[key]
    if (!st) return "Pending"
    if (st === "CHECK") return "Checking…"
    if (st === "CURRENT") return "Up to date"
    if (st === "UPDATE") return "Update available"
    if (st === "ERROR") return "Error"
    return st
  }

  function updateStatusColor(key) {
    var st = root.updateStates[key]
    if (st === "UPDATE") return Style.selectedStateColor(root.contentForeground, Color.accent)
    if (st === "ERROR") return Color.urgent
    if (st === "CURRENT") return Qt.darker(root.contentForeground, 1.6)
    return Qt.darker(root.contentForeground, 1.4)
  }

  readonly property int pendingUpdateCount: {
    var n = 0
    for (var k in root.updateStates) {
      if (root.updateStates[k] === "UPDATE") n++
    }
    n
  }

  readonly property int enabledPluginCount: {
    var n = 0
    for (var i = 0; i < root.pluginRows.length; i++) if (root.pluginRows[i].enabled) n++
    n
  }

  readonly property string headerSummary: {
    var parts = []
    parts.push(root.pluginRows.length + " plugins")
    parts.push(root.enabledPluginCount + " enabled")
    if (root.pendingUpdateCount > 0)
      parts.push(root.pendingUpdateCount + " update" + (root.pendingUpdateCount > 1 ? "s" : "") + " available")
    parts.join(" · ")
  }

  readonly property int selectedRemoveCount: {
    var n = 0
    for (var k in root.removeSelection) if (root.removeSelection[k]) n++
    n
  }

  function toggleRemoveSelection(id) {
    var sel = root.removeSelection
    var next = {}
    for (var k in sel) next[k] = sel[k]
    if (next[id] === true) delete next[id]
    else next[id] = true
    root.removeSelection = next
  }

  function removePlugin(id) {
    root.removePending = [id]
    root.removeConfirmOpen = true
  }

  function removeSelected() {
    var ids = []
    for (var k in root.removeSelection) if (root.removeSelection[k]) ids.push(k)
    if (ids.length === 0) return
    root.removePending = ids
    root.removeConfirmOpen = true
  }

  function confirmRemove() {
    root.removeQueue = root.removePending.slice()
    root.removePending = []
    root.removeConfirmOpen = false
    root.removeNext()
  }

  function cancelRemove() {
    root.removePending = []
    root.removeConfirmOpen = false
  }

  function requestRestartShell() {
    root.restartConfirmOpen = true
  }

  function cancelRestartShell() {
    root.restartConfirmOpen = false
  }

  // Clear the QML compile cache and restart the shell. The shell dies as part
  // of the restart, so the whole job is detached with setsid/nohup and the
  // Process that fires it exits immediately.
  function confirmRestartShell() {
    root.restartConfirmOpen = false
    var script = 'rm -rf "$HOME/.cache/quickshell/qmlcache" "$HOME/.cache/quickshell"/qtpipelinecache-*; omarchy-restart-shell'
    restartShellProcess.command = ["bash", "-c",
      'setsid nohup bash -c "$0" >/dev/null 2>&1 &', script]
    restartShellProcess.running = true
  }

  function removeNext() {
    if (root.removeQueue.length === 0) {
      root.removingPlugin = false
      root.removeSelection = {}
      root.removeSummary = "Removed."
      Qt.callLater(function() { root.refreshPlugins() })
      return
    }
    var id = root.removeQueue.shift()
    root.removingPlugin = true
    root.removeSummary = "Removing " + id + "…"
    removeProcess.command = ["bash", "-c", "omarchy plugin remove \"$0\" --yes 2>&1 | { head -c 8192; cat >/dev/null; }; exit ${PIPESTATUS[0]}", id]
    removeProcess.running = true
  }

  function onRemoveFinished(exitCode) {
    var err = String(removeStdout.text || "").trim()
    if (exitCode !== 0) {
      root.removingPlugin = false
      root.removeQueue = []
      root.removeSummary = "Remove failed" + (err ? ": " + err : "")
      return
    }
    Qt.callLater(function() { root.removeNext() })
  }

  // Reads `git remote get-url origin` for every git-managed plugin dir and
  // fills pluginRepos (keyed by folder name) so each row can offer a repo link.
  function scanPluginRepos() {
    var reg = root.registry
    var dir = reg && reg.pluginsDir ? reg.pluginsDir : ""
    if (!dir || root.reposScanning) return
    root.reposScanning = true
    var script = ""
      + "dirs=\"$0\"\n"
      + "{ for d in \"$dirs\"/*/; do\n"
      + "  [ -d \"$d/.git\" ] || continue\n"
      + "  id=$(basename \"$d\")\n"
      + "  url=$(git -C \"$d\" remote get-url origin 2>/dev/null)\n"
      + "  [ -n \"$url\" ] && echo \"$id|$url\"\n"
      + "done; } | { head -c 8192; cat >/dev/null; }"
    repoScanProcess.command = ["bash", "-c", script, dir]
    repoScanProcess.running = true
  }

  function repoUrlFor(sourceKey) {
    return root.pluginRepos[sourceKey] || ""
  }

  function openPluginRepo(sourceKey) {
    var url = root.repoUrlFor(sourceKey)
    // Only hand http(s) URLs to the browser: a malicious plugin's git remote
    // could otherwise use file://, command:, or custom schemes via xdg-open.
    if (url && /^https?:\/\//.test(url)) Qt.openUrlExternally(url)
  }

  function openRowMenu(id, x, y) {
    root.rowMenuId = id
    root.rowMenuPos = { x: x, y: y }
    root.rowMenuOpen = true
  }

  function closeRowMenu() {
    root.rowMenuOpen = false
    root.rowMenuId = ""
  }

  function rowMenuPlugin() {
    for (var i = 0; i < root.pluginRows.length; i++)
      if (root.pluginRows[i].id === root.rowMenuId) return root.pluginRows[i]
    return null
  }

  // Fetches every git-managed plugin's remote and reports which are behind.
  // The script echoes a CHECK line before each plugin so the updates page can
  // show per-plugin progress while the fetch runs, then the result line.
  function checkUpdates() {
    var reg = root.registry
    var dir = reg && reg.pluginsDir ? reg.pluginsDir : ""
    console.log("pluginsDir=", dir)
    if (!dir || root.checkingUpdates || root.updatingId !== "") return
    root.checkingUpdates = true
    root.updateSummary = ""
    root.updateCheckLineBuf = ""
    root.updateCheckProcessed = 0
    root.checkWatchdog.restart()
    var script = ""
      + "dirs=\"$0\"\n"
      + "{ for d in \"$dirs\"/*/; do\n"
      + "  [ -d \"$d/.git\" ] || continue\n"
      + "  id=$(basename \"$d\")\n"
      + "  echo \"CHECK|$id\"\n"
      + "  if ! timeout 15 git -C \"$d\" fetch --quiet origin HEAD 2>/dev/null; then\n"
      + "    echo \"ERROR|$id\"; continue\n"
      + "  fi\n"
      + "  if [ \"$(git -C \"$d\" rev-parse HEAD)\" = \"$(git -C \"$d\" rev-parse FETCH_HEAD)\" ]; then\n"
      + "    echo \"CURRENT|$id\"\n"
      + "  else\n"
      + "    echo \"UPDATE|$id\"\n"
      + "  fi\n"
      + "done; } | { head -c 65536; cat >/dev/null; }"
    updateCheckProcess.command = ["bash", "-c", script, dir]
    updateCheckProcess.running = true
  }

  // Incremental per-line parse of the streaming check output. The collector's
  // text is cumulative, so diff from the last-processed offset and buffer the
  // tail until a newline lands. Each plugin is reported as CHECK, then
  // CURRENT/UPDATE/ERROR; updateStates updates live so the updates page's rows
  // flip as the fetch for each plugin completes.
  function applyUpdateCheckData(text) {
    var all = String(text || "")
    var fresh = all.substring(root.updateCheckProcessed)
    root.updateCheckProcessed = all.length
    root.updateCheckLineBuf += fresh
    var idx = root.updateCheckLineBuf.lastIndexOf("\n")
    if (idx < 0) return
    var ready = root.updateCheckLineBuf.substring(0, idx + 1)
    root.updateCheckLineBuf = root.updateCheckLineBuf.substring(idx + 1)
    var lines = ready.split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (line === "") continue
      var parts = line.split("|")
      if (parts.length < 2) continue
      var st = {}
      for (var k in root.updateStates) st[k] = root.updateStates[k]
      st[parts[1]] = parts[0]
      root.updateStates = st
    }
  }

  // Finalize after the stream ends: flush any unterminated tail, then compute
  // the summary from the collected per-plugin states.
  function finishUpdateCheck() {
    if (root.updateCheckLineBuf !== "") {
      var tail = root.updateCheckLineBuf.trim()
      root.updateCheckLineBuf = ""
      if (tail !== "") root.applyUpdateCheckData(tail + "\n")
    }
    root.checkWatchdog.stop()
    root.checkingUpdates = false
    var updates = 0
    var errors = 0
    for (var key in root.updateStates) {
      if (root.updateStates[key] === "UPDATE") updates++
      else if (root.updateStates[key] === "ERROR") errors++
    }
    if (updates === 0 && errors === 0)
      root.updateSummary = ""
    else if (updates === 0)
      root.updateSummary = "All plugins up to date" + (errors ? " (" + errors + " error)" : "")
    else
      root.updateSummary = updates + " update" + (updates > 1 ? "s" : "") + " available"
        + (errors ? " (" + errors + " error)" : "")
  }

  function updatePlugin(id) {
    if (root.updatingId !== "") return
    root.updatingId = id
    root.updateSummary = "Updating " + id + "…"
    updateProcess.command = ["bash", "-c", "omarchy plugin update \"$0\" --yes 2>&1 | { head -c 8192; cat >/dev/null; }; exit ${PIPESTATUS[0]}", id]
    updateProcess.running = true
  }

  function updateAll() {
    if (root.updatingId !== "" || root.checkingUpdates || root.updatingAll) return
    var pending = 0
    for (var key in root.updateStates) {
      if (root.updateStates[key] === "UPDATE") pending++
    }
    if (pending === 0) return
    root.updatingAll = true
    root.updateSummary = "Updating all " + pending + "…"
    updateAllProcess.command = ["bash", "-c", "omarchy plugin update --yes 2>&1 | { head -c 8192; cat >/dev/null; }; exit ${PIPESTATUS[0]}"]
    updateAllProcess.running = true
  }

  function onUpdateAllFinished(exitCode) {
    root.updatingAll = false
    if (exitCode === 0)
      root.updateSummary = "All updates applied"
    else {
      var err = String(updateStdout.text || "").trim()
      root.updateSummary = "Bulk update failed" + (err ? ": " + err : "")
    }
    root.refreshPlugins()
    Qt.callLater(function() { root.checkUpdates() })
  }

  function onUpdateFinished(exitCode) {
    var id = root.updatingId
    root.updatingId = ""
    if (exitCode === 0)
      root.updateSummary = "Updated " + id
    else {
      var err = String(updateStdout.text || "").trim()
      root.updateSummary = "Update of " + id + " failed" + (err ? ": " + err : "")
    }
    root.refreshPlugins()
    Qt.callLater(function() { root.checkUpdates() })
  }

  // Fetches the public marketplace catalog (capped at 2 MB like every other
  // retained output) and builds the id -> {verified} map.
  function fetchMarketplace() {
    if (root.marketplaceFetching) return
    root.marketplaceFetching = true
    marketplaceProcess.command = ["bash", "-c",
      "curl -fsSL --max-time 20 https://omarchyplugins.com/catalog.json 2>/dev/null | head -c 4194304; true"]
    marketplaceProcess.running = true
  }

  function applyMarketplaceCatalog(text) {
    root.marketplaceFetching = false
    root.marketplaceFetchedAt = String(new Date().toISOString())
    var map = {}
    try {
      var catalog = JSON.parse(String(text || "{}"))
      var plugins = catalog.plugins || []
      for (var i = 0; i < plugins.length; i++) {
        var entry = plugins[i]
        if (!entry || typeof entry.id !== "string" || !entry.id) continue
        map[entry.id] = { verified: entry.verificationStatus === "verified" }
      }
    } catch (e) {
      console.log("marketplace catalog parse failed:", e)
      return
    }
    root.marketplaceMap = map
    console.log("marketplace entries:", Object.keys(map).length)
  }

  property Process marketplaceProcess: Process {
    onExited: function(exitCode) {
      root.applyMarketplaceCatalog(marketplaceStdout.text)
    }
    stdout: StdioCollector {
      id: marketplaceStdout
      waitForEnd: true
    }
  }

  property Process repoScanProcess: Process {
    onExited: function(exitCode) {
      root.reposScanning = false
      root.applyRepoScan(repoScanStdout.text)
    }
    stdout: StdioCollector {
      id: repoScanStdout
      waitForEnd: true
    }
  }

  function applyRepoScan(text) {
    var out = String(text || "").trim()
    if (out === "") return
    var repos = {}
    var lines = out.split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (line === "") continue
      var bar = line.indexOf("|")
      if (bar < 0) continue
      var key = line.substring(0, bar)
      var url = line.substring(bar + 1).trim()
      if (key && url) repos[key] = url
    }
    root.pluginRepos = repos
  }

  property Process updateCheckProcess: Process {
    onExited: function(exitCode) {
      root.finishUpdateCheck()
    }
    stdout: StdioCollector {
      id: updateCheckStdout
      waitForEnd: false
      onTextChanged: root.applyUpdateCheckData(updateCheckStdout.text)
    }
  }

  property Process updateProcess: Process {
    onExited: function(exitCode) {
      root.onUpdateFinished(exitCode)
    }
    stdout: StdioCollector { id: updateStdout; waitForEnd: true }
  }

  property Process updateAllProcess: Process {
    onExited: function(exitCode) {
      console.log("updateAllProcess onExited exitCode=", exitCode)
      root.onUpdateAllFinished(exitCode)
    }
  }

  // Launches the detached install helper. It only needs to start the
  // setsid/nohup command and exit, so no output collection is required.
  property Process installLaunchProcess: Process {
    onExited: function(exitCode) {
    }
  }

  property Process removeProcess: Process {
    onExited: function(exitCode) {
      root.onRemoveFinished(exitCode)
    }
    stdout: StdioCollector { id: removeStdout; waitForEnd: true }
  }

  // Launches the detached shell restart. The shell dies mid-command, so the
  // work runs setsid/nohup from a short-lived Process that exits immediately.
  property Process restartShellProcess: Process {
    onExited: function(exitCode) {
    }
  }

  // Only accepts GitHub repository URLs (https or git@). Mirrors the
  // marketplace's github-repository validation and how omarchy plugin/theme
  // installs are expected to use github links (omarchy plugin add
  // https://github.com/owner/repo.git). Rejects non-GitHub hosts and any
  // whitespace (space, tab, newline) to avoid crafted markup.
  function isValidGitHubRepoUrl(url) {
    if (!url || typeof url !== "string") return false
    if (/\s/.test(url)) return false
    var u = url.replace(/[.,;!?]+$/, "")
    var httpsPat = /^https:\/\/github\.com\/[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+(?:\.git)?\/?$/
    if (httpsPat.test(u)) {
      var m = u.match(/^https:\/\/github\.com\/([A-Za-z0-9_.-]+)\/([A-Za-z0-9_.-]+)(?:\.git)?\/?$/)
      if (m) {
        var owner = m[1], repo = m[2].replace(/\.git$/, "")
        if (owner.indexOf("..") !== -1 || repo.indexOf("..") !== -1) return false
        if (!/^[A-Za-z0-9]/.test(owner) || !/^[A-Za-z0-9]/.test(repo)) return false
      }
      return true
    }
    var sshPat = /^git@github\.com:[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+(?:\.git)?\/?$/
    if (sshPat.test(u)) {
      var n = u.match(/^git@github\.com:([A-Za-z0-9_.-]+)\/([A-Za-z0-9_.-]+)(?:\.git)?\/?$/)
      if (n) {
        var o = n[1], r = n[2].replace(/\.git$/, "")
        if (o.indexOf("..") !== -1 || r.indexOf("..") !== -1) return false
        if (!/^[A-Za-z0-9]/.test(o) || !/^[A-Za-z0-9]/.test(r)) return false
      }
      return true
    }
    var sshUrlPat = /^ssh:\/\/git@github\.com\/([A-Za-z0-9_.-]+)\/([A-Za-z0-9_.-]+)(?:\.git)?\/?$/
    if (sshUrlPat.test(u)) {
      var g = u.match(/^ssh:\/\/git@github\.com\/([A-Za-z0-9_.-]+)\/([A-Za-z0-9_.-]+)(?:\.git)?\/?$/)
      if (g) {
        var go = g[1], gr = g[2].replace(/\.git$/, "")
        if (go.indexOf("..") !== -1 || gr.indexOf("..") !== -1) return false
        if (!/^[A-Za-z0-9]/.test(go) || !/^[A-Za-z0-9]/.test(gr)) return false
      }
      return true
    }
    return false
  }

  // Accepts either a bare GitHub URL or a full `omarchy plugin add <url>`
  // command. Returns the validated GitHub URL, or "" if none found or not GitHub.
  function extractInstallUrl(text) {
    var t = String(text || "").trim()
    if (t === "") return ""
    function isValid(tok) {
      tok = tok.replace(/[.,;!?]+$/, "")
      return isValidGitHubRepoUrl(tok)
    }
    if (!/\s/.test(t)) {
      return isValid(t) ? t.replace(/[.,;!?]+$/, "") : ""
    }
    var tokens = t.split(/\s+/)
    for (var i = 0; i < tokens.length; i++) {
      var tok = tokens[i].replace(/[.,;!?]+$/, "")
      if (isValid(tok)) return tok
    }
    return ""
  }

  // `--enable` in a pasted command is honored: the plugin is enabled after
  // install, matching `omarchy plugin add <url> --enable`.
  function installCommandHasEnable(text) {
    return /\s--enable\b/.test(" " + String(text || "").trim())
  }

  // Called from the install dialog: extract the URL and ask for
  // confirmation. Only GitHub URLs are accepted (https://github.com/owner/repo
  // or git@github.com:owner/repo.git), matching omarchy plugin/theme
  // expectations and preventing arbitrary host installs. The plugin is
  // installed but NOT enabled by default.
  function requestInstall() {
    var raw = String(installUrlField.text || "").trim()
    if (raw === "") return
    var url = root.extractInstallUrl(raw)
    if (url === "") {
      root.installResult = "Please enter a valid GitHub repository URL (https://github.com/owner/repo or git@github.com:owner/repo.git)"
      root.installFailed = true
      return
    }
    root.installFailed = false
    root.installResult = ""
    root.installPendingUrl = url
    root.installConfirmOpen = true
  }

  function installPlugin() {
    var url = root.installPendingUrl
    if (url === "") return
    root.installConfirmOpen = false
    root.installRunning = true
    root.installFailed = false
    root.installResult = "Installing " + url + "…"
    root.startDetachedInstall(url)
  }

  // Launch the detached helper. `omarchy plugin add` reloads plugins when it
  // finishes, which unloads this panel; the helper is started with
  // setsid/nohup so it survives and finishes the enable itself.
  // The status file is created securely via mktemp to avoid predictable /tmp
  // symlink races (the helper truncates it, so creation must be exclusive).
  property string _installPendingUrl: ""
  property Process installStatusMktmpProcess: Process {
    stdout: StdioCollector {
      id: installMktmpStdout
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.installWatchdog.stop()
        root.installDetachedRunning = false
        root.installRunning = false
        root.installFailed = true
        root.installResult = "Could not create secure status file"
        return
      }
      var p = String(installMktmpStdout.text || "").trim()
      if (p === "" || p.indexOf("/") !== 0) {
        root.installWatchdog.stop()
        root.installDetachedRunning = false
        root.installRunning = false
        root.installFailed = true
        root.installResult = "Could not create secure status file"
        return
      }
      root.installStatusPath = p
      installStatusFile.path = p
      // Directly run omarchy plugin add in a detached shell; no helper script.
      // The plugin is installed but not enabled (user enables manually).
      var launch = ["bash", "-c",
        "setsid nohup bash -c '"
        + "STATUS=\"$2\"; URL=\"$1\"; "
        + "if [ -L \"$STATUS\" ]; then echo \"Refusing symlink\" >&2; exit 1; fi; "
        + "umask 077; chmod 600 \"$STATUS\" 2>/dev/null || true; "
        + "printf \"installing\\n\" >> \"$STATUS\"; "
        + "TMP_OUT=$(mktemp); "
        + "omarchy plugin add \"$URL\" --yes 2>&1 | { head -c 8000 >\"$TMP_OUT\"; cat >/dev/null; }; rc=${PIPESTATUS[0]}; "
        + "out=$(cat \"$TMP_OUT\"); rm -f \"$TMP_OUT\"; "
        // Reserve marker headroom below the 8192 ceiling: 11B header + 8001B
        // output + <=105B id line + <=16B terminal markers always fit in the
        // consumer's first-8192-char inspection window, so a chatty installer
        // can never push install_failed/done out of view.
        + "printf \"%.8000s\\n\" \"$out\" >> \"$STATUS\"; "
        + "head -c 8192 \"$STATUS\" > \"$STATUS.tmp\" 2>/dev/null && mv \"$STATUS.tmp\" \"$STATUS\" 2>/dev/null || true; "
        + "id=\"\"; "
        + "if [ $rc -eq 0 ]; then id=$(printf \"%s\\n\" \"$out\" | sed -n \"s/.*Added \\([^ ]*\\) into.*/\\1/p\"); fi; "
        + "id=${id:0:100}; "
        + "if [ -n \"$id\" ]; then printf \"id=%s\\n\" \"$id\" >> \"$STATUS\"; fi; "
        // done must ALWAYS be the last marker (including on failure): the
        // consumer finalizes only on done, so a bare install_failed would
        // leave the dialog stuck on "Installing…" forever.
        + "if [ $rc -ne 0 ]; then printf \"install_failed\\n\" >> \"$STATUS\"; fi; "
        + "printf \"done\\n\" >> \"$STATUS\"; "
        + "if [ $rc -ne 0 ]; then exit 1; fi; "
        + "' -- \"$0\" \"$1\" >/dev/null 2>&1 &",
        root._installPendingUrl, p]
      installLaunchProcess.command = launch
      installLaunchProcess.running = true
    }
  }

  function startDetachedInstall(url) {
    root._installPendingUrl = url
    root.installDetachedRunning = true
    root.installResult = "Installing " + url + "…"
    root.installWatchdog.restart()
    installStatusMktmpProcess.command = ["bash", "-c", 'umask 077; mktemp "${XDG_RUNTIME_DIR:-/tmp}/omaplug-install-XXXXXX.status" 2>/dev/null || mktemp /tmp/omaplug-install-XXXXXX.status']
    installStatusMktmpProcess.running = true
  }

  function cancelInstallConfirm() {
    root.installPendingUrl = ""
    root.installConfirmOpen = false
  }

  // Poll the detached helper's status file. The helper survives the plugin
  // reload that `omarchy plugin add` triggers (which unloads this panel), so
  // we watch its progress here and refresh when it finishes.
  FileView {
    id: installStatusFile
    path: root.installStatusPath
    watchChanges: true
    printErrors: false
    onLoaded: root.onInstallStatusUpdate()
    onFileChanged: root.onInstallStatusUpdate()
  }

  function onInstallStatusUpdate() {
    if (!root.installDetachedRunning) return
    if (root.installStatusPath === "") return
    var text = ""
    try { text = installStatusFile.text() } catch (e) { return }
    if (text === "") return
    // Enforce strict ceiling: remote output can be attacker-controlled.
    // Truncate to 8192 bytes / 200 lines before allocation in long-lived shell.
    if (text.length > 8192) {
      text = text.substring(0, 8192)
      // Mark as failed if truncated due to excessive output
      if (text.indexOf("install_failed") === -1 && text.indexOf("done") === -1) {
        root.installWatchdog.stop()
        root.installDetachedRunning = false
        root.installRunning = false
        root.installFailed = true
        root.installResult = "Install output too large"
        root.installStatusPath = ""
        return
      }
    }
    var lines = String(text).split("\n")
    if (lines.length > 200) lines = lines.slice(0, 200)
    var id = ""
    var done = false
    var failed = false
    var enabled = false
    var installing = false
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (line.indexOf("id=") === 0) id = line.substring(3)
      else if (line === "installing") installing = true
      else if (line === "done") done = true
      else if (line === "install_failed" || line === "enable_failed") failed = true
      else if (line === "enabled") enabled = true
      else if (line === "install_ok_no_id") { done = true; failed = true }
    }
    if (installing && !done) {
      root.installRunning = true
      root.installResult = "Installing…"
      return
    }
    if (done) {
      root.installWatchdog.stop()
      root.installDetachedRunning = false
      root.installRunning = false
      root.installStatusPath = ""
      if (failed) {
        root.installFailed = true
        root.installResult = "Install failed"
      } else {
        root.installResult = "Installed. Review the code, then enable it in the list."
      }
      root.refreshPlugins()
    }
  }

  function refreshPlugins() {
    var reg = root.registry
    if (!reg || !reg.installedPlugins) {
      pluginRows = []
      return
    }
    var rows = []
    var pdir = (reg.pluginsDir || "").replace(/\/+$/, "") + "/"
    for (var id in reg.installedPlugins) {
      var m = reg.installedPlugins[id]
      if (!m || typeof m !== "object") continue
      var sourceDir = String(m.__sourceDir || "")
      rows.push({
        id: id,
        name: m.name || id,
        version: m.version || "unknown",
        author: m.author || "",
        description: m.description || "",
        kinds: (m.kinds || []).join(", "),
        enabled: reg.isEnabled(id) === true,
        firstParty: m.__isFirstParty === true,
        sourceDir: sourceDir,
        sourceKey: sourceDir.replace(/\/+$/, "").split("/").pop() || "",
        updatable: sourceDir.indexOf(pdir) === 0
      })
    }
    rows.sort(function(a, b) {
      var ka = a.firstParty ? 0 : 1
      var kb = b.firstParty ? 0 : 1
      if (ka !== kb) return ka - kb
      return String(a.name).localeCompare(String(b.name))
    })
    pluginRows = rows
    root.scanPluginRepos()
  }

  function setPluginEnabled(id, value) {
    var reg = root.registry
    if (!reg || typeof reg.setEnabled !== "function") return
    reg.setEnabled(id, value)
  }

  function registryRevision() {
    var reg = root.registry
    return reg ? reg.registryRevision : 0
  }

  Connections {
    target: root.registry
    function onRegistryRevisionChanged() {
      root.invalidateGlyphCache()
      root.refreshPlugins()
    }
  }

  Component.onCompleted: {
    console.log("Panel.qml loaded, filterMode=", root.filterMode, "rows=", root.pluginRows.length)
    refreshPlugins()
    fetchMarketplace()
  }

  // ------------------------------------------------------------- open / close

  function open() {
    refreshPlugins()
    // Refresh marketplace badges at most once per open when data is stale.
    if (!root.marketplaceFetching && Object.keys(root.marketplaceMap).length === 0) fetchMarketplace()
    root.controller.show()
    Qt.callLater(function() {
      if (root.opened) root.primeFocus()
    })
  }

  function close() {
    root.installDialogOpen = false
    root.updatesPageOpen = false
    root.removeConfirmOpen = false
    root.restartConfirmOpen = false
    root.removeSelectMode = false
    root.removeSelection = {}
    root.closeRowMenu()
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // Keyboard focus lands in the search field so the panel can be typed into
  // the moment it opens. A retry covers the brief window where the layer
  // negotiates focus before the field can grab it.
  function primeFocus() {
    if (searchField) searchField.forceActiveFocus()
    focusRetry.restart()
  }

  Timer {
    id: focusRetry
    interval: 120
    repeat: false
    onTriggered: {
      if (root.opened && searchField) searchField.forceActiveFocus()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(560))
    contentHeight: panel.fittedContentHeight(Math.round(Style.space(560)))

    // ------------------------------------------------------------------- content

    // Persistent app header: sits above every page (main, updates, remove).
    Rectangle {
      id: appHeader
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      height: appHeaderColumn.implicitHeight + Style.space(16)
      z: 6000
      color: root.panelBackground

      ColumnLayout {
        id: appHeaderColumn
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: Style.space(8)
        anchors.leftMargin: Style.space(16)
        anchors.rightMargin: Style.space(16)
        anchors.bottomMargin: Style.space(8)
        spacing: Style.space(2)

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(14)

          Text {
            id: appHeaderIcon
            Layout.preferredWidth: Style.space(44)
            Layout.preferredHeight: Style.space(44)
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: root.iconFor("omaplug") || "\udb85\udcd9"
            color: Style.selectedStateColor(root.contentForeground, Color.accent)
            font.family: root.contentFontFamily
            font.pixelSize: Style.space(34)
            font.bold: true
          }

          ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: Style.space(2)

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.space(8)

              Label {
                text: "OMAPLUG"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.title * 1.6
                font.bold: true
                Layout.fillWidth: true
              }

              Button {
                id: marketplaceButton
                text: "\udb86\ude6f  Marketplace"
                tooltipText: "Open the Omarchy plugin marketplace"
                bordered: true
                foreground: root.contentForeground
                accent: Color.accent
                fontFamily: root.contentFontFamily
                fontSize: Style.font.caption
                horizontalPadding: Style.space(8)
                verticalPadding: Style.space(3)
                Layout.alignment: Qt.AlignVCenter
                onClicked: Qt.openUrlExternally("https://omarchyplugins.com")
              }

              Button {
                id: restartShellButton
                text: "\uf021  Restart shell"
                tooltipText: "Clear the QML cache and restart the shell so every plugin reloads from source"
                bordered: true
                foreground: root.contentForeground
                accent: Color.accent
                fontFamily: root.contentFontFamily
                fontSize: Style.font.caption
                horizontalPadding: Style.space(8)
                verticalPadding: Style.space(3)
                Layout.alignment: Qt.AlignVCenter
                onClicked: root.requestRestartShell()
              }
            }

            Label {
              text: root.headerSummary
              textFormat: Text.PlainText
              color: Qt.darker(root.contentForeground, 1.5)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              Layout.fillWidth: true
            }
          }
        }
      }
    }

    Item {
      id: panelContent
      anchors.fill: parent
      clip: true
      anchors.topMargin: appHeader.height

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        onClicked: {} // swallow
      }

      PanelKeyCatcher {
        id: keyCatcher
        anchors.fill: parent
        blocked: searchField.activeFocus || filterDropdown.popupOpen
        onCloseRequested: root.close()
        onTabRequested: function(direction) { root.switchPanel(direction) }
      }

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.space(16)
        spacing: Style.space(10)

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          Label {
            text: "Installed Plugins"
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            Layout.fillWidth: true
          }

          Button {
            iconText: "\uf021"
            tooltipText: "Check updates"
            enabled: !root.checkingUpdates && root.updatingId === "" && !root.updatingAll
            foreground: root.contentForeground
            accent: Color.accent
            fontFamily: root.contentFontFamily
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.space(10)
            verticalPadding: Style.space(5)
            onClicked: {
              root.updatesPageOpen = true
              updatesPageLoader.stayLoaded = true
              if (!root.checkingUpdates) root.checkUpdates()
            }
          }

          Button {
            iconText: "\uf0ed"
            tooltipText: "Install plugin"
            foreground: root.contentForeground
            accent: Color.accent
            fontFamily: root.contentFontFamily
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.space(10)
            verticalPadding: Style.space(5)
            onClicked: root.installDialogOpen = true
          }

          Button {
            text: root.removeSelectMode ? "Done" : "Select"
            tooltipText: "Select plugins to remove"
            enabled: !root.removingPlugin
            foreground: root.contentForeground
            accent: Color.accent
            fontFamily: root.contentFontFamily
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.space(10)
            verticalPadding: Style.space(5)
            onClicked: {
              root.removeSelectMode = !root.removeSelectMode
              if (!root.removeSelectMode) root.removeSelection = {}
            }
          }
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(6)

          Dropdown {
            id: filterDropdown
            Layout.preferredWidth: Style.space(140)
            showLabel: false
            value: String(root.filterMode)
            options: [
              { value: "0", label: "All plugins" },
              { value: "1", label: "Omarchy" },
              { value: "2", label: "Third-party" }
            ]
            foreground: root.contentForeground
            background: root.panelBackground
            popupBorder: Util.alpha(root.contentForeground, 0.2)
            accent: Color.accent
            fontFamily: root.contentFontFamily
            onChanged: function(v) { root.filterMode = parseInt(v) }
          }

          Dropdown {
            id: kindDropdown
            Layout.preferredWidth: Style.space(130)
            showLabel: false
            value: root.filterKind
            options: root.kindOptions
            foreground: root.contentForeground
            background: root.panelBackground
            popupBorder: Util.alpha(root.contentForeground, 0.2)
            accent: Color.accent
            fontFamily: root.contentFontFamily
            onChanged: function(v) { root.filterKind = v }
          }

          TextField {
            id: searchField
            Layout.fillWidth: true
            placeholderText: "Search plugins…"
            foreground: root.contentForeground
            accent: Color.accent
            font.family: root.contentFontFamily
            text: root.searchText
            onTextChanged: root.searchText = text
            Keys.onEscapePressed: { root.close() }
          }
        }

        ListView {
          id: pluginList
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          spacing: Style.space(4)
          model: root.visibleRows
          ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
            implicitWidth: Style.space(6)
            contentItem: Rectangle {
              implicitWidth: Style.space(6)
              implicitHeight: Style.space(6)
              radius: width / 2
              color: Util.alpha(root.contentForeground, 0.45)
            }
          }

          delegate: Rectangle {
            id: pluginRowDelegate
            required property var modelData
            readonly property bool mFirstParty: modelData.firstParty === true
            readonly property var mEntry: mFirstParty ? null : (root.marketplaceMap[String(modelData.id)] || null)
            readonly property bool mListed: mEntry !== null
            readonly property bool mVerified: mListed && mEntry.verified === true
            width: pluginList.width
            height: Math.max(Style.space(56), row.implicitHeight + Style.space(18))
            radius: Style.cornerRadius > 0 ? Style.cornerRadius : 4
            color: hover.hovered
              ? Style.hoverFillFor(root.contentForeground, Color.accent)
              : "transparent"

            RowLayout {
              id: row
              anchors.fill: parent
              anchors.leftMargin: Style.space(10)
              anchors.topMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              anchors.bottomMargin: Style.space(16)
              spacing: Style.space(10)

              Button {
                visible: root.removeSelectMode
                text: root.removeSelection[modelData.id] === true ? "\uf14a" : "\uf0c8"
                tooltipText: "Select plugin for removal"
                enabled: !root.removingPlugin
                Layout.alignment: Qt.AlignVCenter
                foreground: root.contentForeground
                accent: Color.accent
                fontFamily: root.contentFontFamily
                fontSize: Style.font.bodySmall
                horizontalPadding: Style.space(6)
                verticalPadding: Style.space(3)
                onClicked: root.toggleRemoveSelection(modelData.id)
              }

              Rectangle {
                id: pluginIcon
                width: Style.space(28)
                height: width
                radius: 6
                color: root.iconColorFor(modelData.name)

                Text {
                  anchors.centerIn: parent
                  text: root.iconFor(modelData.id) || modelData.name.trim().charAt(0).toUpperCase()
                  textFormat: Text.PlainText
                  color: "white"
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }
              }

              ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: Style.space(2)

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(8)

                  Label {
                    id: pluginNameLabel
                    text: modelData.name
                    textFormat: Text.PlainText
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                    Layout.maximumWidth: (pluginList.width - Style.space(160)) * 0.7
                    elide: Label.ElideRight
                  }

                  Rectangle {
                    id: marketplaceBadge
                    visible: pluginRowDelegate.mListed
                    radius: height / 2
                    implicitWidth: badgeRow.implicitWidth + Style.space(10)
                    implicitHeight: Style.space(16)
                    color: pluginRowDelegate.mVerified
                      ? Util.alpha(Color.accent, 0.18)
                      : Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.08)

                    Row {
                      id: badgeRow
                      anchors.centerIn: parent
                      spacing: Style.space(3)

                      Text {
                        visible: pluginRowDelegate.mVerified
                        text: "\uf058"
                        textFormat: Text.PlainText
                        color: Color.accent
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.caption - 1
                        anchors.verticalCenter: parent.verticalCenter
                      }

                      Text {
                        text: pluginRowDelegate.mVerified
                          ? "Verified"
                          : "Unverified"
                        textFormat: Text.PlainText
                        color: pluginRowDelegate.mVerified
                          ? Color.accent
                          : Qt.darker(root.contentForeground, 2.0)
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.caption - 1
                        anchors.verticalCenter: parent.verticalCenter
                      }
                    }
                  }
                }

                Label {
                  text: modelData.description !== "" ? modelData.description : "No description"
                  textFormat: Text.PlainText
                  color: Qt.darker(root.contentForeground, 1.6)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  Layout.fillWidth: true
                  wrapMode: Label.Wrap
                  maximumLineCount: 3
                  elide: Label.ElideRight
                }


                RowLayout {
                  spacing: Style.space(4)
                  Layout.fillWidth: true

                  Label {
                    visible: modelData.version !== "unknown"
                    text: "v" + modelData.version
                    textFormat: Text.PlainText
                    color: Qt.darker(root.contentForeground, 2.0)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Label {
                    visible: modelData.author !== ""
                    text: "by " + modelData.author
                    textFormat: Text.PlainText
                    color: modelData.firstParty
                      ? Style.selectedStateColor(root.contentForeground, Color.accent)
                      : Qt.darker(root.contentForeground, 2.0)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Label {
                    visible: modelData.kinds !== ""
                    text: "· " + modelData.kinds
                    textFormat: Text.PlainText
                    color: Qt.darker(root.contentForeground, 2.0)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    Layout.fillWidth: true
                    elide: Label.ElideRight
                  }

                }

                // Marketplace listing link on its own line under the
                // version / author / kind row.
                Text {
                  visible: pluginRowDelegate.mListed
                  text: "View on marketplace ↗"
                  textFormat: Text.PlainText
                  color: Color.accent
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  font.underline: marketLinkHover.hovered

                  HoverHandler {
                    id: marketLinkHover
                    cursorShape: Qt.PointingHandCursor
                  }

                  MouseArea {
                    id: marketLinkClick
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openMarketplacePage(modelData.id)
                  }
                }
              }

              ColumnLayout {
                Layout.alignment: Qt.AlignVCenter
                spacing: Style.space(4)

                RowLayout {
                  Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                  spacing: Style.space(6)

                  Button {
                    visible: modelData.updatable
                      && root.pluginRepos[modelData.sourceKey] !== undefined
                    tooltipText: "Open plugin repository"
                    text: "SOURCE \udb85\udd94"
                    bordered: true
                    foreground: root.contentForeground
                    accent: Color.accent
                    fontFamily: root.contentFontFamily
                    fontSize: Style.font.caption
                    iconSize: Style.font.caption
                    horizontalPadding: Style.space(6)
                    verticalPadding: Style.space(3)
                    Layout.alignment: Qt.AlignVCenter
                    onClicked: root.openPluginRepo(modelData.sourceKey)
                  }

                  Button {
                    visible: modelData.updatable
                      && root.updateStates[modelData.sourceKey] === "UPDATE"
                    text: root.updatingId === modelData.id ? "Updating…" : "Update"
                    enabled: root.updatingId === "" && !root.updatingAll
                    bordered: true
                    foreground: root.contentForeground
                    accent: Color.accent
                    fontFamily: root.contentFontFamily
                    fontSize: Style.font.caption
                    horizontalPadding: Style.space(8)
                    verticalPadding: Style.space(3)
                    Layout.alignment: Qt.AlignVCenter
                    onClicked: root.updatePlugin(modelData.id)
                  }

                  ToggleSwitch {
                    id: toggle
                    rounded: true
                    checked: modelData.enabled
                    Layout.alignment: Qt.AlignVCenter
                    foreground: root.contentForeground
                    accent: Color.accent
                    onToggled: {
                      Qt.callLater(function() { root.setPluginEnabled(modelData.id, !modelData.enabled) })
                    }
                  }

                  Button {
                    id: rowMenuButton
                    iconText: "\uf142"
                    tooltipText: "More actions"
                    visible: !modelData.firstParty
                    bordered: true
                    foreground: root.contentForeground
                    accent: Color.accent
                    fontFamily: root.contentFontFamily
                    fontSize: Style.font.bodySmall
                    horizontalPadding: Style.space(6)
                    verticalPadding: Style.space(3)
                    Layout.alignment: Qt.AlignVCenter
                    onClicked: {
                      var btn = rowMenuButton
                      var pt = btn.mapToItem(rowMenuOverlay, 0, btn.height)
                      root.openRowMenu(modelData.id, pt.x, pt.y)
                    }
                  }
                }
              }
            }

            // Row hover background: a HoverHandler (not a MouseArea) so the row
            // highlight never swallows hover from the toggle/update buttons —
            // otherwise their cursor shape and hover visuals wouldn't work.
            HoverHandler {
              id: hover
            }

            // Right-click opens a context menu with enable/disable, source, remove.
            TapHandler {
              id: rowContextTap
              acceptedButtons: Qt.RightButton
              onTapped: function(event) {
                var pt = rowContextTap.mapToItem(rowMenuOverlay, event.point.position.x, event.point.position.y)
                root.openRowMenu(modelData.id, pt.x, pt.y)
              }
            }

            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              height: 1
              color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)
            }
          }
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          Label {
            visible: root.updateSummary !== ""
            text: root.updateSummary
            textFormat: Text.PlainText
            color: Style.selectedStateColor(root.contentForeground, Color.accent)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Label {
            visible: root.removeSummary !== ""
            text: root.removeSummary
            textFormat: Text.PlainText
            color: Style.selectedStateColor(root.contentForeground, Color.accent)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Item {
            Layout.fillWidth: true
          }

          Button {
            visible: root.removeSelectMode && root.selectedRemoveCount > 0
            text: "Remove selected (" + root.selectedRemoveCount + ")"
            enabled: !root.removingPlugin
            foreground: root.contentForeground
            accent: Color.urgent
            fontFamily: root.contentFontFamily
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.space(12)
            verticalPadding: Style.space(6)
            onClicked: root.removeSelected()
          }
        }
      }
    }
    // Full-page view shown when the user asks to check for updates. Lists the
    // git-managed plugins with live per-plugin status (streamed from the check
    // process), a running progress bar while checking, and an Update all button
    // pinned to the bottom.
    Rectangle {
      id: updatesPage
      visible: root.updatesPageOpen
      anchors.fill: parent
      z: 5000
      color: root.panelBackground

      // Contents are heavy (full second list). Instantiate lazily the first
      // time the user opens this page; afterwards they stay alive.
      Loader {
        id: updatesPageLoader
        anchors.fill: parent
        // stayLoaded keeps contents alive after first open
        property bool stayLoaded: false
        active: root.updatesPageOpen || stayLoaded
        sourceComponent: updatesPageComponent
      }

      Component {
        id: updatesPageComponent
        Item {
          anchors.fill: parent

      PanelKeyCatcher {
        anchors.fill: parent
        onCloseRequested: root.updatesPageOpen = false
        onTabRequested: function(direction) { root.switchPanel(direction) }
      }

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.space(16)
        anchors.topMargin: appHeader.height + Style.space(16)
        spacing: Style.space(10)

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          Label {
            text: "Check for updates"
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            Layout.fillWidth: true
          }

          Button {
            text: "Back"
            foreground: root.contentForeground
            accent: Color.accent
            fontFamily: root.contentFontFamily
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.space(10)
            verticalPadding: Style.space(5)
            onClicked: root.updatesPageOpen = false
          }
        }

        Rectangle {
          id: checkProgress
          visible: root.checkingUpdates
          Layout.fillWidth: true
          Layout.preferredHeight: 3
          radius: 1.5
          color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.15)
          clip: true

          Rectangle {
            id: checkProgressChunk
            width: checkProgress.width * 0.4
            height: checkProgress.height
            radius: checkProgress.radius
            color: Style.selectedStateColor(root.contentForeground, Color.accent)

            NumberAnimation on x {
              running: root.checkingUpdates
              loops: Animation.Infinite
              from: -width
              to: checkProgress.width
              duration: 1100
              easing.type: Easing.InOutQuad
            }
          }
        }

        ListView {
          id: updateList
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          spacing: Style.space(4)
          model: root.updateCheckRows
          ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
            implicitWidth: Style.space(6)
            contentItem: Rectangle {
              implicitWidth: Style.space(6)
              implicitHeight: Style.space(6)
              radius: width / 2
              color: Util.alpha(root.contentForeground, 0.45)
            }
          }

          delegate: Rectangle {
            required property var modelData
            width: updateList.width
            height: Math.max(Style.space(52), row.implicitHeight + Style.space(16))
            radius: Style.cornerRadius > 0 ? Style.cornerRadius : 4
            color: hover.hovered
              ? Style.hoverFillFor(root.contentForeground, Color.accent)
              : "transparent"

            RowLayout {
              id: row
              anchors.fill: parent
              anchors.leftMargin: Style.space(10)
              anchors.topMargin: Style.space(8)
              anchors.rightMargin: Style.space(10)
              anchors.bottomMargin: Style.space(12)
              spacing: Style.space(10)

              Rectangle {
                id: updateIcon
                width: Style.space(28)
                height: width
                radius: 6
                color: root.iconColorFor(modelData.name)

                Text {
                  anchors.centerIn: parent
                  text: root.iconFor(modelData.id) || modelData.name.trim().charAt(0).toUpperCase()
                  textFormat: Text.PlainText
                  color: "white"
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }
              }

              ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: Style.space(2)

                Label {
                  text: modelData.name
                  textFormat: Text.PlainText
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  Layout.fillWidth: true
                  elide: Label.ElideRight
                }

                Label {
                  text: root.updateStatusText(modelData.sourceKey)
                  textFormat: Text.PlainText
                  color: root.updateStatusColor(modelData.sourceKey)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              // Per-plugin check status: a ring spinner while the fetch for this
              // plugin is still running, a check icon once it finished (whether
              // current, update available, or errored).
              Item {
                id: checkRing
                visible: root.updateStates[modelData.sourceKey] === "CHECK"
                  || root.updateStates[modelData.sourceKey] === undefined
                Layout.alignment: Qt.AlignVCenter
                width: Style.space(18)
                height: Style.space(18)

                Rectangle {
                  anchors.fill: parent
                  radius: width / 2
                  color: "transparent"
                  border.width: 2
                  border.color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.18)
                }

                Item {
                  id: checkRingArc
                  anchors.fill: parent
                  visible: root.updateStates[modelData.sourceKey] === "CHECK"
                    || root.updateStates[modelData.sourceKey] === undefined

                  RotationAnimation on rotation {
                    running: checkRingArc.visible
                    loops: Animation.Infinite
                    from: 0
                    to: 360
                    duration: 900
                  }

                  Canvas {
                    anchors.fill: parent
                    onPaint: {
                      var ctx = getContext("2d")
                      ctx.reset()
                      ctx.strokeStyle = Style.selectedStateColor(root.contentForeground, Color.accent)
                      ctx.lineWidth = 2
                      ctx.lineCap = "round"
                      var r = width / 2 - 2
                      ctx.beginPath()
                      ctx.arc(width / 2, height / 2, r, -Math.PI / 2, Math.PI / 3, false)
                      ctx.stroke()
                    }
                  }
                }
              }

              Label {
                visible: {
                  var st = root.updateStates[modelData.sourceKey]
                  st === "CURRENT" || st === "UPDATE" || st === "ERROR"
                }
                Layout.alignment: Qt.AlignVCenter
                text: "\uf00c"
                color: {
                  var st = root.updateStates[modelData.sourceKey]
                  if (st === "ERROR") return Color.urgent
                  return Style.selectedStateColor(root.contentForeground, Color.accent)
                }
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
              }
            }

            HoverHandler {
              id: hover
            }

            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              height: 1
              color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)
            }
          }
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          Label {
            text: root.pendingUpdateCount > 0
              ? root.pendingUpdateCount + " update" + (root.pendingUpdateCount > 1 ? "s" : "") + " available"
              : (root.checkingUpdates ? "Checking…" : "No updates available")
            color: Qt.darker(root.contentForeground, 1.5)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Label {
            visible: root.updateSummary !== ""
            text: root.updateSummary
            textFormat: Text.PlainText
            color: Style.selectedStateColor(root.contentForeground, Color.accent)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Item {
            Layout.fillWidth: true
          }

          Button {
            text: root.updatingAll ? "Updating all…" : "Update all"
            enabled: root.pendingUpdateCount > 0
              && !root.checkingUpdates && root.updatingId === "" && !root.updatingAll
            visible: root.pendingUpdateCount > 0
            foreground: root.contentForeground
            accent: Color.accent
            fontFamily: root.contentFontFamily
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.space(12)
            verticalPadding: Style.space(6)
            onClicked: root.updateAll()
          }
        }
      }
        }
      }
    }


    // ── Row context menu ─────────────────────────────────────────────────────
    // Right-click on a plugin row on the main page opens a small menu with the
    // same actions the row buttons offer: enable/disable, open the source repo
    // (when known), and remove. Implemented as an overlay Rectangle (matching
    // the other dialogs) instead of a QQC Popup.
    Rectangle {
      id: rowMenuOverlay
      visible: root.rowMenuOpen
      anchors.fill: parent
      z: 12000
      color: "transparent"
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onEscapePressed: root.closeRowMenu()

      MouseArea {
        anchors.fill: parent
        onClicked: root.closeRowMenu()
      }

      Rectangle {
        id: rowMenu
        x: Math.min(root.rowMenuPos.x, parent.width - width - Style.space(4))
        y: Math.min(root.rowMenuPos.y, parent.height - height - Style.space(4))
        width: rowMenuColumn.implicitWidth + Style.space(8)
        height: rowMenuColumn.implicitHeight + Style.space(8)
        color: root.panelBackground
        radius: Style.cornerRadius
        border.color: Util.alpha(root.contentForeground, 0.2)
        border.width: 1

        ColumnLayout {
          id: rowMenuColumn
          anchors.fill: parent
          anchors.margins: Style.space(4)
          spacing: Style.space(2)
          implicitWidth: Style.space(180)

          property var plugin: root.rowMenuPlugin()

          Button {
            text: rowMenuColumn.plugin && rowMenuColumn.plugin.enabled ? "Disable" : "Enable"
            foreground: root.contentForeground
            accent: Color.accent
            fontFamily: root.contentFontFamily
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.space(8)
            verticalPadding: Style.space(5)
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignLeft
            onClicked: {
              root.setPluginEnabled(root.rowMenuId, !rowMenuColumn.plugin.enabled)
              root.closeRowMenu()
            }
          }

          Button {
            visible: rowMenuColumn.plugin && rowMenuColumn.plugin.sourceKey !== "" && root.pluginRepos[rowMenuColumn.plugin.sourceKey] !== undefined
            text: "Source"
            foreground: root.contentForeground
            accent: Color.accent
            fontFamily: root.contentFontFamily
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.space(8)
            verticalPadding: Style.space(5)
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignLeft
            onClicked: {
              root.openPluginRepo(rowMenuColumn.plugin.sourceKey)
              root.closeRowMenu()
            }
          }

          Button {
            visible: rowMenuColumn.plugin && !rowMenuColumn.plugin.firstParty
            text: "Remove"
            foreground: Color.urgent
            accent: Color.urgent
            fontFamily: root.contentFontFamily
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.space(8)
            verticalPadding: Style.space(5)
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignLeft
            onClicked: {
              var id = root.rowMenuId
              root.closeRowMenu()
              root.removePlugin(id)
            }
          }
        }
      }
    }

    // Confirmation before any plugin removal. Shows what is about to be deleted
    // (single plugin or a multi-selection count) with a Remove / Cancel choice.
    Rectangle {
      id: removeConfirmDialog
      visible: root.removeConfirmOpen
      anchors.fill: parent
      z: 7000
      color: Util.alpha(root.panelBackground, 0.7)
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onEscapePressed: {
        if (!root.removingPlugin) root.removeConfirmOpen = false
      }

      MouseArea {
        anchors.fill: parent
        onClicked: {
          if (!root.removingPlugin) root.removeConfirmOpen = false
        }
      }

      Rectangle {
        id: removeConfirmCard
        anchors.centerIn: parent
        width: Math.min(parent.width - Style.space(32), Style.space(360))
        height: removeConfirmColumn.implicitHeight + Style.space(36)
        color: root.panelBackground
        radius: Style.cornerRadius
        border.color: Color.urgent
        border.width: 1

        ColumnLayout {
          id: removeConfirmColumn
          anchors.fill: parent
          anchors.margins: Style.space(18)
          spacing: Style.space(12)

          Text {
            text: root.removePending.length > 1
              ? "Remove " + root.removePending.length + " plugins?"
              : "Remove this plugin?"
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
          }

          Text {
            text: root.removePending.length > 1
              ? "The selected plugins will be deleted from your config. This cannot be undone."
              : "\"" + (root.removePending.length === 1 ? root.removePending[0] : "") + "\" will be deleted from your config. This cannot be undone."
            textFormat: Text.PlainText
            color: Qt.darker(root.contentForeground, 1.6)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
          }

          RowLayout {
            Layout.fillWidth: true

            Item { Layout.fillWidth: true }

            Button {
              text: "Cancel"
              foreground: root.contentForeground
              accent: Color.accent
              fontFamily: root.contentFontFamily
              fontSize: Style.font.bodySmall
              horizontalPadding: Style.space(12)
              verticalPadding: Style.space(6)
              onClicked: root.cancelRemove()
            }

            Button {
              text: "Remove"
              bordered: true
              foreground: Color.urgent
              accent: Color.urgent
              fontFamily: root.contentFontFamily
              fontSize: Style.font.bodySmall
              horizontalPadding: Style.space(12)
              verticalPadding: Style.space(6)
              onClicked: root.confirmRemove()
            }
          }
        }
      }
    }

    // Confirmation before restarting the shell. Warns that the shell (and this
    // panel) will briefly disappear while plugins reload from source.
    Rectangle {
      id: restartConfirmDialog
      visible: root.restartConfirmOpen
      anchors.fill: parent
      z: 7000
      color: Util.alpha(root.panelBackground, 0.7)
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onEscapePressed: root.cancelRestartShell()

      MouseArea {
        anchors.fill: parent
        onClicked: root.cancelRestartShell()
      }

      Rectangle {
        id: restartConfirmCard
        anchors.centerIn: parent
        width: Math.min(parent.width - Style.space(32), Style.space(360))
        height: restartConfirmColumn.implicitHeight + Style.space(36)
        color: root.panelBackground
        radius: Style.cornerRadius
        border.color: Style.selectedStateColor(root.contentForeground, Color.accent)
        border.width: 1

        ColumnLayout {
          id: restartConfirmColumn
          anchors.fill: parent
          anchors.margins: Style.space(18)
          spacing: Style.space(12)

          Text {
            text: "Restart the shell?"
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            Layout.fillWidth: true
          }

          Text {
            text: "The shell (and this panel) will restart so every plugin reloads from source. This fixes plugins that still run stale compiled QML. Unsaved panel state will be lost."
            color: Qt.darker(root.contentForeground, 1.6)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
          }

          RowLayout {
            Layout.fillWidth: true

            Item { Layout.fillWidth: true }

            Button {
              text: "Cancel"
              foreground: root.contentForeground
              accent: Color.accent
              fontFamily: root.contentFontFamily
              fontSize: Style.font.bodySmall
              horizontalPadding: Style.space(12)
              verticalPadding: Style.space(6)
              onClicked: root.cancelRestartShell()
            }

            Button {
              text: "Restart"
              bordered: true
              foreground: root.contentForeground
              accent: Color.accent
              fontFamily: root.contentFontFamily
              fontSize: Style.font.bodySmall
              horizontalPadding: Style.space(12)
              verticalPadding: Style.space(6)
              onClicked: root.confirmRestartShell()
            }
          }
        }
      }
    }

    Rectangle {
      id: installDialog
      visible: root.installDialogOpen
      anchors.fill: parent
      z: 10000
      color: Util.alpha(root.panelBackground, 0.7)
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onEscapePressed: {
        if (!root.installRunning) root.installDialogOpen = false
      }

      MouseArea {
        anchors.fill: parent
        onClicked: {
          if (!root.installRunning) root.installDialogOpen = false
        }
      }

      Rectangle {
        id: installCard
        anchors.centerIn: parent
        width: Math.min(parent.width - Style.space(32), Style.space(360))
        height: installColumn.implicitHeight + Style.space(36)
        color: root.panelBackground
        radius: Style.cornerRadius
        border.color: Style.selectedStateColor(root.contentForeground, Color.accent)
        border.width: 1

        ColumnLayout {
          id: installColumn
          anchors.fill: parent
          anchors.margins: Style.space(18)
          spacing: Style.space(12)

          Text {
            text: "Install a plugin from a git repo"
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
          }

          Text {
            text: "Plugins run as arbitrary, unsandboxed code inside your omarchy-shell process. Only add repos you trust — review the code before you enable the plugin."
            color: Qt.darker(root.contentForeground, 1.6)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
          }

          TextField {
            id: installUrlField
            placeholderText: "https://github.com/acme/omarchy-weather.git"
            foreground: root.contentForeground
            accent: Color.accent
            font.family: root.contentFontFamily
            Layout.fillWidth: true
            onAccepted: {
              if (installUrlField.text.trim() !== "" && !root.installRunning)
                root.requestInstall()
            }
          }

          Text {
            visible: root.installResult !== ""
            text: root.installResult
            textFormat: Text.PlainText
            color: root.installRunning ? root.contentForeground
              : (root.installFailed ? Color.urgent
                : Style.selectedStateColor(root.contentForeground, Color.accent))
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
          }

          RowLayout {
            Layout.fillWidth: true

            Item { Layout.fillWidth: true }

            Button {
              text: root.installResult !== "" ? "Close" : "Cancel"
              enabled: !root.installRunning
              foreground: root.contentForeground
              accent: Color.accent
              fontFamily: root.contentFontFamily
              fontSize: Style.font.bodySmall
              horizontalPadding: Style.space(12)
              verticalPadding: Style.space(6)
              onClicked: root.installDialogOpen = false
            }

            Button {
              text: root.installRunning ? "Installing…" : "Install"
              enabled: !root.installRunning
              foreground: root.contentForeground
              accent: Color.accent
              fontFamily: root.contentFontFamily
              fontSize: Style.font.bodySmall
              horizontalPadding: Style.space(12)
              verticalPadding: Style.space(6)
              onClicked: root.requestInstall()
            }
          }
        }
      }
    }

    // Confirmation before installing: ask whether to enable the freshly
    // installed plugin. Shown above the install dialog so the entered URL
    // stays visible while deciding.
    Rectangle {
      id: installConfirmDialog
      visible: root.installConfirmOpen
      anchors.fill: parent
      z: 11000
      color: Util.alpha(root.panelBackground, 0.7)
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onEscapePressed: root.cancelInstallConfirm()

      MouseArea {
        anchors.fill: parent
        onClicked: root.cancelInstallConfirm()
      }

      Rectangle {
        id: installConfirmCard
        anchors.centerIn: parent
        width: Math.min(parent.width - Style.space(32), Style.space(380))
        height: installConfirmColumn.implicitHeight + Style.space(36)
        color: root.panelBackground
        radius: Style.cornerRadius
        border.color: Style.selectedStateColor(root.contentForeground, Color.accent)
        border.width: 1

        ColumnLayout {
          id: installConfirmColumn
          anchors.fill: parent
          anchors.margins: Style.space(18)
          spacing: Style.space(12)

          Text {
            text: "Install plugin?"
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
          }

          Text {
            text: "\"" + root.installPendingUrl + "\" will be added via `omarchy plugin add` but will remain DISABLED until you enable it manually. Review the code after install, then enable from the plugin list."
            textFormat: Text.PlainText
            color: Qt.darker(root.contentForeground, 1.6)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
          }

          RowLayout {
            Layout.fillWidth: true

            Item { Layout.fillWidth: true }

            Button {
              text: "Cancel"
              foreground: root.contentForeground
              accent: Color.accent
              fontFamily: root.contentFontFamily
              fontSize: Style.font.bodySmall
              horizontalPadding: Style.space(12)
              verticalPadding: Style.space(6)
              onClicked: root.cancelInstallConfirm()
            }

            Button {
              text: "Install"
              foreground: root.contentForeground
              accent: Color.accent
              fontFamily: root.contentFontFamily
              fontSize: Style.font.bodySmall
              horizontalPadding: Style.space(12)
              verticalPadding: Style.space(6)
              onClicked: root.installPlugin()
            }
          }
        }
      }
    }
  }
}
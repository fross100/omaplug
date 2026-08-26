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
  property var rememberedBarStates: ({})

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

  // Marketplace listing info keyed by plugin id: { verified, snapshotCommit,
  // snapshotStatus }. Fetched from the public catalog so rows can show a
  // verification badge and a "View on marketplace" link for listed plugins.
  property var marketplaceMap: ({})
  property bool marketplaceFetching: false
  property string marketplaceFetchedAt: ""

  // Local HEAD commit for every git-managed plugin dir, keyed by folder name.
  // Filled alongside the repo remote scan so rows can compare the installed
  // code against the marketplace listing's snapshot-checked commit.
  property var pluginCommits: ({})

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
  function shortSha(sha) {
    var s = String(sha || "")
    return s.length > 7 ? s.substring(0, 7) : s
  }
  // Listing checks section on the marketplace plugin page.
  function listingChecksUrlFor(id) {
    return root.marketplaceUrlFor(id) + "#verification"
  }
  function openListingChecks(id) {
    if (root.marketplaceEntry(String(id))) Qt.openUrlExternally(root.listingChecksUrlFor(id))
  }
  // GitHub commit page for a plugin's checked-out code.
  function commitUrlFor(sourceKey, sha) {
    var url = String(root.pluginRepos[sourceKey] || "")
    if (!/^https:\/\/github\.com\//.test(url)) return ""
    var s = String(sha || "")
    if (s === "") return ""
    url = url.replace(/\.git\/?$/, "").replace(/\/+$/, "")
    return url + "/commit/" + s
  }
  // GitHub profile of the plugin's repository owner.
  function authorUrlFor(sourceKey) {
    var url = String(root.pluginRepos[sourceKey] || "")
    var m = url.replace(/\.git\/?$/, "").match(/^https:\/\/github\.com\/([^\/]+)/)
    return m ? "https://github.com/" + m[1] : ""
  }
  // GitHub compare URL from the listing's snapshot-checked commit to the
  // locally installed commit. Only http(s) GitHub remotes are eligible, since
  // this URL goes to the browser.
  function compareUrlFor(sourceKey, fromSha, toSha) {
    var url = String(root.pluginRepos[sourceKey] || "")
    if (!/^https:\/\/github\.com\//.test(url)) return ""
    var f = String(fromSha || "")
    var t = String(toSha || "")
    if (f === "" || t === "" || f === t) return ""
    url = url.replace(/\.git\/?$/, "").replace(/\/+$/, "")
    return url + "/compare/" + f + "..." + t
  }
  // "What's new" link for a plugin with an available update: prefer the
  // marketplace release page (release notes), otherwise the GitHub compare
  // from the installed commit to the latest observed upstream commit.
  function whatsNewUrlFor(sourceKey, id) {
    var entry = root.marketplaceEntry(String(id))
    if (entry && typeof entry.releaseUrl === "string" && entry.releaseUrl !== "")
      return entry.releaseUrl
    var local = root.pluginCommits[String(sourceKey)] || ""
    var upstream = (entry && typeof entry.upstreamCommit === "string") ? entry.upstreamCommit : ""
    return root.compareUrlFor(sourceKey, local, upstream)
  }

  property string searchText: ""
  property int filterMode: 2 // 0 all, 1 omarchy, 2 third-party, 4 adna
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
  // Detached update-runner plumbing (from PR #1): the helper survives the
  // plugin reload that a successful update triggers, and the newly loaded
  // panel reconnects to the same job via this runtime status file.
  property string updateHelperPath: ""
  property string updateRunnerPath: ""
  readonly property string updateStateRoot: {
    var runtime = Quickshell.env("XDG_RUNTIME_DIR")
    return runtime && runtime !== ""
      ? runtime + "/omaplug"
      : Quickshell.env("HOME") + "/.cache/omaplug"
  }
  readonly property string updateStatusPath: root.updateStateRoot + "/update.status"
  readonly property int completedUpdateJobMaxAgeSeconds: 300
  property bool updateDetachedRunning: false
  property bool updateAwaitingStart: false
  property string updateExpectedJobId: ""
  property string updateProbePid: ""
  property int updateDeadProbeCount: 0
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
      // QObject::data is not bindable; reading it while iconFor() participates
      // in a Text binding makes Qt warn on every refresh. Bar buttons are
      // visual items, so the bindable visual-child tree is the right scope.
      var children = node.children
      if (children) {
        for (var j = 0; j < children.length; j++) stack.push(children[j])
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

  // Plugins with a git remote (what update actually applies to). Local /
  // dev plugins without a remote are skipped from the update list.
  readonly property var updateCheckRows: root.pluginRows.filter(function(p) {
    return p.updatable && root.pluginRepos[String(p.sourceKey)] !== undefined
  })

  function updateStatusText(key) {
    var st = root.updateStates[key]
    if (!st) return "Pending"
    if (st === "CHECK") return "Checking…"
    if (st === "CURRENT") return "Up to date"
    if (st === "UPDATE") return "Update available"
    if (st === "LOCAL_CHANGES") return "Local changes"
    if (st === "LOCAL") return "Local plugin"
    if (st === "ERROR") return "Error"
    return st
  }

  function updateStatusColor(key) {
    var st = root.updateStates[key]
    if (st === "UPDATE") return Style.selectedStateColor(root.contentForeground, Color.accent)
    if (st === "ERROR") return Color.urgent
    if (st === "CURRENT") return Qt.darker(root.contentForeground, 1.6)
    if (st === "LOCAL_CHANGES" || st === "LOCAL") return Qt.darker(root.contentForeground, 1.5)
    return Qt.darker(root.contentForeground, 1.4)
  }

  function updateErrorSuffix(count) {
    return count > 0 ? " (" + count + " error" + (count === 1 ? "" : "s") + ")" : ""
  }

  readonly property int pendingUpdateCount: {
    var n = 0
    for (var k in root.updateStates) {
      if (root.pluginRepos[k] === undefined) continue
      if (root.updateStates[k] === "UPDATE") n++
    }
    n
  }

  readonly property int enabledPluginCount: {
    var n = 0
    for (var i = 0; i < root.pluginRows.length; i++)
      if (root.pluginEnabled(root.pluginRows[i].id)) n++
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

  // Reads `git remote get-url origin` and `git rev-parse HEAD` for every
  // git-managed plugin dir and fills pluginRepos / pluginCommits (keyed by
  // folder name) so each row can offer a repo link and compare its installed
  // code against the marketplace listing snapshot.
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
      + "  sha=$(git -C \"$d\" rev-parse HEAD 2>/dev/null)\n"
      + "  [ -n \"$url$sha\" ] && echo \"$id|$url|$sha\"\n"
      + "done; } | { head -c 16384; cat >/dev/null; }"
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

  // Open an http(s) URL in the browser. QDesktopServices can silently no-op
  // under some session setups, so fall back to a detached xdg-open when it
  // reports failure.
  property Process xdgOpenProcess: Process {}
  function openExternal(url) {
    var u = String(url || "")
    if (!/^https?:\/\//.test(u)) return
    console.log("omaplug open:", u)
    if (!Qt.openUrlExternally(u)) {
      console.log("omaplug openUrlExternally failed, falling back to xdg-open")
      xdgOpenProcess.command = ["xdg-open", u]
      xdgOpenProcess.running = true
    }
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
    if (!dir || root.updateHelperPath === "" || root.checkingUpdates || root.updateDetachedRunning) return
    root.checkingUpdates = true
    root.updateSummary = ""
    root.updateStates = ({})
    root.updateCheckLineBuf = ""
    root.updateCheckProcessed = 0
    root.checkWatchdog.restart()
    updateCheckProcess.command = [root.updateHelperPath, dir]
    updateCheckProcess.running = true
  }

  // Per-line parser for plugin-state.sh output: tab-separated
  // "<state>\t<folderKey>[<\torigin-url>]" records. States beyond CHECK are
  // final; a non-empty origin-url also feeds pluginRepos so row links work.
  function applyUpdateCheckLine(line) {
    var cleanLine = String(line || "").trim()
    if (cleanLine === "") return
    var parts = cleanLine.split("\t")
    if (parts.length < 2) return
    var state = parts[0]
    var key = parts[1]
    if (["CHECK", "CURRENT", "UPDATE", "LOCAL_CHANGES", "LOCAL", "ERROR"].indexOf(state) < 0 || key === "") return
    var st = {}
    for (var k in root.updateStates) st[k] = root.updateStates[k]
    st[key] = state
    root.updateStates = st

    if (parts.length > 2 && parts[2] !== "") {
      var repos = {}
      for (var r in root.pluginRepos) repos[r] = root.pluginRepos[r]
      repos[key] = parts[2]
      root.pluginRepos = repos
    }
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
    for (var i = 0; i < lines.length; i++) root.applyUpdateCheckLine(lines[i])
  }

  // Finalize after the stream ends: flush any unterminated tail, then compute
  // the summary from the collected per-plugin states.
  function finishUpdateCheck(exitCode) {
    if (root.updateCheckLineBuf !== "") {
      var tail = root.updateCheckLineBuf.trim()
      root.updateCheckLineBuf = ""
      if (tail !== "") root.applyUpdateCheckLine(tail)
    }
    root.checkWatchdog.stop()
    root.checkingUpdates = false
    var states = {}
    for (var oldKey in root.updateStates) states[oldKey] = root.updateStates[oldKey]
    for (var i = 0; i < root.updateCheckRows.length; i++) {
      var sourceKey = root.updateCheckRows[i].sourceKey
      if (!states[sourceKey] || states[sourceKey] === "CHECK") states[sourceKey] = "ERROR"
    }
    root.updateStates = states
    var updates = 0
    var errors = 0
    for (var key in root.updateStates) {
      if (root.updateStates[key] === "UPDATE") updates++
      else if (root.updateStates[key] === "ERROR") errors++
    }
    if (exitCode !== 0)
      root.updateSummary = "Update check failed" + root.updateErrorSuffix(errors)
    else if (updates === 0 && errors === 0)
      root.updateSummary = ""
    else if (updates === 0)
      root.updateSummary = "No updates available" + root.updateErrorSuffix(errors)
    else
      root.updateSummary = updates + " update" + (updates > 1 ? "s" : "") + " available"
        + root.updateErrorSuffix(errors)
  }

  function updatePlugin(sourceKey) {
    root.startDetachedUpdates([sourceKey])
  }

  function updateAll() {
    if (root.checkingUpdates || root.updateDetachedRunning) return
    var ids = []
    for (var i = 0; i < root.updateCheckRows.length; i++) {
      var key = root.updateCheckRows[i].sourceKey
      if (root.updateStates[key] === "UPDATE") ids.push(key)
    }
    root.startDetachedUpdates(ids)
  }

  // Launch only the repositories proven updateable by the preceding check.
  // The helper is detached because the first successful merge makes Omarchy
  // unload this panel; progress lives at a stable runtime path so the newly
  // loaded instance can reconnect to the same job.
  function startDetachedUpdates(ids) {
    if (!ids || ids.length === 0 || root.checkingUpdates || root.updateDetachedRunning) return
    if (root.updateRunnerPath === "" || root.updateStatusPath === "") {
      root.updateSummary = "Update helper not found"
      return
    }

    root.updateDetachedRunning = true
    root.updateAwaitingStart = true
    root.updateExpectedJobId = Date.now().toString(36) + "-" + Math.floor(Math.random() * 0x1000000).toString(36)
    root.updateProbePid = ""
    root.updateDeadProbeCount = 0
    root.updatingAll = ids.length > 1
    root.updatingId = ids.length === 1 ? ids[0] : ""
    root.updateSummary = ids.length === 1
      ? "Updating " + ids[0] + "…"
      : "Updating 0 of " + ids.length + "…"

    var launch = [root.updateRunnerPath, root.updateStatusPath, root.updateExpectedJobId]
    for (var i = 0; i < ids.length; i++) launch.push(ids[i])
    try {
      Quickshell.execDetached(launch)
    } catch (e) {
      root.markUpdateInterrupted("Update could not start")
      return
    }
    updateStartTimer.restart()
    updateStatusPoll.restart()
  }

  function applyUpdateJobStatus() {
    var text = ""
    try { text = updateStatusFile.text() } catch (e) { return }
    if (String(text || "").trim() === "") return

    var lines = String(text).split("\n")
    var jobId = ""
    var pid = ""
    var total = 0
    var current = ""
    var completed = 0
    var failures = 0
    var finished = 0
    var done = false
    var outcomes = {}

    for (var i = 0; i < lines.length; i++) {
      var parts = lines[i].split("\t")
      var event = parts[0]
      if (event === "job") jobId = parts[1] || ""
      else if (event === "pid") pid = parts[1] || ""
      else if (event === "total") total = parseInt(parts[1] || "0")
      else if (event === "start") current = parts[1] || ""
      else if (event === "ok") {
        outcomes[parts[1]] = "CURRENT"
        completed++
        if (current === parts[1]) current = ""
      } else if (event === "failed") {
        outcomes[parts[1]] = "ERROR"
        completed++
        failures++
        if (current === parts[1]) current = ""
      } else if (event === "finished") {
        finished = parseInt(parts[1] || "0")
      } else if (event === "done") {
        done = true
        completed = parseInt(parts[1] || String(completed)) + parseInt(parts[2] || String(failures))
        failures = parseInt(parts[2] || String(failures))
      }
    }

    // A previous completed job may still be present while the newly detached
    // helper starts. Ignore it until this panel sees its own job id. A panel
    // recreated by Omarchy's hot reload has no expectation and adopts the
    // current job from disk instead.
    var expectingJob = root.updateExpectedJobId !== ""
    if (jobId === "" || (expectingJob && jobId !== root.updateExpectedJobId)) return
    if (!expectingJob && done && finished > 0
        && Date.now() / 1000 - finished > root.completedUpdateJobMaxAgeSeconds) return
    root.updateExpectedJobId = jobId
    root.updateAwaitingStart = false
    updateStartTimer.stop()
    if (pid !== root.updateProbePid) {
      root.updateProbePid = pid
      root.updateDeadProbeCount = 0
    }

    var states = {}
    for (var key in root.updateStates) states[key] = root.updateStates[key]
    for (var outcome in outcomes) states[outcome] = outcomes[outcome]
    root.updateStates = states
    root.updatingAll = total > 1
    root.updatingId = current

    if (done) {
      root.updateDetachedRunning = false
      root.updateAwaitingStart = false
      root.updatingAll = false
      root.updatingId = ""
      root.updateProbePid = ""
      root.updateDeadProbeCount = 0
      updateStartTimer.stop()
      updateStatusPoll.stop()
      var successes = Math.max(0, completed - failures)
      if (failures === 0)
        root.updateSummary = successes === 1 ? "1 plugin updated" : successes + " plugins updated"
      else
        root.updateSummary = successes + " updated, " + failures + " failed"
      root.refreshPlugins()
      return
    }

    root.updateDetachedRunning = true
    root.updateSummary = total > 1
      ? "Updating " + completed + " of " + total + (current ? ": " + current : "") + "…"
      : (current ? "Updating " + current + "…" : "Preparing update…")
    updateStatusPoll.restart()
  }

  function recoverExistingUpdateOrFailStart() {
    if (!root.updateAwaitingStart) return
    root.updateAwaitingStart = false
    root.updateExpectedJobId = ""
    root.updateDetachedRunning = false
    root.applyUpdateJobStatus()
    if (!root.updateDetachedRunning)
      root.markUpdateInterrupted("Update could not start. Another update may already be running.")
  }

  function markUpdateInterrupted(message) {
    root.updateDetachedRunning = false
    root.updateAwaitingStart = false
    root.updatingAll = false
    root.updatingId = ""
    root.updateExpectedJobId = ""
    root.updateProbePid = ""
    root.updateDeadProbeCount = 0
    updateStartTimer.stop()
    updateStatusPoll.stop()
    root.updateSummary = message || "Update interrupted. Check again."
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
        map[entry.id] = {
          verified: entry.verificationStatus === "verified",
          snapshotCommit: typeof entry.verificationCommit === "string" ? entry.verificationCommit : "",
          snapshotStatus: String(entry.verificationSnapshotStatus || entry.verificationCoverage || ""),
          upstreamCommit: typeof entry.upstreamObservedCommit === "string" ? entry.upstreamObservedCommit : "",
          releaseUrl: entry.repositoryRelease && typeof entry.repositoryRelease.url === "string" ? entry.repositoryRelease.url : ""
        }
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
    var commits = {}
    var lines = out.split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (line === "") continue
      var parts = line.split("|")
      if (parts.length < 2) continue
      var key = parts[0].trim()
      var url = (parts[1] || "").trim()
      var sha = (parts[2] || "").trim()
      if (!key) continue
      if (url) repos[key] = url
      if (/^[0-9a-f]{40}$/.test(sha)) commits[key] = sha
    }
    root.pluginRepos = repos
    root.pluginCommits = commits
  }

  property Process updateCheckProcess: Process {
    onExited: function(exitCode) {
      console.log("updateCheckProcess onExited exitCode=", exitCode)
      root.finishUpdateCheck(exitCode)
    }
    stdout: StdioCollector {
      id: updateCheckStdout
      waitForEnd: false
      onTextChanged: root.applyUpdateCheckData(updateCheckStdout.text)
    }
  }

  // Liveness probe for the detached update runner: kill -0 the recorded pid;
  // two consecutive failures mean the helper died without a done marker.
  property Process updateProbeProcess: Process {
    onExited: function(exitCode) {
      if (!root.updateDetachedRunning || root.updateAwaitingStart) return
      if (exitCode === 0) {
        root.updateDeadProbeCount = 0
        return
      }
      root.updateDeadProbeCount++
      updateStatusFile.reload()
      if (root.updateDeadProbeCount >= 2)
        root.markUpdateInterrupted()
    }
  }

  FileView {
    id: updateStatusFile
    path: root.updateStatusPath
    watchChanges: true
    printErrors: false
    onLoaded: root.applyUpdateJobStatus()
    onFileChanged: updateStatusFile.reload()
  }

  Timer {
    id: updateStartTimer
    interval: 3000
    repeat: false
    onTriggered: root.recoverExistingUpdateOrFailStart()
  }

  Timer {
    id: updateStatusPoll
    interval: 500
    repeat: true
    running: root.updateDetachedRunning
    onTriggered: updateStatusFile.reload()
  }

  Timer {
    interval: 2000
    repeat: true
    running: root.updateDetachedRunning && !root.updateAwaitingStart
    onTriggered: {
      if (!updateProbeProcess.running && /^[0-9]+$/.test(root.updateProbePid)) {
        updateProbeProcess.command = ["bash", "-c", 'kill -0 "$0" 2>/dev/null', root.updateProbePid]
        updateProbeProcess.running = true
      }
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
      var kinds = Array.isArray(m.kinds) ? m.kinds : []
      var isBarOption = kinds.indexOf("bar") !== -1
      var isBarWidget = kinds.indexOf("bar-widget") !== -1
      rows.push({
        id: id,
        name: m.name || id,
        version: m.version || "unknown",
        author: m.author || "",
        description: m.description || "",
        kinds: kinds.join(", "),
        canDisable: !isBarOption,
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

  function barStateFor(id) {
    var reg = root.registry
    var config = reg && typeof reg.shellConfigProvider === "function"
      ? reg.shellConfigProvider()
      : null
    var layout = config && config.bar ? config.bar.layout : null
    if (!layout) return null
    var sections = ["left", "center", "right"]
    for (var s = 0; s < sections.length; s++) {
      var entries = layout[sections[s]]
      if (!Array.isArray(entries)) continue
      for (var i = 0; i < entries.length; i++) {
        var entry = entries[i]
        var entryId = reg && typeof reg.barEntryId === "function"
          ? reg.barEntryId(entry)
          : (entry && typeof entry === "object" ? entry.id : entry)
        if (String(entryId || "") === String(id))
          return {
            section: sections[s],
            index: i,
            entry: entry && typeof entry === "object"
              ? JSON.parse(JSON.stringify(entry))
              : { id: String(entryId) }
          }
      }
    }
    return null
  }

  function rememberBarState(id, state) {
    var next = {}
    for (var key in root.rememberedBarStates)
      next[key] = root.rememberedBarStates[key]
    if (state) next[String(id)] = state
    else delete next[String(id)]
    root.rememberedBarStates = next
  }

  function restoreBarSettings(id, state) {
    var reg = root.registry
    var entry = state ? state.entry : null
    if (!entry || !reg || typeof reg.setBarWidget !== "function") return
    var location = root.barStateFor(id)
    if (!location) return
    var selector = { section: location.section, index: location.index }
    for (var key in entry) {
      if (key === "id") continue
      var error = reg.setBarWidget(id, key, entry[key], selector)
      if (error) console.warn("Could not restore " + id + " setting " + key + ": " + error)
    }
  }

  function setPluginEnabled(id, value) {
    var reg = root.registry
    if (!reg || typeof reg.setEnabled !== "function") return
    // Bar options cannot be disabled directly (they are bar placements);
    // guard here so a stale UI can't fight the registry.
    for (var i = 0; i < root.pluginRows.length; i++) {
      var row = root.pluginRows[i]
      if (row.id === id && value === false && row.canDisable === false) return
    }
    var remembered = value ? root.rememberedBarStates[String(id)] : null
    var current = value ? null : root.barStateFor(id)
    var changed = remembered
      ? reg.setEnabled(id, true, remembered)
      : reg.setEnabled(id, value)
    if (!changed) return
    if (!value && current) root.rememberBarState(id, current)
    else if (value && remembered) {
      root.restoreBarSettings(id, remembered)
      root.rememberBarState(id, null)
    }
  }

  function registryRevision() {
    var reg = root.registry
    return reg ? reg.registryRevision : 0
  }

  function pluginEnabled(id) {
    root.registryRevision()
    var reg = root.registry
    var manifest = reg && reg.installedPlugins ? reg.installedPlugins[id] : null
    if (!manifest) return false
    var kinds = Array.isArray(manifest.kinds) ? manifest.kinds : []
    // Built-in widgets remain loadable even while absent from the bar, so the
    // user-facing toggle follows their actual placement instead of isEnabled().
    return kinds.indexOf("bar-widget") !== -1 && typeof reg.inBar === "function"
      ? reg.inBar(id) === true
      : reg.isEnabled(id) === true
  }

  Connections {
    target: root.registry
    function onRegistryRevisionChanged() {
      root.invalidateGlyphCache()
    }
    function onScanFinished() {
      root.refreshPlugins()
    }
  }

  Component.onCompleted: {
    console.log("Panel.qml loaded, filterMode=", root.filterMode, "rows=", root.pluginRows.length)
    root.updateHelperPath = String(Qt.resolvedUrl("plugin-state.sh")).replace(/^file:\/\//, "")
    root.updateRunnerPath = String(Qt.resolvedUrl("update-helper.sh")).replace(/^file:\/\//, "")
    refreshPlugins()
    fetchMarketplace()
    Qt.callLater(function() { updateStatusFile.reload() })
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
            enabled: !root.checkingUpdates && !root.updateDetachedRunning
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
          spacing: 0
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

          delegate: Item {
            id: rowWrapper
            required property var modelData
            required property int index
            width: pluginList.width
            height: pluginRowDelegate.height + Style.space(9)

            Rectangle {
            id: pluginRowDelegate
            readonly property bool mFirstParty: modelData.firstParty === true
            readonly property var mEntry: mFirstParty ? null : (root.marketplaceMap[String(modelData.id)] || null)
            readonly property bool mListed: mEntry !== null
            readonly property bool mVerified: mListed && mEntry.verified === true
            // Marketplace listing snapshot check commit vs installed code.
            readonly property string mSnapshotCommit: mListed && typeof mEntry.snapshotCommit === "string" ? mEntry.snapshotCommit : ""
            readonly property string mLocalCommit: root.pluginCommits[String(modelData.sourceKey)] || ""
            readonly property bool mCommitKnown: mSnapshotCommit !== "" && mLocalCommit !== ""
            readonly property bool mCommitMatches: mCommitKnown && mSnapshotCommit === mLocalCommit
            readonly property string mCompareUrl: root.compareUrlFor(modelData.sourceKey, mSnapshotCommit, mLocalCommit)
            readonly property string mSnapshotUrl: root.commitUrlFor(modelData.sourceKey, mSnapshotCommit)
            readonly property string mLocalUrl: root.commitUrlFor(modelData.sourceKey, mLocalCommit)
            readonly property string mAuthorUrl: modelData.firstParty ? "" : root.authorUrlFor(modelData.sourceKey)
            // True when the bottom action row has a visible button, so the
            // row can collapse entirely (and stop shifting the top row off
            // center) for plugins that have no source/update control.
            readonly property bool mShowSourceRow: (modelData.updatable && root.pluginRepos[String(modelData.sourceKey)] !== undefined) || (modelData.updatable && root.updateStates[String(modelData.sourceKey)] === "UPDATE")
            width: parent.width
            height: Math.max(Style.space(56),
              Math.min(row.implicitHeight + Style.space(22), Style.space(120)))
            clip: true
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
              anchors.bottomMargin: Style.space(10)
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
                    // Take the row's slack and elide; minimumWidth 0 lets the
                    // layout squeeze this instead of pushing the action column
                    // out when the name is very long (issue #4).
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
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

                  Label {
                    visible: modelData.version !== "unknown"
                    text: "v" + modelData.version
                    textFormat: Text.PlainText
                    color: Qt.darker(root.contentForeground, 2.0)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Label {
                  text: modelData.description !== "" ? modelData.description : "No description"
                  textFormat: Text.PlainText
                  color: Qt.darker(root.contentForeground, 1.6)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  Layout.fillWidth: true
                  Layout.minimumWidth: 0
                  wrapMode: Label.Wrap
                  maximumLineCount: 2
                  elide: Label.ElideRight
                }

                // Creator line under the description, linking to the
                // repository owner's GitHub profile when derivable, with
                // the plugin kind on the same line.
                 RowLayout {
                   visible: modelData.author !== ""
                   spacing: Style.space(6)
                   Layout.fillWidth: true

                   Text {
                     text: "by " + modelData.author + (pluginRowDelegate.mAuthorUrl !== "" ? " ↗" : "")
                     Layout.fillWidth: true
                     Layout.minimumWidth: 0
                     elide: Text.ElideRight
                    textFormat: Text.PlainText
                    color: pluginRowDelegate.mAuthorUrl !== ""
                      ? Color.accent
                      : Qt.darker(root.contentForeground, 2.0)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.underline: authorLinkHover.hovered && pluginRowDelegate.mAuthorUrl !== ""

                    ToolTip.text: pluginRowDelegate.mAuthorUrl !== "" ? pluginRowDelegate.mAuthorUrl : ("by " + modelData.author)
                    ToolTip.visible: authorLinkHover.hovered
                    ToolTip.delay: 400

                    HoverHandler {
                      id: authorLinkHover
                      cursorShape: pluginRowDelegate.mAuthorUrl !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                    }

                    MouseArea {
                      anchors.fill: parent
                      enabled: pluginRowDelegate.mAuthorUrl !== ""
                      cursorShape: Qt.PointingHandCursor
                      onClicked: Qt.openUrlExternally(pluginRowDelegate.mAuthorUrl)
                    }
                  }

                  Text {
                    visible: modelData.kinds !== ""
                    text: "· " + modelData.kinds
                    textFormat: Text.PlainText
                    color: Qt.darker(root.contentForeground, 2.0)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                  }
                }

                // Marketplace listing links on their own line under the
                // description row, pipe-separated: the listing page, the
                // snapshot-checked commit (linked), the installed commit when
                // it has moved on, and the listing checks page. The text
                // links flex and elide so this line never pushes the action
                // buttons off the right edge.
                RowLayout {
                  visible: pluginRowDelegate.mListed
                  spacing: Style.space(6)
                  Layout.fillWidth: true

                  // Marketplace icon: the site favicon (Lucide "cable", ISC
                  // licensed), embedded as a transparent PNG data URI so the
                  // panel stays self-contained, plus a trailing arrow. A plain
                  // Item wrapper so hover/tap and the tooltip behave like the
                  // text links above.
                  Item {
                    id: marketLink
                    readonly property int _gap: 2
                    width: marketIcon.width + marketArrow.implicitWidth + _gap
                    height: Math.max(marketIcon.height, marketArrow.implicitHeight)
                    Layout.alignment: Qt.AlignVCenter

                    Image {
                      id: marketIcon
                      anchors.verticalCenter: parent.verticalCenter
                      source: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAABmJLR0QA/wD/AP+gvaeTAAADb0lEQVRYhe2WTWhcVRTHf+fNNAmh1tFQsISUErMSwUicSbOpLTSLiEUTECaTEl2JKEVU6MKvjboRFAu6cCNB7CNS0SKxWbQqtJCYSYsR6spa1Cgu2spYQup85P1d3DfT92YyHcTpqv3D4557vt+599x74TZudVg9Q08Npih1PA922vylbwGUG94H2kNH6YjNrBQabfZ2UVo/gPGAY/AD5cScHVu81iqBZAOn1Pki6DVQAbgrDPE5kKLUmQBejwWfSqcprc8A96GIYMvGqnLpg+Yvn/5vCYiesC4p5dL7Q26qJouq5tL9yL4Btm7iuw9sXrnhQfOXfmqWgBdzOD20E9PUdY6ddF91qoPKpvsi8o/C4AJ7AzruppzocRVEQDfow2bBob4CFe8wcOcN9Lfh2WHgkLK7d0HwcJj6jPn56NK8qcnMAMaTwD5ND+20j8/9tplDr27a7/zpEmIcNAoaRYwjLoV/fa8bgv6amezLTXwfr1HlxECzP2rcAwBmBfPzx6Ms5TJvA9uv5xp0Iq9KFxt8eEExIu9slkC8AtI/bqRbkRYVGKI7ptMm1FXAVkDjGL3kMnMSdzi2rYF6Ha3vb14CFe99tmw8A+wAHonVwOFPyskP2plAbAns2OJfkBxBfAZcjYiuOl5yxOm0Dw2b0PyFX4EnNPXQGPJOOGaQNf/sfDsDV+G1Vrm52LwN/weU3b0LT++4M6QK71Plhk8S2Es2+90vUf22VkDTmR4SwSJogmoHAY7WBF6woOlM7D5p7xKU7TnEPQAYXyHOIM4AJ0KNHVT0bNSkzUugQTfwB37+gIX9KzAmM6sYvcgejFq0twJmXW5k3SKHh4Ew1mM6IZpXIPCKtYMo8DY5y72umG4UIqXJzOOY1tzctiJSje+vGyVgyZ+hEtIaI3q7AQQ8VnMohQ+O4CIYGNuBL2rXSTSw6UIsTNMEAOUyC8AIbhnfIqn3ANjgBcTLof3X5uf3Ayib7sOz88C2Ji7/xux+O7r0e5XRYg/YIeCaC6RXqXCZCpcRr4TB10BP17Rnl1eRfRL5hdHYeSA7Gg3eMgHzl84RsAf4sUEozoPtNX/5YtyIKyFVMH/5lPnLp4BCnayGlm1os/mzGhsYItXzKEa1zVYoXJmz+QuND5GO4ruUOjbAIq9hm3DP+uKRVvFu49bDv15cMTlnbnc+AAAAAElFTkSuQmCC"
                      width: 14
                      height: 14
                      fillMode: Image.PreserveAspectFit
                      cache: false
                    }

                    Text {
                      id: marketArrow
                      x: marketIcon.width + parent._gap
                      anchors.verticalCenter: parent.verticalCenter
                      text: "↗"
                      textFormat: Text.PlainText
                      color: Color.accent
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.caption
                    }

                    HoverHandler {
                      id: marketLinkHover
                      cursorShape: Qt.PointingHandCursor
                    }

                    TapHandler {
                      onTapped: root.openMarketplacePage(modelData.id)
                    }

                    ToolTip.text: root.marketplaceUrlFor(modelData.id)
                    ToolTip.visible: marketLinkHover.hovered
                    ToolTip.delay: 400
                  }

                  Text {
                    text: "|"
                    textFormat: Text.PlainText
                    color: Qt.darker(root.contentForeground, 2.4)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Text {
                    visible: pluginRowDelegate.mSnapshotCommit !== ""
                    text: "\uDB81\uDF91 " + root.shortSha(pluginRowDelegate.mSnapshotCommit)
                    textFormat: Text.PlainText
                    color: pluginRowDelegate.mCommitMatches ? Color.accent : Qt.darker(root.contentForeground, 1.6)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.underline: snapLinkHover.hovered && pluginRowDelegate.mSnapshotUrl !== ""

                    ToolTip.text: pluginRowDelegate.mSnapshotUrl !== ""
                      ? pluginRowDelegate.mSnapshotUrl
                      : pluginRowDelegate.mSnapshotCommit
                    ToolTip.visible: snapLinkHover.hovered
                    ToolTip.delay: 400

                    HoverHandler {
                      id: snapLinkHover
                      cursorShape: pluginRowDelegate.mSnapshotUrl !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                    }

                    MouseArea {
                      anchors.fill: parent
                      enabled: pluginRowDelegate.mSnapshotUrl !== ""
                      cursorShape: Qt.PointingHandCursor
                      onClicked: Qt.openUrlExternally(pluginRowDelegate.mSnapshotUrl)
                    }
                  }

                  Text {
                    // Listing has no snapshot commit yet: fall back to
                    // linking the locally installed code commit alone.
                    visible: pluginRowDelegate.mSnapshotCommit === "" && pluginRowDelegate.mLocalCommit !== ""
                    text: "\uDB81\uDF91 " + root.shortSha(pluginRowDelegate.mLocalCommit) + (pluginRowDelegate.mLocalUrl !== "" ? " ↗" : "")
                    textFormat: Text.PlainText
                    color: Qt.darker(root.contentForeground, 1.6)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.underline: localOnlyLinkHover.hovered && pluginRowDelegate.mLocalUrl !== ""

                    HoverHandler {
                      id: localOnlyLinkHover
                      cursorShape: pluginRowDelegate.mLocalUrl !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                    }

                    MouseArea {
                      anchors.fill: parent
                      enabled: pluginRowDelegate.mLocalUrl !== ""
                      cursorShape: Qt.PointingHandCursor
                      onClicked: Qt.openUrlExternally(pluginRowDelegate.mLocalUrl)
                    }
                  }

                  Text {
                    visible: pluginRowDelegate.mSnapshotCommit !== "" && pluginRowDelegate.mLocalCommit !== "" && !pluginRowDelegate.mCommitMatches
                    text: "→"
                    textFormat: Text.PlainText
                    color: Qt.darker(root.contentForeground, 2.0)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Text {
                    visible: pluginRowDelegate.mSnapshotCommit !== "" && pluginRowDelegate.mLocalCommit !== "" && !pluginRowDelegate.mCommitMatches
                    text: root.shortSha(pluginRowDelegate.mLocalCommit) + (pluginRowDelegate.mLocalUrl !== "" ? " ↗" : "")
                    textFormat: Text.PlainText
                    color: Color.accent
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.underline: localLinkHover.hovered && pluginRowDelegate.mLocalUrl !== ""

                    ToolTip.text: pluginRowDelegate.mLocalUrl !== ""
                      ? pluginRowDelegate.mLocalUrl
                      : pluginRowDelegate.mLocalCommit
                    ToolTip.visible: localLinkHover.hovered
                    ToolTip.delay: 400

                    HoverHandler {
                      id: localLinkHover
                      cursorShape: pluginRowDelegate.mLocalUrl !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                    }

                    MouseArea {
                      anchors.fill: parent
                      enabled: pluginRowDelegate.mLocalUrl !== ""
                      cursorShape: Qt.PointingHandCursor
                      onClicked: Qt.openUrlExternally(pluginRowDelegate.mLocalUrl)
                    }
                  }

                  Text {
                    visible: pluginRowDelegate.mCompareUrl !== ""
                    text: "|"
                    textFormat: Text.PlainText
                    color: Qt.darker(root.contentForeground, 2.4)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Text {
                    visible: pluginRowDelegate.mCompareUrl !== ""
                    text: "view changes ↗"
                    textFormat: Text.PlainText
                    color: Color.accent
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.underline: compareLinkHover.hovered
                    elide: Text.ElideRight
                    ToolTip.text: pluginRowDelegate.mCompareUrl
                    ToolTip.visible: compareLinkHover.hovered
                    ToolTip.delay: 400

                    HoverHandler {
                      id: compareLinkHover
                      cursorShape: Qt.PointingHandCursor
                    }

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: Qt.openUrlExternally(pluginRowDelegate.mCompareUrl)
                    }
                  }

                  Text {
                    text: "|"
                    textFormat: Text.PlainText
                    color: Qt.darker(root.contentForeground, 2.4)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Text {
                    text: "Listing checks ↗"
                    textFormat: Text.PlainText
                    color: Color.accent
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.underline: checksLinkHover.hovered
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    ToolTip.text: root.listingChecksUrlFor(modelData.id)
                    ToolTip.visible: checksLinkHover.hovered
                    ToolTip.delay: 400

                    HoverHandler {
                      id: checksLinkHover
                      cursorShape: Qt.PointingHandCursor
                    }

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.openListingChecks(modelData.id)
                    }
                  }
                }
              }

              // Action column pinned to the right edge of every row; the
              // text columns absorb any width pressure so these controls
              // always stay flush right. Toggle + more-actions on top,
              // source / update buttons stacked underneath.
              ColumnLayout {
                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                spacing: Style.space(4)

                RowLayout {
                  // Toggle and more-actions sit adjacent, flush right.
                  Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                  spacing: Style.space(6)

                  // Inline switch: solid accent track when ON so it reads the
                  // same as the accent-colored author / "View on marketplace"
                  // links (ToggleSwitch's fill is too faint at 0.18 alpha).
                  // Gated like the PR's native toggle: bar options that are
                  // active cannot be switched off directly.
                  Item {
                    id: toggle
                    readonly property bool checked: root.pluginEnabled(rowWrapper.modelData.id)
                    readonly property bool canToggle: rowWrapper.modelData.canDisable || !toggle.checked
                    readonly property int _h: Math.max(22, Math.round(Style.spacing.controlHeight * 0.55))
                    readonly property int _w: Math.round(_h * 1.9)
                    readonly property int _k: Math.max(6, Math.round(_h * 0.72))
                    readonly property int _inset: Math.max(1, Math.round((_h - _k) / 2))
                    implicitWidth: _w
                    implicitHeight: _h
                    opacity: canToggle ? 1 : 0.4
                    Layout.alignment: Qt.AlignVCenter

                    Rectangle {
                      width: toggle._w
                      height: toggle._h
                      radius: Style.cornerRadius > 0 ? height / 2 : 0
                      color: toggle.checked
                        ? Color.accent
                        : Style.normalFillFor(root.contentForeground, Color.accent)
                      Behavior on color { ColorAnimation { duration: 120 } }

                      Rectangle {
                        width: toggle._k
                        height: toggle._k
                        radius: Style.cornerRadius > 0 ? height / 2 : 0
                        x: toggle.checked ? toggle._w - width - toggle._inset : toggle._inset
                        anchors.verticalCenter: parent.verticalCenter
                        color: toggle.checked ? Color.background : Qt.darker(root.contentForeground, 1.25)
                        Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 120 } }
                      }
                    }

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: toggle.canToggle ? Qt.PointingHandCursor : Qt.ArrowCursor
                      onClicked: {
                        if (!toggle.canToggle) return
                        Qt.callLater(function() { root.setPluginEnabled(rowWrapper.modelData.id, !toggle.checked) })
                      }
                    }
                  }

                  Button {
                    id: rowMenuButton
                    iconText: "\uf142"
                    tooltipText: "More actions"
                    visible: !modelData.firstParty
                    bordered: true
                    // Keep the idle border but drop it while hovered.
                    borderSpec: hot ? Border.none()
                      : Border.controlSpec("normal", foreground, Color.accent)
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

                RowLayout {
                  // Collapse completely when no source/update button shows,
                  // so the toggle/more-actions pair stays vertically centered.
                  visible: pluginRowDelegate.mShowSourceRow
                  Layout.fillWidth: true
                  spacing: Style.space(6)

                  Button {
                    visible: modelData.updatable
                      && root.pluginRepos[modelData.sourceKey] !== undefined
                    tooltipText: "Open plugin repository"
                    text: "SOURCE \udb85\udd94"
                    bordered: true
                    // Keep the idle border but drop it while hovered.
                    borderSpec: hot ? Border.none()
                      : Border.controlSpec("normal", foreground, Color.accent)
                    foreground: root.contentForeground
                    accent: Color.accent
                    fontFamily: root.contentFontFamily
                    fontSize: Style.font.caption
                    iconSize: Style.font.caption
                    horizontalPadding: Style.space(6)
                    verticalPadding: Style.space(3)
                    Layout.fillWidth: true
                    onClicked: root.openPluginRepo(modelData.sourceKey)
                  }

                  Button {
                    visible: modelData.updatable
                      && root.updateStates[modelData.sourceKey] === "UPDATE"
                    text: root.updatingId === modelData.sourceKey ? "Updating…" : "Update"
                    enabled: !root.updateDetachedRunning
                    bordered: true
                    // Keep the idle border but drop it while hovered.
                    borderSpec: hot ? Border.none()
                      : Border.controlSpec("normal", foreground, Color.accent)
                    foreground: root.contentForeground
                    accent: Color.accent
                    fontFamily: root.contentFontFamily
                    fontSize: Style.font.caption
                    horizontalPadding: Style.space(8)
                    verticalPadding: Style.space(3)
                    Layout.fillWidth: true
                    onClicked: root.updatePlugin(modelData.sourceKey)
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

            }

            // Divider floats in the gap between row cards, never over text.
            Rectangle {
              visible: index < pluginList.count - 1
              anchors.top: pluginRowDelegate.bottom
              anchors.topMargin: Style.space(4)
              anchors.left: parent.left
              anchors.right: parent.right
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

                Text {
                  id: whatsNewLink
                  readonly property string wnUrl: root.whatsNewUrlFor(modelData.sourceKey, modelData.id)
                  visible: root.updateStates[String(modelData.sourceKey)] === "UPDATE" && wnUrl !== ""
                  text: "What's new ↗"
                  textFormat: Text.PlainText
                  color: Color.accent
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  font.underline: whatsNewLinkHover.hovered
                  ToolTip.text: wnUrl
                  ToolTip.visible: whatsNewLinkHover.hovered
                  ToolTip.delay: 400

                  HoverHandler {
                    id: whatsNewLinkHover
                    cursorShape: Qt.PointingHandCursor
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openExternal(whatsNewLink.wnUrl)
                  }
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

              Button {
                readonly property string st: String(root.updateStates[modelData.sourceKey] || "")
                visible: st === "CURRENT" || st === "UPDATE" || st === "LOCAL_CHANGES"
                  || st === "LOCAL" || st === "ERROR"
                // Icon + label: an "UPDATE" pill when a newer version is
                // available (clickable to update), a plain check otherwise.
                text: st === "UPDATE" ? "\uEAC2 UPDATE" : "\uF00C"
                enabled: st === "UPDATE" && !root.updateDetachedRunning
                onClicked: root.updatePlugin(modelData.sourceKey)
                bordered: true
                // Keep the idle border but drop it on hover, matching the
                // other action buttons.
                borderSpec: hot ? Border.none()
                  : Border.controlSpec("normal", foreground, Color.accent)
                foreground: st === "ERROR" ? Color.urgent : root.contentForeground
                accent: Color.accent
                fontFamily: root.contentFontFamily
                fontSize: Style.font.caption
                horizontalPadding: Style.space(8)
                verticalPadding: Style.space(3)
                Layout.alignment: Qt.AlignVCenter
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
              && !root.checkingUpdates && !root.updateDetachedRunning
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
          readonly property bool pluginIsEnabled: plugin ? root.pluginEnabled(plugin.id) : false

          Button {
            text: rowMenuColumn.pluginIsEnabled
              ? (rowMenuColumn.plugin.canDisable ? "Disable" : "Active bar")
              : "Enable"
            enabled: rowMenuColumn.plugin
              && (rowMenuColumn.plugin.canDisable || !rowMenuColumn.pluginIsEnabled)
            foreground: root.contentForeground
            accent: Color.accent
            fontFamily: root.contentFontFamily
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.space(8)
            verticalPadding: Style.space(5)
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignLeft
            onClicked: {
              root.setPluginEnabled(root.rowMenuId, !rowMenuColumn.pluginIsEnabled)
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

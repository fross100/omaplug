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

  // Third-party plugins receive a scoped shell API and cannot inspect the
  // host's live PluginRegistry. The public CLI is the supported listing API.
  property bool listingPlugins: false
  property int pluginListAttempts: 0

  // Git remote URLs for updatable plugins, keyed by sourceKey. Filled by a
  // background `git remote get-url` scan so each row can offer a repo link.
  property var pluginRepos: ({})
  property bool reposScanning: false

  property string searchText: ""
  property int filterMode: 0 // 0 all, 1 omarchy, 2 third-party, 4 adna

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
  property bool installPendingEnable: false
  // After a successful install, enable the plugin by running the CLI enable
  // command once the shell has had time to discover the new plugin. The CLI's
  // own `--enable` during add races with the reload, so enable runs as a
  // separate step afterwards.
  property bool installShouldEnable: false
  property string installPendingId: ""
  property int installEnableAttempts: 0
  // Paths for the detached install helper. The helper is launched with
  // setsid/nohup because `omarchy plugin add` reloads plugins at the end,
  // which unloads this panel and would kill an ordinary Process mid-run.
  property string installHelperPath: ""
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
  function liveGlyphFor(id) {
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
    removeProcess.command = ["bash", "-c", "omarchy plugin remove \"$0\" --yes", id]
    removeProcess.running = true
  }

  function onRemoveFinished(exitCode) {
    var err = String(removeStderr.text || "").trim()
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
    if (root.reposScanning) return
    root.reposScanning = true
    var script = ""
      + "dirs=\"$HOME/.config/omarchy/plugins\"\n"
      + "for d in \"$dirs\"/*/; do\n"
      + "  [ -d \"$d/.git\" ] || continue\n"
      + "  id=$(basename \"$d\")\n"
      + "  url=$(git -C \"$d\" remote get-url origin 2>/dev/null)\n"
      + "  [ -n \"$url\" ] && echo \"$id|$url\"\n"
      + "done"
    repoScanProcess.command = ["bash", "-c", script]
    repoScanProcess.running = true
  }

  function repoUrlFor(sourceKey) {
    return root.pluginRepos[sourceKey] || ""
  }

  function openPluginRepo(sourceKey) {
    var url = root.repoUrlFor(sourceKey)
    if (url) Qt.openUrlExternally(url)
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
    console.log("checkUpdates start, checkingUpdates=", root.checkingUpdates, "updatingId=", root.updatingId)
    var dir = "$HOME/.config/omarchy/plugins"
    console.log("pluginsDir=", dir)
    if (!dir || root.checkingUpdates || root.updatingId !== "") return
    root.checkingUpdates = true
    root.updateSummary = ""
    root.updateCheckLineBuf = ""
    root.updateCheckProcessed = 0
    root.checkWatchdog.restart()
    var script = ""
      + "dirs=\"$HOME/.config/omarchy/plugins\"\n"
      + "for d in \"$dirs\"/*/; do\n"
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
      + "done"
    updateCheckProcess.command = ["bash", "-c", script]
    console.log("checkUpdates command set, running...")
    updateCheckProcess.running = true
    console.log("checkUpdates running=", updateCheckProcess.running, "pid=", updateCheckProcess.processId)
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
    updateProcess.command = ["bash", "-c", "omarchy plugin update \"$0\" --yes", id]
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
    updateAllProcess.command = ["bash", "-c", "omarchy plugin update --yes"]
    updateAllProcess.running = true
  }

  function onUpdateAllFinished(exitCode) {
    root.updatingAll = false
    if (exitCode === 0)
      root.updateSummary = "All updates applied"
    else {
      var err = String(updateStderr.text || "").trim()
      root.updateSummary = "Bulk update failed" + (err ? ": " + err : "")
    }
    root.refreshPlugins()
    Qt.callLater(function() { root.checkUpdates() })
  }

  function onUpdateFinished(exitCode) {
    console.log("onUpdateFinished exitCode=", exitCode, "id=", root.updatingId)
    var id = root.updatingId
    root.updatingId = ""
    if (exitCode === 0)
      root.updateSummary = "Updated " + id
    else {
      var err = String(updateStderr.text || "").trim()
      root.updateSummary = "Update of " + id + " failed" + (err ? ": " + err : "")
    }
    root.refreshPlugins()
    Qt.callLater(function() { root.checkUpdates() })
  }

  property Process repoScanProcess: Process {
    onExited: function(exitCode) {
      root.reposScanning = false
      console.log("repoScanProcess onExited exitCode=", exitCode, "stdout=", (repoScanStdout.text || "").substring(0, 200))
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
    console.log("applyRepoScan keys=", Object.keys(repos).length)
  }

  property Process updateCheckProcess: Process {
    onExited: function(exitCode) {
      console.log("updateCheckProcess onExited exitCode=", exitCode, "stdout=", (updateCheckStdout.text || "").substring(0, 200))
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
      console.log("updateProcess onExited exitCode=", exitCode, "id=", root.updatingId)
      root.onUpdateFinished(exitCode)
    }
    stdout: StdioCollector { id: updateStdout; waitForEnd: true }
    stderr: StdioCollector { id: updateStderr; waitForEnd: true }
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
      console.log("installLaunchProcess onExited exitCode=", exitCode)
    }
  }

  property Process removeProcess: Process {
    onExited: function(exitCode) {
      console.log("removeProcess onExited exitCode=", exitCode)
      root.onRemoveFinished(exitCode)
    }
    stdout: StdioCollector { id: removeStdout; waitForEnd: true }
    stderr: StdioCollector { id: removeStderr; waitForEnd: true }
  }

  // Launches the detached shell restart. The shell dies mid-command, so the
  // work runs setsid/nohup from a short-lived Process that exits immediately.
  property Process restartShellProcess: Process {
    onExited: function(exitCode) {
      console.log("restartShellProcess onExited exitCode=", exitCode)
    }
  }

  // Accepts either a bare git URL or a full `omarchy plugin add <url>`
  // command. Returns the URL token, or "" if none can be found.
  function extractInstallUrl(text) {
    var t = String(text || "").trim()
    if (t === "") return ""
    // Bare URL (possibly with .git): return it as-is.
    if (t.indexOf("://") !== -1 && t.indexOf(" ") === -1) return t
    if (t.indexOf("git@") === 0 && t.indexOf(" ") === -1) return t
    // Full command: pick the first token that looks like a URL.
    var tokens = t.split(/\s+/)
    for (var i = 0; i < tokens.length; i++) {
      var tok = tokens[i]
      if (tok.indexOf("://") !== -1 || tok.indexOf("git@") === 0)
        return tok
    }
    return ""
  }

  // `--enable` in a pasted command is honored: the plugin is enabled after
  // install, matching `omarchy plugin add <url> --enable`.
  function installCommandHasEnable(text) {
    return /\s--enable\b/.test(" " + String(text || "").trim())
  }

  // Called from the install dialog: extract the URL, then ask whether to
  // enable the plugin after install. A `--enable` in a pasted command
  // pre-chooses the enable option.
  function requestInstall() {
    var url = root.extractInstallUrl(installUrlField.text)
    if (url === "") return
    root.installPendingUrl = url
    root.installPendingEnable = root.installCommandHasEnable(installUrlField.text)
    root.installConfirmOpen = true
  }

  function installPlugin() {
    var url = root.installPendingUrl
    if (url === "") return
    root.installShouldEnable = root.installPendingEnable
    root.installPendingId = ""
    root.installEnableAttempts = 0
    root.installConfirmOpen = false
    root.installRunning = true
    root.installFailed = false
    root.installResult = "Installing " + url + "…"
    root.startDetachedInstall(url)
  }

  // Launch the detached helper. `omarchy plugin add` reloads plugins when it
  // finishes, which unloads this panel; the helper is started with
  // setsid/nohup so it survives and finishes the enable itself.
  function startDetachedInstall(url) {
    var helper = root.installHelperPath
    if (helper === "") {
      root.installFailed = true
      root.installResult = "Install helper not found"
      return
    }
    root.installStatusPath = "/tmp/fross-install-" + Date.now() + ".status"
    root.installDetachedRunning = true
    root.installResult = "Installing " + url + "…"
    var enableFlag = root.installShouldEnable ? "1" : "0"
    var launch = ["bash", "-c",
      "setsid nohup \"$0\" \"$1\" \"$2\" \"$3\" >/dev/null 2>&1 &",
      helper, url, root.installStatusPath, enableFlag]
    // Use a short-lived Process to fire the helper; it exits immediately.
    installLaunchProcess.command = launch
    installLaunchProcess.running = true
    installStatusFile.path = root.installStatusPath
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
    var lines = String(text).split("\n")
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
      root.installDetachedRunning = false
      root.installRunning = false
      root.installStatusPath = ""
      if (failed) {
        root.installFailed = true
        root.installResult = "Install failed"
      } else if (root.installShouldEnable && !enabled) {
        root.installFailed = true
        root.installResult = "Installed, but enabling failed"
      } else if (root.installShouldEnable) {
        root.installResult = "Installed and enabled."
      } else {
        root.installResult = "Installed. Review the code, then enable it in the list."
      }
      root.refreshPlugins()
    }
  }

  function refreshPlugins() {
    if (pluginListProcess.running) return
    listingPlugins = true
    var script = ""
      + "catalog=$(omarchy plugin catalog) || exit $?\n"
      + "listed=$(omarchy plugin list --json) || exit $?\n"
      + "jq -cn --argjson catalog \"$catalog\" --argjson listed \"$listed\" '\n"
      + "  $catalog | map(. as $plugin | (($listed | map(select(.id == $plugin.id)) | .[0]) // {}) as $state | $plugin + $state)\n"
      + "'"
    pluginListProcess.command = ["bash", "-c", script]
    pluginListProcess.running = true
  }

  function applyPluginList(text) {
    var plugins = []
    try {
      var parsed = JSON.parse(String(text || ""))
      if (Array.isArray(parsed)) plugins = parsed
    } catch (e) {
      console.warn("omaplug: could not parse plugin list:", e)
    }
    var rows = []
    for (var i = 0; i < plugins.length; i++) {
      var m = plugins[i]
      if (!m || typeof m !== "object") continue
      var id = String(m.id || "")
      if (id === "") continue
      var firstParty = m.firstParty === true
      var sourceDir = String(m.sourceDir || "")
      rows.push({
        id: id,
        name: m.name || id,
        version: m.version || "",
        author: m.author || "",
        description: m.description || "",
        kinds: (m.kinds || []).join(", "),
        enabled: m.enabled === true,
        firstParty: firstParty,
        sourceDir: sourceDir,
        sourceKey: sourceDir.replace(/\/+$/, "").split("/").pop() || id,
        updatable: !firstParty && sourceDir !== "",
        canDisable: m.canDisable !== false
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
    pluginToggleProcess.command = ["omarchy", "plugin", value ? "enable" : "disable", id]
    pluginToggleProcess.running = true
  }

  property Process pluginListProcess: Process {
    onExited: function(exitCode) {
      root.listingPlugins = false
      if (exitCode === 0) {
        root.pluginListAttempts = 0
        root.applyPluginList(pluginListStdout.text)
      } else if (root.pluginListAttempts < 3) {
        // During shell startup the panel can load just before the IPC endpoint
        // accepts requests. Retry briefly instead of presenting a blank list.
        root.pluginListAttempts++
        pluginListRetry.restart()
      } else {
        console.warn("omaplug: plugin list failed:", pluginListStderr.text)
      }
    }
    stdout: StdioCollector { id: pluginListStdout; waitForEnd: true }
    stderr: StdioCollector { id: pluginListStderr; waitForEnd: true }
  }

  Timer {
    id: pluginListRetry
    interval: 500
    repeat: false
    onTriggered: root.refreshPlugins()
  }

  property Process pluginToggleProcess: Process {
    onExited: function(exitCode) {
      if (exitCode !== 0) console.warn("omaplug: plugin toggle failed:", pluginToggleStderr.text)
      Qt.callLater(root.refreshPlugins)
    }
    stderr: StdioCollector { id: pluginToggleStderr; waitForEnd: true }
  }

  Component.onCompleted: {
    console.log("Panel.qml loaded, filterMode=", root.filterMode, "rows=", root.pluginRows.length)
    root.installHelperPath = String(Qt.resolvedUrl("install-helper.sh")).replace(/^file:\/\//, "")
    refreshPlugins()
  }

  // ------------------------------------------------------------- open / close

  function open() {
    refreshPlugins()
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
            required property var modelData
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
                tooltipText: "Select " + modelData.name
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
                    text: modelData.name
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                    Layout.fillWidth: true
                    elide: Label.ElideRight
                  }
                }

                Label {
                  text: modelData.description !== "" ? modelData.description : "No description"
                  color: Qt.darker(root.contentForeground, 1.6)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  Layout.fillWidth: true
                  wrapMode: Label.Wrap
                  maximumLineCount: 2
                  elide: Label.ElideRight
                }

                RowLayout {
                  spacing: Style.space(4)
                  Layout.fillWidth: true

                  Label {
                    visible: modelData.version !== "unknown"
                    text: "v" + modelData.version
                    color: Qt.darker(root.contentForeground, 2.0)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Label {
                    visible: modelData.author !== ""
                    text: "by " + modelData.author
                    color: modelData.firstParty
                      ? Style.selectedStateColor(root.contentForeground, Color.accent)
                      : Qt.darker(root.contentForeground, 2.0)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Label {
                    visible: modelData.kinds !== ""
                    text: "· " + modelData.kinds
                    color: Qt.darker(root.contentForeground, 2.0)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    Layout.fillWidth: true
                    elide: Label.ElideRight
                  }
                }
              }

              ColumnLayout {
                Layout.alignment: Qt.AlignVCenter
                spacing: Style.space(4)

                RowLayout {
                  Layout.alignment: Qt.AlignHCenter
                  spacing: Style.space(6)

                  Button {
                    visible: modelData.updatable
                      && root.pluginRepos[modelData.sourceKey] !== undefined
                    tooltipText: root.pluginRepos[modelData.sourceKey] !== undefined
                      ? String(root.pluginRepos[modelData.sourceKey]) : ""
                    text: "SOURCE \udb85\udd94"
                    bordered: true
                    foreground: root.contentForeground
                    accent: Color.accent
                    fontFamily: root.contentFontFamily
                    fontSize: Style.font.caption
                    iconSize: Style.font.caption
                    horizontalPadding: Style.space(6)
                    verticalPadding: Style.space(3)
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
            color: Style.selectedStateColor(root.contentForeground, Color.accent)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Label {
            visible: root.removeSummary !== ""
            text: root.removeSummary
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
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  Layout.fillWidth: true
                  elide: Label.ElideRight
                }

                Label {
                  text: root.updateStatusText(modelData.sourceKey)
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
            placeholderText: "https://github.com/acme/omarchy-weather.git or omarchy plugin add <url> --enable"
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
            text: "\"" + root.installPendingUrl + "\" will be added via `omarchy plugin add`. Do you want to enable it right after installing?"
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
              onClicked: {
                root.installPendingEnable = false
                root.installPlugin()
              }
            }

            Button {
              text: "Install & Enable"
              bordered: true
              foreground: root.contentForeground
              accent: Color.accent
              fontFamily: root.contentFontFamily
              fontSize: Style.font.bodySmall
              horizontalPadding: Style.space(12)
              verticalPadding: Style.space(6)
              onClicked: {
                root.installPendingEnable = true
                root.installPlugin()
              }
            }
          }
        }
      }
    }
  }
}

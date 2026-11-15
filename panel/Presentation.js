.pragma library

function marketplaceUrl(pluginId) {
  return "https://plugins.omarchy.org/plugin.html?id=" + encodeURIComponent(String(pluginId))
}

function listingChecksUrl(pluginId) {
  return marketplaceUrl(pluginId) + "#verification"
}

function shortSha(sha) {
  var value = String(sha || "")
  return value.length > 7 ? value.substring(0, 7) : value
}

function normalizedGitHubUrl(repoUrl) {
  var url = String(repoUrl || "").trim()
  var match = url.match(/^(?:https:\/\/github\.com\/|git@github\.com:|ssh:\/\/git@github\.com\/)([A-Za-z0-9][A-Za-z0-9_.-]*)\/([A-Za-z0-9][A-Za-z0-9_.-]*?)(?:\.git)?\/?$/)
  if (!match || match[1].indexOf("..") !== -1 || match[2].indexOf("..") !== -1) return ""
  return "https://github.com/" + match[1] + "/" + match[2]
}

function commitUrl(repoUrl, sha) {
  var url = normalizedGitHubUrl(repoUrl)
  var commit = String(sha || "")
  return url !== "" && commit !== "" ? url + "/commit/" + commit : ""
}

function authorUrl(repoUrl) {
  var match = normalizedGitHubUrl(repoUrl).match(/^https:\/\/github\.com\/([^\/]+)/)
  return match ? "https://github.com/" + match[1] : ""
}

function compareUrl(repoUrl, fromSha, toSha) {
  var url = normalizedGitHubUrl(repoUrl)
  var from = String(fromSha || "")
  var to = String(toSha || "")
  if (url === "" || from === "" || to === "" || from === to) return ""
  return url + "/compare/" + from + "..." + to
}

// Catalog release links are remote input and go straight to the browser, so
// only https GitHub URLs are eligible.
function releaseUrl(url) {
  var value = String(url || "").trim()
  if (value.length > 512) return ""
  return /^https:\/\/github\.com\/[A-Za-z0-9][A-Za-z0-9_.-]*\/[A-Za-z0-9][A-Za-z0-9_.-]*\/[^\s"'<>]*$/.test(value)
    ? value : ""
}

// Qt's attached ToolTip text is AutoText, so manifest-derived text must reach
// it markup-free or an <img> tag loads a remote resource on hover. Stray angle
// brackets go too: Qt only treats text as rich if it can find a tag.
function tooltipText(value) {
  return String(value || "")
    .replace(/<[^>]*>/g, "")
    .replace(/[<>\u0000-\u001f\u007f]/g, " ")
    .slice(0, 512)
}

function kindLabel(kinds, knownKinds) {
  if (!kinds) return ""
  var parts = String(kinds).split(",")
  var labels = []
  for (var i = 0; i < parts.length; i++) {
    var kind = parts[i].trim()
    if (kind === "") continue
    var label = kind
    for (var j = 0; j < knownKinds.length; j++) {
      if (knownKinds[j].value === kind) {
        label = knownKinds[j].label
        break
      }
    }
    labels.push(label)
  }
  return labels.join(", ").toUpperCase()
}

function iconColor(name) {
  var value = String(name || "")
  var hash = 0
  for (var i = 0; i < value.length; i++) hash = (hash * 31 + value.charCodeAt(i)) | 0
  var palette = [
    "#c0392b", "#2980b9", "#27ae60", "#d35400", "#8e44ad",
    "#16a085", "#e67e22", "#2c3e50", "#c0272f", "#21618c",
    "#1e8449", "#b9770e", "#7d3c98", "#117a65", "#ca6f1e"
  ]
  return palette[Math.abs(hash) % palette.length]
}

function commitVerification(entry, commit) {
  if (!entry) return "Not listed"
  if (!entry.verified && entry.snapshotStatus !== "update-unverified") return "Unverified"
  if (!/^[0-9a-f]{40}$/.test(String(commit || ""))
      || !/^[0-9a-f]{40}$/.test(String(entry.snapshotCommit || ""))) return "Verification unavailable"
  return entry.verified && commit === entry.snapshotCommit ? "Verified" : "Update Unverified"
}

function bulkUpdateKeys(rows, states, marketplace, scope, incomingCommits) {
  var sources = Object.create(null)
  var keys = []
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i]
    var key = String(row.sourceKey || "")
    if (!key || states[key] !== "UPDATE") continue
    var entry = marketplace[String(row.id)]
    var status = commitVerification(entry, (incomingCommits || {})[key])
    var allowed = scope === "all" || status === "Verified"
      || (scope === "pending" && status === "Update Unverified")
    if (sources[key] === undefined) {
      keys.push(key)
      sources[key] = true
    }
    // A repository updates as a unit: every plugin it contains must qualify.
    sources[key] = sources[key] && allowed
  }
  return keys.filter(function(key) { return sources[key] })
}

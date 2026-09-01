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
  var url = String(repoUrl || "")
  if (!/^https:\/\/github\.com\//.test(url)) return ""
  return url.replace(/\.git\/?$/, "").replace(/\/+$/, "")
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

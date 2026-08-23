# 🧩 Omaplug

**A small tool for managing your Omarchy plugins.**

[![Marketplace](https://img.shields.io/badge/Omarchy_Marketplace-listed-blue)](https://omarchyplugins.com/plugin.html?id=omaplug) [![Verified](https://img.shields.io/badge/Automated_Security_Baseline-verified-brightgreen)](https://github.com/HANCORE-linux/omarchy-plugin-marketplace/blob/main/SECURITY.md#automated-security-baseline)

Access it right from the Omarchy bar — it gives you a centralized place to view and organize the plugins you have installed. Here are a few things you can use it for:

- Easily turn individual plugins on or off as needed.
- Check for available updates and update them individually — or all at once.
- Remove plugins individually, or several in one go.
- Jump straight to each plugin's repo, or browse the [Omarchy marketplace](https://omarchyplugins.com).

Omaplug is listed on the marketplace: [omarchyplugins.com/plugin.html?id=omaplug](https://omarchyplugins.com/plugin.html?id=omaplug)

## Screenshots

![Omaplug preview](preview.png)

<table>
  <tr>
    <td align="center"><img src="preview_main.png" alt="Main plugin list" width="280"/></td>
    <td align="center"><img src="preview_check-update.png" alt="Checking for updates" width="280"/></td>
    <td align="center"><img src="preview_add.png" alt="Installing a plugin" width="280"/></td>
  </tr>
  <tr>
    <td align="center">Plugin list</td>
    <td align="center">Checking for updates</td>
    <td align="center">Installing a plugin</td>
  </tr>
  <tr>
    <td align="center"><img src="preview_filter.png" alt="Scope filter" width="280"/></td>
    <td align="center"><img src="preview_filter_2.png" alt="Type filter" width="280"/></td>
    <td align="center"><img src="preview_action.png" alt="Row action menu" width="280"/></td>
  </tr>
  <tr>
    <td align="center">Scope filter</td>
    <td align="center">Type filter</td>
    <td align="center">Row action menu</td>
  </tr>
</table>

## What it can do

- **🔌 Enable / disable** — every discovered plugin (Omarchy's own and third-party) gets a simple toggle. Flipping it goes through the same registry the `omarchy plugin enable/disable` command uses, so what you see here is always what's really running.
- **🔄 Check for updates** — scans every git-managed plugin, peeks at its remote, and tells you per plugin if it's *Up to date*, an *Update is available*, or something went *wrong* — streamed live as it checks.
- **⬆️ Update (or update everything)** — apply one update, or blast through every plugin with a pending update in a single click.
- **➕ Install** — paste a git repo URL and add a plugin in one step. It'll warn you first that plugins run as unsandboxed code, because honesty is the default here.
- **🗑️ Remove** — third-party plugins only. Trash one, or enter Select mode to check several and remove them all at once (with a confirmation, no accidents).
- **🔗 Source link** — every git-managed plugin gets a `SOURCE` button that jumps straight to its repo page.
- **🔍 Search & filter** — narrow the list to Omarchy plugins, third-party plugins, or search by name, description, ID, author, or kind.
- **♻️ Restart shell** — if a plugin ever acts up from stale compiled code, one button clears the QML cache and restarts the shell so everything reloads fresh.

## Install

```bash
omarchy plugin add https://github.com/fross100/omaplug --enable
```

## Remove

```bash
omarchy plugin remove omaplug
```

## Remove manually

No terminal? No problem — or maybe you just like doing things the hands-on way. Here's how to remove it by hand:

1. Delete the plugin folder:

```bash
rm -rf ~/.config/omarchy/plugins/omaplug
```

2. Remove the `"id": "omaplug"` entry from the bar layout in `~/.config/omarchy/shell.json`.

3. Restart the shell to apply:

```bash
omarchy-restart-shell
```

## Requirements

- Omarchy 4.x
- Quickshell
- `git`, `jq`, and the `omarchy` CLI
- Standard coreutils (`setsid`, `nohup`, `timeout`, `sed`)

## License

[MIT](LICENSE) © 2026 Fross
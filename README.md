# Espanso for Omarchy Top Bar

Control [Espanso](https://espanso.org/) directly from the Omarchy status bar.

## Features

- **Status & One-Click Toggle:** View daemon health and instantly enable or disable text expansions with a toggle switch.
- **Lost-Keyboard Detection:** Espanso's Wayland backend never rescans input devices, so after a monitor USB hub power-cycles (display sleep, cable reseat, KVM switch, dock) it keeps reporting "running" while it no longer sees keystrokes. The plugin spots this in the journal, turns the bar icon urgent, and explains it in the panel.
- **Restart & Logs:** Restart the `espanso` user service or follow its journal from the panel, without opening a terminal.
- **Native Search Launcher:** Open Espanso's native GUI modal (`espanso cmd search`) to search and inject snippets into active windows.
- **In-Panel Snippet Explorer:** Instant live filtering and preview of all defined matches (sorted alphabetically A-Z); click any snippet to copy its replacement text to the clipboard.
- **Bar Shortcuts:**
  - **Left-Click:** Open/close the dropdown panel.
  - **Right-Click:** Instantly trigger native search.
  - **Middle-Click:** Instantly toggle expansions on/off.

## Dependencies

- `espanso` or `espanso-wayland`, running as the `espanso` systemd user service (what the install helper sets up)
- `wl-clipboard` (for snippet clipboard copying)
- `journalctl`, `pgrep`, `ps` (present on any Omarchy install; used for the health check)

## Installation

```bash
omarchy plugin add https://github.com/taisau/omarchy-espanso.git --enable
```

Or manually clone into your user plugins:

```bash
git clone https://github.com/taisau/omarchy-espanso.git ~/.config/omarchy/plugins/io.github.taisau.espanso
```

And add to `~/.config/omarchy/shell.json` in `bar.layout.right`:

```json
{ "id": "io.github.taisau.espanso" }
```

## Removal

```bash
omarchy plugin remove io.github.taisau.espanso
```

## License

MIT

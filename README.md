# Espanso for Omarchy Top Bar

Control [Espanso](https://espanso.org/) directly from the Omarchy status bar.

## Features

- **Status & One-Click Toggle:** View daemon health and instantly enable or disable text expansions with a toggle switch.
- **Native Search Launcher:** Open Espanso's native GUI modal (`espanso cmd search`) to search and inject snippets into active windows.
- **In-Panel Snippet Explorer:** Instant live filtering and preview of all defined matches (sorted alphabetically A-Z); click any snippet to copy its replacement text to the clipboard.
- **Bar Shortcuts:**
  - **Left-Click:** Open/close the dropdown panel.
  - **Right-Click:** Instantly trigger native search.
  - **Middle-Click:** Instantly toggle expansions on/off.

## Dependencies

- `espanso` or `espanso-wayland`
- `wl-clipboard` (for snippet clipboard copying)

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

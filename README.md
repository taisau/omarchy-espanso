# Espanso for Omarchy Top Bar

Control [Espanso](https://espanso.org/) directly from the Omarchy status bar.

## Features

- **Status & One-Click Toggle:** View daemon health and instantly enable or disable text expansions with a toggle switch.
- **Native Search Launcher:** Open Espanso's native GUI modal (`espanso cmd search`) to search and inject snippets into active windows.
- **In-Panel Snippet Explorer:** Instant live filtering and preview of all defined matches; click any snippet to copy its replacement text to clipboard.
- **Quick Controls:** Fast access to open your `~/.config/espanso` folder, edit `base.yml`, restart the service, or tail daemon logs.
- **Bar Shortcuts:**
  - **Left-Click:** Open/close the dropdown panel.
  - **Right-Click:** Instantly trigger native search.
  - **Middle-Click:** Instantly toggle expansions on/off.

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

## License

MIT

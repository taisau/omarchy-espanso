# Espanso for Omarchy Top Bar

Control [Espanso](https://espanso.org/) directly from the Omarchy status bar.

## Features

- **Status & One-Click Toggle:** View daemon health and instantly enable or disable text expansions with a toggle switch.
- **Native Search Launcher:** Open Espanso's native GUI modal (`espanso cmd search`) to search and inject snippets into active windows.
- **In-Panel Snippet Explorer:** Instant live filtering and preview of all defined matches (sorted alphabetically A-Z); click any snippet to copy its replacement text to the clipboard.
- **Manage simple expansions:** Use **New** to add a trigger and replacement. The form offers a **Word match** switch for each expansion. Expansions created here have Edit and Delete actions. A confirmation appears before deletion.
- **Bar Shortcuts:**
  - **Left-Click:** Open/close the dropdown panel.
  - **Right-Click:** Instantly trigger native search.
  - **Middle-Click:** Instantly toggle expansions on/off.

## Dependencies

- `espanso` or `espanso-wayland`
- `wl-clipboard` (for snippet clipboard copying)
- Python 3 (for safe, atomic edits to the panel's managed match file)

## Managed matches

The panel writes only `~/.config/espanso/match/omarchy-plugin.yml`. This file is JSON-formatted YAML that Espanso reads normally. Other Espanso matches remain visible in the panel and can still be copied, but their files are never modified by the panel. The managed file supports simple `trigger` and `replace` rules, a per-match `word` boolean, and multiline replacement text. Word matches use Espanso's configured word separators. Advanced matches with variables or forms should be edited in their own Espanso files.

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

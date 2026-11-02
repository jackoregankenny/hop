# Configuring Hop (for agents)

Hop is configured by one JSON file and no database. Its Settings window is only a face on that
file (it rewrites it with sorted keys), so you never need to drive the UI. Edit the file, run the
check, done: Hop applies saved changes immediately, no restart.

- Config: `~/.config/hop/config.json` (or `$HOP_HOME/config.json`). Missing file = defaults.
- Scripts: `~/.config/hop/scripts/` (executables, see below).
- Validate: `/Applications/Hop.app/Contents/MacOS/Hop --check`. Prints `error:` / `warning:` lines
  and `ok: …`. Exit 0 = valid, 1 = errors. Fix every `error:` line; `warning:` lines are hotkeys
  bound to names that do not exist yet (for example an app that is not installed).
- Inspect: `Hop --menu` prints the menu-bar menu, the feature switches and every registered hotkey.
- Feature switches (Window Snapping, Clipboard History, Browser Tabs, Exchange Rates, File Search,
  Check for Updates) live in Settings › General, not in the file:
  `defaults write dev.hop.launcher feature.<name> -bool false` with name one of
  windowSnapping, clipboardHistory, browserTabs, exchangeRates, fileSearch, automaticUpdates
  (the key behind Check for Updates). Hop picks it up the next time its panel opens.
- Updates are never installed on their own: Hop only checks. Installing is the user's choice
  (**Update to X…** in the menu, or ⌘U in the panel).

## config.json

Every key is optional. Unknown keys are errors.

```json
{
  "hotkeys": { "ctrl+opt+v": "Clipboard History", "ctrl+opt+s": "Slack", "cmd+space": "none" },
  "snippets": [ { "name": "Sign-off", "keyword": "sig", "text": "Thanks,\n{clipboard}" } ],
  "quicklinks": [ { "name": "npm", "key": "npm", "url": "https://www.npmjs.com/search?q={query}" } ],
  "theme": { "preset": "midnight", "accent": "#7c8cff" },
  "snapGap": 0
}
```

### hotkeys: `{ "combo": "action" }`

- Combo: modifiers `cmd` `opt` `ctrl` `shift` joined with `+`, then one key: `a`–`z`, `0`–`9`,
  `left` `right` `up` `down` `return` `space` `tab` `escape` `delete` `minus` `equal` `comma`
  `period` `slash` `semicolon` `f1`–`f6`.
- Action: `show` (open Hop), or the exact name of anything Hop lists: a command (`Clipboard History`,
  `Toggle Dark Mode`, `Lock Screen`…), a window action (`Left Half`, `Top Left Quarter`,
  `Center Third`, `Maximize`, `Restore Window`, `Next Display`…), an app (`Slack`), a snippet name,
  a script title or a quicklink name. Case does not matter.
- Your entries are added on top of the defaults. `"none"` turns a default off.
- Defaults: `cmd+space` and `opt+space` open Hop; window snapping uses Rectangle's layout
  (`ctrl+opt+left/right/up/down` halves, `ctrl+opt+u/i/j/k` quarters, `ctrl+opt+d/f/g` thirds,
  `ctrl+opt+e/t` two thirds, `ctrl+opt+return` maximize, `ctrl+opt+c` center,
  `ctrl+opt+delete` restore, `ctrl+opt+cmd+left/right` displays).

### snippets: `[{ "name", "keyword"?, "text" }]`

Typing the name or keyword in Hop pastes `text`. Placeholders: `{date}` `{time}` `{datetime}`
`{clipboard}`. Needs `text` and one of `name` / `keyword`.

### quicklinks: `[{ "name", "url", "key"? }]`

Shown as **Bookmarks** in Settings and the launcher.

A URL with `{query}` becomes a search: typing `key something` opens it with `something`. Without
`{query}` it is a plain link listed by name.

### theme: preset name, or `{ "preset", …overrides }`

| Key | Values |
|---|---|
| preset | default, compact, midnight, graphite, paper, terminal |
| appearance | auto, dark, light |
| blur | auto (Liquid Glass on macOS 26, blur before), glass, clear, popover, hud, sidebar, menu, none |
| background, accent | `#rgb`, `#rrggbb`, `#rrggbbaa` (background tints the glass or blur) |
| font | system, rounded, mono, serif, or an installed font name |
| fontSize 11–22, width 480–1400, rows 3–14, rowHeight 32–80, radius 0–32 | numbers |

### snapGap

Points of space around snapped windows. Number, default 0.

## Scripts: `~/.config/hop/scripts/`

Any executable with metadata comments. Raycast's script-command format works unchanged; `@hop.`
works the same as `@raycast.`.

```sh
#!/bin/sh
# @raycast.title What's on Port
# @raycast.mode fullOutput          # silent | compact | inline | fullOutput
# @raycast.icon 🔌
# @raycast.argument1 { "type": "text", "placeholder": "port" }
lsof -nP -iTCP:"$1" -sTCP:LISTEN
```

Required: `title`. A script with `argument1` runs from a query like `port 3000`. Scripts get a
PATH with Homebrew, run from their folder, and are stopped after 30 s.

## Ground rules

- Keep the file valid JSON and run `--check` after every edit.
- Do not write anything else into `~/.config/hop/`; Hop only reads `config.json` and `scripts/`.
- Clipboard history and usage data are never written to this folder.

# Hop

A ⌘Space launcher for macOS in plain Swift + AppKit: about 500 KB, no dependencies, no runtime.
It reaches into what macOS already exposes (Accessibility, CoreAudio, IOKit,
Dictionary Services, Spotlight, Apple Events, the `shortcuts` CLI) instead of shipping its own.

Looking for tiling? That's a separate app: [Tiles](https://github.com/jackoregankenny/tiles).

Configured by one plain JSON file that applies the moment it's saved, and `Hop --check` validates
it, so you or an agent can set it up by editing text. [AGENTS.md](AGENTS.md) is the reference.

## Install

Download `Hop.zip` from the [latest release](https://github.com/jackoregankenny/hop/releases/latest),
unzip, and move it to `/Applications`. The build is not notarized, so clear the download flag once:

```sh
xattr -dr com.apple.quarantine /Applications/Hop.app
```

Hop checks GitHub Releases every few hours but never installs on its own. When there is a new
version, the menu-bar icon gets a small dot and a brief glint, and the panel's footer says
"Update to X available · ⌘U". Press ⌘U, or choose **Update to X…** in the menu, and Hop installs it,
only if the download's SHA-256 matches the release and its bundle id and version are right, then
restarts. Turn the checks off with **Check for Updates** in Settings. Releases are signed with a
Developer ID, so Accessibility and other permissions carry over from one version to the next.

App icons are drawn once into small PNGs in `~/Library/Caches/dev.hop.launcher/icons` (about
1 MB for 130 apps, refreshed when an app updates), so results never wait on icon loading. It's a
cache: deleting it is safe.

## Build from source

Needs only the Xcode command line tools.

```sh
./build.sh          # builds build/Hop.app
./build.sh test     # self-test
./build.sh snaptest # presses the real snap hotkeys on a throwaway Finder window and checks where it lands
open build/Hop.app
./build.sh release 0.3.0   # test, sign with your Developer ID, notarize, tag and publish (from your Mac)
```

Source builds are version `dev` and never update themselves.


⌥Space opens it. ⌘Space works once Spotlight's shortcut is off (System Settings → Keyboard →
Keyboard Shortcuts → Spotlight). Window actions, menu search, window switching, media keys and
paste need Accessibility: run **Grant Accessibility Access** from the launcher. Dev builds are
ad-hoc signed and get a new identity on every rebuild, so macOS asks again for those; releases keep theirs.

## What you can type

| Type | Get |
|---|---|
| `vsc`, `saf`, `spotfy` | apps by prefix, initials, typos. Learns what you use (see Ranking) |
| a window or tab title | switch to any open window (all apps), or any tab in Safari, Orion, Chrome, Arc, Brave, Edge |
| a menu command, e.g. `export pdf` | runs that item from the frontmost app's menu bar |
| `left half`, `top left quarter`, `center third`, `max`… | snap the focused window (also on global hotkeys, below) |
| `wifi`, `bluetooth`, `displays`, `dock` | System Settings panes |
| `speakers`, `airpods`, `microphone` | switch sound output and input |
| `12*7+3`, `5 km to mi`, `100 usd to eur` | math, units, live ECB rates. ↵ copies, ⌘↵ pastes |
| `time in tokyo`, `sf time`, `1700000000` | world clock, unix timestamps |
| `define serendipity` | the built-in macOS dictionary, offline |
| `:fire` | emoji by name, ↵ pastes |
| `clip`, `clip foo` | clipboard history: text and images, including what dictation apps like Wispr Flow paste (memory only, skips password-manager copies), ↵ pastes |
| `quit slack`, `kill node` | quit or force quit running apps |
| `battery`, `vol 30`, `mute`, `keep awake`, `lock` | system controls |
| your Shortcuts by name | runs them through the Shortcuts app |
| `yt`, `gh`, `x`, `wiki`, `maps`, `r` + query | site search; add your own as bookmarks with `{query}` |
| a question, or anything not on the Mac | one **Search Google** row, placed by intent (see Ranking) |

Keys: ↑↓ move, ↵ run, ⌘↵ alternate (reveal, copy, paste), ⌘1–9 run a row, Tab completes, Esc clears then closes.

## Ranking

Real names beat keywords, and Hop's own commands (Settings, Edit Config, Quit…) rank below
your apps and System Settings, so `settings` opens macOS settings, not Hop's.

On top of that it learns: everything you open (apps, commands, settings, files, bookmarks) gets a
score that halves every week, so what you use often rises above a closer-matching name you never
open, and what you stopped using fades. It also remembers what you picked for
each query (`s` → Slack); a new choice takes over after a pick or two. All of it is a few
numbers in Hop's preferences, nothing leaves the Mac.

There is a single web row and no autocomplete. It goes **first** when the query reads like a
question (`how do i…`, `why…`, `best…`, a `?`, four or more words) or nothing here matches well,
and **last** when something on the Mac clearly does. Menu items of the front app only show when
they are about as good as the best match, so `slack` lists Slack, not *Hide Slack* and *Quit Slack*.

Files follow the same idea. Spotlight indexes everything, so Hop keeps only files a person
would look for: ones you have opened (macOS records that; generated, cloned and unzipped files
never get it), ranked by how recently, plus new files near the top of Desktop, Documents and
Downloads. Never-opened source code, JSON, logs, test fixtures, `node_modules`, build output,
hidden folders and `~/Library` stay out.

## Settings

**Settings…** in the ⚡ menu-bar menu (or `hop settings` in the launcher) opens a small window
that writes straight to config.json, so the file stays the one source of truth: edit there, here,
or let an agent do it.

- **General**: the feature switches, Launch at Login, theme and appearance. Off means off: no
  hotkeys, timers, network or Apple Events, not just hidden results.
  - **Window Snapping**: every window command and every hotkey bound to one, including your own
  - **Clipboard History**: stops the clipboard poller and forgets what it held
  - **Browser Tabs**, **Exchange Rates** (the only network call Hop makes), **File Search**, **Check for Updates**
- **Hotkeys**: every shortcut; click one and press a new combination, pick the action from the list,
  + and − to add or remove. Only differences from the defaults are written.
- **Bookmarks**: name, keyword and URL. A URL with `{query}` becomes a search (`npm react`).
  **Add Current Page** saves the front tab of whichever browser window is nearest the front.
- **Snippets**: name, keyword and the text itself, or **Add Clipboard**.

Saving pages also works from anywhere: **Save Current Page** in the launcher (`bookmark`) or
**Save Current Page as Bookmark** in the menu. The menu also pastes snippets directly.

## Themes

A `"theme"` key in config.json: a preset name, or a preset plus overrides. No CSS, just the Mac's
own blur materials and a few numbers.

```json
"theme": "midnight"
"theme": { "preset": "paper", "accent": "#2563eb", "fontSize": 16, "width": 820 }
```

Presets: `default`, `compact`, `midnight`, `graphite`, `paper`, `terminal`. Keys: `appearance`
(auto, dark, light), `blur` (auto, glass, clear, popover, hud, sidebar, menu, none; `auto` is
Liquid Glass on macOS 26 and the classic blur before it), `background` and `accent`
(`#rrggbb` or `#rrggbbaa`), `font` (system, rounded, mono, serif, or a font name), `fontSize`,
`width`, `rows`, `rowHeight`, `radius`. Changes apply when you save.

## Snippets

Text you paste from the launcher: type a snippet's name or keyword, ↵ pastes it into the app you
were in, ⌘↵ copies. Placeholders: `{date}`, `{time}`, `{datetime}`, `{clipboard}`. Snippet names can
be bound to hotkeys like any other command.

```json
"snippets": [
  { "name": "Sign-off", "keyword": "sig", "text": "Thanks,\nSam" },
  { "name": "Markdown link from clipboard", "keyword": "mdl", "text": "[link]({clipboard})" }
]
```

## Window snapping

Works from the launcher or from global hotkeys with no setup, using Rectangle's layout so the
muscle memory carries over. Switch it all off in Settings › General. Pressing Left or Right Half again cycles ½ → ⅔ → ⅓.

| Keys | Action |
|---|---|
| ⌃⌥ ← → ↑ ↓ | left, right, top, bottom half |
| ⌃⌥ U I J K | top left, top right, bottom left, bottom right quarter |
| ⌃⌥ D F G | left, center, right third |
| ⌃⌥ E T | left, right two thirds |
| ⌃⌥↩ · ⌃⌥⇧↑ · ⌃⌥C | maximize · maximize height · center |
| ⌃⌥= · ⌃⌥- | make larger · make smaller |
| ⌃⌥⌫ | restore the window's previous frame |
| ⌃⌥⌘ ← → | previous, next display |

Launcher-only: Center Half, Almost Maximize, Move Left/Right/Up/Down (to the edge, keeping size).
Bind any of them in the config.

## Config: `~/.config/hop/config.json`

Settings edits this file for you; **Edit Hop Config** opens it directly (with an example the first time). Saved changes apply immediately, and
`Hop --check` (the binary is in `Hop.app/Contents/MacOS/`) reports any mistakes with exit code 1.
Your hotkeys are added on top of the defaults; any command title can be bound, and `"none"` turns
a default off. Full reference: [AGENTS.md](AGENTS.md).

```json
{
  "hotkeys": { "ctrl+opt+v": "Clipboard History", "ctrl+opt+shift+left": "Move Left", "cmd+space": "none" },
  "snapGap": 0,
  "quicklinks": [ { "name": "npm", "key": "npm", "url": "https://www.npmjs.com/search?q={query}" } ]
}
```

## Plugins: script commands

Drop executables in `~/.config/hop/scripts`. The header uses Raycast's script-command format,
so scripts written for it run unchanged (`@hop.*` works too). See `scripts/` for examples.

```sh
#!/bin/sh
# @raycast.title What's on Port
# @raycast.mode fullOutput          # silent | compact | inline | fullOutput
# @raycast.argument1 { "type": "text", "placeholder": "port" }
lsof -nP -iTCP:"$1" -sTCP:LISTEN
```

Typing `port 3000` runs it with `3000`; output shows in the panel, ↵ copies a line.

Flags: `--check` (validate config), `--menu` (print the menu, feature switches and hotkeys), `--update-now`. Dev builds
(`./build.sh`) also compile `tests/` and add `--selftest`, `--probe` (read-only report of what it can
see) and, for screenshots, `--show --query "text" --snapshot out.png` (with `HOP_FAKE_UPDATE=0.9.9` to
show the update cues); release builds leave them out.

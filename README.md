# App themes for Omarchy

Choose the Omarchy theme for each app independently — or leave an app with its
native look.

The main reason this exists: Omarchy enforces a browser color policy on
Chromium-family browsers. Chrome, Edge, and Brave then show **“Your browser is
managed by your organization”** and lock the theme picker. Setting the browser
to **Native** removes that policy, while every other app keeps following
Omarchy.

## Features

- **Per-app choice:** follow the current Omarchy theme, use the app's native
  look, or pin a different Omarchy theme to that one app.
- **Global switch:** pause all per-app choices and make every app follow
  Omarchy. Your saved choices return when you turn it back on.
- **All apps:** apply one theme everywhere, follow Omarchy everywhere, or make
  every app native in one action.
- **Search every app:** the app list uses the same desktop entries as Omarchy's
  launcher, so it includes Files, Zed, and every other installed app. The list
  is scrollable; supported apps come first, followed by apps that follow the
  system GTK theme. The theme list is searchable too.
- **Browsers:** controls Chromium, Google Chrome, Microsoft Edge, and Brave.
  Native mode removes the `BrowserThemeColor` policy that triggers Chrome’s
  “set by your organization” message.
- **Apps:** browsers, Alacritty, Foot, Kitty, Ghostty, btop, Helix, Neovim,
  tmux, VS Code (Code, Insiders, VSCodium, Cursor), Zed, Obsidian, Claude Code,
  Pi, T3 Code, and Hermes.
- **Survives theme switches:** a small theme-set hook reapplies your choices
  after Omarchy finishes setting a new theme.
- **Reset:** one click restores every app to Omarchy defaults. This also
  restores Omarchy’s browser policy; choose **Native** for browsers afterward if
  you want to keep them unmanaged.
- **Bar widget:** click the brush icon, press `Super + Shift + A`, or run
  `omarchy-shell shell toggle io.github.anishvarsha.app-theme` to change an
  app, pick a theme, or reset.

## Install

```sh
omarchy plugin add https://github.com/anishvarsha/omarchy-app-theme.git --enable
```

Or add it first and review the code before enabling:

```sh
omarchy plugin add https://github.com/anishvarsha/omarchy-app-theme.git
omarchy plugin enable io.github.anishvarsha.app-theme --section right
```

### Browser control (one-time setup)

Changing browser theming needs to edit root-owned policy files. The widget
offers a **Set up** button the first time; it runs a one-time `pkexec` helper
that installs:

- `/usr/local/bin/omarchy-app-theme-browser` — a small root-owned script that
  can only remove the browser color policy or write one validated color.
- `/etc/sudoers.d/omarchy-app-theme-browser` — a passwordless rule for **that
  helper only**, so later theme switches do not ask for a password.

You can also run the setup from a terminal:

```sh
pkexec ~/.config/omarchy/plugins/io.github.anishvarsha.app-theme/bin/install-privileged.sh
```

### Optional command line

The widget installs the theme hook automatically, so nothing else is required
for per-app themes to survive theme switches. To also get the
`omarchy-app-theme` command:

```sh
ln -s ~/.config/omarchy/plugins/io.github.anishvarsha.app-theme/bin/omarchy-app-theme ~/.local/bin/omarchy-app-theme
```

## Use

Click the brush in the bar, or press `Super + Shift + A`:

- **Search** — type in the search box to filter all installed apps. Files and
  other apps without an adapter are listed under **Other installed apps** and
  follow the system GTK theme.
- **Per-app theming switch** — turn every override off and make every app
  follow Omarchy. Turning it back on restores the saved choices.
- **App row** — open that app’s settings.
- **All apps** — apply a theme to every app, or switch all apps to Omarchy or
  native mode at once.
- **Follow Omarchy** — normal Omarchy theming.
- **Native look** — remove Omarchy theming for that app. For Claude Code, Pi,
  T3 Code, and Hermes this clears the Omarchy theme and restores the app’s
  default look.
- **A theme name** — pin that theme to the app, even when you switch the
  desktop to another theme.
- **Reset everything to Omarchy defaults** — puts every app back on the
  current Omarchy theme and removes override files.

The same settings live in `~/.config/omarchy/app-theme/config.conf`:

```ini
enabled=true
browser=off
btop=catppuccin
nvim=tokyo-night
tmux=catppuccin
terminal=default
kitty=tokyo-night
claude=gruvbox
pi=default
```

Values are `default`, `off`, or a theme slug such as `catppuccin`. `terminal`
sets all four terminals; a per-terminal line overrides it. `enabled=false`
pauses every per-app choice and applies Omarchy everywhere. After editing, run
`omarchy-app-theme apply`, or just reopen the widget.

## How it works

Omarchy writes app configs into `~/.local/state/omarchy/current/theme/`. The
engine points each app at either that live theme, removes/neutralizes its
include, or renders another theme with Omarchy’s own
`omarchy-theme-set-templates` in a throwaway `HOME` and points the app there.

Neovim uses Omarchy’s `~/.config/nvim/lua/plugins/theme.lua` link. tmux is
applied live through Omarchy’s tmux script; while tmux is pinned, the plugin
keeps a small managed `run-shell` block in `tmux.conf` so the choice survives
starting a new tmux server.

Zed gets a generated custom theme in `~/.config/zed/themes/` and a managed
theme value in `~/.config/zed/settings.json`. The settings editor preserves
comments and trailing commas. Native mode removes the generated theme and
restores the theme value that was there before the plugin first changed it.

Claude Code, Pi, T3 Code, and Hermes use Omarchy’s own theme-set scripts. A
pinned theme is given to those scripts through a throwaway `HOME` pointing at
the rendered theme, while their real config directories are passed back
through `CLAUDE_CONFIG_DIR`, `T3CODE_HOME`, `HERMES_HOME`, or a symlinked
`~/.pi`. This keeps their native configuration and hot reload intact.

The theme-set hook is installed at
`~/.config/omarchy/hooks/theme-set.d/50-app-theme`. It runs after Omarchy’s own
post-theme commands, so it has the final say.

For browsers, Omarchy writes
`/etc/chromium/policies/managed/color.json` (and the Chrome/Edge/Brave
equivalents). Native mode removes those files. The root helper is deliberately
narrow: no arguments beyond `off` or `set <six hex digits>`, fixed paths, and
no shell evaluation.

## Remove

```sh
~/.config/omarchy/plugins/io.github.anishvarsha.app-theme/bin/omarchy-app-theme uninstall --purge
omarchy plugin remove io.github.anishvarsha.app-theme
```

`uninstall --purge` resets all apps to Omarchy defaults, removes the theme-set
hook, and deletes this extension’s config and state. It cannot remove the root
helper, so finish with:

```sh
sudo rm -f /usr/local/bin/omarchy-app-theme-browser
sudo rm -f /etc/sudoers.d/omarchy-app-theme-browser
```

If you installed the optional CLI symlink:

```sh
rm -f ~/.local/bin/omarchy-app-theme
```

## Notes

- The engine needs `bash`, `jq`, `flock`, `python3` (for Zed settings), and
  Omarchy’s theme commands.
- Apps that are not installed are skipped. Apps without an adapter, such as
  Files, are still listed in the panel but follow the system GTK theme.
- VS Code gets one extension containing every Omarchy theme, so switching
  between pinned themes applies immediately. Reload VS Code once after
  installing or updating this plugin (`Ctrl+Shift+P` → **Developer: Reload
  Window**) so it can discover that extension; after that, theme changes do not
  need a reload.
- Obsidian and Neovim are updated on disk; restart or reload them if they do
  not pick up the change.
- tmux is updated immediately when it is running. Starting tmux applies a
  pinned theme through the managed startup hook.
- Plugins run unsandboxed inside `omarchy-shell`. This one only runs the shell
  scripts in its own `bin/` directory and, for browser control, the privileged
  helper described above.

## License

MIT

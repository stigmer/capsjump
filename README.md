<p align="center">
  <img src="packaging/icon.svg" width="160" alt="CapsJump icon: the Caps Lock arrow leaping, with motion lines behind it">
</p>

<h1 align="center">CapsJump</h1>

<p align="center"><strong>Caps Lock finally has a job.</strong><br>Hold it and press a key to bring an app forward, land on a site in the right Chrome account, snap a window, or open a link.</p>

<p align="center">
  <a href="https://github.com/stigmer/capsjump/releases/latest"><img src="https://img.shields.io/github/v/release/stigmer/capsjump" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-0a0a0a" alt="macOS 13 or later">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-5c5c5c" alt="MIT license"></a>
</p>

<p align="center"><a href="https://stigmer.github.io/capsjump/">stigmer.github.io/capsjump</a></p>

Caps Lock has spent decades waiting for someone to SHOUT. CapsJump gives it a real job. Hold Caps Lock and press S: your terminal is just there. Caps Lock and G: the GitHub tab in your work Chrome account comes forward (not your personal one, never your personal one), or opens there if it isn't open yet. Caps Lock and ←: the front window takes the left half of the screen. Caps Lock and W: a Slack channel opens. One small file, `~/.capsjump.yaml`, says which key does what.

## Install

```sh
brew trust stigmer/tap
brew install --cask stigmer/tap/capsjump
capsjump setup
capsjump init
```

- `brew trust` is asked once per machine: Homebrew 7 loads casks only from taps you trust.
- `capsjump setup` asks for the app's permissions once (upgrades keep them) and starts CapsJump at login.
- `capsjump init` writes a starter `~/.capsjump.yaml` in your first Chrome account; `capsjump profiles` lists the others. Edit it, then run `capsjump check`.

## Configure

```yaml
sites:
- name: github
  account: you@work.com
  open: https://github.com/your-org/your-repo/pulls
  match: [github.com/your-org/your-repo/pulls, github.com/]
- name: claude-client
  account: client@example.com
  open: https://claude.ai/new

keys:
  s: {app: iTerm}
  t: {app: Finder}
  o: {app: ~/Applications/Obsidian.app}
  g: {site: github}
  f1: {site: claude-client}
  left: {window: left-half}
  right: {window: right-half}
  f: {window: maximize}
  w: {url: 'slack://channel?team=T123&id=C456'}
```

### Keys

Each entry under `keys:` is Caps Lock + one key. Key names: `a`–`z`, `0`–`9`, `f1`–`f12`, `left`, `right`, `up`, `down`. On an Apple keyboard, `f1`–`f12` work with or without fn. Each key does exactly one thing:

- `app`: an app's name, such as `Slack`, or a path to an .app that starts with `/` or `~/`. A name is looked for in `/Applications`, `/Applications/Utilities`, `/System/Applications`, `/System/Applications/Utilities`, `~/Applications` and `/System/Library/CoreServices`, in that order. The app comes forward, starting if it isn't running and opening a window if it has none.
- `site`: one of the sites below. See [What a jump does](#what-a-jump-does).
- `window`: `left-half`, `right-half` or `maximize`, for the front window, within the screen it is on.
- `url`: any link with a scheme. It opens the way a clicked link does: `slack://…` or `zoommtg://…` in the app that owns it, `https://…` in your default browser. Unlike `site`, it opens afresh each time; use `site` to land on a tab that is already open in a Chrome account.

While Caps Lock is held, a key with nothing bound does nothing. A file with no `keys:` leaves Caps Lock as it is.

### Sites

- `name`: the site's name, lower-case letters, digits and hyphens. Each site is also the link `capsjump://<name>`, for launchers and scripts.
- `account`: the account's email, or the profile's name for a profile with no signed-in account. `capsjump profiles` lists both.
- `profile`: a profile folder (`Profile 26`) instead of, or as well as, `account`, for when two profiles share an account or a name.
- `open`: the page opened when no tab matches.
- `match`: URL prefixes without the scheme, most specific first. A tab matches when its URL (without `https://` and `www.`) starts with one. The default is the `open` URL's host, e.g. `claude.ai/`.

This is the layout CapsJump itself writes, and a file in it never loses anything when CapsJump saves it. Edits apply as soon as the file is saved. Unknown keys are refused, so a typo is reported instead of being ignored. A broken edit keeps the keys you had and says what is wrong in a notification, and `capsjump check` lists every problem with its line.

## How Caps Lock becomes CapsJump's key

While CapsJump runs, macOS's own key mapping (the one `hidutil` sets) turns Caps Lock into F18, a key no keyboard has, and CapsJump watches for it. Caps Lock then no longer types capitals and its light stays off. Miss SHOUTING? Hold Shift, like everyone else. CapsJump gives Caps Lock back whenever it quits: from its own quit, at logout, when stopped, and when uninstalled with Homebrew. If it ever crashes, Caps Lock does nothing until CapsJump starts again or the Mac restarts.

macOS keeps every app's shortcuts out of password fields, so the keys do nothing while one has focus and work again as soon as you leave it.

## Pause, quit or turn it off

CapsJump puts its mark in the menu bar, dimmed while it doesn't have Caps Lock. Its menu:

- **Pause Keys / Resume Keys**: gives Caps Lock back, or takes it again. A pause lasts until you resume, across restarts.
- **Add Current Tab…**: turns the tab in front of Chrome into a site with a key. The page and its account come filled in; pick a key, click Add, and Caps Lock with that key lands there from then on. If the page is already one of your sites, it offers that site another key instead.
- **Edit Config…**: opens `~/.capsjump.yaml` in your editor, writing a starter file first if there is none. Saving applies the change at once.
- **Check Config**: shows what `capsjump check` shows.
- **Start at Login**: whether CapsJump starts when you log in.
- **Quit CapsJump**: gives Caps Lock back. It starts again at the next login, unless Start at Login is off.

From a terminal: `capsjump pause`, `capsjump resume` and `capsjump quit`. To remove it: `brew uninstall --cask capsjump`, which quits it first.

## What a jump does

A `site` key, or the link `capsjump://<name>`, runs a jump:

1. Finds the site's Chrome profile from Chrome's own profile list.
2. If Chrome is running, looks through that profile's windows, front to back, for a tab whose URL matches the first `match` prefix, then the next, preferring a window's active tab. It brings that tab and its window to the front.
3. Otherwise it opens the `open` page in that profile: a new tab in its window, or a new window, starting Chrome if needed.

Chrome's scripting interface doesn't say which profile a window belongs to, but its window title does (it ends in `– <profile label>`), and macOS Accessibility reads that title. CapsJump pairs each Chrome window with its title, so a window's profile is known without guessing. Accessibility lists only the windows on the current Space, so CapsJump sees only those: from a full-screen window or another desktop, a site whose tab is in a window elsewhere gets a new tab instead of being focused. Keep Chrome's windows on one desktop and out of full screen for jumps to find them. If two profiles carry the same label, their windows can't be told apart, so their sites always open a new tab; `capsjump check` says when that applies.

If a permission is missing, the jump fails with a notification. It never opens a duplicate tab instead.

## Permissions

CapsJump asks for three, all at once, with `capsjump setup`, or by itself the first time a jump finds one missing:

- **Accessibility**, for the keys, to move windows, and to read Chrome's window titles and raise a window. The keys start by themselves as soon as it is granted.
- **Automation of Google Chrome**, to read and switch tabs.
- **Notifications**, to say why a key or a jump did nothing.

Setup also adds CapsJump to your login items, so the keys are there from the moment you log in. Turn that off in System Settings › General › Login Items & Extensions.

Releases are signed with a Developer ID and notarized, so macOS keeps these grants across upgrades.

## Commands

| Command | |
| --- | --- |
| `capsjump init` | Write a starter `~/.capsjump.yaml`. Never overwrites. |
| `capsjump profiles` | List Chrome's profiles: folder, account, name and window label. |
| `capsjump check` | Validate the file, resolve every site and key, and confirm CapsJump.app is running with Caps Lock mapped. Exits non-zero on a problem. |
| `capsjump jump <site>` | Jump, exactly as the link does. |
| `capsjump setup` | Ask for the permissions, start CapsJump at login, and show each one's state. |
| `capsjump pause` / `capsjump resume` | Give Caps Lock back, or take it again. |
| `capsjump quit` | Quit CapsJump.app, giving Caps Lock back. |
| `capsjump logs [--last 2h]` | Show recent keys, jumps and failures from the macOS log. |
| `capsjump version` | Print the version. |

CapsJump runs from login, with its mark in the menu bar and no Dock icon.

## Develop

Requires Xcode 16 or later (Swift 6).

```sh
make test            # unit tests (Swift Testing)
make app             # .build/bundle/CapsJump.app, universal, signed ad hoc
make install-local   # install that build to ~/Applications and the CLI to ~/.local/bin
```

A local build is signed ad hoc, and macOS ties its permissions to that exact build, so every rebuild asks for them again: `make install-local` clears the old entries, then run `capsjump setup`. Released builds don't have this problem.

Layout:

- `Sources/CapsJumpCore`: all the rules (reading, checking and writing the config, key names, what each key event does, window frames, Chrome profiles, links, window pairing, choosing a tab), with no system calls. Nearly every test is here.
- `Sources/CapsJumpChrome`: the live side of a jump: Apple Events to Chrome, Accessibility, launching Chrome, permissions.
- `Sources/CapsJumpSystem`: the live side of the keys: the Caps Lock mapping, the event tap, watching and saving the config, moving windows, opening apps and links. Saving has its own tests, on a real disk, because its bugs would lose your file.
- `Sources/CapsJumpApp`: the background app that runs the keys and receives `capsjump://` links.
- `Sources/capsjump`: the CLI.
- `packaging/icon.svg` is the icon's source and `packaging/menubar.svg` the menu bar's; `scripts/make-icon.sh` renders them into `packaging/AppIcon.icns` and `packaging/MenuBarIcon*.png`.
- `site/` is the website, hand-written with no build; `.github/workflows/pages.yaml` publishes it to GitHub Pages when it changes on `main`.
- `scripts/bundle.sh` builds the app bundle; `scripts/notarize.sh` and `scripts/macos-import-signing-keychain.sh` are the release's signing steps.

## Release

Bump `VERSION`, merge, and push the tag `v<VERSION>`. `.github/workflows/release.yaml` tests, builds, signs, notarizes and staples, publishes the GitHub release, and updates the cask in [stigmer/homebrew-tap](https://github.com/stigmer/homebrew-tap). It needs the repository secrets listed at the top of that workflow.

## License

MIT

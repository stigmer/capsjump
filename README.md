<img src="packaging/icon.svg" width="96" alt="Nightcrawler icon">

# Nightcrawler

Jump to a site's tab in the right Chrome account, or open it there.

You use Chrome with several accounts (work, a client, personal), each in its own profile. You want one key to bring up GitHub in the work account: the GitHub tab already open there if there is one, otherwise a new one in that account's window. Nightcrawler does that from a link, `nightcrawler://github`, so any launcher that can open a link (karayaml, Raycast, Alfred, a Shortcut, `open` in a terminal) gets it.

Named after the X-Men character who teleports.

## Install

```sh
brew trust stigmer/tap                 # Homebrew asks once per machine for a third-party tap
brew install --cask stigmer/tap/nightcrawler
nightcrawler setup                     # grant its permissions once; upgrades keep them
nightcrawler init                      # writes ~/.nightcrawler.yaml, listing your Chrome accounts
```

Edit `~/.nightcrawler.yaml`, then run `nightcrawler check`.

## Configure

```yaml
sites:
  - name: github                       # nightcrawler://github
    account: you@work.com              # email, or the profile's name when it has no signed-in account
    open: https://github.com/your-org/your-repo/pulls
    match: [github.com/your-org/your-repo/pulls, github.com/]   # optional
  - name: claude-client
    account: client@example.com
    open: https://claude.ai/new
```

- `name`: the link's name, lower-case letters, digits and hyphens.
- `account`: the account's email, or the profile's name for a profile with no signed-in account. `nightcrawler profiles` lists both.
- `profile`: a profile folder (`Profile 26`) instead of, or as well as, `account`, for when two profiles share an account or a name.
- `open`: the page opened when no tab matches.
- `match`: URL prefixes without the scheme, most specific first. A tab matches when its URL (without `https://` and `www.`) starts with one. The default is the `open` URL's host, e.g. `claude.ai/`.

The file is read on every jump, so edits apply at once. Unknown keys are refused, so a typo is reported instead of being ignored.

## Bind it to a key

With [karayaml](https://github.com/swarupdonepudi/karayaml) (a release with `url:` entries):

```yaml
- key: g
  url: nightcrawler://github
```

From anywhere else: `open nightcrawler://github`, or `nightcrawler jump github`.

## What a jump does

1. Finds the site's Chrome profile from Chrome's own profile list.
2. If Chrome is running, looks through that profile's windows, front to back, for a tab whose URL matches the first `match` prefix, then the next, preferring a window's active tab. It brings that tab and its window to the front.
3. Otherwise it opens the `open` page in that profile: a new tab in its window, or a new window, starting Chrome if needed.

Chrome's scripting interface doesn't say which profile a window belongs to, but its window title does (it ends in `– <profile label>`), and macOS Accessibility reads that title. Nightcrawler pairs each Chrome window with its title, so a window's profile is known without guessing. Accessibility lists only the windows on the current Space, so Nightcrawler sees only those: from a full-screen window or another desktop, a site whose tab is in a window elsewhere gets a new tab instead of being focused. Keep Chrome's windows on one desktop and out of full screen for jumps to find them. If two profiles carry the same label, their windows can't be told apart, so their sites always open a new tab; `nightcrawler check` says when that applies.

If a permission is missing, the jump fails with a notification. It never opens a duplicate tab instead.

## Permissions

Nightcrawler asks for three, all at once, with `nightcrawler setup`, or by itself the first time a jump finds one missing:

- **Accessibility**, to read Chrome's window titles and raise a window.
- **Automation of Google Chrome**, to read and switch tabs.
- **Notifications**, to say why a jump failed.

Releases are signed with a Developer ID and notarized, so macOS keeps these grants across upgrades.

## Commands

| Command | |
| --- | --- |
| `nightcrawler init` | Write a starter `~/.nightcrawler.yaml`. Never overwrites. |
| `nightcrawler profiles` | List Chrome's profiles: folder, account, name and window label. |
| `nightcrawler check` | Validate the file, resolve every site, and confirm Nightcrawler.app receives the links. Exits non-zero on a problem. |
| `nightcrawler jump <site>` | Jump, exactly as the link does. |
| `nightcrawler setup` | Ask for the permissions and show each one's state. |
| `nightcrawler logs [--last 2h]` | Show recent jumps and failures from the macOS log. |
| `nightcrawler version` | Print the version. |

Nightcrawler stays running in the background after its first jump (no Dock icon or menu), so later jumps are immediate.

## Develop

Requires Xcode 16 or later (Swift 6).

```sh
make test            # unit tests (Swift Testing)
make app             # .build/bundle/Nightcrawler.app, universal, signed ad hoc
make install-local   # install that build to ~/Applications and the CLI to ~/.local/bin
```

A local build is signed ad hoc, and macOS ties its permissions to that exact build, so every rebuild asks for them again: `make install-local` clears the old entries, then run `nightcrawler setup`. Released builds don't have this problem.

Layout:

- `Sources/NightcrawlerCore`: all the rules (config, Chrome profiles, links, window pairing, choosing a tab), with no system calls. Every test is here.
- `Sources/NightcrawlerChrome`: the live side: Apple Events to Chrome, Accessibility, launching Chrome, permissions.
- `Sources/NightcrawlerApp`: the background app that receives `nightcrawler://` links.
- `Sources/nightcrawler`: the CLI.
- `packaging/icon.svg` is the icon's source; `scripts/make-icon.sh` renders it into `packaging/AppIcon.icns`.
- `scripts/bundle.sh` builds the app bundle; `scripts/notarize.sh` and `scripts/macos-import-signing-keychain.sh` are the release's signing steps.

## Release

Bump `VERSION`, merge, and push the tag `v<VERSION>`. `.github/workflows/release.yaml` tests, builds, signs, notarizes and staples, publishes the GitHub release, and updates the cask in [stigmer/homebrew-tap](https://github.com/stigmer/homebrew-tap). It needs the repository secrets listed at the top of that workflow.

## License

MIT

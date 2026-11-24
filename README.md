<p align="center">
  <img src="docs/hero.svg" alt="SuperNav: Pop!_OS-style keyboard navigation for macOS" width="100%">
</p>

<p align="center">
  <a href="https://github.com/trenner1/supernav/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/trenner1/supernav?color=7b5cff"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-48b0f7">
  <img alt="Universal" src="https://img.shields.io/badge/Apple%20silicon%20%2B%20Intel-universal-2fd6a7">
</p>

SuperNav brings the Pop!_OS habit of hopping around your desk with the keyboard to macOS. Hold left Control and an arrow key to jump to the next monitor. The cursor follows, and the top window there gets focus, so you can start typing straight away.

## Shortcuts

<p align="center">
  <img src="docs/shortcuts.svg" alt="Shortcuts: left Control + up/down for stacked monitors, left Control + Shift + left/right for side-by-side monitors, Control + left/right for workspaces" width="100%">
</p>

| Keys | Action |
| --- | --- |
| <kbd>⌃ left</kbd> <kbd>↑</kbd> / <kbd>↓</kbd> | Jump to the monitor above or below |
| <kbd>⌃ left</kbd> <kbd>⇧</kbd> <kbd>←</kbd> / <kbd>→</kbd> | Jump to the monitor on the left or right |
| <kbd>⌃</kbd> <kbd>←</kbd> / <kbd>→</kbd> | Switch workspace on the current monitor (built into macOS) |

Right Control is left alone, so <kbd>⌃ right</kbd> <kbd>↑</kbd> / <kbd>↓</kbd> still opens Mission Control and App Exposé.

## Install

### Homebrew

```sh
brew tap trenner1/tap
brew trust trenner1/tap
brew install --cask supernav
```

Homebrew only installs from taps you've trusted, which is what `brew trust` does.

### Download

Grab `SuperNav.zip` from the [latest release](https://github.com/trenner1/supernav/releases/latest), unzip it and drag **SuperNav.app** into Applications.

### From source

```sh
git clone https://github.com/trenner1/supernav.git
cd supernav
make install IDENTITY=-
```

This builds `~/Applications/SuperNav.app` and adds a LaunchAgent so it starts at login. `IDENTITY=-` signs it ad hoc. If you have a code-signing certificate, pass its name instead, so macOS keeps the Accessibility permission across rebuilds.

## First launch

1. **Open it.** Release downloads from version 1.0.1 are Developer ID signed and notarized by Apple. Open SuperNav normally.
2. **Grant Accessibility.** SuperNav needs it to read keys and focus windows. Turn it on under **System Settings → Privacy & Security → Accessibility**. It starts working within a couple of seconds, with no restart needed.
3. **Start at login** (Homebrew and download installs). Add SuperNav under **System Settings → General → Login Items**.

When SuperNav is running, its icon (two side-by-side rectangles) appears in the menu bar.

Workspace switching uses macOS's own Mission Control shortcuts. Keep **Move left/right a space** enabled under **System Settings → Keyboard → Keyboard Shortcuts → Mission Control**, and **Displays have separate Spaces** on under **Desktop & Dock**.

## Arranging screens

Monitor jumps follow the macOS display arrangement by default. If that doesn't match how your screens sit on your desk:

1. Click the SuperNav menu bar icon and choose **Arrange Screens…**
2. Drag the screens into place. The hint underneath tells you which shortcut reaches each layout.
3. Click **Done**.

The layout is saved per display, so it survives reboots and replugging. **Use macOS Arrangement** in the same menu clears it.

## Uninstall

```sh
brew uninstall --cask supernav
```

For a source install, run `make uninstall` from the repo instead.

## Signed and notarized releases

Release builds require Xcode command-line tools, a paid Apple Developer Program
membership, and a **Developer ID Application** identity (certificate plus private
key) in your keychain. Check existing identities before creating another:

```sh
security find-identity -v -p codesigning
```

In Xcode, use Settings → Accounts → your team → Manage Certificates to create or
manage the identity. If Xcode reports an Account Holder role error, create the
certificate at https://developer.apple.com/account/resources/certificates/list
using a CSR from Keychain Access → Certificate Assistant → Request a Certificate
From a Certificate Authority, then import the downloaded certificate on the same
Mac. Existing certificates need their original private key; a
`.cer` download alone cannot restore that key. Import a backed-up `.p12` or use
the Mac where the identity was created when applicable. Keep default certificate
trust settings.

Store notarization credentials once in Keychain. Run this interactively, supplying
your Apple account, Developer Team ID, and an app-specific password when prompted:

```sh
xcrun notarytool store-credentials supernav-notary
```

Create an app-specific password at https://account.apple.com. Do not put passwords,
private keys, or certificate exports in this repository.

```sh
make release RELEASE_IDENTITY='Developer ID Application: Your Name (TEAMID)'
```

The release command builds a universal app, signs with hardened runtime and a
secure timestamp, submits it to Apple, waits for acceptance, staples and validates
the ticket, checks Gatekeeper, and then creates `build/release/SuperNav.zip`.
`NOTARY_PROFILE` can override the default Keychain profile. Submission results are
saved in `build/release/notarization.json`; for rejected submissions, use the ID
there with `xcrun notarytool log ID --keychain-profile supernav-notary`.

Upload only the final `SuperNav.zip` to a new GitHub release, then update the
Homebrew cask version, URL, and SHA-256 with the hash printed by the command.
Older releases before 1.0.1 are unnotarized. Accessibility permission is still
required for all versions.

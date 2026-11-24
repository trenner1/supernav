# SuperNav

Pop!_OS-style keyboard navigation for macOS.

- **Left Control+↑ / ↓** jumps to the monitor above or below, moves the cursor there and focuses its top window
- **Control+← / →** switches workspace (Space) on the monitor under the cursor; this is macOS's own Mission Control shortcut

Right Control+↑ / ↓ still opens Mission Control and App Exposé.

## Install

```sh
make install
```

Builds `~/Applications/SuperNav.app` and installs a LaunchAgent so it starts at login. Grant it Accessibility access in System Settings → Privacy & Security → Accessibility.

Workspace switching relies on the default Mission Control shortcuts (Ctrl+← / →) and "Displays have separate Spaces".

Builds are signed with a code-signing identity named `SuperNav Signing` so the Accessibility grant survives rebuilds. Without one, sign ad hoc with `make install IDENTITY=-` and re-grant access after each rebuild.

`make uninstall` removes it.

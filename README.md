# SuperNav

Pop!_OS-style keyboard navigation for macOS.

- **Option+← / →** switches workspace (Space) on the current monitor
- **Option+↑ / ↓** jumps to the monitor above or below, moves the cursor there and focuses its top window

## Install

```sh
make install
```

Builds `~/Applications/SuperNav.app` and installs a LaunchAgent so it starts at login. Grant it Accessibility access in System Settings → Privacy & Security → Accessibility.

Workspace switching relies on the default Mission Control shortcuts (Ctrl+← / →) and "Displays have separate Spaces".

Builds are signed with a code-signing identity named `SuperNav Signing` so the Accessibility grant survives rebuilds. Without one, sign ad hoc with `make install IDENTITY=-` and re-grant access after each rebuild.

`make uninstall` removes it.

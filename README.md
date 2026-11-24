# SuperNav

Pop!_OS-style keyboard navigation for macOS.

- **Left Control+↑ / ↓** jumps to the monitor above or below, moves the cursor there and focuses its top window
- **Left Control+Shift+← / →** does the same for the monitor to the left or right
- **Control+← / →** switches workspace (Space) on the monitor under the cursor; this is macOS's own Mission Control shortcut

Right Control+↑ / ↓ still opens Mission Control and App Exposé.

## Arranging screens

By default monitor jumps follow the macOS display arrangement. To use a different layout, choose **Arrange Screens…** from the SuperNav menu bar icon and drag the screens to match your desk, then press **Done**. The layout is saved per display. **Use macOS Arrangement** clears it.

## Install

```sh
make install
```

Builds `~/Applications/SuperNav.app` and installs a LaunchAgent so it starts at login. Grant it Accessibility access in System Settings → Privacy & Security → Accessibility.

Workspace switching relies on the default Mission Control shortcuts (Ctrl+← / →) and "Displays have separate Spaces".

Builds are signed with a code-signing identity named `SuperNav Signing` so the Accessibility grant survives rebuilds. Without one, sign ad hoc with `make install IDENTITY=-` and re-grant access after each rebuild.

`make uninstall` removes it.

# AVCO Website Viewer

This package contains the standalone macOS app and its editable source.

## Install (Apple Silicon only)

1. Download [`installer/AVCO Website Viewer Installer.pkg`](installer/AVCO%20Website%20Viewer%20Installer.pkg) and double-click it.
2. On the destination screen, choose **Install for all users of this computer** (installs to `/Applications`) or **Install for me only** (installs to `~/Applications`) — the usual macOS installer choice.
3. Click through Install. A shortcut to the app is added to your Desktop automatically.
4. If macOS blocks the first launch, Control-click the app (or its Desktop shortcut) and choose **Open** once.

The Mac still needs Git, Python 3, Node.js, and npm to run the projects the app opens. Projects using pnpm, Yarn, or Bun also need their corresponding package manager.

The installer only builds for Apple Silicon (arm64) — it won't run on an Intel Mac.

### Building the installer yourself

After rebuilding the `.app` (see below), regenerate the `.pkg` from the `installer/` folder:

```bash
cd installer
pkgbuild --component "../AVCO Website Viewer.app" --install-location "/Applications" \
  --scripts scripts --identifier com.avcopremier.websiteviewer.pkg --version 1 component.pkg
productbuild --distribution distribution.xml --package-path . --resources . \
  "AVCO Website Viewer Installer.pkg"
```

## Run the app manually (no installer)

1. Place the `AVCO Website Viewer.app` file in Applications or on the Desktop.
2. Keep website folders in `~/avco` on that Mac.
3. Double-click the app.

If macOS blocks the transferred app, Control-click it and choose **Open** the first time.

## GitHub tab

Click **⇄ GitHub** in the toolbar to sign in with GitHub (device flow — no password typed into the app), pick an organization, and browse it:

- **Local** — every Git repo already checked out in the current folder, with branch, uncommitted-change count, and ahead/behind counts. Pull or Commit & Push directly from here (same safety-checked push flow as the Projects cards).
- **Pushed** — every repo in the selected GitHub organization, with a Branches list per repo. "Pull / Clone" checks a repo+branch out locally if it isn't already, or fast-forwards it if it is.

Both tabs auto-refresh every 60 seconds while the GitHub panel is open.

Sign-in uses OAuth Device Flow against a public GitHub OAuth App (Client ID `Ov23lirZ0powZkv1K4wB`, no client secret involved — safe to ship in the app). The resulting token is stored at `~/.avco-website-viewer-github.json` (mode 600), never in this repo.

## Auto-updates

The app checks this GitHub repo's `main` branch for a newer commit every time it launches. If one exists, it downloads it, replaces itself in place, and relaunches — no manual reinstall needed after the first install.

## Continue development

The `Source` folder contains:

- `main.swift` — native macOS window and toolbar
- `website-viewer` — dashboard, local servers, Git controls, build console, and API
- `pullrecents` — bulk repository updater
- `Info.plist` — macOS application metadata

After changing the source, rebuild the native executable with Swift and copy the helper scripts into the app's `Contents/Resources` folder before signing the app again.

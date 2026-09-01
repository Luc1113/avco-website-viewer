# AVCO Website Viewer

This package contains the standalone macOS app and its editable source.

## Run the app

1. Place the `AVCO Website Viewer.app` file in Applications or on the Desktop.
2. Keep website folders in `~/avco` on that Mac.
3. Double-click the app.

The destination Mac needs Git, Python 3, Node.js, and npm. Projects using pnpm, Yarn, or Bun also need their corresponding package manager.

If macOS blocks the transferred app, Control-click it and choose **Open** the first time.

## Continue development

The `Source` folder contains:

- `main.swift` — native macOS window and toolbar
- `website-viewer` — dashboard, local servers, Git controls, build console, and API
- `pullrecents` — bulk repository updater
- `Info.plist` — macOS application metadata

After changing the source, rebuild the native executable with Swift and copy the helper scripts into the app's `Contents/Resources` folder before signing the app again.

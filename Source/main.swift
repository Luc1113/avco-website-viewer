import Cocoa
import WebKit

/// Checks the app's own GitHub repo for a newer commit and, if found,
/// downloads it and replaces the running .app in place before relaunching.
/// Comparison is by commit SHA, not a version number.
enum UpdateManager {
    static let owner = "Luc1113"
    static let repo = "avco-website-viewer"
    static let branch = "main"

    /// Record of the commit this install was last synced to. Lives outside
    /// the .app bundle so it survives the bundle being swapped out.
    private static var recordURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AVCOWebsiteViewer", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("last-synced-commit.txt")
    }

    private static var lastSyncedCommit: String? {
        try? String(contentsOf: recordURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func recordSyncedCommit(_ sha: String) {
        try? sha.write(to: recordURL, atomically: true, encoding: .utf8)
    }

    private static func remoteHeadSHA(completion: @escaping (String?) -> Void) {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/commits/\(branch)")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sha = json["sha"] as? String else {
                completion(nil)
                return
            }
            completion(sha)
        }.resume()
    }

    /// Calls back with the new commit SHA if an update is available, else nil.
    static func checkForUpdate(completion: @escaping (String?) -> Void) {
        remoteHeadSHA { remote in
            guard let remote else { completion(nil); return }
            guard let local = lastSyncedCommit else {
                // No baseline yet (fresh install) — adopt current HEAD as the
                // baseline instead of forcing a redundant download.
                recordSyncedCommit(remote)
                completion(nil)
                return
            }
            completion(remote == local ? nil : remote)
        }
    }

    /// Downloads `remoteSHA`, swaps it in for the running .app, then relaunches.
    static func performUpdate(to remoteSHA: String, completion: @escaping (Bool) -> Void) {
        let zipURL = URL(string: "https://codeload.github.com/\(owner)/\(repo)/zip/refs/heads/\(branch)")!
        URLSession.shared.downloadTask(with: zipURL) { tempFile, _, _ in
            guard let tempFile else { completion(false); return }
            let workDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("avco-update-\(UUID().uuidString)")
            do {
                try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
                let zipPath = workDir.appendingPathComponent("update.zip")
                try FileManager.default.moveItem(at: tempFile, to: zipPath)

                let unzip = Process()
                unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                unzip.arguments = ["-x", "-k", zipPath.path, workDir.path]
                try unzip.run()
                unzip.waitUntilExit()
                guard unzip.terminationStatus == 0 else { completion(false); return }

                // GitHub's codeload zip always names the top folder "<repo>-<branch>".
                let extractedRoot = workDir.appendingPathComponent("\(repo)-\(branch)")
                let newAppPath = extractedRoot.appendingPathComponent("AVCO Website Viewer.app")
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: newAppPath.path, isDirectory: &isDir), isDir.boolValue else {
                    completion(false); return
                }

                let currentAppPath = Bundle.main.bundleURL.path
                let executableName = Bundle.main.executableURL?.lastPathComponent ?? "AVCOWebsiteViewer"
                let scriptPath = workDir.appendingPathComponent("swap.sh")
                let script = """
                #!/bin/bash
                for i in $(seq 1 20); do
                  pgrep -f "\(currentAppPath)/Contents/MacOS/\(executableName)" >/dev/null 2>&1 || break
                  sleep 0.3
                done
                rm -rf "\(currentAppPath)"
                mv "\(newAppPath.path)" "\(currentAppPath)"
                open "\(currentAppPath)"
                rm -rf "\(workDir.path)"
                """
                try script.write(to: scriptPath, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath.path)

                let relaunch = Process()
                relaunch.executableURL = URL(fileURLWithPath: "/bin/bash")
                relaunch.arguments = [scriptPath.path]
                try relaunch.run()

                recordSyncedCommit(remoteSHA)
                completion(true)
            } catch {
                completion(false)
            }
        }.resume()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate {
    private let dashboardURL = URL(string: "http://127.0.0.1:47831")!
    private let avcoFolder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("avco", isDirectory: true)
    private var window: NSWindow!
    private var webView: WKWebView!
    private var backend: Process?
    private var pullProcess: Process?
    private var statusLabel: NSTextField!

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildWindow()
        statusLabel.stringValue = "Checking for updates…"
        UpdateManager.checkForUpdate { [weak self] newSHA in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let newSHA else {
                    self.startBackend()
                    self.waitForDashboard(attempt: 0)
                    return
                }
                self.statusLabel.stringValue = "Updating to latest \(newSHA.prefix(7))…"
                UpdateManager.performUpdate(to: newSHA) { success in
                    DispatchQueue.main.async {
                        if success {
                            NSApp.terminate(nil)
                        } else {
                            self.statusLabel.stringValue = "Update failed — continuing…"
                            self.startBackend()
                            self.waitForDashboard(attempt: 0)
                        }
                    }
                }
            }
        }
    }

    private func buildWindow() {
        let frame = NSRect(x: 0, y: 0, width: 1220, height: 820)
        window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "AVCO Website Viewer"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(red: 0.01, green: 0.06, blue: 0.03, alpha: 1)
        window.minSize = NSSize(width: 860, height: 600)
        window.center()

        let root = NSView(frame: frame)
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(red: 0.01, green: 0.06, blue: 0.03, alpha: 1).cgColor

        let toolbar = NSView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.wantsLayer = true
        toolbar.layer?.backgroundColor = NSColor(red: 0.025, green: 0.13, blue: 0.07, alpha: 1).cgColor

        let home = NSButton(title: "← Projects", target: self, action: #selector(showDashboard))
        home.translatesAutoresizingMaskIntoConstraints = false
        home.bezelStyle = .rounded
        home.contentTintColor = NSColor(red: 0.46, green: 0.96, blue: 0.59, alpha: 1)

        let reload = NSButton(title: "↻ Reload", target: self, action: #selector(reloadPage))
        reload.translatesAutoresizingMaskIntoConstraints = false
        reload.bezelStyle = .rounded
        reload.contentTintColor = NSColor(red: 0.46, green: 0.96, blue: 0.59, alpha: 1)

        let pullAll = NSButton(title: "↓ Pull All", target: self, action: #selector(pullAllRepositories))
        pullAll.translatesAutoresizingMaskIntoConstraints = false
        pullAll.bezelStyle = .rounded
        pullAll.contentTintColor = NSColor(red: 0.46, green: 0.96, blue: 0.59, alpha: 1)

        let terminal = NSButton(title: ">_ AVCO Terminal", target: self, action: #selector(openAVCOTerminal))
        terminal.translatesAutoresizingMaskIntoConstraints = false
        terminal.bezelStyle = .rounded
        terminal.contentTintColor = NSColor(red: 0.46, green: 0.96, blue: 0.59, alpha: 1)

        let closeAll = NSButton(title: "■ Close All", target: self, action: #selector(closeAllWebsites))
        closeAll.translatesAutoresizingMaskIntoConstraints = false
        closeAll.bezelStyle = .rounded
        closeAll.contentTintColor = NSColor(red: 1, green: 0.58, blue: 0.62, alpha: 1)

        let title = NSTextField(labelWithString: "AVCO  ·  WEBSITE OPERATIONS")
        title.translatesAutoresizingMaskIntoConstraints = false
        title.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        title.textColor = NSColor(red: 0.79, green: 1, blue: 0.83, alpha: 1)

        statusLabel = NSTextField(labelWithString: "Starting local workspace…")
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        statusLabel.textColor = NSColor(red: 0.52, green: 0.77, blue: 0.59, alpha: 1)

        let configuration = WKWebViewConfiguration()
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.setValue(false, forKey: "drawsBackground")

        toolbar.addSubview(home)
        toolbar.addSubview(reload)
        toolbar.addSubview(pullAll)
        toolbar.addSubview(terminal)
        toolbar.addSubview(closeAll)
        toolbar.addSubview(title)
        toolbar.addSubview(statusLabel)
        root.addSubview(toolbar)
        root.addSubview(webView)
        window.contentView = root

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: root.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 76),
            home.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 16),
            home.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor, constant: 10),
            reload.leadingAnchor.constraint(equalTo: home.trailingAnchor, constant: 8),
            reload.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor, constant: 10),
            pullAll.leadingAnchor.constraint(equalTo: reload.trailingAnchor, constant: 8),
            pullAll.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor, constant: 10),
            terminal.leadingAnchor.constraint(equalTo: pullAll.trailingAnchor, constant: 8),
            terminal.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor, constant: 10),
            closeAll.leadingAnchor.constraint(equalTo: terminal.trailingAnchor, constant: 8),
            closeAll.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor, constant: 10),
            title.centerXAnchor.constraint(equalTo: toolbar.centerXAnchor),
            title.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor, constant: 10),
            statusLabel.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -18),
            statusLabel.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor, constant: 10),
            webView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func startBackend() {
        guard let viewer = Bundle.main.url(forResource: "website-viewer", withExtension: nil) else {
            statusLabel.stringValue = "Website Viewer helper is missing"
            return
        }
        let process = Process()
        process.executableURL = viewer
        process.arguments = ["--no-open", "--port", "47831"]
        process.currentDirectoryURL = avcoFolder
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
        backend = process
    }

    private func waitForDashboard(attempt: Int) {
        var request = URLRequest(url: dashboardURL)
        request.timeoutInterval = 0.5
        URLSession.shared.dataTask(with: request) { [weak self] _, response, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    self.statusLabel.stringValue = "● Workspace connected"
                    self.webView.load(URLRequest(url: self.dashboardURL))
                } else if attempt < 80 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        self.waitForDashboard(attempt: attempt + 1)
                    }
                } else {
                    self.statusLabel.stringValue = "Unable to start workspace"
                }
            }
        }.resume()
    }

    @objc private func showDashboard() {
        webView.load(URLRequest(url: dashboardURL))
    }

    @objc private func reloadPage() {
        webView.reload()
    }

    @objc private func pullAllRepositories() {
        guard pullProcess == nil else {
            statusLabel.stringValue = "Repository update already running…"
            return
        }
        guard let pullHelper = Bundle.main.url(forResource: "pullrecents", withExtension: nil) else {
            statusLabel.stringValue = "Pull helper is missing"
            return
        }
        let process = Process()
        process.executableURL = pullHelper
        process.currentDirectoryURL = avcoFolder
        process.standardOutput = Pipe()
        process.standardError = process.standardOutput
        statusLabel.stringValue = "↓ Pulling all repositories…"
        process.terminationHandler = { [weak self] finished in
            DispatchQueue.main.async {
                guard let self else { return }
                self.pullProcess = nil
                if finished.terminationStatus == 0 {
                    self.statusLabel.stringValue = "✓ All repositories are current"
                } else {
                    self.statusLabel.stringValue = "Some repositories need attention"
                }
                self.webView.evaluateJavaScript("load()")
            }
        }
        do {
            try process.run()
            pullProcess = process
        } catch {
            pullProcess = nil
            statusLabel.stringValue = "Unable to start repository update"
        }
    }

    @objc private func openAVCOTerminal() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", avcoFolder.path]
        try? process.run()
        statusLabel.stringValue = "AVCO Terminal opened"
    }

    @objc private func closeAllWebsites() {
        var request = URLRequest(url: dashboardURL.appendingPathComponent("api/stop-all"))
        request.httpMethod = "POST"
        URLSession.shared.dataTask(with: request) { [weak self] _, response, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    self.statusLabel.stringValue = "■ All local websites closed"
                    self.webView.load(URLRequest(url: self.dashboardURL))
                } else {
                    self.statusLabel.stringValue = "Unable to close local websites"
                }
            }
        }.resume()
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView.url?.port == 47831 {
            statusLabel.stringValue = "● Workspace connected"
        } else if let host = webView.url?.host {
            statusLabel.stringValue = "● Previewing \(host)"
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        pullProcess?.terminate()
        backend?.terminate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

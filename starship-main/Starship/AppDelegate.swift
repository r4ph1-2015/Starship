import AppKit
import ServiceManagement
import Foundation
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let library = WallpaperLibrary()
    let wallpaper = WallpaperEngine()
    let lockScreen = LockScreenManager()
    var statusItem: NSStatusItem!
    var window: NSWindow?
    var applyButton: NSButton?
    var progress: NSProgressIndicator?
    var progressLabel: NSTextField?

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerLoginItem(); makeMenuBar()
        if let active = library.active() { wallpaper.play(active) }
    }

    private func registerLoginItem() {
        do { try SMAppService.mainApp.register() } catch { NSLog("Starship login item: \(error)") }
    }

    private func makeMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "★"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Starship", action: #selector(openStarship), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Starship", action: #selector(quitStarship), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    @objc func openStarship() { if window == nil { createWindow() }; window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func quitStarship() { NSApp.terminate(nil) }

    private func createWindow() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 590, height: 310), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        w.title = "Starship"; w.isReleasedWhenClosed = false; w.delegate = self; w.center()
        let c = w.contentView!
        let title = NSTextField(labelWithString: "Starship"); title.frame = NSRect(x: 28, y: 248, width: 530, height: 35); title.font = .boldSystemFont(ofSize: 28); c.addSubview(title)
        let subtitle = NSTextField(labelWithString: "Native Swift animated wallpaper"); subtitle.frame = NSRect(x: 30, y: 220, width: 500, height: 22); subtitle.textColor = .secondaryLabelColor; c.addSubview(subtitle)
        let open = button("Open Wallpaper…", x: 28, y: 158, width: 220, action: #selector(openWallpaper)); c.addSubview(open)
        let quit = button("Quit Starship", x: 272, y: 158, width: 150, action: #selector(quitStarship)); c.addSubview(quit)
        let apply = button("Apply to Lock Screen", x: 28, y: 105, width: 220, action: #selector(applyLockScreen)); c.addSubview(apply); applyButton = apply
        let restore = button("Restore Apple Lock Screen", x: 272, y: 105, width: 250, action: #selector(restoreLockScreen)); c.addSubview(restore)
        let p = NSProgressIndicator(frame: NSRect(x: 28, y: 66, width: 494, height: 16)); p.isIndeterminate = false; p.minValue = 0; p.maxValue = 100; p.isHidden = true; c.addSubview(p); progress = p
        let label = NSTextField(labelWithString: ""); label.frame = NSRect(x: 28, y: 35, width: 494, height: 22); label.alignment = .center; label.isHidden = true; c.addSubview(label); progressLabel = label
        window = w; w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }

    private func button(_ title: String, x: CGFloat, y: CGFloat, width: CGFloat, action: Selector) -> NSButton { let b = NSButton(frame: NSRect(x: x, y: y, width: width, height: 36)); b.title = title; b.bezelStyle = .rounded; b.target = self; b.action = action; return b }
    func windowWillClose(_ notification: Notification) { }

    @objc func openWallpaper() {
        let p = NSOpenPanel(); p.canChooseFiles = true; p.canChooseDirectories = false; p.allowsMultipleSelection = false; p.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie]
        guard p.runModal() == .OK, let url = p.url else { return }
        do { let imported = try library.importVideo(url); wallpaper.play(imported) } catch { alert("Could not open wallpaper", error.localizedDescription) }
    }

    @objc func applyLockScreen() {
        guard let source = library.active() else { alert("No wallpaper selected", "Choose a wallpaper first."); return }
        applyButton?.isEnabled = false; progress?.isHidden = false; progressLabel?.isHidden = false
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.lockScreen.apply(source: source) { value, stage in
                    DispatchQueue.main.async { self.progress?.doubleValue = Double(value); self.progressLabel?.stringValue = "\(stage) — \(value)%" }
                }
                DispatchQueue.main.async { self.applyButton?.isEnabled = true; self.alert("Lock Screen updated", "Starship installed the selected video into the active Apple Aerial slot.") }
            } catch { DispatchQueue.main.async { self.applyButton?.isEnabled = true; self.alert("Lock Screen failed", error.localizedDescription) } }
        }
    }

    @objc func restoreLockScreen() { do { try lockScreen.restore(); alert("Apple Lock Screen restored", "The original Apple Aerial video and wallpaper selection were restored.") } catch { alert("Restore failed", error.localizedDescription) } }
    private func alert(_ title: String, _ text: String) { let a = NSAlert(); a.messageText = title; a.informativeText = text; a.runModal() }
}

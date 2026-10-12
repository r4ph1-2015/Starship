import AppKit
import AVFoundation
import QuartzCore

final class WallpaperEngine: NSObject {
    private var windows: [NSWindow] = []
    private var layers: [AVPlayerLayer] = []
    private var player: AVQueuePlayer?
    private var playerLooper: AVPlayerLooper?
    private let imageExtensions = Set(["jpg", "jpeg", "png", "webp", "gif", "avif", "heic", "heif"])
    private(set) var volume: Float = UserDefaults.standard.object(forKey: "wallpaperVolume") as? Float ?? 0.5
    private(set) var isMuted = UserDefaults.standard.object(forKey: "wallpaperMuted") as? Bool ?? false

    func setVolume(_ value: Float) {
        volume = min(1, max(0, value))
        UserDefaults.standard.set(volume, forKey: "wallpaperVolume")
        if volume > 0 && isMuted { setMuted(false) }
        player?.volume = volume
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        UserDefaults.standard.set(muted, forKey: "wallpaperMuted")
        player?.isMuted = muted
    }

    func toggleMute() { setMuted(!isMuted) }

    func stop() {
        player?.pause()
        playerLooper = nil
        windows.forEach { $0.orderOut(nil) }
        player = nil
        layers.removeAll()
        windows.removeAll()
    }

    func play(_ url: URL) throws {
        stop()
        if imageExtensions.contains(url.pathExtension.lowercased()) {
            for screen in NSScreen.screens {
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
            }
            return
        }
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 3
        let player = AVQueuePlayer()
        player.volume = volume
        player.isMuted = isMuted
        player.preventsDisplaySleepDuringVideoPlayback = false
        playerLooper = AVPlayerLooper(player: player, templateItem: item)
        self.player = player
        let level = CGWindowLevelForKey(.desktopWindow)
        for screen in NSScreen.screens {
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = NSWindow.Level(rawValue: Int(level))
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.isOpaque = true; window.backgroundColor = .black; window.ignoresMouseEvents = true
            let view = NSView(frame: window.contentRect(forFrameRect: screen.frame)); view.wantsLayer = true
            window.contentView = view
            let layer = AVPlayerLayer(player: player)
            layer.frame = view.bounds; layer.videoGravity = .resizeAspectFill
            view.layer?.addSublayer(layer)
            window.orderFrontRegardless()
            windows.append(window)
            layers.append(layer)
        }
        player.play()
    }
}

import AppKit
import AVFoundation
import QuartzCore

final class WallpaperEngine: NSObject {
    private var windows: [NSWindow] = []
    private var players: [AVPlayer] = []
    private var layers: [AVPlayerLayer] = []
    private var observers: [NSObjectProtocol] = []

    func stop() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        players.forEach { $0.pause() }
        windows.forEach { $0.orderOut(nil) }
        players.removeAll(); layers.removeAll(); windows.removeAll()
    }

    func play(_ url: URL) {
        stop()
        let level = CGWindowLevelForKey(.desktopWindow)
        for screen in NSScreen.screens {
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = NSWindow.Level(rawValue: Int(level))
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.isOpaque = true; window.backgroundColor = .black; window.ignoresMouseEvents = true
            let view = NSView(frame: window.contentRect(forFrameRect: screen.frame)); view.wantsLayer = true
            window.contentView = view
            let player = AVPlayer(url: url)
            let layer = AVPlayerLayer(player: player)
            layer.frame = view.bounds; layer.videoGravity = .resizeAspectFill
            view.layer?.addSublayer(layer)
            let token = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { [weak self, weak player] _ in
                player?.seek(to: .zero) { _ in player?.play() }
                _ = self
            }
            observers.append(token)
            window.orderFrontRegardless(); player.play()
            windows.append(window); players.append(player); layers.append(layer)
        }
    }
}

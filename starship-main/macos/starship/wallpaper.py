import AppKit
import AVFoundation
import Quartz

from .logger import log, log_exception

class WallpaperEngine:
    def __init__(self):
        self.sessions = []

    def stop(self):
        log(f"Stopping {len(self.sessions)} wallpaper session(s).")
        for session in self.sessions:
            try:
                session["queue"].pause()
            except Exception as exc:
                log_exception("Queue pause error", exc)
            try:
                session["window"].orderOut_(None)
            except Exception as exc:
                log_exception("Window stop error", exc)
        self.sessions = []

    def play(self, path):
        self.stop()
        path = str(path)
        screens = list(AppKit.NSScreen.screens())
        log(f"Starting wallpaper: {path}")
        log(f"Detected {len(screens)} screen(s).")

        for index, screen in enumerate(screens):
            try:
                frame = screen.frame()

                window = AppKit.NSWindow.alloc().initWithContentRect_styleMask_backing_defer_(
                    frame,
                    AppKit.NSWindowStyleMaskBorderless,
                    AppKit.NSBackingStoreBuffered,
                    False,
                )
                window.setOpaque_(True)
                window.setBackgroundColor_(AppKit.NSColor.blackColor())
                window.setLevel_(
                    Quartz.CGWindowLevelForKey(Quartz.kCGDesktopWindowLevelKey)
                )
                window.setIgnoresMouseEvents_(True)
                window.setCollectionBehavior_(
                    AppKit.NSWindowCollectionBehaviorCanJoinAllSpaces
                    | AppKit.NSWindowCollectionBehaviorStationary
                )

                url = AppKit.NSURL.fileURLWithPath_(path)
                item = AVFoundation.AVPlayerItem.playerItemWithURL_(url)

                # Use the Objective-C queue factory. The PyObjC binding for
                # insertItem:atIndex: is not available in this environment.
                queue = AVFoundation.AVQueuePlayer.queuePlayerWithItems_([item])

                # Loop the item forever.
                looper = AVFoundation.AVPlayerLooper.playerLooperWithPlayer_templateItem_(
                    queue, item
                )

                layer = AVFoundation.AVPlayerLayer.playerLayerWithPlayer_(queue)
                view = AppKit.NSView.alloc().initWithFrame_(
                    ((0, 0), (frame.size.width, frame.size.height))
                )
                view.setWantsLayer_(True)
                view.layer().addSublayer_(layer)
                layer.setFrame_(view.bounds())
                layer.setVideoGravity_(AVFoundation.AVLayerVideoGravityResizeAspectFill)

                window.setContentView_(view)
                window.orderFrontRegardless()
                queue.play()

                self.sessions.append({
                    "window": window,
                    "queue": queue,
                    "looper": looper,
                    "layer": layer,
                    "view": view,
                })
                log(f"Started screen {index + 1}.")
            except Exception as exc:
                log_exception(f"Screen {index + 1} wallpaper error", exc)
                self.stop()
                raise

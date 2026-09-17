import AppKit
import AVFoundation

from .logger import log, log_exception
from .library import Library
from .wallpaper import WallpaperEngine
from .downloader import download_video

class StarshipApp(AppKit.NSObject):
    def applicationDidFinishLaunching_(self, notification):
        log("Starting Starship.")
        self.library = Library()
        self.engine = WallpaperEngine()
        self.main_window = None
        self.setup_menu()
        log("Application finished launching.")

        active = self.library.active()
        if active:
            log(f"Restoring active wallpaper: {active}")
            try:
                self.engine.play(active)
            except Exception as exc:
                log_exception("Restore wallpaper error", exc)

    def setup_menu(self):
        log("Creating menu bar item.")
        self.status_item = AppKit.NSStatusBar.systemStatusBar().statusItemWithLength_(
            AppKit.NSVariableStatusItemLength
        )
        self.status_item.setTitle_("★")

        menu = AppKit.NSMenu.alloc().initWithTitle_("Starship")
        menu.setAutoenablesItems_(False)

        open_item = AppKit.NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(
            "Open Starship", "openStarship:", ""
        )
        quit_item = AppKit.NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(
            "Quit Starship", "quitStarship:", "q"
        )

        for item in (open_item, quit_item):
            item.setTarget_(self)
            item.setEnabled_(True)
            menu.addItem_(item)

        self.status_item.setMenu_(menu)
        log("Menu bar item and clickable menu items ready.")

    def openStarship_(self, sender):
        log("Menu action: Open Starship")
        self.show_main_window()

    def quitStarship_(self, sender):
        log("Menu action: Quit Starship")
        self.engine.stop()
        AppKit.NSApp.terminate_(None)

    def show_main_window(self):
        log("Showing main window.")
        if self.main_window is None:
            frame = ((0, 0), (520, 280))
            style = (
                AppKit.NSTitledWindowMask
                | AppKit.NSClosableWindowMask
                | AppKit.NSResizableWindowMask
            )
            self.main_window = AppKit.NSWindow.alloc().initWithContentRect_styleMask_backing_defer_(
                frame, style, AppKit.NSBackingStoreBuffered, False
            )
            self.main_window.setTitle_("Starship")
            self.main_window.center()

            content = AppKit.NSView.alloc().initWithFrame_(((0, 0), (520, 280)))
            self.main_window.setContentView_(content)

            title = AppKit.NSTextField.labelWithString_("Starship")
            title.setFont_(AppKit.NSFont.boldSystemFontOfSize_(30))
            title.setFrame_(((40, 190), (440, 40)))
            content.addSubview_(title)

            subtitle = AppKit.NSTextField.labelWithString_(
                "Choose a video to use as your animated wallpaper."
            )
            subtitle.setFrame_(((40, 155), (440, 24)))
            content.addSubview_(subtitle)

            open_button = AppKit.NSButton.buttonWithTitle_target_action_(
                "Open Wallpaper…", self, "openWallpaper:"
            )
            open_button.setFrame_(((40, 100), (200, 40)))
            content.addSubview_(open_button)

            quit_button = AppKit.NSButton.buttonWithTitle_target_action_(
                "Quit Starship", self, "quitStarship:"
            )
            quit_button.setFrame_(((40, 45), (200, 40)))
            content.addSubview_(quit_button)

            self.open_button = open_button
            self.quit_button = quit_button

        try:
            self.main_window.makeKeyAndOrderFront_(None)
            self.main_window.orderFrontRegardless()
            AppKit.NSApp.activateIgnoringOtherApps_(True)
            log("Main window opened.")
        except Exception as exc:
            log_exception("Main window show error", exc)
            self.main_window = None
            self.show_error(str(exc))

    def openWallpaper_(self, sender):
        log("Open Wallpaper button pressed.")
        panel = AppKit.NSOpenPanel.openPanel()
        panel.setCanChooseFiles_(True)
        panel.setCanChooseDirectories_(False)
        panel.setAllowsMultipleSelection_(False)
        panel.setAllowedFileTypes_(["mp4", "mov", "m4v", "webm", "avi", "mkv"])

        result = panel.runModal()
        log(f"Open panel result: {result}")

        if result != AppKit.NSModalResponseOK:
            return

        url = panel.URL()
        if not url:
            log("No file selected.")
            return

        path = url.path()
        log(f"Selected wallpaper: {path}")

        try:
            imported = self.library.import_video(path)
            self.engine.play(imported)
            log(f"Wallpaper set: {imported}")
        except Exception as exc:
            log_exception("Wallpaper import error", exc)
            self.show_error(str(exc))

    def show_error(self, message):
        alert = AppKit.NSAlert.alloc().init()
        alert.setMessageText_("Starship")
        alert.setInformativeText_(message)
        alert.addButtonWithTitle_("OK")
        alert.runModal()

def main():
    app = AppKit.NSApplication.sharedApplication()
    delegate = StarshipApp.alloc().init()
    app.setDelegate_(delegate)
    app.setActivationPolicy_(AppKit.NSApplicationActivationPolicyAccessory)
    app.run()

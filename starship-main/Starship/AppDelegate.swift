import AppKit
import AVKit
import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

private enum WallpaperChoice {
    case gallery(GalleryWallpaper)
    case personal(URL)

    var name: String {
        switch self {
        case .gallery(let item): item.name
        case .personal(let url): url.deletingPathExtension().lastPathComponent
        }
    }

    var ext: String {
        switch self {
        case .gallery(let item): item.fileExtension.uppercased()
        case .personal(let url): url.pathExtension.uppercased()
        }
    }

    var isVideo: Bool {
        switch self {
        case .gallery(let item): item.isVideo
        case .personal(let url): ["mp4", "mov", "m4v"].contains(url.pathExtension.lowercased())
        }
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String
    enum CodingKeys: String, CodingKey { case tagName = "tag_name", htmlURL = "html_url" }
}

private final class WallpaperArtworkView: NSView {
    override func layout() {
        super.layout()
        layer?.sublayers?.forEach { sublayer in
            if sublayer is AVPlayerLayer { sublayer.frame = bounds }
        }
    }
}

private final class LiveCardPreview {
    let player: AVQueuePlayer
    private var looper: AVPlayerLooper?
    private(set) var layers: [AVPlayerLayer] = []

    init(url: URL) {
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 2
        player = AVQueuePlayer()
        player.isMuted = true
        looper = AVPlayerLooper(player: player, templateItem: item)
    }

    func attach(to artwork: NSView) -> AVPlayerLayer {
        let layer = AVPlayerLayer(player: player)
        layer.frame = artwork.bounds
        layer.videoGravity = .resizeAspectFill
        layer.needsDisplayOnBoundsChange = true
        artwork.layer?.insertSublayer(layer, at: 0)
        layers.append(layer)
        return layer
    }

    func detachLayers() {
        layers.forEach { $0.player = nil; $0.removeFromSuperlayer() }
        layers.removeAll()
    }

    func stop() {
        player.pause()
        detachLayers()
        looper = nil
        player.removeAllItems()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSSearchFieldDelegate {
    private enum Section: Int { case home, explore, library }

    private let library = WallpaperLibrary()
    private let wallpaper = WallpaperEngine()
    private let gallery = GalleryCatalog()

    private var statusItem: NSStatusItem!
    private var window: NSWindow?
    private var scrollView: NSScrollView!
    private var contentStack: NSStackView!
    private var searchField: NSSearchField!
    private var sectionControl: NSSegmentedControl!
    private var featuredArtwork: NSView!
    private var featuredImage: NSImageView!
    private var featuredPlayer: AVPlayerView!
    private var featuredPlaceholder: NSView!
    private var featuredName: NSTextField!
    private var featuredDetails: NSTextField!
    private var primaryButton: NSButton!
    private var statusLabel: NSTextField!
    private var importButton: NSButton!
    private var volumeSlider: NSSlider!
    private var muteButton: NSButton!
    private var muteMenuItem: NSMenuItem!
    private var menuVolumeSlider: NSSlider!
    private var previewPlayer: AVQueuePlayer?
    private var previewLooper: AVPlayerLooper?
    private var featuredPreviewUsesCardPlayer = false
    private var liveCardPreviews: [String: LiveCardPreview] = [:]

    private var remoteWallpapers: [GalleryWallpaper] = []
    private var localWallpapers: [URL] = []
    private var visibleChoices: [WallpaperChoice] = []
    private var selectedChoice: WallpaperChoice?
    private var selectedGallery: GalleryWallpaper?
    private var galleryLoadInProgress = false
    private var galleryDownloadQueue: [GalleryWallpaper] = []
    private var galleryDownloadIndex = 0
    private var galleryDownloadBytes = 0
    private var galleryDownloadFailures = 0
    private var currentBulkDownloadPath: String?
    private var pendingApplyGalleryPath: String?
    private var knownGalleryNames = Set(UserDefaults.standard.stringArray(forKey: "knownGitHubWallpaperNames") ?? [])
    private var currentSection: Section = .home

    func applicationDidFinishLaunching(_ notification: Notification) {
        makeMenuBar()
        if let active = library.active() { try? wallpaper.play(active) }
        DispatchQueue.main.async {
            self.openStarship()
            self.checkForUpdates(showCurrentVersion: false)
        }
    }

    private func makeMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let symbol = NSImage(systemSymbolName: "snowflake", accessibilityDescription: "Starship Snowflake")
        symbol?.isTemplate = true
        statusItem.button?.image = symbol
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Starship Snowflake", action: #selector(openStarship), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "About Starship Snowflake", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdatesManually), keyEquivalent: ""))
        menu.addItem(.separator())
        muteMenuItem = NSMenuItem(title: "Mute Wallpaper", action: #selector(toggleWallpaperMute), keyEquivalent: "")
        menu.addItem(muteMenuItem)
        let volumeItem = NSMenuItem()
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        let label = NSTextField(labelWithString: "Volume")
        label.font = .systemFont(ofSize: 12)
        menuVolumeSlider = NSSlider(value: Double(wallpaper.volume), minValue: 0, maxValue: 1, target: self, action: #selector(menuVolumeChanged(_:)))
        menuVolumeSlider.widthAnchor.constraint(equalToConstant: 140).isActive = true
        row.addArrangedSubview(label)
        row.addArrangedSubview(menuVolumeSlider)
        volumeItem.view = row
        menu.addItem(volumeItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Starship", action: #selector(quitStarship), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
        refreshVolumeControls()
    }

    @objc private func openStarship() {
        if window == nil { createWindow() }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        refreshLibrary()
        if remoteWallpapers.isEmpty && !galleryLoadInProgress { loadGallery() }
    }

    @objc private func quitStarship() { NSApp.terminate(nil) }

    @objc private func checkForUpdatesManually() {
        checkForUpdates(showCurrentVersion: true)
    }

    private func checkForUpdates(showCurrentVersion: Bool) {
        guard let url = URL(string: "https://api.github.com/repos/r4ph1-2015/Starship/releases/latest") else { return }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Starship-Snowflake/2026.1", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            let release = data.flatMap { try? JSONDecoder().decode(GitHubRelease.self, from: $0) }
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            DispatchQueue.main.async {
                guard statusCode == 200, let release, let releaseURL = URL(string: release.htmlURL) else {
                    if showCurrentVersion {
                        self.alert("Couldn’t check for updates", "Connect to the internet and try again later.")
                    }
                    return
                }
                guard Self.isVersion(release.tagName, newerThan: "2026.1") else {
                    if showCurrentVersion {
                        self.alert("You’re up to date", "Starship Snowflake 2026.1 is the latest version available.")
                    }
                    return
                }
                let alert = NSAlert()
                alert.messageText = "Starship Snowflake update available"
                alert.informativeText = "Version \(release.tagName) is available. Open the GitHub release to download and replace this app."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "View Release")
                alert.addButton(withTitle: "Later")
                if let window = self.window, window.isVisible {
                    alert.beginSheetModal(for: window) { response in
                        if response == .alertFirstButtonReturn { NSWorkspace.shared.open(releaseURL) }
                    }
                } else if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(releaseURL)
                }
            }
        }.resume()
    }

    private static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        func parts(_ text: String) -> [Int] {
            text.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        }
        let lhs = parts(candidate)
        let rhs = parts(current)
        for index in 0..<max(lhs.count, rhs.count) {
            let a = index < lhs.count ? lhs[index] : 0
            let b = index < rhs.count ? rhs[index] : 0
            if a != b { return a > b }
        }
        return false
    }
    func windowWillClose(_ notification: Notification) { stopPreview(); stopAllCardPreviews() }

    private func createWindow() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1160, height: 820), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.title = "Starship Snowflake"
        w.minSize = NSSize(width: 780, height: 620)
        w.isReleasedWhenClosed = false
        w.titlebarAppearsTransparent = true
        w.toolbarStyle = .unified
        w.delegate = self
        w.center()
        w.contentView = buildInterface()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        refreshLibrary()
        loadGallery()
    }

    private func buildInterface() -> NSView {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(calibratedWhite: 0.075, alpha: 1).cgColor

        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        let brandMark = NSView()
        brandMark.translatesAutoresizingMaskIntoConstraints = false
        brandMark.wantsLayer = true
        brandMark.layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.12).cgColor
        brandMark.layer?.cornerRadius = 9
        let snowflake = NSTextField(labelWithString: "❄")
        snowflake.font = .systemFont(ofSize: 19, weight: .medium)
        snowflake.textColor = .white
        snowflake.alignment = .center
        snowflake.translatesAutoresizingMaskIntoConstraints = false
        brandMark.addSubview(snowflake)
        let brand = NSTextField(labelWithString: "Starship")
        brand.font = .systemFont(ofSize: 16, weight: .bold)
        brand.textColor = .white
        let brandStack = NSStackView(views: [brandMark, brand])
        brandStack.orientation = .horizontal
        brandStack.alignment = .centerY
        brandStack.spacing = 9
        brandStack.translatesAutoresizingMaskIntoConstraints = false

        sectionControl = NSSegmentedControl(labels: ["Home", "Explore", "Library"], trackingMode: .selectOne, target: self, action: #selector(sectionChanged(_:)))
        sectionControl.selectedSegment = Section.home.rawValue
        sectionControl.segmentStyle = .rounded
        sectionControl.translatesAutoresizingMaskIntoConstraints = false

        searchField = NSSearchField()
        searchField.placeholderString = "Search wallpapers"
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.widthAnchor.constraint(equalToConstant: 210).isActive = true

        importButton = iconButton("square.and.arrow.down", help: "Import wallpapers from this Mac", action: #selector(importWallpaper))
        let about = iconButton("info.circle", help: "About Starship Snowflake", action: #selector(showAbout))
        let refresh = iconButton("arrow.clockwise", help: "Refresh GitHub gallery", action: #selector(loadGallery))

        [brandStack, sectionControl, searchField, importButton, refresh, about].forEach { header.addSubview($0) }
        root.addSubview(header)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 17),
            header.heightAnchor.constraint(equalToConstant: 44),
            brandMark.widthAnchor.constraint(equalToConstant: 34), brandMark.heightAnchor.constraint(equalToConstant: 34),
            snowflake.centerXAnchor.constraint(equalTo: brandMark.centerXAnchor), snowflake.centerYAnchor.constraint(equalTo: brandMark.centerYAnchor),
            brandStack.leadingAnchor.constraint(equalTo: header.leadingAnchor), brandStack.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            sectionControl.centerXAnchor.constraint(equalTo: header.centerXAnchor), sectionControl.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            searchField.trailingAnchor.constraint(equalTo: importButton.leadingAnchor, constant: -10), searchField.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            importButton.trailingAnchor.constraint(equalTo: refresh.leadingAnchor, constant: -8), importButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            refresh.trailingAnchor.constraint(equalTo: about.leadingAnchor, constant: -8), refresh.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            about.trailingAnchor.constraint(equalTo: header.trailingAnchor), about.centerYAnchor.constraint(equalTo: header.centerYAnchor)
        ])

        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        let document = NSView()
        document.translatesAutoresizingMaskIntoConstraints = false
        contentStack = NSStackView()
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.distribution = .fill
        contentStack.spacing = 24
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(contentStack)
        scrollView.documentView = document
        NSLayoutConstraint.activate([
            document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            contentStack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 28),
            contentStack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -28),
            contentStack.topAnchor.constraint(equalTo: document.topAnchor, constant: 10),
            contentStack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -26)
        ])

        statusLabel = NSTextField(labelWithString: "Connecting to the Starship gallery…")
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = NSColor(white: 1, alpha: 0.52)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scrollView)
        root.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor), scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4), scrollView.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -7),
            statusLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 30), statusLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -30),
            statusLabel.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12), statusLabel.heightAnchor.constraint(equalToConstant: 16)
        ])
        rebuildContent()
        return root
    }

    private func rebuildContent() {
        guard contentStack != nil else { return }
        detachCardPreviewLayers()
        contentStack.arrangedSubviews.forEach { contentStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        let hero = buildHero()
        contentStack.addArrangedSubview(hero)
        hero.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        let carouselTitle = sectionHeading("Quick picks", subtitle: "A few scenes to get you started")
        contentStack.addArrangedSubview(carouselTitle)
        carouselTitle.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        let carousel = buildCarousel()
        contentStack.addArrangedSubview(carousel)
        carousel.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        let gridTitle = sectionHeading(sectionTitle(), subtitle: sectionSubtitle())
        contentStack.addArrangedSubview(gridTitle)
        gridTitle.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        let grid = buildWallpaperGrid()
        contentStack.addArrangedSubview(grid)
        grid.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        if let selectedChoice { select(selectedChoice) }
        startVisibleCardPreviews()
    }

    private func buildHero() -> NSView {
        let hero = NSView()
        hero.translatesAutoresizingMaskIntoConstraints = false
        hero.wantsLayer = true
        hero.layer?.cornerRadius = 22
        hero.layer?.masksToBounds = true
        hero.layer?.backgroundColor = NSColor(calibratedRed: 0.13, green: 0.23, blue: 0.31, alpha: 1).cgColor
        featuredArtwork = hero
        featuredImage = NSImageView()
        featuredImage.translatesAutoresizingMaskIntoConstraints = false
        featuredImage.imageScaling = .scaleProportionallyUpOrDown
        featuredImage.wantsLayer = true
        featuredImage.layer?.contentsGravity = .resizeAspectFill
        featuredImage.isHidden = true
        featuredPlayer = AVPlayerView()
        featuredPlayer.translatesAutoresizingMaskIntoConstraints = false
        featuredPlayer.controlsStyle = .none
        featuredPlayer.isHidden = true
        let overlay = NSView()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = NSColor(calibratedWhite: 0, alpha: 0.20).cgColor
        featuredPlaceholder = NSView()
        featuredPlaceholder.translatesAutoresizingMaskIntoConstraints = false
        featuredPlaceholder.wantsLayer = true
        featuredPlaceholder.layer?.backgroundColor = NSColor(calibratedRed: 0.14, green: 0.29, blue: 0.38, alpha: 1).cgColor
        let snowflake = NSTextField(labelWithString: "❄")
        snowflake.font = .systemFont(ofSize: 100, weight: .ultraLight)
        snowflake.textColor = NSColor(white: 1, alpha: 0.12)
        snowflake.translatesAutoresizingMaskIntoConstraints = false
        featuredPlaceholder.addSubview(snowflake)

        let copy = NSStackView()
        copy.orientation = .vertical
        copy.alignment = .leading
        copy.spacing = 7
        copy.translatesAutoresizingMaskIntoConstraints = false
        let eyebrow = NSTextField(labelWithString: "YOUR WALLPAPER COLLECTION")
        eyebrow.font = .systemFont(ofSize: 10, weight: .bold)
        eyebrow.textColor = NSColor(white: 1, alpha: 0.72)
        featuredName = NSTextField(labelWithString: "A calmer desktop starts here")
        featuredName.font = .systemFont(ofSize: 31, weight: .bold)
        featuredName.textColor = .white
        featuredName.lineBreakMode = .byTruncatingTail
        featuredDetails = NSTextField(labelWithString: "Explore wallpapers from GitHub or import your own.")
        featuredDetails.font = .systemFont(ofSize: 12)
        featuredDetails.textColor = NSColor(white: 1, alpha: 0.78)
        featuredDetails.lineBreakMode = .byTruncatingTail
        let actionRow = NSStackView()
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.spacing = 12
        primaryButton = NSButton(title: "Set as Desktop", target: self, action: #selector(useSelectedWallpaper))
        primaryButton.bezelStyle = .rounded
        primaryButton.controlSize = .large
        primaryButton.keyEquivalent = "\r"
        primaryButton.isEnabled = false
        primaryButton.contentTintColor = .labelColor
        muteButton = iconButton(wallpaper.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", help: "Toggle wallpaper audio", action: #selector(toggleWallpaperMute))
        muteButton.bezelStyle = .rounded
        volumeSlider = NSSlider(value: Double(wallpaper.volume), minValue: 0, maxValue: 1, target: self, action: #selector(volumeChanged(_:)))
        volumeSlider.isContinuous = true
        volumeSlider.widthAnchor.constraint(equalToConstant: 110).isActive = true
        actionRow.addArrangedSubview(primaryButton)
        actionRow.addArrangedSubview(muteButton)
        actionRow.addArrangedSubview(volumeSlider)
        copy.addArrangedSubview(eyebrow)
        copy.addArrangedSubview(featuredName)
        copy.addArrangedSubview(featuredDetails)
        copy.addArrangedSubview(actionRow)

        [featuredPlaceholder, featuredImage, featuredPlayer, overlay, copy].forEach { hero.addSubview($0) }
        NSLayoutConstraint.activate([
            hero.heightAnchor.constraint(equalToConstant: 350),
            featuredPlaceholder.leadingAnchor.constraint(equalTo: hero.leadingAnchor), featuredPlaceholder.trailingAnchor.constraint(equalTo: hero.trailingAnchor), featuredPlaceholder.topAnchor.constraint(equalTo: hero.topAnchor), featuredPlaceholder.bottomAnchor.constraint(equalTo: hero.bottomAnchor),
            featuredImage.leadingAnchor.constraint(equalTo: hero.leadingAnchor), featuredImage.trailingAnchor.constraint(equalTo: hero.trailingAnchor), featuredImage.topAnchor.constraint(equalTo: hero.topAnchor), featuredImage.bottomAnchor.constraint(equalTo: hero.bottomAnchor),
            featuredPlayer.leadingAnchor.constraint(equalTo: hero.leadingAnchor), featuredPlayer.trailingAnchor.constraint(equalTo: hero.trailingAnchor), featuredPlayer.topAnchor.constraint(equalTo: hero.topAnchor), featuredPlayer.bottomAnchor.constraint(equalTo: hero.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: hero.leadingAnchor), overlay.trailingAnchor.constraint(equalTo: hero.trailingAnchor), overlay.topAnchor.constraint(equalTo: hero.topAnchor), overlay.bottomAnchor.constraint(equalTo: hero.bottomAnchor),
            snowflake.trailingAnchor.constraint(equalTo: featuredPlaceholder.trailingAnchor, constant: -90), snowflake.topAnchor.constraint(equalTo: featuredPlaceholder.topAnchor, constant: 50),
            copy.leadingAnchor.constraint(equalTo: hero.leadingAnchor, constant: 28), copy.trailingAnchor.constraint(lessThanOrEqualTo: hero.trailingAnchor, constant: -22), copy.bottomAnchor.constraint(equalTo: hero.bottomAnchor, constant: -27)
        ])
        return hero
    }

    private func sectionHeading(_ title: String, subtitle: String) -> NSView {
        let heading = NSView()
        heading.translatesAutoresizingMaskIntoConstraints = false
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 19, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        let subtitleLabel = NSTextField(labelWithString: subtitle)
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        heading.addSubview(titleLabel)
        heading.addSubview(subtitleLabel)
        NSLayoutConstraint.activate([
            heading.heightAnchor.constraint(equalToConstant: 42), titleLabel.leadingAnchor.constraint(equalTo: heading.leadingAnchor), titleLabel.topAnchor.constraint(equalTo: heading.topAnchor),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor), subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3)
        ])
        return heading
    }

    private func buildCarousel() -> NSView {
        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        let strip = NSStackView()
        strip.orientation = .horizontal
        strip.alignment = .top
        strip.spacing = 12
        strip.translatesAutoresizingMaskIntoConstraints = false
        let choices = filteredChoices()
        visibleChoices = choices
        for (index, choice) in choices.prefix(8).enumerated() { strip.addArrangedSubview(wallpaperCard(choice, index: index, compact: true)) }
        wrapper.addSubview(strip)
        NSLayoutConstraint.activate([
            wrapper.heightAnchor.constraint(equalToConstant: 132), strip.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor), strip.trailingAnchor.constraint(lessThanOrEqualTo: wrapper.trailingAnchor), strip.topAnchor.constraint(equalTo: wrapper.topAnchor), strip.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor)
        ])
        return wrapper
    }

    private func buildWallpaperGrid() -> NSView {
        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        let grid = NSGridView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 14
        grid.columnSpacing = 14
        let choices = filteredChoices()
        visibleChoices = choices
        let columns = 4
        let shown = Array(choices.prefix(48))
        for start in stride(from: 0, to: shown.count, by: columns) {
            let rowChoices = Array(shown[start..<min(start + columns, shown.count)])
            let cards = rowChoices.enumerated().map { offset, choice in wallpaperCard(choice, index: start + offset, compact: false) }
            grid.addRow(with: cards)
        }
        wrapper.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor), grid.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor), grid.topAnchor.constraint(equalTo: wrapper.topAnchor), grid.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
            wrapper.heightAnchor.constraint(equalToConstant: CGFloat(max(1, (shown.count + columns - 1) / columns) * 190))
        ])
        return wrapper
    }

    private func wallpaperCard(_ choice: WallpaperChoice, index: Int, compact: Bool) -> NSView {
        let card = NSView()
        card.translatesAutoresizingMaskIntoConstraints = false
        let artwork = WallpaperArtworkView()
        artwork.translatesAutoresizingMaskIntoConstraints = false
        artwork.wantsLayer = true
        artwork.layer?.cornerRadius = compact ? 13 : 15
        artwork.layer?.masksToBounds = true
        let seed = abs(choice.name.hashValue % 5)
        let colors: [[CGFloat]] = [[0.10,0.26,0.34],[0.17,0.22,0.39],[0.28,0.17,0.29],[0.11,0.31,0.28],[0.30,0.25,0.15]]
        let c = colors[seed]
        artwork.layer?.backgroundColor = NSColor(calibratedRed: c[0], green: c[1], blue: c[2], alpha: 1).cgColor
        let icon = NSTextField(labelWithString: choice.isVideo ? "▶" : "❄")
        icon.font = .systemFont(ofSize: compact ? 17 : 21, weight: .medium)
        icon.textColor = NSColor(white: 1, alpha: 0.48)
        icon.translatesAutoresizingMaskIntoConstraints = false
        artwork.addSubview(icon)
        if choice.isVideo {
            if attachCardPreview(for: choice, in: artwork) { icon.isHidden = true }
        } else if let url = mediaURL(for: choice), let image = thumbnail(for: url, maxPixel: 500) {
            let thumb = NSImageView(image: image)
            thumb.translatesAutoresizingMaskIntoConstraints = false
            thumb.imageScaling = .scaleProportionallyUpOrDown
            thumb.wantsLayer = true
            thumb.layer?.contentsGravity = .resizeAspectFill
            artwork.addSubview(thumb)
            artwork.addSubview(icon)
            NSLayoutConstraint.activate([thumb.leadingAnchor.constraint(equalTo: artwork.leadingAnchor), thumb.trailingAnchor.constraint(equalTo: artwork.trailingAnchor), thumb.topAnchor.constraint(equalTo: artwork.topAnchor), thumb.bottomAnchor.constraint(equalTo: artwork.bottomAnchor)])
        }
        let name = NSTextField(labelWithString: choice.name)
        name.font = .systemFont(ofSize: compact ? 11 : 12, weight: .medium)
        name.textColor = .labelColor
        name.lineBreakMode = .byTruncatingMiddle
        name.translatesAutoresizingMaskIntoConstraints = false
        let source = NSTextField(labelWithString: choice.ext + (isGallery(choice) ? "  ·  GITHUB" : "  ·  MY WALLPAPERS"))
        source.font = .systemFont(ofSize: 9, weight: .medium)
        source.textColor = .secondaryLabelColor
        source.translatesAutoresizingMaskIntoConstraints = false
        let choose = NSButton(title: "", target: self, action: #selector(cardSelected(_:)))
        choose.tag = index
        choose.isBordered = false
        choose.translatesAutoresizingMaskIntoConstraints = false
        choose.setAccessibilityLabel("Set \(choice.name) as wallpaper")
        card.addSubview(artwork)
        card.addSubview(name)
        if !compact { card.addSubview(source) }
        card.addSubview(choose)
        NSLayoutConstraint.activate([
            card.widthAnchor.constraint(equalToConstant: compact ? 150 : 230),
            artwork.leadingAnchor.constraint(equalTo: card.leadingAnchor), artwork.trailingAnchor.constraint(equalTo: card.trailingAnchor), artwork.topAnchor.constraint(equalTo: card.topAnchor), artwork.heightAnchor.constraint(equalToConstant: compact ? 92 : 138),
            icon.centerXAnchor.constraint(equalTo: artwork.centerXAnchor), icon.centerYAnchor.constraint(equalTo: artwork.centerYAnchor),
            name.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 1), name.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -1), name.topAnchor.constraint(equalTo: artwork.bottomAnchor, constant: 7),
            choose.leadingAnchor.constraint(equalTo: card.leadingAnchor), choose.trailingAnchor.constraint(equalTo: card.trailingAnchor), choose.topAnchor.constraint(equalTo: card.topAnchor), choose.bottomAnchor.constraint(equalTo: card.bottomAnchor)
        ])
        if !compact {
            NSLayoutConstraint.activate([source.leadingAnchor.constraint(equalTo: name.leadingAnchor), source.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 3), source.bottomAnchor.constraint(equalTo: card.bottomAnchor)])
        } else {
            name.bottomAnchor.constraint(equalTo: card.bottomAnchor).isActive = true
        }
        return card
    }

    private func isGallery(_ choice: WallpaperChoice) -> Bool { if case .gallery = choice { return true }; return false }

    private func filteredChoices() -> [WallpaperChoice] {
        let query = searchField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let remote = remoteWallpapers.filter { query.isEmpty || $0.name.localizedStandardContains(query) }.map(WallpaperChoice.gallery)
        let local = localWallpapers.filter { query.isEmpty || library.displayName(for: $0).localizedStandardContains(query) }.map(WallpaperChoice.personal)
        switch currentSection {
        case .home: return Array(remote.prefix(24)) + Array(local.prefix(12))
        case .explore: return remote
        case .library: return local
        }
    }

    private func sectionTitle() -> String {
        switch currentSection { case .home: "Starship’s collection"; case .explore: "Explore the gallery"; case .library: "My Wallpapers" }
    }
    private func sectionSubtitle() -> String {
        switch currentSection {
        case .home: "Video previews loop while this window is open · click a wallpaper to set it"
        case .explore: "Video previews loop while open · click to set · saves to Snowflake on launch"
        case .library: "Video previews loop while open · click to set · stored in ~/Applications/Snowflake"
        }
    }

    @objc private func sectionChanged(_ sender: NSSegmentedControl) {
        currentSection = Section(rawValue: sender.selectedSegment) ?? .home
        rebuildContent()
    }

    @objc private func cardSelected(_ sender: NSButton) {
        let choices = filteredChoices()
        guard choices.indices.contains(sender.tag) else { return }
        select(choices[sender.tag])
        useSelectedWallpaper()
    }

    private func attachCardPreview(for choice: WallpaperChoice, in artwork: NSView) -> Bool {
        guard choice.isVideo, let url = mediaURL(for: choice) else { return false }
        let key = url.standardizedFileURL.path
        let preview = liveCardPreviews[key] ?? LiveCardPreview(url: url)
        liveCardPreviews[key] = preview
        _ = preview.attach(to: artwork)
        return true
    }

    private func detachCardPreviewLayers() {
        liveCardPreviews.values.forEach { $0.detachLayers() }
    }

    private func startVisibleCardPreviews() {
        let unused = liveCardPreviews.filter { $0.value.layers.isEmpty }.map(\.key)
        for key in unused {
            liveCardPreviews.removeValue(forKey: key)?.stop()
        }
        guard window?.isVisible == true else {
            liveCardPreviews.values.forEach { $0.player.pause() }
            return
        }
        liveCardPreviews.values.forEach { $0.player.play() }
    }

    private func stopAllCardPreviews() {
        liveCardPreviews.values.forEach { $0.stop() }
        liveCardPreviews.removeAll()
    }

    private func mediaURL(for choice: WallpaperChoice) -> URL? {
        switch choice {
        case .personal(let url): url
        case .gallery(let item): library.cachedGalleryWallpaper(identifier: item.path, expectedSize: item.size)
        }
    }

    private func thumbnail(for url: URL, maxPixel: Int = 600) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    private func select(_ choice: WallpaperChoice) {
        stopPreview()
        selectedChoice = choice
        selectedGallery = nil
        primaryButton.isEnabled = true
        featuredImage.image = nil
        featuredImage.isHidden = true
        featuredPlayer.isHidden = true
        featuredPlaceholder.isHidden = false
        switch choice {
        case .gallery(let item):
            selectedGallery = item
            featuredName.stringValue = item.name
            let isSaved = library.cachedGalleryWallpaper(identifier: item.path, expectedSize: item.size) != nil
            featuredDetails.stringValue = "GitHub gallery  ·  \(item.fileExtension.uppercased())  ·  \(WallpaperLibrary.formatBytes(item.size))  ·  \(isSaved ? "Saved in Snowflake" : "Saving to Snowflake")"
            primaryButton.title = isSaved ? "Set as Desktop" : "Save & Set as Desktop"
            if let local = library.cachedGalleryWallpaper(identifier: item.path, expectedSize: item.size) {
                if item.isVideo {
                    featuredPlaceholder.isHidden = true
                    showVideoPreview(local)
                } else if let image = thumbnail(for: local, maxPixel: 1000) {
                    featuredImage.image = image
                    featuredImage.isHidden = false
                }
            }
        case .personal(let url):
            featuredName.stringValue = library.displayName(for: url)
            featuredDetails.stringValue = "On this Mac  ·  \(url.pathExtension.uppercased())  ·  My Wallpapers"
            primaryButton.title = "Set as Desktop"
            featuredPlaceholder.isHidden = true
            if choice.isVideo {
                showVideoPreview(url)
            } else if let image = thumbnail(for: url, maxPixel: 1000) {
                featuredImage.image = image
                featuredImage.isHidden = false
            } else {
                featuredPlaceholder.isHidden = false
            }
        }
    }

    private func showVideoPreview(_ url: URL) {
        let key = url.standardizedFileURL.path
        if let sharedPreview = liveCardPreviews[key] {
            featuredPreviewUsesCardPlayer = true
            featuredPlayer.player = sharedPreview.player
        } else {
            let item = AVPlayerItem(url: url)
            item.preferredForwardBufferDuration = 2
            let player = AVQueuePlayer()
            player.isMuted = true
            previewLooper = AVPlayerLooper(player: player, templateItem: item)
            previewPlayer = player
            featuredPreviewUsesCardPlayer = false
            featuredPlayer.player = player
            player.play()
        }
        featuredPlayer.isHidden = false
    }

    private func stopPreview() {
        if !featuredPreviewUsesCardPlayer { previewPlayer?.pause() }
        previewPlayer = nil
        previewLooper = nil
        featuredPreviewUsesCardPlayer = false
        featuredPlayer?.player = nil
        featuredPlayer?.isHidden = true
    }

    func controlTextDidChange(_ notification: Notification) { rebuildContent() }

    private func refreshLibrary() {
        localWallpapers = library.wallpapers(excludingGalleryNames: knownGalleryNames)
        if selectedChoice == nil,
           let active = library.active(),
           localWallpapers.contains(where: { $0.standardizedFileURL == active.standardizedFileURL }) {
            selectedChoice = .personal(active)
        }
        rebuildContent()
    }

    @objc private func loadGallery() {
        guard !galleryLoadInProgress else { return }
        galleryLoadInProgress = true
        statusLabel?.stringValue = "Loading GitHub wallpapers…"
        gallery.fetch { [weak self] result in
            guard let self else { return }
            self.galleryLoadInProgress = false
            switch result {
            case .success(let items):
                self.remoteWallpapers = items
                self.knownGalleryNames = Set(items.map { $0.name.lowercased() })
                UserDefaults.standard.set(Array(self.knownGalleryNames), forKey: "knownGitHubWallpaperNames")
                self.statusLabel.stringValue = "Found \(items.count) GitHub wallpapers. Saving them to Snowflake…"
                self.downloadAllGalleryWallpapers(items)
            case .failure:
                self.statusLabel.stringValue = "Couldn’t load the GitHub gallery. Check your connection and try Refresh."
            }
            self.refreshLibrary()
        }
    }

    private func downloadAllGalleryWallpapers(_ items: [GalleryWallpaper]) {
        galleryDownloadQueue = items
        galleryDownloadIndex = 0
        galleryDownloadBytes = 0
        galleryDownloadFailures = 0
        downloadNextGalleryWallpaper()
    }

    private func downloadNextGalleryWallpaper() {
        while galleryDownloadIndex < galleryDownloadQueue.count {
            let item = galleryDownloadQueue[galleryDownloadIndex]
            galleryDownloadIndex += 1
            if library.cachedGalleryWallpaper(identifier: item.path, expectedSize: item.size) != nil {
                galleryDownloadBytes += item.size
                continue
            }
            currentBulkDownloadPath = item.path
            statusLabel.stringValue = "Downloading wallpaper \(galleryDownloadIndex) of \(galleryDownloadQueue.count) · \(item.name)"
            gallery.download(item) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let temporaryFile):
                    DispatchQueue.global(qos: .utility).async {
                        do {
                            let local = try self.library.storeGalleryWallpaper(temporaryFile, named: item.name, identifier: item.path)
                            try? FileManager.default.removeItem(at: temporaryFile)
                            DispatchQueue.main.async {
                                self.galleryDownloadBytes += item.size
                                self.currentBulkDownloadPath = nil
                                if item.isVideo { self.rebuildContent() }
                                if self.pendingApplyGalleryPath == item.path {
                                    self.pendingApplyGalleryPath = nil
                                    self.applyGalleryWallpaper(local, item: item)
                                }
                                self.downloadNextGalleryWallpaper()
                            }
                        } catch {
                            try? FileManager.default.removeItem(at: temporaryFile)
                            DispatchQueue.main.async {
                                self.galleryDownloadFailures += 1
                                self.currentBulkDownloadPath = nil
                                if self.pendingApplyGalleryPath == item.path { self.pendingApplyGalleryPath = nil; self.primaryButton.isEnabled = true }
                                self.downloadNextGalleryWallpaper()
                            }
                        }
                    }
                case .failure:
                    self.galleryDownloadFailures += 1
                    self.currentBulkDownloadPath = nil
                    if self.pendingApplyGalleryPath == item.path { self.pendingApplyGalleryPath = nil; self.primaryButton.isEnabled = true }
                    self.downloadNextGalleryWallpaper()
                }
            }
            return
        }
        currentBulkDownloadPath = nil
        let total = WallpaperLibrary.formatBytes(galleryDownloadBytes)
        if galleryDownloadFailures == 0 {
            statusLabel.stringValue = "All \(galleryDownloadQueue.count) GitHub wallpapers are saved in ~/Applications/Snowflake · \(total)"
        } else {
            statusLabel.stringValue = "Saved \(galleryDownloadQueue.count - galleryDownloadFailures) wallpapers · \(galleryDownloadFailures) will retry next time you open Starship"
        }
        rebuildContent()
    }

    @objc private func importWallpaper() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.movie, .image]
        panel.prompt = "Import wallpapers"
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        importButton.isEnabled = false
        statusLabel.stringValue = urls.count == 1 ? "Importing wallpaper…" : "Importing \(urls.count) wallpapers…"
        DispatchQueue.global(qos: .userInitiated).async {
            var lastImported: URL?
            var importError: Error?
            for (index, url) in urls.enumerated() {
                DispatchQueue.main.async { self.statusLabel.stringValue = "Importing \(index + 1) of \(urls.count)…" }
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
                do { lastImported = try self.library.importWallpaper(url) } catch { importError = error; break }
            }
            DispatchQueue.main.async {
                self.importButton.isEnabled = true
                self.refreshLibrary()
                if let importError { self.statusLabel.stringValue = "Import couldn’t be completed."; self.alert("Could not import wallpaper", importError.localizedDescription) }
                else if let lastImported { self.statusLabel.stringValue = "Added \(self.library.displayName(for: lastImported)) to My Wallpapers."; self.currentSection = .library; self.sectionControl.selectedSegment = Section.library.rawValue; self.rebuildContent(); self.select(.personal(lastImported)) }
            }
        }
    }

    @objc private func useSelectedWallpaper() {
        guard let choice = selectedChoice else { return }
        primaryButton.isEnabled = false
        switch choice {
        case .gallery(let item):
            if let local = library.cachedGalleryWallpaper(identifier: item.path, expectedSize: item.size) {
                applyGalleryWallpaper(local, item: item)
            } else if currentBulkDownloadPath == item.path || galleryDownloadQueue[galleryDownloadIndex...].contains(where: { $0.path == item.path }) {
                pendingApplyGalleryPath = item.path
                statusLabel.stringValue = "Saving \(item.name) to Snowflake… it will be set when ready."
            } else {
                statusLabel.stringValue = "Downloading \(item.name)…"
                gallery.download(item) { [weak self] result in
                    guard let self else { return }
                    switch result {
                    case .success(let temporaryFile):
                        DispatchQueue.global(qos: .userInitiated).async {
                            do {
                                let local = try self.library.storeGalleryWallpaper(temporaryFile, named: item.name, identifier: item.path)
                                try? FileManager.default.removeItem(at: temporaryFile)
                                DispatchQueue.main.async { self.applyGalleryWallpaper(local, item: item) }
                            } catch {
                                try? FileManager.default.removeItem(at: temporaryFile)
                                DispatchQueue.main.async { self.primaryButton.isEnabled = true; self.alert("Could not use wallpaper", error.localizedDescription) }
                            }
                        }
                    case .failure(let error): self.primaryButton.isEnabled = true; self.statusLabel.stringValue = "Download failed. Try again."; self.alert("Could not download wallpaper", error.localizedDescription)
                    }
                }
            }
        case .personal(let url):
            do { stopPreview(); featuredPlaceholder?.isHidden = false; try library.setActive(url); try wallpaper.play(url); statusLabel.stringValue = "Set \(url.lastPathComponent) as your desktop wallpaper." }
            catch { alert("Could not set wallpaper", error.localizedDescription) }
            primaryButton.isEnabled = true
        }
    }

    private func applyGalleryWallpaper(_ local: URL, item: GalleryWallpaper) {
        do {
            stopPreview()
            featuredPlaceholder?.isHidden = false
            try library.setActive(local)
            try wallpaper.play(local)
            statusLabel.stringValue = "Set \(item.name) as your desktop wallpaper."
            primaryButton.isEnabled = true
        } catch {
            primaryButton.isEnabled = true
            alert("Could not use wallpaper", error.localizedDescription)
        }
    }

    @objc private func toggleWallpaperMute() { wallpaper.toggleMute(); refreshVolumeControls() }
    @objc private func volumeChanged(_ sender: NSSlider) { wallpaper.setVolume(Float(sender.doubleValue)); refreshVolumeControls() }
    @objc private func menuVolumeChanged(_ sender: NSSlider) { wallpaper.setVolume(Float(sender.doubleValue)); refreshVolumeControls() }

    private func refreshVolumeControls() {
        muteMenuItem?.title = wallpaper.isMuted ? "Unmute Wallpaper" : "Mute Wallpaper"
        menuVolumeSlider?.doubleValue = Double(wallpaper.volume)
        volumeSlider?.doubleValue = Double(wallpaper.volume)
        muteButton?.image = NSImage(systemSymbolName: wallpaper.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", accessibilityDescription: wallpaper.isMuted ? "Unmute wallpaper" : "Mute wallpaper")
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Starship Snowflake 2026.1"
        alert.informativeText = "Author: r4ph1-2015\n\nBrowse the Starship GitHub collection, import wallpapers from your Mac, and set a video or image as your desktop. GitHub wallpapers are saved in ~/Applications/Snowflake the first time Starship opens."
        alert.alertStyle = .informational
        if let window, window.isVisible { alert.beginSheetModal(for: window, completionHandler: nil) } else { alert.runModal() }
    }

    private func iconButton(_ symbol: String, help: String, action: Selector) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: help) ?? NSImage(), target: self, action: action)
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.toolTip = help
        button.contentTintColor = NSColor(white: 1, alpha: 0.85)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 30).isActive = true
        button.heightAnchor.constraint(equalToConstant: 30).isActive = true
        return button
    }

    private func alert(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.alertStyle = .warning
        if let window { alert.beginSheetModal(for: window, completionHandler: nil) } else { alert.runModal() }
    }
}

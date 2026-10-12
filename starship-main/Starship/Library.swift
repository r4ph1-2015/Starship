import Foundation
import CryptoKit

final class WallpaperLibrary {
    private struct FingerprintRecord: Codable {
        let size: Int64
        let modified: TimeInterval
        let digest: String
    }

    let directory: URL
    private let activeFile: URL
    private let galleryDirectory: URL
    private let userImportsFile: URL
    private let galleryDownloadsFile: URL
    private let fingerprintCacheFile: URL
    private let supported = Set(["mp4", "mov", "m4v", "jpg", "jpeg", "png", "webp", "gif", "avif", "heic", "heif"])
    private let fingerprintLock = NSLock()
    private let galleryDownloadsLock = NSLock()
    private var fingerprintRecords: [String: FingerprintRecord] = [:]
    private var galleryDownloads: [String: String] = [:]

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let starshipDirectory = support.appendingPathComponent("Starship", isDirectory: true)
        let applications = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        directory = applications.appendingPathComponent("Snowflake", isDirectory: true)
        galleryDirectory = starshipDirectory.appendingPathComponent("GalleryDownloads", isDirectory: true)
        activeFile = starshipDirectory.appendingPathComponent("active.txt")
        userImportsFile = starshipDirectory.appendingPathComponent("user-imports.plist")
        galleryDownloadsFile = starshipDirectory.appendingPathComponent("gallery-downloads.plist")
        fingerprintCacheFile = starshipDirectory.appendingPathComponent("fingerprints.plist")
        if let data = try? Data(contentsOf: fingerprintCacheFile),
           let records = try? PropertyListDecoder().decode([String: FingerprintRecord].self, from: data) {
            fingerprintRecords = records
        }
        if let data = try? Data(contentsOf: galleryDownloadsFile),
           let records = try? PropertyListDecoder().decode([String: String].self, from: data) {
            galleryDownloads = records
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: galleryDirectory, withIntermediateDirectories: true)
    }

    func importWallpaper(_ source: URL) throws -> URL {
        let ext = source.pathExtension.lowercased()
        guard supported.contains(ext) else {
            throw NSError(domain: "Starship", code: 1, userInfo: [NSLocalizedDescriptionKey: "Choose a supported video or image wallpaper."])
        }
        // Reuse an existing identical wallpaper instead of creating another copy
        // every time it is downloaded or imported.
        if let sourceFingerprint = fingerprint(source, persist: false),
           let existing = matchingImportedWallpaper(named: source.lastPathComponent, fingerprint: sourceFingerprint) {
            markAsUserImported(existing)
            try setActive(existing)
            return existing
        }

        let baseName = source.lastPathComponent
        var destination = directory.appendingPathComponent(baseName)
        var suffix = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            let stem = source.deletingPathExtension().lastPathComponent
            destination = directory.appendingPathComponent("\(stem) (\(suffix)).\(ext)")
            suffix += 1
        }
        try FileManager.default.copyItem(at: source, to: destination)
        markAsUserImported(destination)
        try setActive(destination)
        return destination
    }

    func cachedGalleryWallpaper(identifier: String, expectedSize: Int? = nil) -> URL? {
        galleryDownloadsLock.lock()
        let filename = galleryDownloads[identifier]
        galleryDownloadsLock.unlock()
        guard let filename else { return nil }
        let file = directory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        if let expectedSize {
            guard let actualSize = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  actualSize == expectedSize else { return nil }
        }
        return file
    }

    func storeGalleryWallpaper(_ source: URL, named name: String, identifier: String) throws -> URL {
        let ext = URL(fileURLWithPath: name).pathExtension.lowercased()
        guard supported.contains(ext) else {
            throw NSError(domain: "Starship", code: 3, userInfo: [NSLocalizedDescriptionKey: "This GitHub wallpaper format is not supported."])
        }
        let cleanName = URL(fileURLWithPath: name).lastPathComponent
        galleryDownloadsLock.lock()
        let existingFilename = galleryDownloads[identifier]
        galleryDownloadsLock.unlock()
        var destination = existingFilename.map { directory.appendingPathComponent($0) }
        if let existing = destination,
           FileManager.default.fileExists(atPath: existing.path),
           fingerprint(existing) == fingerprint(source, persist: false) {
            saveFingerprintCache()
            return existing
        }
        if destination == nil {
            destination = directory.appendingPathComponent(cleanName)
            if let candidate = destination, FileManager.default.fileExists(atPath: candidate.path) {
                let stem = URL(fileURLWithPath: cleanName).deletingPathExtension().lastPathComponent
                let extPart = URL(fileURLWithPath: cleanName).pathExtension
                var suffix = 1
                repeat {
                    let suffixText = suffix == 1 ? "GitHub" : "GitHub \(suffix)"
                    destination = directory.appendingPathComponent("\(stem) (\(suffixText)).\(extPart)")
                    suffix += 1
                } while destination.map { FileManager.default.fileExists(atPath: $0.path) } == true
            }
        }
        guard let destination else { throw NSError(domain: "Starship", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not choose a file name for this wallpaper."]) }
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.copyItem(at: source, to: destination)
        galleryDownloadsLock.lock()
        galleryDownloads[identifier] = destination.lastPathComponent
        if let data = try? PropertyListEncoder().encode(galleryDownloads) {
            try? data.write(to: galleryDownloadsFile, options: .atomic)
        }
        galleryDownloadsLock.unlock()
        saveFingerprintCache()
        return destination
    }

    func wallpapers(excludingGalleryNames galleryNames: Set<String> = []) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        let importedNames = userImportedNames()
        galleryDownloadsLock.lock()
        let downloadedNames = Set(galleryDownloads.values)
        galleryDownloadsLock.unlock()
        let normalizedGalleryNames = Set(galleryNames.map { $0.lowercased() })
        let candidates = urls.filter { url in
            guard supported.contains(url.pathExtension.lowercased()) else { return false }
            return importedNames.contains(url.lastPathComponent) ||
                (!downloadedNames.contains(url.lastPathComponent) &&
                 !isLegacyGalleryDownload(url) &&
                 !normalizedGalleryNames.contains(displayName(for: url).lowercased()))
        }
        var unique: [String: URL] = [:]
        let activeURL = active()?.standardizedFileURL
        for url in candidates {
            let key = "\(displayName(for: url).lowercased())|\(fingerprint(url) ?? url.lastPathComponent)"
            guard let current = unique[key] else {
                unique[key] = url
                continue
            }
            if url.standardizedFileURL == activeURL ||
                (current.standardizedFileURL != activeURL && isCleanerName(url, than: current)) ||
                (importedNames.contains(url.lastPathComponent) && !importedNames.contains(current.lastPathComponent)) {
                unique[key] = url
            }
        }
        saveFingerprintCache()
        return unique.values.sorted {
            displayName(for: $0).localizedStandardCompare(displayName(for: $1)) == .orderedAscending
        }
    }

    func displayName(for url: URL) -> String {
        var name = url.lastPathComponent
        let uuidPrefix = #"^(?:starship-)?[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}[-_]"#
        while let range = name.range(of: uuidPrefix, options: .regularExpression) {
            name.removeSubrange(range)
        }
        return name
    }

    private func isLegacyGalleryDownload(_ url: URL) -> Bool {
        var name = url.lastPathComponent
        let uuidPrefix = #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}[-_]"#
        while let range = name.range(of: uuidPrefix, options: .regularExpression) {
            name.removeSubrange(range)
        }
        let stagedGalleryName = #"^starship-[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}[-_]"#
        return name.range(of: stagedGalleryName, options: .regularExpression) != nil
    }

    private func userImportedNames() -> Set<String> {
        guard let data = try? Data(contentsOf: userImportsFile),
              let names = try? PropertyListDecoder().decode(Set<String>.self, from: data) else { return [] }
        return names
    }

    private func markAsUserImported(_ url: URL) {
        var names = userImportedNames()
        names.insert(url.lastPathComponent)
        if let data = try? PropertyListEncoder().encode(names) {
            try? data.write(to: userImportsFile, options: .atomic)
        }
    }

    private func isCleanerName(_ lhs: URL, than rhs: URL) -> Bool {
        let lhsName = lhs.lastPathComponent
        let rhsName = rhs.lastPathComponent
        let lhsClean = displayName(for: lhs) == lhsName
        let rhsClean = displayName(for: rhs) == rhsName
        if lhsClean != rhsClean { return lhsClean }
        return lhsName.localizedStandardCompare(rhsName) == .orderedAscending
    }

    // A bounded first/last sample keeps startup work small even for large videos.
    // Combined with normalized names, it identifies duplicate copies from older imports.
    private func matchingImportedWallpaper(named name: String, fingerprint expected: String) -> URL? {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        let match = urls.first { url in
            supported.contains(url.pathExtension.lowercased()) &&
                displayName(for: url).caseInsensitiveCompare(name) == .orderedSame &&
                fingerprint(url) == expected
        }
        saveFingerprintCache()
        return match
    }

    private func fingerprint(_ url: URL, persist: Bool = true) -> String? {
        let chunkSize = 64 * 1024
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? NSNumber,
              let modificationDate = attributes[.modificationDate] as? Date,
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = fileSize.int64Value
        let modified = modificationDate.timeIntervalSince1970
        let cacheKey = url.standardizedFileURL.path
        if persist {
            fingerprintLock.lock()
            let cached = fingerprintRecords[cacheKey]
            fingerprintLock.unlock()
            if let cached, cached.size == size, cached.modified == modified { return cached.digest }
        }
        guard let first = try? handle.read(upToCount: chunkSize) else { return nil }
        var sample = first
        if size > chunkSize {
            do {
                try handle.seek(toOffset: UInt64(max(0, size - Int64(chunkSize))))
                sample.append(try handle.read(upToCount: chunkSize) ?? Data())
            } catch { return nil }
        }
        sample.append(contentsOf: withUnsafeBytes(of: size.bigEndian, Array.init))
        let digest = SHA256.hash(data: sample).map { String(format: "%02x", $0) }.joined()
        if persist {
            fingerprintLock.lock()
            fingerprintRecords[cacheKey] = FingerprintRecord(size: size, modified: modified, digest: digest)
            fingerprintLock.unlock()
        }
        return digest
    }

    private func saveFingerprintCache() {
        fingerprintLock.lock()
        defer { fingerprintLock.unlock() }
        guard let data = try? PropertyListEncoder().encode(fingerprintRecords) else { return }
        try? data.write(to: fingerprintCacheFile, options: .atomic)
    }

    func setActive(_ url: URL) throws {
        let parent = url.deletingLastPathComponent().standardizedFileURL
        guard parent == directory.standardizedFileURL || parent == galleryDirectory.standardizedFileURL,
              FileManager.default.fileExists(atPath: url.path) else {
            throw NSError(domain: "Starship", code: 2, userInfo: [NSLocalizedDescriptionKey: "This wallpaper is no longer available in your library."])
        }
        try url.path.write(to: activeFile, atomically: true, encoding: .utf8)
    }

    static func formatBytes(_ size: Int) -> String {
        let bytes = Double(max(0, size))
        if bytes < 1024 { return "\(Int(bytes)) B" }
        let units = ["KB", "MB", "GB", "TB"]
        var value = bytes / 1024
        var unit = 0
        while value >= 1024 && unit < units.count - 1 { value /= 1024; unit += 1 }
        return String(format: value >= 100 ? "%.0f %@" : value >= 10 ? "%.1f %@" : "%.2f %@", value, units[unit])
    }

    func active() -> URL? {
        guard let path = try? String(contentsOf: activeFile, encoding: .utf8), !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path.trimmingCharacters(in: .whitespacesAndNewlines))
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

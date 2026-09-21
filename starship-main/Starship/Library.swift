import Foundation

final class WallpaperLibrary {
    let directory: URL
    private let activeFile: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = support.appendingPathComponent("Starship/Wallpapers", isDirectory: true)
        activeFile = directory.appendingPathComponent("active.txt")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func importVideo(_ source: URL) throws -> URL {
        let ext = source.pathExtension.lowercased()
        guard ["mp4", "mov", "m4v"].contains(ext) else { throw NSError(domain: "Starship", code: 1, userInfo: [NSLocalizedDescriptionKey: "Choose an MP4, MOV, or M4V video."]) }
        let dest = directory.appendingPathComponent(UUID().uuidString + "-" + source.lastPathComponent)
        try FileManager.default.copyItem(at: source, to: dest)
        try dest.path.write(to: activeFile, atomically: true, encoding: .utf8)
        return dest
    }

    func active() -> URL? {
        guard let p = try? String(contentsOf: activeFile, encoding: .utf8), !p.isEmpty else { return nil }
        let url = URL(fileURLWithPath: p.trimmingCharacters(in: .whitespacesAndNewlines))
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

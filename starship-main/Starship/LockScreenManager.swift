import Foundation
import AVFoundation

final class LockScreenManager {
    private let fm = FileManager.default
    private let base: URL
    private let aerials: URL
    private let videos: URL
    private let index: URL
    private let backup: URL
    private let encoder = TemporalEncoder()

    init() {
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        base = support.appendingPathComponent("com.apple.wallpaper")
        aerials = base.appendingPathComponent("aerials")
        videos = aerials.appendingPathComponent("videos")
        index = base.appendingPathComponent("Store/Index.plist")
        backup = support.appendingPathComponent("Starship/LockScreenBackups")
    }

    func apply(source: URL, progress: @escaping (Int, String) -> Void) throws {
        guard #available(macOS 26, *) else { throw NSError(domain: "Starship", code: 26, userInfo: [NSLocalizedDescriptionKey: "Lock Screen mode requires macOS Tahoe (26) or newer."]) }
        guard fm.fileExists(atPath: index.path), fm.fileExists(atPath: videos.path) else { throw NSError(domain: "Starship", code: 2, userInfo: [NSLocalizedDescriptionKey: "Open System Settings → Wallpaper and download an Apple Aerial first."]) }
        try fm.createDirectory(at: backup, withIntermediateDirectories: true)
        progress(2, "Preparing Lock Screen")
        try backupOriginals()
        let slot = try activeOrBestAerialSlot()
        progress(5, "Encoding HEVC Main10")
        let asset = AVAsset(url: source); let duration = asset.duration.seconds
        let loops = duration > 0 && duration < 285 ? max(1, min(8, Int(ceil(300 / duration)))) : 1
        let temp = videos.appendingPathComponent(".starship-\(UUID().uuidString).mov")
        try encoder.encode(source: source, output: temp, loopCount: loops, bitrateMbps: 12) { p in progress(5 + Int(Double(p) * 0.84), "Encoding Lock Screen video") }
        guard fm.fileExists(atPath: temp.path) else { throw NSError(domain: "Starship", code: 3, userInfo: [NSLocalizedDescriptionKey: "Native encoder produced no movie."]) }
        progress(90, "Verifying encoded movie")
        guard verifyTemporalMetadata(temp) else { throw NSError(domain: "Starship", code: 4, userInfo: [NSLocalizedDescriptionKey: "Encoded movie is missing Tahoe temporal HEVC metadata (tscl/tsas)."] ) }
        progress(93, "Installing Aerial video")
        stopWallpaperProcesses(); try? fm.removeItem(at: slot); try fm.moveItem(at: temp, to: slot)
        progress(95, "Selecting Lock Screen Aerial")
        try updateIndexAssetID(slot.deletingPathExtension().lastPathComponent)
        restartWallpaperProcesses(); progress(100, "Complete")
    }

    func restore() throws {
        let indexBackup = backup.appendingPathComponent("Index.plist.apple-original")
        guard fm.fileExists(atPath: indexBackup.path) else { throw NSError(domain: "Starship", code: 10, userInfo: [NSLocalizedDescriptionKey: "No Starship Lock Screen backup was found."]) }
        let files = try fm.contentsOfDirectory(at: backup, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasSuffix(".apple-original.mov") }
        stopWallpaperProcesses()
        for file in files { let name = file.deletingPathExtension().lastPathComponent.replacingOccurrences(of: ".apple-original", with: ""); let target = videos.appendingPathComponent(name + ".mov"); if fm.fileExists(atPath: target.path) { try? fm.removeItem(at: target) }; try fm.copyItem(at: file, to: target) }
        if fm.fileExists(atPath: index.path) { try fm.removeItem(at: index) }; try fm.copyItem(at: indexBackup, to: index); restartWallpaperProcesses()
    }

    private func backupOriginals() throws {
        if !fm.fileExists(atPath: backup.appendingPathComponent("Index.plist.apple-original").path) { try fm.copyItem(at: index, to: backup.appendingPathComponent("Index.plist.apple-original")) }
        let slot = try activeOrBestAerialSlot(); let b = backup.appendingPathComponent(slot.lastPathComponent + ".apple-original.mov"); if !fm.fileExists(atPath: b.path) { try fm.copyItem(at: slot, to: b) }
    }

    private func activeOrBestAerialSlot() throws -> URL {
        let candidates = try fm.contentsOfDirectory(at: videos, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]).filter { $0.pathExtension.lowercased() == "mov" }
        if candidates.isEmpty { throw NSError(domain: "Starship", code: 5, userInfo: [NSLocalizedDescriptionKey: "No downloaded Apple Aerial video was found."]) }
        if let live = findLiveAerial() { return live }
        var best = candidates[0]
        var bestSize: Int64 = -1
        for candidate in candidates {
            let size = Int64((try? candidate.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            if size > bestSize {
                best = candidate
                bestSize = size
            }
        }
        return best
    }

    private func findLiveAerial() -> URL? {
        for name in ["WallpaperAerialsExtension", "WallpaperAerialExtension", "WallpaperAerial", "WallpaperVideoExtension"] {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep"); p.arguments = ["-x", name]; let pipe = Pipe(); p.standardOutput = pipe; try? p.run(); p.waitUntilExit()
            let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            for pid in text.split(whereSeparator: \.isNewline) {
                let l = Process(); l.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof"); l.arguments = ["-Fn", "-p", String(pid)]; let lp = Pipe(); l.standardOutput = lp; try? l.run(); l.waitUntilExit(); let out = String(data: lp.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                for line in out.split(separator: "\n") where line.hasPrefix("n") && line.contains("/aerials/videos/") && line.hasSuffix(".mov") { let u = URL(fileURLWithPath: String(line.dropFirst())); if fm.fileExists(atPath: u.path) { return u } }
            }
        }; return nil
    }

    private func updateIndexAssetID(_ slotID: String) throws {
        var obj = try PropertyListSerialization.propertyList(from: Data(contentsOf: index), options: [], format: nil)
        func walk(_ value: inout Any) -> Bool {
            if var d = value as? [String: Any] {
                if let content = d["Content"] as? [String: Any], let choices = content["Choices"] as? [[String: Any]] {
                    for choice in choices where (choice["Provider"] as? String) == "com.apple.wallpaper.choice.aerials" {
                        if var config = choice["Configuration"] as? Data, var nested = try? PropertyListSerialization.propertyList(from: config, options: [], format: nil) { replaceAssetIDs(&nested, with: slotID); config = try! PropertyListSerialization.data(fromPropertyList: nested, format: .binary, options: 0); var c = choice; c["Configuration"] = config; var cs = choices; if let i = cs.firstIndex(where: { ($0["Provider"] as? String) == "com.apple.wallpaper.choice.aerials" }) { cs[i] = c; var nc = content; nc["Choices"] = cs; d["Content"] = nc; value = d; return true } }
                    }
                }
                for key in d.keys { var child = d[key]!; if walk(&child) { d[key] = child; value = d; return true } }
            } else if var a = value as? [Any] { for i in a.indices { var child = a[i]; if walk(&child) { a[i] = child; value = a; return true } } }
            return false
        }
        _ = walk(&obj)
        let data = try PropertyListSerialization.data(fromPropertyList: obj, format: .binary, options: 0); try data.write(to: index, options: .atomic)
    }

    private func replaceAssetIDs(_ value: inout Any, with id: String) {
        if var d = value as? [String: Any] { for k in d.keys { if k == "assetID", d[k] is String { d[k] = id } else if var child = d[k] { replaceAssetIDs(&child, with: id); d[k] = child } }; value = d }
        else if var a = value as? [Any] { for i in a.indices { replaceAssetIDs(&a[i], with: id) }; value = a }
    }

    private func verifyTemporalMetadata(_ url: URL) -> Bool { guard let data = try? Data(contentsOf: url) else { return false }; let tscl = data.range(of: Data("tscl".utf8)) != nil; let tsas = data.range(of: Data("tsas".utf8)) != nil; return tscl && tsas }
    private func stopWallpaperProcesses() { for p in ["WallpaperAerialsExtension", "WallpaperAerialExtension", "WallpaperAgent"] { let x = Process(); x.executableURL = URL(fileURLWithPath: "/usr/bin/killall"); x.arguments = [p]; try? x.run(); x.waitUntilExit() }; Thread.sleep(forTimeInterval: 1) }
    private func restartWallpaperProcesses() { stopWallpaperProcesses(); Thread.sleep(forTimeInterval: 3) }
}

import Foundation

struct GalleryWallpaper {
    let path: String
    let size: Int

    var name: String { URL(fileURLWithPath: path).lastPathComponent }
    var fileExtension: String { URL(fileURLWithPath: path).pathExtension.lowercased() }
    var isVideo: Bool { ["mp4", "mov", "m4v"].contains(fileExtension) }
    var url: URL? {
        let encodedPath = path.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }.joined(separator: "/")
        return URL(string: "https://raw.githubusercontent.com/r4ph1-2015/Starship/main/\(encodedPath)")
    }
}

final class GalleryCatalog {
    private struct TreeResponse: Decodable {
        let tree: [TreeEntry]
        let truncated: Bool
    }

    private struct TreeEntry: Decodable {
        let path: String
        let type: String
        let size: Int?
    }

    private let supported = Set(["jpg", "jpeg", "png", "webp", "gif", "avif", "heic", "heif", "mp4", "mov", "m4v"])
    private let treeURL = URL(string: "https://api.github.com/repos/r4ph1-2015/Starship/git/trees/main?recursive=1")!

    func fetch(completion: @escaping (Result<[GalleryWallpaper], Error>) -> Void) {
        var request = URLRequest(url: treeURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Starship-Snowflake/2026.1", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: request) { [supported] data, response, error in
            if let error { DispatchQueue.main.async { completion(.failure(error)) }; return }
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode), let data else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                let error = NSError(domain: "StarshipGallery", code: code, userInfo: [NSLocalizedDescriptionKey: "The Starship gallery is unavailable right now."])
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            do {
                let tree = try JSONDecoder().decode(TreeResponse.self, from: data)
                guard !tree.truncated else { throw NSError(domain: "StarshipGallery", code: 1, userInfo: [NSLocalizedDescriptionKey: "The GitHub gallery is too large to load completely."]) }
                let items = tree.tree.compactMap { entry -> GalleryWallpaper? in
                    guard entry.type == "blob", entry.path.hasPrefix("gallery/") else { return nil }
                    let ext = URL(fileURLWithPath: entry.path).pathExtension.lowercased()
                    guard supported.contains(ext) else { return nil }
                    return GalleryWallpaper(path: entry.path, size: entry.size ?? 0)
                }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                DispatchQueue.main.async { completion(.success(items)) }
            } catch { DispatchQueue.main.async { completion(.failure(error)) } }
        }.resume()
    }

    func download(_ item: GalleryWallpaper, completion: @escaping (Result<URL, Error>) -> Void) {
        guard let url = item.url else {
            DispatchQueue.main.async { completion(.failure(NSError(domain: "StarshipGallery", code: 2, userInfo: [NSLocalizedDescriptionKey: "This wallpaper has an invalid GitHub path."]))) }
            return
        }
        URLSession.shared.downloadTask(with: url) { location, response, error in
            if let error { DispatchQueue.main.async { completion(.failure(error)) }; return }
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode), let location else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                let failure = NSError(domain: "StarshipGallery", code: code, userInfo: [NSLocalizedDescriptionKey: "GitHub could not download this wallpaper."])
                DispatchQueue.main.async { completion(.failure(failure)) }
                return
            }
            let staged = FileManager.default.temporaryDirectory.appendingPathComponent("starship-\(UUID().uuidString)-\(item.name)")
            do {
                try FileManager.default.moveItem(at: location, to: staged)
                DispatchQueue.main.async { completion(.success(staged)) }
            } catch { DispatchQueue.main.async { completion(.failure(error)) } }
        }.resume()
    }
}

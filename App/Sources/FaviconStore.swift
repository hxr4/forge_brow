import AppKit

final class FaviconStore {
    static let shared = FaviconStore()

    private var memory: [String: NSImage] = [:]
    private let folder: URL
    private let queue = DispatchQueue(label: "forge.favicons", qos: .utility)

    private init() {
        folder = Storage.directory.appendingPathComponent("favicons", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func host(of url: String) -> String? {
        guard let host = URL(string: url)?.host, !host.isEmpty else { return nil }
        return host
    }

    private func fileURL(forHost host: String) -> URL {
        let safe = host.replacingOccurrences(of: "[^A-Za-z0-9.-]",
                                             with: "_",
                                             options: .regularExpression)
        return folder.appendingPathComponent(safe + ".png")
    }

    func icon(for url: String) -> NSImage? {
        guard let host = host(of: url) else { return nil }
        if let cached = memory[host] { return cached }
        guard let data = try? Data(contentsOf: fileURL(forHost: host)),
              let image = NSImage(data: data) else { return nil }
        memory[host] = image
        return image
    }

    func store(_ image: NSImage, for url: String) {
        guard let host = host(of: url) else { return }
        memory[host] = image
        let destination = fileURL(forHost: host)
        queue.async {
            guard let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else { return }
            try? png.write(to: destination, options: .atomic)
        }
    }
}

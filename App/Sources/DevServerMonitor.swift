import Foundation

struct DevServer: Equatable {
    let port: Int
    let processName: String
    let pid: Int

    var url: String { "http://localhost:\(port)" }
}

final class DevServerMonitor {
    static let shared = DevServerMonitor()

    private(set) var servers: [DevServer] = []
    var onChange: (([DevServer]) -> Void)?

    private var timer: Timer?
    private let scanQueue = DispatchQueue(label: "com.forge.devservers")

    func start(interval: TimeInterval = 3) {
        stop()
        scan()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.scan()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func scan() {
        scanQueue.async { [weak self] in
            let found = DevServerMonitor.listListeningPorts()
            DispatchQueue.main.async {
                guard let self, found != self.servers else { return }
                self.servers = found
                self.onChange?(found)
            }
        }
    }

    private static func listListeningPorts() -> [DevServer] {
        guard FileManager.default.isExecutableFile(atPath: "/usr/sbin/lsof") else { return [] }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-iTCP", "-sTCP:LISTEN", "-P", "-n", "-F", "pcn"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return [] }
        return parse(output)
    }

    static func parse(_ output: String) -> [DevServer] {
        var results: [Int: DevServer] = [:]
        var currentPID = 0
        var currentCommand = ""

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let marker = line.first else { continue }
            let value = String(line.dropFirst())

            switch marker {
            case "p":
                currentPID = Int(value) ?? 0
            case "c":
                currentCommand = value
            case "n":
                guard let port = port(from: value), port >= 1024 else { continue }
                if results[port] == nil {
                    results[port] = DevServer(port: port, processName: currentCommand, pid: currentPID)
                }
            default:
                continue
            }
        }

        return results.values.filter(isInteresting).sorted { $0.port < $1.port }
    }

    private static let devProcesses: Set<String> = [
        "node", "deno", "bun", "python", "python3", "ruby", "php", "java", "dotnet",
        "go", "cargo", "rustc", "air", "nginx", "httpd", "caddy", "gunicorn", "uvicorn",
        "hugo", "jekyll", "esbuild", "vite", "webpack", "next-server", "rails", "puma",
        "dart", "flutter", "ollama", "docker", "com.docker.backend", "postgres", "mysqld",
        "mongod", "redis-server", "supabase", "firebase", "wrangler", "serve", "http-server"
    ]

    private static let noisyProcesses: [String] = [
        "controlcenter", "rapportd", "sharingd", "airplay", "adobe", "creative cloud",
        "spotify", "dropbox", "code helper", "antigravity", "whatsapp", "discord",
        "chrome", "brave", "firefox", "safari", "music", "photos", "steam", "zoom",
        "onedrive", "teams", "slack", "forge helper", "forge browser"
    ]

    private static let devPorts: Set<Int> = [
        1313, 3000, 3001, 3002, 3003, 4000, 4200, 4321, 5173, 5174, 5432, 5500,
        6379, 7860, 8000, 8001, 8080, 8081, 8100, 8888, 9000, 9090, 11434, 27017
    ]

    static func isInteresting(_ server: DevServer) -> Bool {
        let name = server.processName.lowercased()
        for noise in noisyProcesses where name.contains(noise) { return false }
        if devProcesses.contains(name) { return true }
        for candidate in devProcesses where name.hasPrefix(candidate) { return true }
        return devPorts.contains(server.port)
    }

    private static func port(from address: String) -> Int? {
        guard let separator = address.lastIndex(of: ":") else { return nil }
        let portText = address[address.index(after: separator)...]
        return Int(portText)
    }
}

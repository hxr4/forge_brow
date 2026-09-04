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

        return results.values.sorted { $0.port < $1.port }
    }

    private static func port(from address: String) -> Int? {
        guard let separator = address.lastIndex(of: ":") else { return nil }
        let portText = address[address.index(after: separator)...]
        return Int(portText)
    }
}

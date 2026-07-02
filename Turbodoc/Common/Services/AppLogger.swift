import OSLog

enum AppLogger {
    private static let subsystem =
        Bundle.main.bundleIdentifier ?? "ai.turbodoc.ios.TurbodocApp"

    static let editor = Logger(subsystem: subsystem, category: "editor")
    static let notes = Logger(subsystem: subsystem, category: "notes")
    static let network = Logger(subsystem: subsystem, category: "network")
    static let authentication = Logger(subsystem: subsystem, category: "authentication")
    static let profile = Logger(subsystem: subsystem, category: "profile")
    static let sync = Logger(subsystem: subsystem, category: "sync")
}

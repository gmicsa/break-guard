import Foundation

struct SessionRecord: Codable, Identifiable {
    let id: String
    let startedAt: Date
    let endedAt: Date?      // nil only for the live in-progress session (never persisted as nil); flushed sessions store the quit timestamp
    let durationSeconds: TimeInterval
    let type: SessionType
}

enum SessionType: String, Codable {
    case work = "work"
    case `break` = "break"
}

struct DayFile: Codable {
    let date: String        // "YYYY-MM-DD"
    var sessions: [SessionRecord]
}

struct DaySummary {
    let date: Date
    let totalWorkSeconds: TimeInterval
    let totalBreakSeconds: TimeInterval
    var totalSeconds: TimeInterval { totalWorkSeconds + totalBreakSeconds }
    let sessions: [SessionRecord]
}

final class StatsStore {
    static let shared = StatsStore()
    private init() {}

    private let appSupportURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("BreakGuard")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f
    }()

    func recordWorkSession(start: Date, end: Date) {
        let duration = end.timeIntervalSince(start)
        guard duration > 0 else { return }
        for (segStart, segEnd, segDate) in splitAtMidnight(start: start, end: end) {
            let record = SessionRecord(
                id: UUID().uuidString,
                startedAt: segStart,
                endedAt: segEnd,
                durationSeconds: segEnd.timeIntervalSince(segStart),
                type: .work
            )
            append(record, to: segDate)
        }
    }

    func recordBreakSession(start: Date, end: Date) {
        let duration = end.timeIntervalSince(start)
        guard duration >= 5 else { return }
        for (segStart, segEnd, segDate) in splitAtMidnight(start: start, end: end) {
            let record = SessionRecord(
                id: UUID().uuidString,
                startedAt: segStart,
                endedAt: segEnd,
                durationSeconds: segEnd.timeIntervalSince(segStart),
                type: .break
            )
            append(record, to: segDate)
        }
    }

    func todaySummary() -> DaySummary {
        summary(for: Date())
    }

    func lastNDays(_ n: Int) -> [DaySummary] {
        let cal = Calendar.current
        let today = Date()
        return (0..<n).reversed().map { offset -> DaySummary in
            let date = cal.date(byAdding: .day, value: -offset, to: today)!
            return summary(for: date)
        }
    }

    // MARK: - Private

    private func isEndOfDay(_ record: SessionRecord) -> Bool {
        let threshold = SettingsManager.shared.endOfDayThresholdMinutes
        guard threshold > 0, record.type == .break else { return false }
        return record.durationSeconds >= TimeInterval(threshold * 60)
    }

    private func summary(for date: Date) -> DaySummary {
        let dayFile = load(date: date)
        var totalWork: TimeInterval = 0
        var totalBreak: TimeInterval = 0
        var visibleSessions: [SessionRecord] = []
        for s in dayFile.sessions {
            if isEndOfDay(s) { continue }
            visibleSessions.append(s)
            switch s.type {
            case .work:  totalWork  += s.durationSeconds
            case .break: totalBreak += s.durationSeconds
            }
        }
        return DaySummary(
            date: date,
            totalWorkSeconds: totalWork,
            totalBreakSeconds: totalBreak,
            sessions: visibleSessions
        )
    }

    private func append(_ record: SessionRecord, to date: Date) {
        var dayFile = load(date: date)
        dayFile.sessions.append(record)
        save(dayFile, date: date)
    }

    private func splitAtMidnight(start: Date, end: Date) -> [(Date, Date, Date)] {
        let cal = Calendar.current
        var results: [(Date, Date, Date)] = []
        var current = start
        while true {
            let dayStart = cal.startOfDay(for: current)
            guard let nextMidnight = cal.date(byAdding: .day, value: 1, to: dayStart) else { break }
            if end <= nextMidnight {
                results.append((current, end, current))
                break
            } else {
                results.append((current, nextMidnight, current))
                current = nextMidnight
            }
        }
        return results
    }

    private func fileURL(date: Date) -> URL {
        let name = "stats-\(dateFormatter.string(from: date)).json"
        return appSupportURL.appendingPathComponent(name)
    }

    private func load(date: Date) -> DayFile {
        let url = fileURL(date: date)
        let key = dateFormatter.string(from: date)
        guard let data = try? Data(contentsOf: url) else {
            return DayFile(date: key, sessions: [])
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let dayFile = try? decoder.decode(DayFile.self, from: data) {
            return dayFile
        }
        // Corrupt file — rename to .bak.json and start fresh
        let bakURL = url.deletingPathExtension().appendingPathExtension("bak.json")
        try? FileManager.default.moveItem(at: url, to: bakURL)
        return DayFile(date: key, sessions: [])
    }

    private func save(_ dayFile: DayFile, date: Date) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(dayFile) else { return }
        try? data.write(to: fileURL(date: date), options: .atomic)
    }
}

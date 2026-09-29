import AppKit

final class StatsView: NSView {

    // Weak singleton so SessionManager.tick() can call refresh() without a strong dependency
    static weak var shared: StatsView?

    private var sessionManager: SessionManager
    private var sessions: [SessionRecord] = []
    private var totalWorkSeconds: TimeInterval = 0
    private var totalBreakSeconds: TimeInterval = 0

    // MARK: - Subviews

    private let dateLabel = NSTextField(labelWithString: "")
    private let workLabel  = NSTextField(labelWithString: "")
    private let breakLabel = NSTextField(labelWithString: "")
    private let tableView  = NSTableView()
    private let scrollView = NSScrollView()
    private let chartView  = BarChartView()

    // MARK: - Init

    init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
        super.init(frame: .zero)
        StatsView.shared = self
        setupLayout()
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Layout

    private func setupLayout() {
        // Today header
        dateLabel.font = NSFont.boldSystemFont(ofSize: 15)
        dateLabel.textColor = NSColor.labelColor

        // Summary box
        let summaryBox = NSBox()
        summaryBox.boxType = .primary
        summaryBox.titlePosition = .noTitle
        summaryBox.contentViewMargins = NSSize(width: 12, height: 8)

        workLabel.font = NSFont.systemFont(ofSize: 16, weight: .medium)
        breakLabel.font = NSFont.systemFont(ofSize: 16, weight: .medium)

        let summaryStack = NSStackView(views: [workLabel, breakLabel])
        summaryStack.spacing = 32
        summaryStack.orientation = .horizontal
        summaryBox.contentView?.addSubview(summaryStack)
        summaryStack.translatesAutoresizingMaskIntoConstraints = false
        if let cv = summaryBox.contentView {
            NSLayoutConstraint.activate([
                summaryStack.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 8),
                summaryStack.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -8),
                summaryStack.topAnchor.constraint(equalTo: cv.topAnchor, constant: 4),
                summaryStack.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -4)
            ])
        }

        // Session log
        let logLabel = NSTextField(labelWithString: "Session Log")
        logLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)

        setupTableView()

        // Chart section
        let chartLabel = NSTextField(labelWithString: "Last 7 Days")
        chartLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)

        chartView.translatesAutoresizingMaskIntoConstraints = false

        // Main stack
        let stack = NSStackView(views: [dateLabel, summaryBox, logLabel, scrollView, chartLabel, chartView])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 36),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            summaryBox.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: 180),
            chartView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            chartView.heightAnchor.constraint(equalToConstant: 260)
        ])
    }

    private func setupTableView() {
        let typeCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("type"))
        typeCol.title = "Type"; typeCol.width = 50
        let startCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("start"))
        startCol.title = "Start"; startCol.width = 90
        let endCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("end"))
        endCol.title = "End"; endCol.width = 90
        let durCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("duration"))
        durCol.title = "Duration"; durCol.width = 100

        for col in [typeCol, startCol, endCol, durCol] {
            tableView.addTableColumn(col)
        }

        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = false
        tableView.focusRingType = .none

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .lineBorder
    }

    // MARK: - Refresh

    func refresh() {
        let store = StatsStore.shared.todaySummary()
        var allSessions = store.sessions

        // Synthetic ongoing record
        let sm = sessionManager
        if sm.state == .manualBreak, let lock = sm.lockDate {
            let ongoing = SessionRecord(
                id: "__ongoing_break__",
                startedAt: lock,
                endedAt: nil,
                durationSeconds: sm.elapsed,
                type: .break
            )
            allSessions.append(ongoing)
        } else if sm.state != .locked, let start = sm.sessionStart {
            let ongoing = SessionRecord(
                id: "__ongoing__",
                startedAt: start,
                endedAt: nil,
                durationSeconds: sm.elapsed,
                type: .work
            )
            allSessions.append(ongoing)
        }

        sessions = allSessions.filter { $0.durationSeconds >= 60 || $0.endedAt == nil }.sorted { $0.startedAt < $1.startedAt }

        // Totals
        let isWorking = sm.state == .working || sm.state == .warned || sm.state == .snoozed
        totalWorkSeconds = store.totalWorkSeconds + (isWorking ? sm.elapsed : 0)
        totalBreakSeconds = store.totalBreakSeconds + (sm.state == .manualBreak ? sm.elapsed : 0)

        // Update date label
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        dateLabel.stringValue = "TODAY — \(formatter.string(from: Date()))"

        // Update summary
        workLabel.stringValue = "💻 Total Work    \(formatDuration(totalWorkSeconds))"
        breakLabel.stringValue = "🌿 Total Break    \(formatDuration(totalBreakSeconds))"

        tableView.reloadData()

        // Chart — add current session elapsed to today's bar
        var summaries = StatsStore.shared.lastNDays(7)
        if !summaries.isEmpty && (isWorking || sm.state == .manualBreak) {
            let last = summaries[summaries.count - 1]
            summaries[summaries.count - 1] = DaySummary(
                date: last.date,
                totalWorkSeconds: last.totalWorkSeconds + (isWorking ? sm.elapsed : 0),
                totalBreakSeconds: last.totalBreakSeconds + (sm.state == .manualBreak ? sm.elapsed : 0),
                sessions: last.sessions
            )
        }
        chartView.daySummaries = summaries.filter { $0.totalWorkSeconds > 0 || $0.totalBreakSeconds > 0 }
        chartView.needsDisplay = true
    }

    // MARK: - Helpers

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}

// MARK: - NSTableViewDataSource / Delegate

extension StatsView: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { sessions.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let session = sessions[row]
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 12)
        label.translatesAutoresizingMaskIntoConstraints = false

        switch tableColumn?.identifier.rawValue {
        case "type":
            label.stringValue = session.type == .work ? "💻" : "🌿"
            label.alignment = .center
        case "start":
            label.stringValue = formatTime(session.startedAt)
        case "end":
            if let end = session.endedAt {
                label.stringValue = formatTime(end)
            } else {
                label.stringValue = "ongoing"
                label.textColor = NSColor.secondaryLabelColor
            }
        case "duration":
            if session.endedAt == nil && session.durationSeconds < 60 {
                label.stringValue = "-"
                label.textColor = NSColor.secondaryLabelColor
            } else {
                label.stringValue = formatDuration(session.durationSeconds)
            }
        default:
            break
        }

        let container = NSTableCellView()
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }
}

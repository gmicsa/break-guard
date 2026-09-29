import AppKit

final class BarChartView: NSView {
    var daySummaries: [DaySummary] = [] {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // 1. Fill background
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()

        let leftMargin: CGFloat = 44
        let rightMargin: CGFloat = 80
        let topMargin: CGFloat = 24
        let bottomMargin: CGFloat = 36
        let chartRect = CGRect(
            x: leftMargin,
            y: bottomMargin,
            width: bounds.width - leftMargin - rightMargin,
            height: bounds.height - topMargin - bottomMargin
        )

        // 2. Find scale — axis rounds up to next integer hour, bars fill to 90% of that
        let maxSeconds = daySummaries.map { $0.totalWorkSeconds + $0.totalBreakSeconds }.max() ?? 3600
        let maxHours = max(1, Int(ceil(maxSeconds / 3600)))
        let axisMaxSeconds = Double(maxHours) * 3600
        let scale = CGFloat(chartRect.height * 0.9) / CGFloat(axisMaxSeconds)

        // 3. Draw Y-axis gridlines at each integer hour
        let axisAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 9),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        // Choose step so we get at most ~5 gridlines
        let step = maxHours <= 5 ? 1 : maxHours <= 10 ? 2 : (maxHours + 4) / 5
        var hour = step
        while hour <= maxHours {
            let y = chartRect.minY + CGFloat(hour * 3600) * scale
            ctx.setStrokeColor(NSColor.separatorColor.cgColor)
            ctx.setLineWidth(0.5)
            ctx.move(to: CGPoint(x: chartRect.minX, y: y))
            ctx.addLine(to: CGPoint(x: chartRect.maxX, y: y))
            ctx.strokePath()

            let str = NSAttributedString(string: "\(hour)h", attributes: axisAttrs)
            let size = str.size()
            str.draw(at: CGPoint(x: chartRect.minX - size.width - 4, y: y - size.height / 2))
            hour += step
        }

        // 4. Draw bars
        let n = daySummaries.count
        guard n > 0 else { return }
        let barGap: CGFloat = 12
        let totalGap = CGFloat(n - 1) * barGap
        let barWidth = max(8, (chartRect.width - totalGap) / CGFloat(n))

        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: NSColor.labelColor
        ]
        let dayAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 10),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        for (i, summary) in daySummaries.enumerated() {
            let barX = chartRect.minX + CGFloat(i) * (barWidth + barGap)

            let workH = max(summary.totalWorkSeconds > 0 ? 2 : 0, CGFloat(summary.totalWorkSeconds) * scale)
            let breakH = max(summary.totalBreakSeconds > 0 ? 2 : 0, CGFloat(summary.totalBreakSeconds) * scale)
            let stackH = workH + breakH

            // Work segment (bottom) — flat top if break sits above, rounded top if alone
            if workH > 0 {
                let rect = CGRect(x: barX, y: chartRect.minY, width: barWidth, height: workH)
                if breakH > 0 {
                    NSColor.systemBlue.setFill()
                    rect.fill()
                } else {
                    drawRoundedTopBar(ctx: ctx, rect: rect, color: NSColor.systemBlue)
                }
            }
            // Break segment (top) — always rounded
            if breakH > 0 {
                let rect = CGRect(x: barX, y: chartRect.minY + workH, width: barWidth, height: breakH)
                drawRoundedTopBar(ctx: ctx, rect: rect, color: NSColor.systemGreen)
            }

            // Total label above stack
            let totalSec = summary.totalWorkSeconds + summary.totalBreakSeconds
            if totalSec > 0 {
                let str = NSAttributedString(string: "Total \(formatDuration(totalSec))", attributes: labelAttrs)
                let size = str.size()
                str.draw(at: CGPoint(x: barX + (barWidth - size.width) / 2, y: chartRect.minY + stackH + 2))
            }

            // Work / Break labels inside bars (white, near bottom of each segment)
            let insideAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9, weight: .medium),
                .foregroundColor: NSColor.white
            ]
            if workH >= 16 {
                let str = NSAttributedString(string: "Work \(formatDuration(summary.totalWorkSeconds))", attributes: insideAttrs)
                let size = str.size()
                str.draw(at: CGPoint(x: barX + (barWidth - size.width) / 2, y: chartRect.minY + 3))
            }
            if breakH >= 16 {
                let str = NSAttributedString(string: "Break \(formatDuration(summary.totalBreakSeconds))", attributes: insideAttrs)
                let size = str.size()
                str.draw(at: CGPoint(x: barX + (barWidth - size.width) / 2, y: chartRect.minY + workH + 3))
            }

            // Day label
            let dayStr = NSAttributedString(string: dayName(for: summary.date, isLast: i == n - 1), attributes: dayAttrs)
            let daySize = dayStr.size()
            dayStr.draw(at: CGPoint(x: barX + (barWidth - daySize.width) / 2, y: chartRect.minY - daySize.height - 7))
        }

        // 5. Legend (bottom-right)
        drawLegend(ctx: ctx)
    }

    private func drawRoundedTopBar(ctx: CGContext, rect: CGRect, color: NSColor) {
        let r: CGFloat = 3
        let path = NSBezierPath()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.line(to: CGPoint(x: rect.minX, y: rect.maxY - r))
        path.appendArc(withCenter: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r, startAngle: 180, endAngle: 90, clockwise: true)
        path.line(to: CGPoint(x: rect.maxX - r, y: rect.maxY))
        path.appendArc(withCenter: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r, startAngle: 90, endAngle: 0, clockwise: true)
        path.line(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.close()
        color.setFill()
        path.fill()
    }

    private func drawLegend(ctx: CGContext) {
        let dotSize: CGFloat = 8
        let spacing: CGFloat = 4
        let itemSpacing: CGFloat = 16
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let workStr = NSAttributedString(string: "Work", attributes: attrs)
        let breakStr = NSAttributedString(string: "Break", attributes: attrs)
        let workSize = workStr.size()
        let breakSize = breakStr.size()
        var x: CGFloat = 44   // aligned with left chart margin
        let y: CGFloat = 2

        // Blue dot
        NSColor.systemBlue.setFill()
        CGRect(x: x, y: y + (workSize.height - dotSize) / 2, width: dotSize, height: dotSize).fill()
        x += dotSize + spacing
        workStr.draw(at: CGPoint(x: x, y: y))
        x += workSize.width + itemSpacing

        // Green dot
        NSColor.systemGreen.setFill()
        CGRect(x: x, y: y + (breakSize.height - dotSize) / 2, width: dotSize, height: dotSize).fill()
        x += dotSize + spacing
        breakStr.draw(at: CGPoint(x: x, y: y))
    }

    private func dayName(for date: Date, isLast: Bool) -> String {
        if isLast { return "Today" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        if h > 0 { return "\(h)h\(m)m" }
        return "\(m)m"
    }
}

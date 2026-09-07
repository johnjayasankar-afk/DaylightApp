import AppKit
import DaylightCore

@MainActor
final class TimelineCanvas: NSView {
    var samples: [TimelineSample] = []
    var anchors: [ResolvedAnchor] = []
    var now: Date = Date()
    var playheadTitle = "Now"
    var reduceMotion = false
    var solar: SolarDay?
    var hoverMinutes: Int?
    var onLiveMove: ((ResolvedAnchor, Int) -> Void)?
    var onCommitMove: ((ResolvedAnchor, Int) -> Void)?
    var onAddAt: ((Int) -> Void)?
    var onCancelMove: ((ResolvedAnchor, Int) -> Void)?
    var onDragSettled: (() -> Void)?
    var editingEnabled = true
    var minKelvin = ColorTemperature.advancedRange.lowerBound
    var maxKelvin = ColorTemperature.advancedRange.upperBound

    private var dragging: ResolvedAnchor?
    private var selectedAnchor: ResolvedAnchor?
    private var lastMinutes: Int?
    private var startMinutes: Int?
    private var nudgeStartMinutes: Int?
    private var nudgeAnchor: ResolvedAnchor?
    private var nudgeUndoArmed = false
    private var nudgeSettle: Timer?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityLabel("24-hour lighting timeline")
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize { NSSize(width: 640, height: 188) }

    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 8 else { return }
        let chart = bounds.insetBy(dx: 8, dy: 10)
        drawBackdrop(in: chart)
        drawWarmth(in: chart)
        drawBrightness(in: chart)
        drawHours(in: chart)
        if let sunrise = solar?.sunrise {
            drawGuide(x: x(for: sunrise, in: chart), label: "Sunrise", in: chart)
        }
        if let sunset = solar?.sunset {
            drawGuide(x: x(for: sunset, in: chart), label: "Sunset", in: chart)
        }
        drawNow(in: chart)
        drawAnchors(in: chart)
        drawHover(in: chart)
        drawLegend(in: chart)
        if window?.firstResponder === self {
            Style.accent.withAlphaComponent(0.5).setStroke()
            let focus = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10)
            focus.lineWidth = 1.5
            focus.stroke()
        }
    }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard editingEnabled else {
            super.keyDown(with: event)
            return
        }
        let step = event.modifierFlags.contains(.shift) ? 1 : 15
        switch event.keyCode {
        case 123:
            nudgeClockAnchor(by: -step)
        case 124:
            nudgeClockAnchor(by: step)
        default:
            super.keyDown(with: event)
        }
    }

    override func accessibilityPerformIncrement() -> Bool {
        guard editingEnabled else { return false }
        nudgeClockAnchor(by: 15)
        return true
    }

    override func accessibilityPerformDecrement() -> Bool {
        guard editingEnabled else { return false }
        nudgeClockAnchor(by: -15)
        return true
    }

    override func mouseDown(with event: NSEvent) {
        guard editingEnabled else { return }
        if event.clickCount == 2 {
            onAddAt?(snappedMinutes(from: event))
            dragging = nil
            selectedAnchor = nil
            lastMinutes = nil
            needsDisplay = true
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        dragging = nearestClockAnchor(to: point.x)
        selectedAnchor = dragging
        startMinutes = dragging.map(clockMinutes(for:))
        lastMinutes = nil
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let anchor = dragging else { return }
        let minutes = snappedMinutes(from: event)
        lastMinutes = minutes
        onLiveMove?(anchor, minutes)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard dragging != nil else { return }
        if let anchor = dragging, let minutes = lastMinutes {
            onCommitMove?(anchor, minutes)
        }
        dragging = nil
        lastMinutes = nil
        startMinutes = nil
    }

    @discardableResult
    func cancelInteraction() -> Bool {
        var interacting = dragging != nil
        if let anchor = dragging {
            onCancelMove?(anchor, startMinutes ?? clockMinutes(for: anchor))
        } else if nudgeUndoArmed, let anchor = nudgeAnchor ?? selectedAnchor, let start = nudgeStartMinutes {
            onCancelMove?(anchor, start)
            interacting = true
        }
        dragging = nil
        lastMinutes = nil
        startMinutes = nil
        clearNudgeSession()
        needsDisplay = true
        return interacting
    }

    override func mouseMoved(with event: NSEvent) {
        let xPosition = convert(event.locationInWindow, from: nil).x
        hoverMinutes = Int(min(max((xPosition - 8) / max(bounds.width - 16, 1), 0), 1) * 1440)
        toolTip = hoverLabel()
        setAccessibilityValue(hoverLabel())
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hoverMinutes = nil
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        ))
    }

    private func drawBackdrop(in chart: NSRect) {
        let path = NSBezierPath(roundedRect: chart, xRadius: 12, yRadius: 12)
        NSGraphicsContext.current?.saveGraphicsState()
        path.addClip()
        let night = NSColor(srgbRed: 0.16, green: 0.18, blue: 0.28, alpha: 0.22)
        let day = NSColor(srgbRed: 0.96, green: 0.82, blue: 0.52, alpha: 0.20)
        let evening = NSColor(srgbRed: 0.86, green: 0.50, blue: 0.28, alpha: 0.22)
        if let gradient = NSGradient(colorsAndLocations: (night, 0), (day, 0.38), (day, 0.55), (evening, 0.78), (night, 1)) {
            gradient.draw(in: chart, angle: 0)
        }
        NSGraphicsContext.current?.restoreGraphicsState()
        NSColor.separatorColor.withAlphaComponent(0.45).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func drawWarmth(in chart: NSRect) {
        guard samples.count > 1 else { return }
        let line = NSBezierPath()
        var points: [CGPoint] = []
        for sample in samples {
            points.append(CGPoint(x: x(for: sample.date, in: chart), y: yTemperature(sample.output.temperature.kelvin, in: chart)))
        }
        smooth(line, through: points)
        let fill = NSBezierPath()
        fill.append(line)
        fill.line(to: CGPoint(x: chart.maxX, y: chart.maxY))
        fill.line(to: CGPoint(x: chart.minX, y: chart.maxY))
        fill.close()
        Style.warm.withAlphaComponent(0.20).setFill()
        fill.fill()
        Style.accent.setStroke()
        line.lineWidth = 2.2
        line.lineJoinStyle = .round
        line.stroke()
    }

    private func drawBrightness(in chart: NSRect) {
        guard samples.count > 1 else { return }
        let path = NSBezierPath()
        var points: [CGPoint] = []
        for sample in samples {
            let value = sample.output.hardwareBrightness?.fraction ?? sample.output.softwareDimming.factor
            points.append(CGPoint(x: x(for: sample.date, in: chart), y: chart.maxY - value * (chart.height - 28) - 14))
        }
        smooth(path, through: points)
        NSColor.secondaryLabelColor.withAlphaComponent(0.7).setStroke()
        path.setLineDash([3.5, 3], count: 2, phase: 0)
        path.lineWidth = 1.1
        path.stroke()
    }

    private func drawHours(in chart: NSRect) {
        for hour in stride(from: 0, through: 24, by: 3) {
            let xPos = chart.minX + chart.width * CGFloat(hour) / 24
            NSColor.secondaryLabelColor.withAlphaComponent(0.18).setStroke()
            let tick = NSBezierPath()
            tick.move(to: CGPoint(x: xPos, y: chart.maxY - 4))
            tick.line(to: CGPoint(x: xPos, y: chart.maxY))
            tick.stroke()
            let label = ClockFormat.compactHour(hour)
            NSAttributedString(
                string: label,
                attributes: [.font: NSFont.systemFont(ofSize: 9, weight: .medium), .foregroundColor: NSColor.tertiaryLabelColor]
            ).draw(at: CGPoint(x: xPos - 8, y: chart.maxY + 1))
        }
    }

    private func drawNow(in chart: NSRect) {
        let nowX = x(for: now, in: chart)
        if !reduceMotion {
            Style.accent.withAlphaComponent(0.14).setFill()
            NSBezierPath(ovalIn: NSRect(x: nowX - 9, y: chart.minY + 2, width: 18, height: chart.height - 4)).fill()
        }
        Style.accent.withAlphaComponent(0.88).setStroke()
        let line = NSBezierPath()
        line.move(to: CGPoint(x: nowX, y: chart.minY + 4))
        line.line(to: CGPoint(x: nowX, y: chart.maxY - 4))
        line.lineWidth = 1.5
        line.stroke()
        let pill = NSAttributedString(
            string: playheadTitle,
            attributes: [.font: NSFont.systemFont(ofSize: 9, weight: .semibold), .foregroundColor: NSColor.white]
        )
        let size = pill.size()
        let pillX = min(max(nowX - size.width / 2 - 5, chart.minX + 4), chart.maxX - size.width - 14)
        let rect = NSRect(x: pillX, y: chart.minY + 6, width: size.width + 10, height: 15)
        Style.accent.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
        pill.draw(at: CGPoint(x: rect.minX + 5, y: rect.minY + 1))
    }

    private func drawAnchors(in chart: NSRect) {
        for anchor in anchors {
            let ax = x(for: anchor.date, in: chart)
            let solar = anchor.kind == .sunrise || anchor.kind == .sunset
            let selected = selectedAnchor?.id == anchor.id || dragging?.id == anchor.id
            let size: CGFloat = selected ? 14 : 12
            let dot = NSRect(x: ax - size / 2, y: chart.minY + chart.height * 0.28 - (size - 12) / 2, width: size, height: size)
            (solar ? Style.cool : Style.accent).setFill()
            NSBezierPath(ovalIn: dot).fill()
            NSColor.white.withAlphaComponent(0.92).setStroke()
            let ring = NSBezierPath(ovalIn: dot.insetBy(dx: 0.6, dy: 0.6))
            ring.lineWidth = selected ? 2 : 1.4
            ring.stroke()
            if selected {
                Style.accent.withAlphaComponent(0.28).setStroke()
                let halo = NSBezierPath(ovalIn: dot.insetBy(dx: -3, dy: -3))
                halo.lineWidth = 1.5
                halo.stroke()
            }
            let title = NSAttributedString(
                string: anchor.name,
                attributes: [.font: NSFont.systemFont(ofSize: 9, weight: .medium), .foregroundColor: NSColor.labelColor]
            )
            title.draw(at: CGPoint(x: min(max(ax - title.size().width / 2, chart.minX), chart.maxX - title.size().width), y: dot.maxY + 4))
        }
    }

    private func drawHover(in chart: NSRect) {
        guard let minutes = hoverMinutes, dragging == nil else { return }
        let xPos = chart.minX + chart.width * CGFloat(minutes) / 1440
        NSColor.secondaryLabelColor.withAlphaComponent(0.25).setStroke()
        let line = NSBezierPath()
        line.move(to: CGPoint(x: xPos, y: chart.minY))
        line.line(to: CGPoint(x: xPos, y: chart.maxY))
        line.stroke()
        let text = NSAttributedString(
            string: hoverLabel(),
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium), .foregroundColor: NSColor.labelColor]
        )
        let size = text.size()
        let rect = NSRect(x: min(max(xPos - size.width / 2 - 6, chart.minX + 4), chart.maxX - size.width - 12), y: chart.minY + 26, width: size.width + 12, height: 18)
        NSColor.windowBackgroundColor.withAlphaComponent(0.92).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        text.draw(at: CGPoint(x: rect.minX + 6, y: rect.minY + 2))
    }

    private func drawGuide(x: CGFloat, label: String, in chart: NSRect) {
        NSColor.secondaryLabelColor.withAlphaComponent(0.28).setStroke()
        let path = NSBezierPath()
        path.move(to: CGPoint(x: x, y: chart.minY))
        path.line(to: CGPoint(x: x, y: chart.maxY))
        path.setLineDash([2.5, 3], count: 2, phase: 0)
        path.stroke()
        NSAttributedString(string: label, attributes: [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor.secondaryLabelColor])
            .draw(at: CGPoint(x: min(x + 5, chart.maxX - 46), y: chart.minY + 24))
    }

    private func smooth(_ path: NSBezierPath, through points: [CGPoint]) {
        guard let first = points.first else { return }
        path.move(to: first)
        if reduceMotion || points.count == 2 {
            for point in points.dropFirst() {
                path.line(to: point)
            }
            return
        }
        for index in 0..<(points.count - 1) {
            let current = points[index]
            let next = points[index + 1]
            let mid = CGPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2)
            path.curve(to: mid, controlPoint1: CGPoint(x: (current.x + mid.x) / 2, y: current.y), controlPoint2: CGPoint(x: (mid.x + next.x) / 2, y: next.y))
        }
        if let last = points.last {
            path.line(to: last)
        }
    }

    private func drawLegend(in chart: NSRect) {
        let warmth = NSAttributedString(
            string: "Warmth",
            attributes: [.font: NSFont.systemFont(ofSize: 9, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor]
        )
        let brightness = NSAttributedString(
            string: "Brightness",
            attributes: [.font: NSFont.systemFont(ofSize: 9, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor]
        )
        let origin = CGPoint(x: chart.minX + 10, y: chart.maxY - 18)
        Style.accent.setStroke()
        let solid = NSBezierPath()
        solid.move(to: CGPoint(x: origin.x, y: origin.y + 6))
        solid.line(to: CGPoint(x: origin.x + 12, y: origin.y + 6))
        solid.lineWidth = 2
        solid.stroke()
        warmth.draw(at: CGPoint(x: origin.x + 16, y: origin.y))
        NSColor.secondaryLabelColor.withAlphaComponent(0.7).setStroke()
        let dashed = NSBezierPath()
        let dashX = origin.x + 62
        dashed.move(to: CGPoint(x: dashX, y: origin.y + 6))
        dashed.line(to: CGPoint(x: dashX + 12, y: origin.y + 6))
        dashed.setLineDash([3, 2], count: 2, phase: 0)
        dashed.lineWidth = 1.2
        dashed.stroke()
        brightness.draw(at: CGPoint(x: dashX + 16, y: origin.y))
    }

    private func clearNudgeSession() {
        nudgeUndoArmed = false
        nudgeStartMinutes = nil
        nudgeAnchor = nil
        nudgeSettle?.invalidate()
        nudgeSettle = nil
    }

    private func nudgeClockAnchor(by delta: Int) {
        let chart = bounds.insetBy(dx: 8, dy: 10)
        let candidate = dragging
            ?? selectedAnchor
            ?? nearestClockAnchor(to: x(for: now, in: chart))
            ?? anchors.first(where: \.movable)
        guard let anchor = candidate else { return }
        let next = TimelineSnap.minutes(clockMinutes(for: anchor) + delta, fine: true)
        lastMinutes = next
        selectedAnchor = anchor
        if !nudgeUndoArmed {
            nudgeStartMinutes = clockMinutes(for: anchor)
            nudgeAnchor = anchor
            onCommitMove?(anchor, next)
            nudgeUndoArmed = true
        } else {
            onLiveMove?(anchor, next)
        }
        nudgeSettle?.invalidate()
        let timer = Timer(timeInterval: 0.55, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.clearNudgeSession()
                self?.onDragSettled?()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        nudgeSettle = timer
        needsDisplay = true
    }

    private func clockMinutes(for anchor: ResolvedAnchor) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: anchor.date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    private func nearestClockAnchor(to xPosition: CGFloat) -> ResolvedAnchor? {
        let chart = bounds.insetBy(dx: 8, dy: 10)
        let match = anchors
            .filter(\.movable)
            .min { abs(x(for: $0.date, in: chart) - xPosition) < abs(x(for: $1.date, in: chart) - xPosition) }
        guard let match else { return nil }
        return abs(x(for: match.date, in: chart) - xPosition) < 22 ? match : nil
    }

    private func snappedMinutes(from event: NSEvent) -> Int {
        let xPosition = convert(event.locationInWindow, from: nil).x
        let raw = Int(min(max((xPosition - 8) / max(bounds.width - 16, 1), 0), 1) * 1440)
        return TimelineSnap.minutes(raw, fine: event.modifierFlags.contains(.shift))
    }

    private func hoverLabel() -> String {
        let minutes = hoverMinutes ?? 0
        let sample = samples.min {
            abs(x(for: $0.date, in: bounds) - (bounds.minX + 8 + CGFloat(minutes) / 1440 * (bounds.width - 16)))
                < abs(x(for: $1.date, in: bounds) - (bounds.minX + 8 + CGFloat(minutes) / 1440 * (bounds.width - 16)))
        }
        let kelvin = sample.map { Int($0.output.temperature.kelvin.rounded()) } ?? 0
        let phrase = sample?.output.temperature.comfortPhrase ?? ""
        return "\(TimeOfDay(minutesFromMidnight: minutes).formatted) · \(kelvin) K · \(phrase)"
    }

    private func x(for date: Date, in chart: NSRect) -> CGFloat {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        if let next = calendar.date(byAdding: .day, value: 1, to: start), date >= next {
            return chart.maxX
        }
        if date < start {
            return chart.minX
        }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return chart.minX + CGFloat(minutes) / 1440 * chart.width
    }

    private func yTemperature(_ kelvin: Double, in chart: NSRect) -> CGFloat {
        let fraction = CGFloat(TimelineSnap.temperatureFraction(kelvin: kelvin, range: minKelvin ... maxKelvin))
        return chart.maxY - fraction * (chart.height - 28) - 14
    }
}

import AppKit
import DaylightCore

@MainActor
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
final class VerticalRule: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        widthAnchor.constraint(equalToConstant: 1).isActive = true
        updateChrome()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateChrome()
    }

    private func updateChrome() {
        layer?.backgroundColor = NSColor.separatorColor.cgColor
    }
}

@MainActor
final class HairlineView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 1).isActive = true
        wantsLayer = true
        updateChrome()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateChrome()
    }

    private func updateChrome() {
        layer?.backgroundColor = NSColor.separatorColor.cgColor
    }
}

@MainActor
final class ActionMap: NSObject {
    private var handlers: [Int: () -> Void] = [:]
    private var nextID = 1

    func bind(_ button: NSButton, _ handler: @escaping () -> Void) {
        let id = nextID
        nextID += 1
        button.tag = id
        button.target = self
        button.action = #selector(run(_:))
        handlers[id] = handler
    }

    @objc private func run(_ sender: NSButton) {
        handlers[sender.tag]?()
    }

    func removeAll() {
        handlers.removeAll()
    }
}

@MainActor
final class CardView: NSView {
    var highlighted = false {
        didSet { updateChrome() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = Style.cardRadius
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateChrome()
    }

    override func updateLayer() {
        super.updateLayer()
        updateChrome()
    }

    override func layout() {
        super.layout()
        updateChrome()
    }

    private func updateChrome() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if highlighted {
            layer?.backgroundColor = Style.accent.withAlphaComponent(dark ? 0.16 : 0.10).cgColor
            layer?.borderColor = Style.accent.withAlphaComponent(dark ? 0.42 : 0.28).cgColor
        } else {
            layer?.backgroundColor = (dark ? NSColor.white.withAlphaComponent(0.055) : NSColor.white.withAlphaComponent(0.70)).cgColor
            layer?.borderColor = (dark ? NSColor.white.withAlphaComponent(0.09) : NSColor.black.withAlphaComponent(0.055)).cgColor
        }
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = dark ? 0.26 : 0.07
        layer?.shadowRadius = 12
        layer?.shadowOffset = CGSize(width: 0, height: -1)
        layer?.masksToBounds = false
    }

    static func wrap(_ view: NSView, padding: CGFloat = 16) -> CardView {
        let card = CardView()
        view.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: padding),
            view.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -padding),
            view.topAnchor.constraint(equalTo: card.topAnchor, constant: padding),
            view.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -padding)
        ])
        return card
    }
}

@MainActor
final class KelvinSwatch: NSView {
    var kelvin: Double = ColorTemperature.daylightReference.kelvin {
        didSet { needsDisplay = true }
    }
    var restored = false {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 14).isActive = true
        heightAnchor.constraint(equalToConstant: 14).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize { NSSize(width: 14, height: 14) }

    override func draw(_ dirtyRect: NSRect) {
        let inset = bounds.insetBy(dx: 1, dy: 1)
        if restored {
            NSColor.secondaryLabelColor.withAlphaComponent(0.35).setStroke()
            let ring = NSBezierPath(ovalIn: inset)
            ring.lineWidth = 1.4
            ring.stroke()
            return
        }
        Style.kelvinColor(kelvin).setFill()
        NSBezierPath(ovalIn: inset).fill()
        NSColor.white.withAlphaComponent(0.45).setStroke()
        let shine = NSBezierPath(ovalIn: inset.insetBy(dx: 0.6, dy: 0.6))
        shine.lineWidth = 0.8
        shine.stroke()
    }
}

enum ActionTitles {
    static func resume(paused: Bool, pauseEndsAt: Date?, holding: Bool, holdEndsAt: Date?, now: Date = Date()) -> String {
        if paused {
            if let end = pauseEndsAt, end.timeIntervalSince(now) > 0 {
                return "Resume · \(RulesEngine.compact(end.timeIntervalSince(now)))"
            }
            return "Resume"
        }
        if holding {
            if let end = holdEndsAt, end.timeIntervalSince(now) > 0 {
                return "End hold · \(RulesEngine.compact(end.timeIntervalSince(now)))"
            }
            return "End hold"
        }
        return "Resume"
    }
}

@MainActor
final class WarmthWashView: NSView {
    var kelvin: Double = ColorTemperature.daylightReference.kelvin {
        didSet { chaseKelvin() }
    }
    var restored = false {
        didSet { needsDisplay = true }
    }
    var reduceMotion = false {
        didSet {
            if reduceMotion {
                displayedKelvin = kelvin
                chase?.invalidate()
                chase = nil
            }
            needsDisplay = true
        }
    }
    private var displayedKelvin = ColorTemperature.daylightReference.kelvin
    private var chase: Timer?

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            chase?.invalidate()
            chase = nil
        }
    }

    override var isFlipped: Bool { true }

    private func chaseKelvin() {
        if reduceMotion || abs(kelvin - displayedKelvin) < 8 {
            displayedKelvin = kelvin
            chase?.invalidate()
            chase = nil
            needsDisplay = true
            return
        }
        if chase == nil {
            let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tickChase() }
            }
            timer.tolerance = 0.01
            RunLoop.main.add(timer, forMode: .common)
            chase = timer
        }
    }

    private func tickChase() {
        let delta = kelvin - displayedKelvin
        if abs(delta) < 6 {
            displayedKelvin = kelvin
            chase?.invalidate()
            chase = nil
            needsDisplay = true
            return
        }
        displayedKelvin += delta * 0.24
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let base = dark ? NSColor.black.withAlphaComponent(0.18) : NSColor.white.withAlphaComponent(0.08)
        base.setFill()
        bounds.fill()
        if restored {
            NSColor.secondaryLabelColor.withAlphaComponent(dark ? 0.08 : 0.05).setFill()
            bounds.fill()
            return
        }
        let color = Style.kelvinColor(displayedKelvin)
        if reduceMotion {
            color.withAlphaComponent(dark ? 0.20 : 0.12).setFill()
            bounds.fill()
            return
        }

        let colors = [
            color.withAlphaComponent(dark ? 0.38 : 0.28).cgColor,
            color.withAlphaComponent(0.0).cgColor
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            ctx.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: bounds.midX, y: bounds.minY + 8),
                startRadius: 4,
                endCenter: CGPoint(x: bounds.midX, y: bounds.midY),
                endRadius: max(bounds.width, bounds.height) * 0.72,
                options: [.drawsAfterEndLocation]
            )
        }
    }
}

enum KeyFocus {
    static func isEditing(_ responder: NSResponder?) -> Bool {
        responder is NSText
            || responder is NSComboBox
            || responder is NSDatePicker
    }

    static func isAdjusting(_ responder: NSResponder?) -> Bool {
        responder is GradientSlider
            || responder is TimelineCanvas
            || responder is NSSlider
            || responder is NSPopUpButton
            || responder is NSSegmentedControl
    }
}

enum SliderTrack: Equatable {
    case warmth
    case brightness
    case dimming
}

@MainActor
final class GradientSlider: NSControl {
    var minValue = 2700.0
    var maxValue = 7000.0
    var track: SliderTrack = .warmth {
        didSet {
            needsDisplay = true
            applyAccessibilityName()
        }
    }
    private var stored = ColorTemperature.daylightReference.kelvin
    var onChange: ((Double) -> Void)?
    var onCommit: ((Double) -> Void)?
    var onCancel: ((Double) -> Void)?
    var isTracking = false
    private var preDragValue: Double?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    var doubleValueSafe: Double {
        get { stored }
        set {
            stored = min(max(newValue, minValue), maxValue)
            needsDisplay = true
            setAccessibilityValue(accessibilityLabel(for: stored))
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 28).isActive = true
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        isEnabled = true
        focusRingType = .exterior
        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
        applyAccessibilityName()
    }

    private func applyAccessibilityName() {
        switch track {
        case .warmth: setAccessibilityLabel("Warmth")
        case .brightness: setAccessibilityLabel("Hardware brightness")
        case .dimming: setAccessibilityLabel("Software dimming")
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize { NSSize(width: 240, height: 28) }

    override func draw(_ dirtyRect: NSRect) {
        let alpha: CGFloat = isEnabled ? 1 : 0.42
        let trackRect = NSRect(x: 8, y: 11, width: bounds.width - 16, height: 6)
        let path = NSBezierPath(roundedRect: trackRect, xRadius: 3, yRadius: 3)
        NSGraphicsContext.current?.saveGraphicsState()
        path.addClip()
        trackGradient()?.draw(in: trackRect, angle: 0)
        NSGraphicsContext.current?.restoreGraphicsState()
        NSColor.black.withAlphaComponent(0.12 * alpha).setStroke()
        path.lineWidth = 0.5
        path.stroke()

        let t = CGFloat((stored - minValue) / max(maxValue - minValue, 1))
        let knobX = trackRect.minX + t * trackRect.width
        let knob = NSRect(x: knobX - 8, y: 6, width: 16, height: 16)
        NSColor.black.withAlphaComponent(0.18 * alpha).setFill()
        NSBezierPath(ovalIn: knob.offsetBy(dx: 0, dy: 1)).fill()
        knobColor().withAlphaComponent(alpha).setFill()
        NSBezierPath(ovalIn: knob).fill()
        NSColor.white.withAlphaComponent(0.9 * alpha).setStroke()
        let ring = NSBezierPath(ovalIn: knob.insetBy(dx: 0.6, dy: 0.6))
        ring.lineWidth = 1.5
        ring.stroke()

        if window?.firstResponder === self {
            Style.accent.withAlphaComponent(0.55).setStroke()
            let focus = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
            focus.lineWidth = 1.5
            focus.stroke()
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isEnabled else {
            super.keyDown(with: event)
            return
        }
        let step = (maxValue - minValue) / 48
        switch event.keyCode {
        case 123:
            nudge(-(event.modifierFlags.contains(.shift) ? step / 4 : step))
        case 124:
            nudge(event.modifierFlags.contains(.shift) ? step / 4 : step)
        case 36, 76:
            onCommit?(stored)
        default:
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        window?.makeFirstResponder(self)
        preDragValue = stored
        isTracking = true
        move(with: event)
        let mask: NSEvent.EventTypeMask = [.leftMouseUp, .leftMouseDragged]
        while isTracking {
            guard let next = window?.nextEvent(matching: mask) else {
                cancelTracking()
                break
            }
            if next.type == .leftMouseUp {
                mouseUp(with: next)
                break
            }
            mouseDragged(with: next)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEnabled, isTracking else { return }
        move(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled, isTracking else { return }
        move(with: event)
        isTracking = false
        preDragValue = nil
        onCommit?(stored)
    }

    override func resignFirstResponder() -> Bool {
        if isTracking {
            cancelTracking(revert: false)
        }
        return super.resignFirstResponder()
    }

    func cancelTracking(revert: Bool = false) {
        guard isTracking else { return }
        isTracking = false
        if revert {
            if let preDragValue {
                stored = preDragValue
            }
            preDragValue = nil
            if let onCancel {
                onCancel(stored)
            } else {
                onChange?(stored)
            }
            needsDisplay = true
            return
        }
        preDragValue = nil
        onCommit?(stored)
        needsDisplay = true
    }

    override func accessibilityPerformIncrement() -> Bool {
        guard isEnabled else { return false }
        nudge((maxValue - minValue) / 48)
        return true
    }

    override func accessibilityPerformDecrement() -> Bool {
        guard isEnabled else { return false }
        nudge(-(maxValue - minValue) / 48)
        return true
    }

    private func nudge(_ delta: Double) {
        doubleValueSafe += delta
        onChange?(stored)
        onCommit?(stored)
    }

    private func move(with event: NSEvent) {
        let x = convert(event.locationInWindow, from: nil).x
        let t = min(max((x - 8) / max(bounds.width - 16, 1), 0), 1)
        stored = minValue + Double(t) * (maxValue - minValue)
        needsDisplay = true
        setAccessibilityValue(accessibilityLabel(for: stored))
        onChange?(stored)
    }

    private func trackGradient() -> NSGradient? {
        switch track {
        case .warmth:
            return NSGradient(colors: [
                Style.kelvinColor(minValue),
                Style.kelvinColor((minValue + maxValue) / 2),
                Style.kelvinColor(maxValue)
            ])
        case .brightness:
            return NSGradient(colors: [
                NSColor(srgbRed: 0.16, green: 0.16, blue: 0.18, alpha: 1),
                NSColor(srgbRed: 0.92, green: 0.90, blue: 0.84, alpha: 1)
            ])
        case .dimming:
            return NSGradient(colors: [
                NSColor(srgbRed: 0.28, green: 0.28, blue: 0.30, alpha: 1),
                NSColor(srgbRed: 0.78, green: 0.78, blue: 0.80, alpha: 1)
            ])
        }
    }

    private func knobColor() -> NSColor {
        switch track {
        case .warmth:
            return Style.kelvinColor(stored)
        case .brightness, .dimming:
            let t = (stored - minValue) / max(maxValue - minValue, 1)
            return NSColor(white: 0.28 + 0.62 * t, alpha: 1)
        }
    }

    private func accessibilityLabel(for value: Double) -> String {
        switch track {
        case .warmth:
            return ColorTemperature(kelvin: value).roundedLabel
        case .brightness, .dimming:
            return "\(Int((value * 100).rounded())) percent"
        }
    }
}

@MainActor
final class PillButton: NSButton {
    var active = false {
        didSet { updateChrome() }
    }
    private var hovered = false

    convenience init(title: String) {
        self.init(title: title, target: nil, action: nil)
        bezelStyle = .inline
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        font = .systemFont(ofSize: 12, weight: .medium)
        contentTintColor = .labelColor
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 28).isActive = true
        widthAnchor.constraint(greaterThanOrEqualToConstant: 72).isActive = true
        updateChrome()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateChrome()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        updateChrome()
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        updateChrome()
    }

    override var isEnabled: Bool {
        get { super.isEnabled }
        set {
            super.isEnabled = newValue
            updateChrome()
        }
    }

    func updateChrome() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let alpha: CGFloat = isEnabled ? 1 : 0.42
        if !isEnabled {
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(dark ? 0.05 : 0.04).cgColor
            contentTintColor = NSColor.secondaryLabelColor.withAlphaComponent(0.8)
            alphaValue = alpha
            return
        }
        alphaValue = 1
        if active {
            layer?.backgroundColor = Style.accent.withAlphaComponent(dark ? 0.32 : 0.22).cgColor
            contentTintColor = dark ? Style.accentSoft : Style.accent
        } else {
            let fill: CGFloat = hovered ? (dark ? 0.12 : 0.09) : (dark ? 0.08 : 0.06)
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(fill).cgColor
            contentTintColor = .labelColor
        }
    }
}

@MainActor
final class SidebarRow: NSButton {
    var active = false {
        didSet { updateChrome() }
    }
    private var hovered = false

    convenience init(tab: MainTab) {
        self.init(title: "  \(tab.title)", target: nil, action: nil)
        image = Style.symbol(tab.systemImage, size: 13)
        imagePosition = .imageLeading
        bezelStyle = .inline
        isBordered = false
        alignment = .left
        font = .systemFont(ofSize: 13, weight: .medium)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 32).isActive = true
        setAccessibilityLabel(tab.title)
        updateChrome()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateChrome()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        updateChrome()
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        updateChrome()
    }

    func updateChrome() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if active {
            layer?.backgroundColor = Style.accent.withAlphaComponent(dark ? 0.30 : 0.20).cgColor
        } else {
            layer?.backgroundColor = hovered ? NSColor.labelColor.withAlphaComponent(dark ? 0.08 : 0.05).cgColor : NSColor.clear.cgColor
        }
        contentTintColor = active ? (dark ? Style.accentSoft : Style.accent) : .labelColor
        font = .systemFont(ofSize: 13, weight: active ? .semibold : .medium)
    }
}

@MainActor
final class QuietButton: NSButton {
    private var hovered = false
    private var prominent = false
    private var destructive = false

    convenience init(title: String, destructive: Bool = false, prominent: Bool = false) {
        self.init(title: title, target: nil, action: nil)
        bezelStyle = .rounded
        font = .systemFont(ofSize: 12, weight: prominent ? .semibold : .medium)
        self.prominent = prominent
        self.destructive = destructive
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        if destructive {
            contentTintColor = .systemRed
        }
        if prominent {
            bezelColor = Style.accent
        }
        updateChrome()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateChrome()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        updateChrome()
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        updateChrome()
    }

    override var isEnabled: Bool {
        get { super.isEnabled }
        set {
            super.isEnabled = newValue
            updateChrome()
        }
    }

    private func updateChrome() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        alphaValue = isEnabled ? 1 : 0.45
        if !isEnabled {
            layer?.backgroundColor = NSColor.clear.cgColor
            return
        }
        if prominent {
            layer?.backgroundColor = Style.accent.withAlphaComponent(hovered ? (dark ? 0.38 : 0.28) : (dark ? 0.26 : 0.18)).cgColor
        } else if hovered {
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(dark ? 0.08 : 0.05).cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
        if destructive {
            contentTintColor = .systemRed
        }
    }
}

@MainActor
enum FilePanels {
    static func present(_ panel: NSSavePanel, over window: NSWindow?, completion: @escaping (URL) -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        let host = window ?? NSApp.keyWindow ?? NSApp.mainWindow
        if let host, host.isVisible {
            panel.beginSheetModal(for: host) { response in
                guard response == .OK, let url = panel.url else { return }
                completion(url)
            }
        } else {
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                completion(url)
            }
        }
    }
}

@MainActor
enum SettingsAlerts {
    static func confirmImport(over window: NSWindow?, completion: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Replace current \(Brand.name) settings?"
        alert.informativeText = "Schedules, display names, and overrides on this Mac will be replaced by the file. This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")
        present(alert, over: window, completion: completion)
    }

    static func confirmReset(over window: NSWindow?, completion: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Reset \(Brand.name) to defaults?"
        alert.informativeText = "Schedules, display names, and overrides on this Mac will be replaced with the built-in starting points. This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        present(alert, over: window, completion: completion)
    }

    private static func present(_ alert: NSAlert, over window: NSWindow?, completion: @escaping (Bool) -> Void) {
        let host = window ?? NSApp.keyWindow ?? NSApp.mainWindow
        if let host, host.isVisible {
            alert.beginSheetModal(for: host) { response in
                completion(response == .alertFirstButtonReturn)
            }
        } else {
            completion(alert.runModal() == .alertFirstButtonReturn)
        }
    }
}

@MainActor
final class PeriodBadge: NSView {
    private let label = Style.label("", font: .systemFont(ofSize: 11, weight: .semibold), color: .white)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            heightAnchor.constraint(equalToConstant: 22)
        ])
        setContentHuggingPriority(.defaultHigh, for: .horizontal)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func set(title: String, kelvin: Double?) {
        label.stringValue = title
        setAccessibilityLabel(title)
        isHidden = title.isEmpty
        guard let kelvin else {
            label.textColor = .secondaryLabelColor
            layer?.backgroundColor = NSColor.secondaryLabelColor.withAlphaComponent(0.16).cgColor
            return
        }
        let rgb = TemperatureAppearance.rgb(for: kelvin)
        let luminance = 0.2126 * rgb.r + 0.7152 * rgb.g + 0.0722 * rgb.b
        label.textColor = luminance > 0.62 ? NSColor(white: 0.16, alpha: 1) : .white
        layer?.backgroundColor = Style.kelvinColor(kelvin).withAlphaComponent(luminance > 0.8 ? 0.94 : 0.80).cgColor
    }
}

@MainActor
final class StepDots: NSView {
    var count = 6
    var index = 0 { didSet { needsDisplay = true } }

    override var intrinsicContentSize: NSSize { NSSize(width: 120, height: 10) }

    override func draw(_ dirtyRect: NSRect) {
        let spacing: CGFloat = 14
        let start = (bounds.width - CGFloat(count - 1) * spacing) / 2
        for i in 0..<count {
            let rect = NSRect(x: start + CGFloat(i) * spacing - 3.5, y: 1.5, width: 7, height: 7)
            if i == index {
                Style.accent.setFill()
            } else {
                NSColor.secondaryLabelColor.withAlphaComponent(0.35).setFill()
            }
            NSBezierPath(ovalIn: rect).fill()
        }
    }
}

@MainActor
final class SunMarkView: NSView {
    var kelvin: Double = 4200 {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let size = min(bounds.width, bounds.height)
        let sun = NSRect(x: (bounds.width - size * 0.42) / 2, y: size * 0.12, width: size * 0.42, height: size * 0.42)
        Style.kelvinColor(kelvin).setFill()
        NSBezierPath(ovalIn: sun).fill()
        Style.kelvinColor(min(kelvin + 1400, 7000)).setFill()
        NSBezierPath(ovalIn: sun.insetBy(dx: size * 0.06, dy: size * 0.06)).fill()

        NSColor.labelColor.withAlphaComponent(0.12).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: bounds.height * 0.58, width: bounds.width, height: bounds.height)).fill()

        Style.accent.setStroke()
        let horizon = NSBezierPath()
        horizon.lineWidth = 2
        horizon.move(to: CGPoint(x: 16, y: bounds.height * 0.58))
        horizon.curve(
            to: CGPoint(x: bounds.width - 16, y: bounds.height * 0.58),
            controlPoint1: CGPoint(x: bounds.width * 0.35, y: bounds.height * 0.50),
            controlPoint2: CGPoint(x: bounds.width * 0.68, y: bounds.height * 0.66)
        )
        horizon.stroke()
    }
}

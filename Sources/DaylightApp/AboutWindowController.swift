import AppKit
import DaylightCore

@MainActor
final class AboutWindowController: NSWindowController {
    private let wash = WarmthWashView()
    private let name = Style.label(Brand.name, font: .systemFont(ofSize: 26, weight: .semibold))
    private var sunMark: SunMarkView?

    init(kelvin: Double? = nil, reduceMotion: Bool = false) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 460),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "About \(Brand.name)"
        window.center()
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .windowBackgroundColor
        super.init(window: window)
        window.contentView = build()
        setKelvin(kelvin, reduceMotion: reduceMotion)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func setKelvin(_ kelvin: Double?, reduceMotion: Bool = false) {
        wash.reduceMotion = reduceMotion
        wash.restored = kelvin == nil
        if let kelvin {
            wash.kelvin = kelvin
            sunMark?.kelvin = kelvin
            name.textColor = Style.temperature(kelvin: kelvin)
        } else {
            sunMark?.kelvin = ColorTemperature.daylightReference.kelvin
            name.textColor = Style.accent
        }
    }

    private func build() -> NSView {
        wash.translatesAutoresizingMaskIntoConstraints = false
        wash.heightAnchor.constraint(equalToConstant: 118).isActive = true
        wash.wantsLayer = true
        wash.layer?.cornerRadius = Style.cardRadius
        wash.layer?.cornerCurve = .continuous

        let mark: NSView
        if let icon = NSApp.applicationIconImage, icon.size.width > 16 {
            let image = NSImageView(image: icon)
            image.imageScaling = .scaleProportionallyUpOrDown
            image.translatesAutoresizingMaskIntoConstraints = false
            image.heightAnchor.constraint(equalToConstant: 76).isActive = true
            image.widthAnchor.constraint(equalToConstant: 76).isActive = true
            mark = image
        } else {
            let sun = SunMarkView()
            sun.translatesAutoresizingMaskIntoConstraints = false
            sun.heightAnchor.constraint(equalToConstant: 92).isActive = true
            sun.widthAnchor.constraint(equalToConstant: 168).isActive = true
            sunMark = sun
            mark = sun
        }
        mark.translatesAutoresizingMaskIntoConstraints = false
        wash.addSubview(mark)
        NSLayoutConstraint.activate([
            mark.centerXAnchor.constraint(equalTo: wash.centerXAnchor),
            mark.centerYAnchor.constraint(equalTo: wash.centerYAnchor)
        ])

        name.alignment = .center
        let version = Style.caption("Version \(Brand.marketingVersion) (\(Brand.buildNumber))")
        version.alignment = .center
        let tag = Style.label(Brand.tagline, font: .systemFont(ofSize: 13), color: .secondaryLabelColor)
        tag.alignment = .center
        let about = Style.label(Brand.about, font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
        about.alignment = .center
        let privacy = Style.label(Brand.privacy, font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
        privacy.alignment = .center
        let copy = Style.caption("© \(Brand.copyrightYear) \(Brand.name)")
        copy.alignment = .center

        let stack = Stack(axis: .vertical, spacing: 9, views: [wash, name, version, tag, about, privacy, copy])
        stack.alignment = .centerX
        stack.translatesAutoresizingMaskIntoConstraints = false

        let effect = NSVisualEffectView()
        effect.material = .underWindowBackground
        effect.blendingMode = .behindWindow
        effect.state = .followsWindowActiveState
        effect.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: effect.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: effect.leadingAnchor, constant: 36),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: effect.trailingAnchor, constant: -36),
            wash.widthAnchor.constraint(equalToConstant: 280)
        ])
        return effect
    }
}

@MainActor
final class HelpWindowController: NSWindowController {
    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(Brand.name) Help"
        window.minSize = NSSize(width: 440, height: 360)
        window.center()
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        super.init(window: window)
        window.contentView = build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private func build() -> NSView {
        let rows: [(String, String)] = [
            ("Open Daylight", "Click the menu bar sun"),
            ("Restore output", "⌥-click the menu bar sun, or ⌘⌥R"),
            ("Status menu", "Right-click the menu bar sun"),
            ("Emergency restore", Brand.emergencyRestoreShortcut),
            ("Today / Schedule / Displays / Settings", "⌘1  ⌘2  ⌘3  ⌘4"),
            ("Undo / redo a schedule edit", "⌘Z  ⇧⌘Z"),
            ("Cut / Copy / Paste", "⌘X  ⌘C  ⌘V"),
            ("Minimize", "⌘M"),
            ("Settings", "⌘,"),
            ("Copy the current status", "⇧⌘C"),
            ("Choose which display sliders affect", "Today or Displays"),
            ("Previous / next display", "⌘[  ⌘]"),
            ("Close the main window", "Esc or ⌘W"),
            ("Close About or Help", "Esc or ⌘W"),
            ("Pause thirty minutes", "⌘P"),
            ("Resume automation", "⌘R"),
            ("Turn Daylight off or on", "⌘⌥D"),
            ("Preview the day in the interface", "⌘Y"),
            ("Live day preview", "⌘⌥Y — not while paused"),
            ("Stop preview", "⌘."),
            ("Close the menu bar panel", "Esc — first releases a slider, then closes"),
            ("Cancel a slider or timeline drag", "Esc restores the previous value"),
            ("Export settings", "⇧⌘E"),
            ("Import settings", "⇧⌘I"),
            ("Fine-tune a timeline time", "Hold Shift while dragging"),
            ("Add a time on the timeline", "Double-click — keeps wake, wind-down, and solar times"),
            ("Edit weekday times on a weekend", "Uncheck Editing weekend — the timeline shows Friday or Monday"),
            ("Until the next change", "Follows the live next schedule time"),
            ("Hold until I resume", "Status says held — it does not count down to Wake"),
            ("Undo / redo a timeline edit", "Today or Schedule, or ⌘Z / ⇧⌘Z"),
            ("Link displays", "Groups every active display"),
            ("Change how long a time takes to arrive", "Schedule → each time, or Settings → default transitions"),
            ("Skip or close setup", "Esc, Skip, or close — marks setup complete and opens Daylight"),
            ("Move through setup", "←  →"),
            ("Nudge a timeline time", "←  → when the timeline is focused  (Shift for one minute)"),
            ("Restore on sleep", "Settings — native tables return before this Mac sleeps"),
            ("Approve launch at login", "System Settings → Login Items"),
            ("Quit", "⌘Q")
        ]
        var views: [NSView] = [
            Style.section("How to use \(Brand.name)"),
            Style.caption("Slider changes are temporary and follow the selected display. They do not rewrite the saved schedule — a slider hold is labeled Manual, not Focus. Pause, Restore, and Color Work return native tables; the interface says so instead of showing a schedule Kelvin that is not on the panel. Day preview locks lighting controls and schedule edits until you stop. A solar schedule uses your wake and wind-down warmth, and sunrise offsets follow the calendar (including DST). The default transition slider updates every existing time; you can still refine one time on Schedule. Double-click the timeline to add a time. Reduce motion follows System Settings as well as the in-app checkbox. Weekend nights keep Friday’s weekday settings until Saturday morning.")
        ]
        for (name, keys) in rows {
            let left = Style.label(name, font: .systemFont(ofSize: 13))
            let right = Style.mono(keys, size: 12)
            right.alignment = .right
            let row = Stack(axis: .horizontal, spacing: 12, views: [left, NSView(), right])
            row.setHuggingPriority(.defaultLow, for: .horizontal)
            views.append(row)
            views.append(Style.hairline())
        }
        views.append(Style.caption(Brand.about))
        let stack = Stack(axis: .vertical, spacing: 8, views: views)
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 28, right: 24)

        let document = FlippedView()
        document.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.documentView = document
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.widthAnchor.constraint(equalTo: document.widthAnchor),
            document.bottomAnchor.constraint(equalTo: stack.bottomAnchor),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        ])
        let effect = NSVisualEffectView()
        effect.material = .underWindowBackground
        effect.blendingMode = .behindWindow
        effect.state = .followsWindowActiveState
        scroll.pinToEdges(of: effect)
        return effect
    }
}

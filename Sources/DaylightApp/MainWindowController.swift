import AppKit
import DaylightCore
import UniformTypeIdentifiers

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    private let controller: AppController
    private let actions = ActionMap()
    private let sidebarRows: [MainTab: SidebarRow]
    private let today: TodayPane
    private let schedule: SchedulePane
    private let displays: DisplaysPane
    private let settings: SettingsPane
    private let contentHost = FlippedView()
    private let sidebarBrand = Style.label(Brand.name, font: .systemFont(ofSize: 20, weight: .semibold))
    private let sidebarWash = WarmthWashView()
    private let sidebarKelvin = Style.mono("", size: 12)
    private let sidebarClock = Style.mono("", size: 11)
    private let sidebarStatus = Style.caption("")
    private let sidebarNext = Style.caption("")
    private var current: MainTab = .today
    private var hostHeight: NSLayoutConstraint?
    private var clockTick: Timer?
    private var tabScroll: [MainTab: NSPoint] = [:]
    var onClose: (() -> Void)?

    init(controller: AppController) {
        self.controller = controller
        self.today = TodayPane(controller: controller)
        self.schedule = SchedulePane(controller: controller)
        self.displays = DisplaysPane(controller: controller)
        self.settings = SettingsPane(controller: controller)
        var rows: [MainTab: SidebarRow] = [:]
        for tab in MainTab.allCases {
            rows[tab] = SidebarRow(tab: tab)
        }
        self.sidebarRows = rows

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = Brand.name
        window.minSize = NSSize(width: 840, height: 580)
        if !window.setFrameUsingName("Daylight.Main") {
            window.center()
        }
        window.setFrameAutosaveName("Daylight.Main")
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .windowBackgroundColor
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.acceptsMouseMovedEvents = true
        super.init(window: window)
        window.delegate = self
        window.contentView = build()
        show(controller.selectedTab)
        startClockTick()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func startClockTick() {
        clockTick?.invalidate()
        clockTick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickClock() }
        }
        if let clockTick {
            RunLoop.main.add(clockTick, forMode: .common)
        }
    }

    func tickClock() {
        today.refreshClock()
        sidebarClock.stringValue = ClockFormat.shortTime(controller.evaluationDate)
        if controller.livePreview == nil {
            sidebarNext.stringValue = StatusExplainer.nextChangeLine(
                wake: controller.decision?.nextWake,
                automation: controller.decision?.automation ?? controller.snapshot?.automation ?? .automatic,
                at: controller.evaluationDate
            )
        }
        if current == .schedule {
            schedule.refreshClock()
        }
    }

    func refresh() {
        if current != controller.selectedTab {
            show(controller.selectedTab)
            return
        }
        sidebarRows.forEach { $0.value.active = $0.key == current }
        sidebarKelvin.stringValue = controller.presentedKelvinLabel
        sidebarClock.stringValue = ClockFormat.shortTime(controller.evaluationDate)
        sidebarWash.kelvin = controller.presentedKelvin
        sidebarWash.restored = controller.chromeKelvin == nil
        sidebarWash.reduceMotion = controller.reduceMotionActive
        if let kelvin = controller.selectedOutput?.temperature.kelvin {
            sidebarKelvin.textColor = Style.temperature(kelvin: kelvin)
            sidebarBrand.textColor = Style.temperature(kelvin: kelvin)
        } else {
            sidebarBrand.textColor = Style.accent
            sidebarKelvin.textColor = .secondaryLabelColor
        }
        sidebarStatus.stringValue = controller.settings.disabled ? "Off" : (controller.presentedModeTitle.isEmpty ? Brand.name : controller.presentedModeTitle)
        sidebarNext.stringValue = controller.liveNextChangeLine
        if let display = controller.selectedDisplay, controller.selectedOutput == nil || controller.isScheduleFallback(display) {
            window?.title = "\(Brand.name) — \(controller.presentedKelvinLabel)"
        } else if let output = controller.selectedOutput {
            window?.title = "\(Brand.name) — \(output.temperature.roundedLabel)"
        } else {
            window?.title = "\(Brand.name) — \(controller.presentedKelvinLabel)"
        }
        switch current {
        case .today: today.refresh()
        case .schedule: schedule.refresh()
        case .displays: displays.refresh()
        case .settings: settings.refresh()
        }
        layoutCurrentPane()
    }

    func show(_ tab: MainTab) {
        if let scroll = contentHost.enclosingScrollView {
            tabScroll[current] = scroll.contentView.bounds.origin
        }
        current = tab
        controller.selectTab(tab)
        contentHost.subviews.forEach { $0.removeFromSuperview() }
        currentPane.pinToEdges(of: contentHost)
        if let origin = tabScroll[tab] {
            contentHost.enclosingScrollView?.contentView.scroll(to: origin)
        } else {
            contentHost.enclosingScrollView?.contentView.scroll(to: .zero)
        }
        refresh()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender.attachedSheet != nil { return false }
        clockTick?.invalidate()
        clockTick = nil
        onClose?()
        return true
    }

    func windowDidResize(_ notification: Notification) {
        layoutCurrentPane()
    }

    private var currentPane: NSView {
        switch current {
        case .today: return today
        case .schedule: return schedule
        case .displays: return displays
        case .settings: return settings
        }
    }

    private func layoutCurrentPane() {
        let pane = currentPane
        pane.layoutSubtreeIfNeeded()
        let height = max(pane.fittingSize.height, 400)
        if let hostHeight {
            if abs(hostHeight.constant - height) > 1 {
                hostHeight.constant = height
            }
        } else {
            let constraint = contentHost.heightAnchor.constraint(equalToConstant: height)
            constraint.priority = .defaultHigh
            constraint.isActive = true
            hostHeight = constraint
        }
    }

    private func build() -> NSView {
        let root = NSView()
        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        sidebar.state = .followsWindowActiveState
        sidebar.translatesAutoresizingMaskIntoConstraints = false

        sidebarBrand.textColor = Style.accent
        sidebarWash.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(sidebarWash)
        let wordmark = Style.caption("Lighting for your day")
        let nav = Stack(axis: .vertical, spacing: 3)
        for tab in MainTab.allCases {
            if let row = sidebarRows[tab] {
                actions.bind(row) { [weak self] in self?.show(tab) }
                row.toolTip = tab.tooltip
                nav.addArrangedSubview(row)
                row.widthAnchor.constraint(equalToConstant: Style.sidebarWidth - 24).isActive = true
            }
        }
        let version = Style.caption("Version \(Brand.marketingVersion) (\(Brand.buildNumber))")
        sidebarNext.maximumNumberOfLines = 3
        let footer = Stack(axis: .vertical, spacing: 4, views: [sidebarClock, sidebarKelvin, sidebarStatus, sidebarNext, version])
        let side = Stack(axis: .vertical, spacing: 16, views: [sidebarBrand, wordmark, nav, NSView(), footer])
        side.edgeInsets = NSEdgeInsets(top: 40, left: 12, bottom: 18, right: 12)
        side.pinToEdges(of: sidebar)

        let divider = VerticalRule()

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 28, left: 0, bottom: 22, right: 0)
        scroll.scrollerInsets = NSEdgeInsets(top: 28, left: 0, bottom: 0, right: 0)
        scroll.documentView = contentHost
        contentHost.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(sidebar)
        root.addSubview(divider)
        root.addSubview(scroll)
        NSLayoutConstraint.activate([
            sidebarWash.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            sidebarWash.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            sidebarWash.topAnchor.constraint(equalTo: sidebar.topAnchor),
            sidebarWash.heightAnchor.constraint(equalToConstant: 168),
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: Style.sidebarWidth),
            divider.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            divider.topAnchor.constraint(equalTo: root.topAnchor),
            divider.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            scroll.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            contentHost.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            contentHost.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            contentHost.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        ])
        return root
    }
}

@MainActor
final class TodayPane: NSView {
    private let controller: AppController
    private let actions = ActionMap()
    private let wash = WarmthWashView()
    private let headline = Style.title("")
    private let explanation = Style.label("", font: .systemFont(ofSize: 13), color: .secondaryLabelColor)
    private let next = Style.caption("")
    private let kelvin = Style.mono("", size: 13)
    private let period = PeriodBadge()
    private let timeline = TimelineCanvas()
    private let warmth = GradientSlider()
    private let brightness = GradientSlider()
    private let dimming = GradientSlider()
    private let warmthValue = Style.mono("")
    private let brightnessValue = Style.mono("")
    private let dimmingValue = Style.mono("")
    private let notes = Style.caption("")
    private let canvasCaption = Style.caption("")
    private let contextLine = Style.caption("")
    private let clock = Style.mono("", size: 12)
    private let displayPopup = NSPopUpButton()
    private var lastDisplayTitles: [String] = []
    private var modePills: [LightingMode: PillButton] = [:]
    private let duration = NSSegmentedControl(labels: OverrideDuration.menuCases.map(\.shortTitle), trackingMode: .selectOne, target: nil, action: nil)
    private let scope = NSButton(checkboxWithTitle: "Only the selected display", target: nil, action: nil)
    private let pause = QuietButton(title: "Pause 30m")
    private let resume = QuietButton(title: "Resume")
    private let undoButton = QuietButton(title: "Undo")
    private let redoButton = QuietButton(title: "Redo")
    private let preview = QuietButton(title: "Preview my day")
    private let live = QuietButton(title: "Live preview")
    private let stop = QuietButton(title: "Stop preview")

    init(controller: AppController) {
        self.controller = controller
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        build()
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func refreshClock() {
        clock.stringValue = ClockFormat.shortTime(controller.evaluationDate)
        if controller.livePreview == nil {
            next.stringValue = StatusExplainer.nextChangeLine(
                wake: controller.decision?.nextWake,
                automation: controller.decision?.automation ?? controller.snapshot?.automation ?? .automatic,
                at: controller.evaluationDate
            )
        }
        refreshHoldChrome()
        configureTimeline(timeline, controller: controller)
        canvasCaption.stringValue = scheduleTimelineCaption(controller: controller, schedule: controller.activeSchedule)
    }

    func refresh() {
        headline.stringValue = controller.presentedHeadline
        explanation.preferredMaxLayoutWidth = max(bounds.width - 80, 280)
        explanation.stringValue = controller.snapshot?.explanation ?? Brand.tagline
        next.stringValue = controller.liveNextChangeLine
        kelvin.stringValue = controller.presentedKelvinLabel
        wash.kelvin = controller.presentedKelvin
        wash.restored = controller.chromeKelvin == nil
        period.set(
            title: controller.presentedModeTitle,
            kelvin: controller.chromeKelvin
        )
        clock.stringValue = ClockFormat.shortTime(controller.evaluationDate)
        notes.stringValue = ([
            controller.simulationMode ? "Simulation mode is on. Hardware is not being changed." : nil,
            controller.selectedAdjustment.message
        ] + controller.lastNotes)
            .compactMap { $0 }
            .joined(separator: "\n")
        notes.isHidden = notes.stringValue.isEmpty
        let selectedName = controller.selectedDisplay.map { controller.displayMenuTitle($0) }
        let selectedTarget = controller.selectedDisplay.map { controller.targetCaption(for: $0) }
        contextLine.stringValue = [controller.snapshot?.displaySummary, selectedName, selectedTarget]
            .compactMap { $0 }
            .joined(separator: " · ")
        configureTimeline(timeline, controller: controller)
        canvasCaption.stringValue = scheduleTimelineCaption(controller: controller, schedule: controller.activeSchedule)
        wash.reduceMotion = controller.reduceMotionActive
        let tracking = warmth.isTracking || brightness.isTracking || dimming.isTracking
        if !tracking {
            if let output = controller.selectedOutput {
                warmth.minValue = controller.settings.temperatureRange.lowerBound
                warmth.maxValue = controller.settings.temperatureRange.upperBound
                warmth.doubleValueSafe = output.temperature.kelvin
                brightness.doubleValueSafe = output.hardwareBrightness?.fraction ?? 0.8
                dimming.doubleValueSafe = output.softwareDimming.factor
                warmthValue.stringValue = output.temperature.roundedLabel
                brightnessValue.stringValue = "\(output.hardwareBrightness?.percent ?? 80)%"
                dimmingValue.stringValue = "\(output.softwareDimming.percent)%"
            } else {
                warmth.minValue = controller.settings.temperatureRange.lowerBound
                warmth.maxValue = controller.settings.temperatureRange.upperBound
                warmth.doubleValueSafe = ColorTemperature.daylightReference.kelvin
                warmthValue.stringValue = controller.presentedKelvinLabel
                brightnessValue.stringValue = "—"
                dimmingValue.stringValue = "—"
                brightness.doubleValueSafe = 0.8
                dimming.doubleValueSafe = SoftwareDimming.none.factor
            }
        }
        let titles = controller.displays.map { controller.displayMenuTitle($0) }
        displayPopup.isHidden = controller.displays.count < 2
        if titles != lastDisplayTitles {
            lastDisplayTitles = titles
            displayPopup.removeAllItems()
            displayPopup.addItems(withTitles: titles)
        }
        if let selectedID = controller.selectedDisplayID,
           let index = controller.displays.firstIndex(where: { $0.id == selectedID }) {
            displayPopup.selectItem(at: index)
        }
        let hasHardware = controller.selectedDisplay?.capabilities.brightness == .hardware
        brightness.superview?.isHidden = !hasHardware
        scope.title = controller.isSelectedDisplayLinked ? "Only this linked group" : "Only the selected display"
        scope.state = controller.sliderAffectsAllDisplays ? .off : .on
        scope.isHidden = controller.displays.count < 2
        let previewing = controller.livePreview != nil
        undoButton.isEnabled = !previewing && !controller.undoStack.isEmpty
        redoButton.isEnabled = !previewing && !controller.redoStack.isEmpty
        refreshHoldChrome()
        let modesEnabled = !controller.settings.disabled && !previewing
        preview.isHidden = previewing
        live.isHidden = previewing
        stop.isHidden = !previewing
        preview.isEnabled = modesEnabled
        live.isEnabled = modesEnabled && !controller.isPausedNow
        live.toolTip = controller.isPausedNow ? "Resume automation to preview on the display." : "Apply the day preview to the display."
        stop.isEnabled = previewing
        let adjustable = controller.canAdjustSelectedDisplay
        warmth.isEnabled = adjustable
        brightness.isEnabled = adjustable
        dimming.isEnabled = adjustable
        duration.isEnabled = modesEnabled
        scope.isEnabled = modesEnabled
        pause.isHidden = controller.isPausedNow
        pause.isEnabled = !controller.isPausedNow && modesEnabled
        resume.isHidden = previewing || (!controller.isPausedNow && controller.activeOverride == nil)
        resume.isEnabled = !previewing && (controller.isPausedNow || controller.activeOverride != nil)
        if let index = OverrideDuration.menuCases.firstIndex(of: controller.sliderDuration) {
            duration.selectedSegment = index
        }
        let paused = controller.isPausedNow
        let active = controller.activeOverride?.mode ?? .automatic
        if paused || controller.settings.disabled || previewing {
            for (mode, pill) in modePills {
                pill.active = false
                pill.isEnabled = mode == .automatic && !controller.settings.disabled && !previewing
            }
        } else if controller.activeOverride?.isManualAdjustment == true {
            for (_, pill) in modePills {
                pill.isEnabled = true
                pill.active = false
            }
        } else {
            for (mode, pill) in modePills {
                pill.isEnabled = true
                pill.active = mode == (controller.activeOverride == nil ? .automatic : active)
            }
        }
    }

    private func refreshHoldChrome() {
        if controller.isPausedNow, let remaining = controller.settings.pause.expiresAt?.timeIntervalSinceNow, remaining > 0 {
            pause.title = "Paused · \(RulesEngine.compact(remaining))"
        } else {
            pause.title = "Pause 30m"
        }
        resume.title = ActionTitles.resume(
            paused: controller.isPausedNow,
            pauseEndsAt: controller.settings.pause.expiresAt,
            holding: controller.activeOverride != nil,
            holdEndsAt: controller.activeOverride?.expiresAt
        )
    }

    private func build() {
        wash.translatesAutoresizingMaskIntoConstraints = false
        wash.heightAnchor.constraint(equalToConstant: 136).isActive = true
        wash.wantsLayer = true
        wash.layer?.cornerRadius = Style.cardRadius
        wash.layer?.cornerCurve = .continuous
        let headerText = Stack(axis: .vertical, spacing: 6, views: [
            Stack(axis: .horizontal, spacing: 0, views: [period, NSView(), clock]),
            headline,
            explanation,
            next,
            kelvin,
            contextLine
        ])
        headerText.edgeInsets = NSEdgeInsets(top: 16, left: 18, bottom: 16, right: 18)
        headerText.pinToEdges(of: wash)

        let primary = Stack(axis: .horizontal, spacing: 6)
        let secondary = Stack(axis: .horizontal, spacing: 6)
        let tertiary = Stack(axis: .horizontal, spacing: 6)
        for (index, mode) in LightingMode.allCases.enumerated() {
            let pill = PillButton(title: mode.title)
            pill.toolTip = mode.summary
            actions.bind(pill) { [weak self] in
                self?.controller.setMode(mode, duration: self?.controller.sliderDuration ?? .minutes(30))
            }
            modePills[mode] = pill
            if index < 3 {
                primary.addArrangedSubview(pill)
            } else if index < 5 {
                secondary.addArrangedSubview(pill)
            } else {
                tertiary.addArrangedSubview(pill)
            }
        }
        let modes = Stack(axis: .vertical, spacing: 6, views: [primary, secondary, tertiary])

        warmth.track = .warmth
        warmth.setAccessibilityLabel("Warmth")
        warmth.onChange = { [weak self] value in
            self?.warmthValue.stringValue = ColorTemperature(kelvin: value).roundedLabel
            self?.controller.applySlider(temperature: value)
        }
        warmth.onCommit = { [weak self] value in self?.controller.finishSlider(temperature: value) }
        warmth.onCancel = { [weak self] _ in self?.controller.abandonSlider() }
        brightness.track = .brightness
        brightness.minValue = 0.12
        brightness.maxValue = 1
        brightness.setAccessibilityLabel("Hardware brightness")
        brightness.onChange = { [weak self] value in
            self?.brightnessValue.stringValue = "\(Int((value * 100).rounded()))%"
            self?.controller.applySlider(brightness: value)
        }
        brightness.onCommit = { [weak self] value in self?.controller.finishSlider(brightness: value) }
        brightness.onCancel = { [weak self] _ in self?.controller.abandonSlider() }
        dimming.track = .dimming
        dimming.minValue = SoftwareDimming.readableRange.lowerBound
        dimming.maxValue = SoftwareDimming.readableRange.upperBound
        dimming.setAccessibilityLabel("Software dimming")
        dimming.onChange = { [weak self] value in
            self?.dimmingValue.stringValue = "\(Int((value * 100).rounded()))%"
            self?.controller.applySlider(dimming: value)
        }
        dimming.onCommit = { [weak self] value in self?.controller.finishSlider(dimming: value) }
        dimming.onCancel = { [weak self] _ in self?.controller.abandonSlider() }

        duration.selectedSegment = 1
        duration.target = self
        duration.action = #selector(durationChanged)
        duration.setAccessibilityLabel("Keep slider changes")
        duration.segmentDistribution = .fillEqually
        scope.target = self
        scope.action = #selector(scopeChanged)
        displayPopup.target = self
        displayPopup.action = #selector(displayChosen)
        displayPopup.setAccessibilityLabel("Display")

        actions.bind(pause) { [weak self] in
            self?.controller.pause(duration: .minutes(30))
        }
        actions.bind(resume) { [weak self] in self?.controller.resume() }
        let restore = QuietButton(title: "Restore")
        actions.bind(restore) { [weak self] in self?.controller.restoreNow() }
        actions.bind(preview) { [weak self] in self?.controller.previewDay(applyToHardware: false) }
        actions.bind(live) { [weak self] in self?.controller.previewDay(applyToHardware: true) }
        actions.bind(stop) { [weak self] in self?.controller.cancelPreview(applyCleanup: true) }
        actions.bind(undoButton) { [weak self] in self?.controller.undoSchedule() }
        actions.bind(redoButton) { [weak self] in self?.controller.redoSchedule() }
        stop.isHidden = true
        let copy = QuietButton(title: "Copy status")
        actions.bind(copy) { [weak self] in self?.controller.copyStatus() }

        timeline.heightAnchor.constraint(equalToConstant: 188).isActive = true

        let stack = Stack(axis: .vertical, spacing: 14, views: [
            wash,
            displayPopup,
            CardView.wrap(modes),
            CardView.wrap(Stack(axis: .vertical, spacing: 8, views: [
                timeline,
                canvasCaption,
                Stack(axis: .horizontal, spacing: 8, views: [undoButton, redoButton])
            ])),
            CardView.wrap(Stack(axis: .vertical, spacing: 10, views: [
                Style.caption("A slider change is a temporary override. It does not rewrite the saved schedule."),
                labeled("Warmth", warmth, warmthValue),
                labeled("Brightness", brightness, brightnessValue),
                labeled("Software dimming", dimming, dimmingValue),
                Stack(axis: .horizontal, spacing: 10, views: [Style.caption("Keep for"), duration, scope]),
                Stack(axis: .horizontal, spacing: 8, views: [pause, resume, restore]),
                Stack(axis: .horizontal, spacing: 8, views: [preview, live, stop, copy]),
                notes
            ]))
        ])
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 22, bottom: 24, right: 22)
        stack.pinToEdges(of: self)
    }

    private func labeled(_ title: String, _ control: NSView, _ value: NSView) -> NSView {
        Stack(axis: .vertical, spacing: 4, views: [
            Stack(axis: .horizontal, spacing: 8, views: [
                Style.label(title, font: .systemFont(ofSize: 12, weight: .medium)),
                NSView(),
                value
            ]),
            control
        ])
    }

    @objc private func durationChanged() {
        let cases = OverrideDuration.menuCases
        let index = duration.selectedSegment
        if cases.indices.contains(index) {
            controller.setSliderDuration(cases[index])
        }
    }

    @objc private func scopeChanged() {
        controller.setSliderAffectsAllDisplays(scope.state == .off)
    }

    @objc private func displayChosen() {
        let index = displayPopup.indexOfSelectedItem
        if controller.displays.indices.contains(index) {
            controller.selectDisplay(id: controller.displays[index].id)
        }
    }
}

@MainActor
final class SchedulePane: NSView, NSComboBoxDelegate {
    private let controller: AppController
    private let actions = ActionMap()
    private let timeline = TimelineCanvas()
    private let approach = NSPopUpButton()
    private let summary = Style.caption("")
    private let weekend = NSButton(checkboxWithTitle: "Use a separate weekend schedule", target: nil, action: nil)
    private let editingWeekend = NSButton(checkboxWithTitle: "Editing weekend", target: nil, action: nil)
    private let city = NSComboBox()
    private let cityNote = Style.caption("")
    private let sunriseOffset = NSSlider()
    private let sunsetOffset = NSSlider()
    private let sunriseLabel = Style.mono("Sunrise +0m")
    private let sunsetLabel = Style.mono("Sunset +0m")
    private let canvasCaption = Style.caption("")
    private let anchorsHost = Stack(axis: .vertical, spacing: 10)
    private var lastAnchorSignature = ""
    private var editorSliders: [String: GradientSlider] = [:]
    private var editorKelvin: [String: NSTextField] = [:]
    private var editorPickers: [String: NSDatePicker] = [:]
    private var editorTransitions: [String: NSSlider] = [:]
    private var editorTransitionLabels: [String: NSTextField] = [:]
    private var editorRemoves: [String: QuietButton] = [:]
    private var timeUndoArmed = false
    private var timeSettle: Timer?
    private var transitionUndoArmed = false
    private var transitionSettle: Timer?
    private let undoButton = QuietButton(title: "Undo")
    private let redoButton = QuietButton(title: "Redo")
    private let resetTimesButton = QuietButton(title: "Reset times")
    private let addCustomButton = QuietButton(title: "Add custom time")
    private let previewLockNote = Style.caption("Stop the preview to edit the schedule.")

    init(controller: AppController) {
        self.controller = controller
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        build()
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func refreshClock() {
        configureTimeline(timeline, controller: controller)
    }

    func refresh() {
        if let index = ScheduleApproach.allCases.firstIndex(of: controller.activeSchedule.approach) {
            approach.selectItem(at: index)
        }
        summary.stringValue = controller.activeSchedule.approach.summary
        weekend.state = controller.settings.useWeekendSchedule ? .on : .off
        editingWeekend.state = controller.editingWeekendSchedule ? .on : .off
        editingWeekend.isHidden = !controller.settings.useWeekendSchedule
        if city.currentEditor() == nil {
            city.stringValue = controller.settings.location?.name ?? ""
            refreshCityNote(city.stringValue)
        }
        let schedule = controller.activeSchedule
        if !sunriseOffset.isHighlighted {
            sunriseOffset.intValue = Int32(schedule.sunriseOffsetMinutes)
            sunriseLabel.stringValue = offsetText("Sunrise", schedule.sunriseOffsetMinutes)
        }
        if !sunsetOffset.isHighlighted {
            sunsetOffset.intValue = Int32(schedule.sunsetOffsetMinutes)
            sunsetLabel.stringValue = offsetText("Sunset", schedule.sunsetOffsetMinutes)
        }
        let solarish = schedule.approach == .solar || schedule.approach == .hybrid
        sunriseOffset.superview?.isHidden = !solarish
        sunsetOffset.superview?.isHidden = !solarish
        refreshClock()
        canvasCaption.stringValue = scheduleTimelineCaption(controller: controller, schedule: schedule)
        let previewing = controller.livePreview != nil
        undoButton.isEnabled = !previewing && !controller.undoStack.isEmpty
        redoButton.isEnabled = !previewing && !controller.redoStack.isEmpty
        resetTimesButton.isEnabled = !previewing && schedule.approach != .custom
        resetTimesButton.toolTip = previewing
            ? "Stop the preview to edit the schedule."
            : schedule.approach == .custom
            ? "Switch to Personal to reset wake and wind-down."
            : "Restore the default wake and wind-down times."
        addCustomButton.isEnabled = !previewing
        approach.isEnabled = !previewing
        weekend.isEnabled = !previewing
        editingWeekend.isEnabled = !previewing
        city.isEnabled = !previewing
        sunriseOffset.isEnabled = !previewing
        sunsetOffset.isEnabled = !previewing
        previewLockNote.isHidden = !previewing
        rebuildAnchorsIfNeeded()
    }

    private func build() {
        approach.addItems(withTitles: ScheduleApproach.allCases.map(\.title))
        approach.target = self
        approach.action = #selector(approachChanged)
        weekend.target = self
        weekend.action = #selector(weekendToggled)
        editingWeekend.target = self
        editingWeekend.action = #selector(editingToggled)

        city.addItems(withObjectValues: Cities.featured.map(\.name))
        city.completes = true
        city.placeholderString = "City for sunrise and sunset"
        city.delegate = self
        city.target = self
        city.action = #selector(cityChosen)
        city.setContentHuggingPriority(.defaultLow, for: .horizontal)

        sunriseOffset.minValue = -90
        sunriseOffset.maxValue = 90
        sunriseOffset.target = self
        sunriseOffset.action = #selector(offsetsChanged)
        sunsetOffset.minValue = -90
        sunsetOffset.maxValue = 90
        sunsetOffset.target = self
        sunsetOffset.action = #selector(offsetsChanged)

        actions.bind(undoButton) { [weak self] in self?.controller.undoSchedule() }
        actions.bind(redoButton) { [weak self] in self?.controller.redoSchedule() }
        actions.bind(resetTimesButton) { [weak self] in
            self?.controller.updateSchedule { $0.personalAnchors = DailySchedule.personal(preset: self?.controller.settings.preset ?? .balanced).personalAnchors }
        }
        actions.bind(addCustomButton) { [weak self] in self?.controller.addCustomAnchor() }
        let clear = QuietButton(title: "Clear location")
        actions.bind(clear) { [weak self] in self?.controller.setLocation(nil) }

        timeline.heightAnchor.constraint(equalToConstant: 188).isActive = true

        let stack = Stack(axis: .vertical, spacing: 14, views: [
            Style.title("Schedule"),
            CardView.wrap(Stack(axis: .vertical, spacing: 8, views: [
                Style.label("How Daylight should follow your day", font: .systemFont(ofSize: 13, weight: .medium)),
                approach,
                summary,
                weekend,
                editingWeekend
            ])),
            CardView.wrap(Stack(axis: .vertical, spacing: 8, views: [
                Style.caption("Optional location for sunrise and sunset. Typed locally — no permission."),
                Stack(axis: .horizontal, spacing: 8, views: [city, clear]),
                cityNote,
                labeled(sunriseLabel, sunriseOffset),
                labeled(sunsetLabel, sunsetOffset)
            ])),
            CardView.wrap(Stack(axis: .vertical, spacing: 8, views: [
                timeline,
                canvasCaption,
                previewLockNote
            ])),
            Stack(axis: .horizontal, spacing: 8, views: [undoButton, redoButton, resetTimesButton, addCustomButton]),
            anchorsHost
        ])
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 22, bottom: 24, right: 22)
        stack.pinToEdges(of: self)
    }

    private func rebuildAnchorsIfNeeded() {
        let schedule = controller.activeSchedule
        let signature = schedule.approach.rawValue + "|" + schedule.personalAnchors.map(\.id).joined() + "|" + schedule.customAnchors.map(\.id).joined() + (controller.editingWeekendSchedule ? "w" : "d")
        guard signature != lastAnchorSignature else {
            refreshAnchorValues()
            return
        }
        lastAnchorSignature = signature
        editorSliders.removeAll()
        editorKelvin.removeAll()
        editorPickers.removeAll()
        editorTransitions.removeAll()
        editorTransitionLabels.removeAll()
        editorRemoves.removeAll()
        anchorsHost.arrangedSubviews.forEach {
            anchorsHost.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        if schedule.approach != .custom {
            for (index, anchor) in schedule.personalAnchors.enumerated() {
                anchorsHost.addArrangedSubview(anchorEditor(anchor, personalIndex: index, customID: nil))
            }
        } else if schedule.customAnchors.isEmpty {
            anchorsHost.addArrangedSubview(Style.caption("Add a time on the timeline or with Add custom time. Wake and wind-down stay saved if you switch back to Personal."))
        }
        for anchor in schedule.customAnchors {
            anchorsHost.addArrangedSubview(anchorEditor(anchor, personalIndex: nil, customID: anchor.id))
        }
    }

    private func refreshAnchorValues() {
        let schedule = controller.activeSchedule
        for (index, anchor) in schedule.personalAnchors.enumerated() {
            applyEditorValues(key: "personal-\(index)", anchor: anchor)
        }
        for anchor in schedule.customAnchors {
            applyEditorValues(key: anchor.id, anchor: anchor)
        }
    }

    private func applyEditorValues(key: String, anchor: ScheduleAnchor) {
        if let slider = editorSliders[key], !slider.isTracking {
            slider.doubleValueSafe = anchor.output.temperature.kelvin
            editorKelvin[key]?.stringValue = anchor.output.temperature.roundedLabel
        }
        if case .clock(let time) = anchor.timing, let picker = editorPickers[key],
           picker.currentEditor() == nil, picker.window?.firstResponder !== picker {
            Style.setTime(picker, time)
        }
        if let slider = editorTransitions[key], !slider.isHighlighted {
            slider.intValue = Int32(anchor.transitionMinutes)
            editorTransitionLabels[key]?.stringValue = "\(anchor.transitionMinutes)-minute transition"
        }
        let previewing = controller.livePreview != nil
        editorSliders[key]?.isEnabled = !previewing
        editorPickers[key]?.isEnabled = !previewing
        editorTransitions[key]?.isEnabled = !previewing
        editorRemoves[key]?.isEnabled = !previewing
    }

    private func anchorEditor(_ anchor: ScheduleAnchor, personalIndex: Int?, customID: String?) -> NSView {
        let name = Style.label(anchor.name, font: .systemFont(ofSize: 13, weight: .medium))
        let kelvin = Style.mono(anchor.output.temperature.roundedLabel)
        let slider = GradientSlider()
        slider.minValue = controller.settings.temperatureRange.lowerBound
        slider.maxValue = controller.settings.temperatureRange.upperBound
        slider.doubleValueSafe = anchor.output.temperature.kelvin
        let key = customID ?? "personal-\(personalIndex ?? 0)"
        editorSliders[key] = slider
        editorKelvin[key] = kelvin
        slider.onChange = { value in
            kelvin.stringValue = ColorTemperature(kelvin: value).roundedLabel
        }
        slider.onCommit = { [weak self] value in
            self?.controller.updateSchedule({ schedule in
                if let personalIndex, schedule.personalAnchors.indices.contains(personalIndex) {
                    schedule.personalAnchors[personalIndex].output.temperature.kelvin = value
                } else if let customID, let index = schedule.customAnchors.firstIndex(where: { $0.id == customID }) {
                    schedule.customAnchors[index].output.temperature.kelvin = value
                }
            }, recordUndo: true)
        }
        var views: [NSView] = [Stack(axis: .horizontal, spacing: 10, views: [name, kelvin])]
        let solarTimesFollowSun = controller.activeSchedule.approach == .solar && personalIndex != nil
        if case .clock(let time) = anchor.timing, !solarTimesFollowSun {
            let picker = Style.timePicker(time: time, tag: personalIndex ?? 800, target: self, action: #selector(timeChanged(_:)))
            picker.identifier = NSUserInterfaceItemIdentifier(key)
            editorPickers[key] = picker
            views.append(picker)
        } else if solarTimesFollowSun {
            views.append(Style.caption("This warmth is used at sunrise or sunset. The clock time follows the sun."))
        }
        views.append(slider)
        let transition = NSSlider()
        transition.minValue = 5
        transition.maxValue = 90
        transition.intValue = Int32(anchor.transitionMinutes)
        transition.identifier = NSUserInterfaceItemIdentifier(key)
        transition.target = self
        transition.action = #selector(transitionChanged(_:))
        transition.setAccessibilityLabel("Transition length")
        let transitionLabel = Style.mono("\(anchor.transitionMinutes)-minute transition")
        editorTransitions[key] = transition
        editorTransitionLabels[key] = transitionLabel
        views.append(labeled(transitionLabel, transition))
        if let customID {
            let remove = QuietButton(title: "Remove", destructive: true)
            actions.bind(remove) { [weak self] in self?.controller.removeCustomAnchor(id: customID) }
            editorRemoves[key] = remove
            views.append(remove)
        }
        return CardView.wrap(Stack(axis: .vertical, spacing: 8, views: views))
    }

    private func labeled(_ title: NSView, _ control: NSView) -> NSView {
        Stack(axis: .vertical, spacing: 4, views: [title, control])
    }

    private func offsetText(_ name: String, _ minutes: Int) -> String {
        if minutes == 0 { return "\(name) at the calculated time" }
        if minutes > 0 { return "\(name) \(minutes) minutes later" }
        return "\(name) \(abs(minutes)) minutes earlier"
    }

    @objc private func approachChanged() {
        let cases = ScheduleApproach.allCases
        let index = approach.indexOfSelectedItem
        guard cases.indices.contains(index) else { return }
        controller.setApproach(cases[index])
    }

    @objc private func weekendToggled() {
        controller.settings.useWeekendSchedule = weekend.state == .on
        if !controller.settings.useWeekendSchedule {
            controller.editingWeekendSchedule = false
            controller.settings.lastEditingWeekend = false
        }
        controller.persist()
        controller.evaluateAndApply()
    }

    @objc private func editingToggled() {
        controller.editingWeekendSchedule = editingWeekend.state == .on
        controller.settings.lastEditingWeekend = controller.editingWeekendSchedule
        controller.persist()
        lastAnchorSignature = ""
        refresh()
    }

    @objc private func cityChosen() {
        applyCity(city.stringValue)
    }

    func comboBoxSelectionDidChange(_ notification: Notification) {
        applyCity(Style.comboSelection(city))
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard obj.object as? NSComboBox === city else { return }
        applyCity(city.stringValue)
    }

    private func applyCity(_ query: String) {
        refreshCityNote(query)
        switch Cities.status(for: query) {
        case .empty:
            controller.setLocation(nil)
        case .matched(let match):
            controller.setLocation(match)
        case .unrecognized:
            let kept = controller.settings.location?.name ?? ""
            city.stringValue = kept
            if kept.isEmpty {
                cityNote.stringValue = "City not recognized — pick from the list or leave blank."
            } else {
                cityNote.stringValue = "City not recognized — still using \(kept)."
            }
            cityNote.isHidden = false
        }
    }

    private func refreshCityNote(_ query: String) {
        switch Cities.status(for: query) {
        case .empty, .matched:
            cityNote.stringValue = ""
            cityNote.isHidden = true
        case .unrecognized:
            cityNote.stringValue = "City not recognized — pick from the list or leave blank."
            cityNote.isHidden = false
        }
    }

    @objc private func offsetsChanged() {
        controller.setSolarOffset(sunrise: Int(sunriseOffset.intValue), sunset: Int(sunsetOffset.intValue))
    }

    @objc private func timeChanged(_ sender: NSDatePicker) {
        let time = Style.time(from: sender)
        let identifier = sender.identifier?.rawValue ?? ""
        controller.updateSchedule({ schedule in
            if identifier.hasPrefix("personal-"), let index = Int(identifier.replacingOccurrences(of: "personal-", with: "")), schedule.personalAnchors.indices.contains(index) {
                schedule.personalAnchors[index].timing = .clock(time)
            } else if let index = schedule.customAnchors.firstIndex(where: { $0.id == identifier }) {
                schedule.customAnchors[index].timing = .clock(time)
            }
        }, recordUndo: !timeUndoArmed)
        timeUndoArmed = true
        timeSettle?.invalidate()
        timeSettle = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.timeUndoArmed = false }
        }
        if let timeSettle {
            RunLoop.main.add(timeSettle, forMode: .common)
        }
    }

    @objc private func transitionChanged(_ sender: NSSlider) {
        let identifier = sender.identifier?.rawValue ?? ""
        let minutes = min(max(Int(sender.intValue), 5), 90)
        editorTransitionLabels[identifier]?.stringValue = "\(minutes)-minute transition"
        controller.updateSchedule({ schedule in
            if identifier.hasPrefix("personal-"), let index = Int(identifier.replacingOccurrences(of: "personal-", with: "")), schedule.personalAnchors.indices.contains(index) {
                schedule.personalAnchors[index].transitionMinutes = minutes
            } else if let index = schedule.customAnchors.firstIndex(where: { $0.id == identifier }) {
                schedule.customAnchors[index].transitionMinutes = minutes
            }
        }, recordUndo: !transitionUndoArmed)
        transitionUndoArmed = true
        transitionSettle?.invalidate()
        transitionSettle = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.transitionUndoArmed = false }
        }
        if let transitionSettle {
            RunLoop.main.add(transitionSettle, forMode: .common)
        }
    }
}

@MainActor
final class DisplaysPane: NSView {
    private let controller: AppController
    private let actions = ActionMap()
    private let host = Stack(axis: .vertical, spacing: 12)
    private var linkButton: QuietButton?
    private var unlinkButton: QuietButton?
    private var signature = ""
    private var retained: [NSObject] = []
    private var offsetLabels: [String: NSTextField] = [:]
    private var targetLabels: [String: NSTextField] = [:]
    private var cards: [String: CardView] = [:]
    private var selectedCaptions: [String: NSTextField] = [:]
    private var swatches: [String: KelvinSwatch] = [:]
    private var offsetSliders: [String: NSSlider] = [:]
    private var lastScrolledSelection: String?

    init(controller: AppController) {
        self.controller = controller
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let link = QuietButton(title: "Link all active displays")
        actions.bind(link) { [weak self] in self?.controller.linkSelectedDisplays() }
        let unlink = QuietButton(title: "Unlink")
        actions.bind(unlink) { [weak self] in self?.controller.unlinkDisplays() }
        self.linkButton = link
        self.unlinkButton = unlink
        let stack = Stack(axis: .vertical, spacing: 14, views: [
            Style.title("Displays"),
            Style.caption("Each display can be named, excluded, or given a small brightness offset. Cards show that display’s real target, including a scoped hold. Linking groups every active display so a manual override applies to all of them. Idle and mirrored displays are not linked."),
            Stack(axis: .horizontal, spacing: 8, views: [link, unlink]),
            host
        ])
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 22, bottom: 24, right: 22)
        stack.pinToEdges(of: self)
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func refresh() {
        let next = controller.displays.map { display in
            let prefs = controller.settings.preferences(for: display.identity)
            return "\(display.id)|\(prefs.customName ?? "")|\(prefs.excludedFromAutomation)|\(controller.settings.isLinked(display.id))|\(display.connection.rawValue)|\(display.isMirrored)"
        }.joined(separator: ",")
        if next != signature {
            signature = next
            rebuild()
        }
        let linkable = DisplayTargeting.linkableDisplayKeys(controller.displays).count
        linkButton?.title = "Link all active displays"
        linkButton?.isEnabled = linkable > 1
        unlinkButton?.isEnabled = !controller.settings.groups.isEmpty
        for display in controller.displays {
            let prefs = controller.settings.preferences(for: display.identity)
            if let slider = offsetSliders[display.id], !slider.isHighlighted {
                slider.doubleValue = prefs.brightnessOffset
            }
            offsetLabels[display.id]?.stringValue = offsetText(prefs.brightnessOffset)
            cards[display.id]?.highlighted = display.id == controller.selectedDisplayID
            if display.id == controller.selectedDisplayID, lastScrolledSelection != display.id, let card = cards[display.id] {
                lastScrolledSelection = display.id
                card.scrollToVisible(card.bounds)
            }
            selectedCaptions[display.id]?.stringValue = display.id == controller.selectedDisplayID
                ? "Selected for sliders and modes"
                : "Click the card to control this display"
            if let output = controller.desiredOutput(for: display) {
                swatches[display.id]?.kelvin = output.temperature.kelvin
                swatches[display.id]?.restored = false
            } else {
                swatches[display.id]?.kelvin = ColorTemperature.daylightReference.kelvin
                swatches[display.id]?.restored = true
            }
            if let label = targetLabels[display.id] {
                let role = display.isMain ? "Main display" : (display.identity.isBuiltin ? "Built-in" : "External")
                let group = controller.settings.isLinked(display.id) ? "Linked" : "Independent"
                var detail = "\(role) · \(display.connection.title) · \(group)"
                if display.isMirrored { detail += " · Mirrored" }
                label.stringValue = "\(display.widthPixels)×\(display.heightPixels) · \(detail) · \(controller.targetCaption(for: display))"
            }
        }
    }

    private func rebuild() {
        retained.removeAll()
        offsetLabels.removeAll()
        offsetSliders.removeAll()
        lastScrolledSelection = nil
        targetLabels.removeAll()
        cards.removeAll()
        selectedCaptions.removeAll()
        swatches.removeAll()
        host.arrangedSubviews.forEach {
            host.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for display in controller.displays {
            host.addArrangedSubview(card(for: display))
        }
        if controller.displays.isEmpty {
            host.addArrangedSubview(Style.caption("No displays are visible to this process."))
        }
    }

    private func card(for display: ConnectedDisplay) -> NSView {
        let prefs = controller.settings.preferences(for: display.identity)
        let name = NSTextField(string: controller.displayName(display))
        name.placeholderString = "Display name"
        name.isBezeled = true
        name.bezelStyle = .roundedBezel
        name.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let nameDelegate = NameDelegate { [weak self] text in
            self?.controller.renameDisplay(display, to: text)
        }
        retained.append(nameDelegate)
        name.delegate = nameDelegate
        let exclude = NSButton(checkboxWithTitle: "Exclude from automation", target: nil, action: nil)
        exclude.state = prefs.excludedFromAutomation ? .on : .off
        exclude.isEnabled = !display.isMirrored || prefs.excludedFromAutomation
        if display.isMirrored {
            exclude.toolTip = "Mirrored displays follow the primary. Exclude the main display instead."
        }
        actions.bind(exclude) { [weak self] in
            self?.controller.setExcluded(display, excluded: exclude.state == .on)
        }
        let offset = NSSlider()
        offset.minValue = -0.2
        offset.maxValue = 0.2
        offset.doubleValue = prefs.brightnessOffset
        offset.setAccessibilityLabel("Brightness offset")
        let offsetCaption = Style.caption(offsetText(prefs.brightnessOffset))
        offsetLabels[display.id] = offsetCaption
        let proxy = OffsetProxy { [weak self] value in
            offsetCaption.stringValue = self?.offsetText(value) ?? ""
            self?.controller.setBrightnessOffset(display, offset: value)
        }
        retained.append(proxy)
        offset.target = proxy
        offset.action = #selector(OffsetProxy.changed(_:))
        offsetSliders[display.id] = offset
        let group = controller.settings.isLinked(display.id) ? "Linked" : "Independent"
        let role = display.isMain ? "Main display" : (display.identity.isBuiltin ? "Built-in" : "External")
        var detail = "\(role) · \(display.connection.title) · \(group)"
        if display.isMirrored { detail += " · Mirrored" }
        let notes = display.capabilities.notes.joined(separator: " ")
        let target = Style.caption("\(display.widthPixels)×\(display.heightPixels) · \(detail) · \(controller.targetCaption(for: display))")
        targetLabels[display.id] = target
        let selected = Style.caption(display.id == controller.selectedDisplayID
            ? "Selected for sliders and modes"
            : "Click the card to control this display")
        selectedCaptions[display.id] = selected
        let swatch = KelvinSwatch()
        if let output = controller.desiredOutput(for: display) {
            swatch.kelvin = output.temperature.kelvin
        } else {
            swatch.restored = true
        }
        swatches[display.id] = swatch
        var rows: [NSView] = [
            Stack(axis: .horizontal, spacing: 8, views: [swatch, name]),
            selected,
            Style.caption("\(display.capabilities.warmth.label) · \(display.capabilities.brightness.label)"),
            target
        ]
        if !notes.isEmpty {
            rows.append(Style.caption(notes))
        }
        if display.isMirrored {
            offset.isEnabled = false
            offset.toolTip = "Mirrored displays follow the primary. Adjust brightness on the main display instead."
            offsetCaption.stringValue = "Brightness offset follows the primary display"
        }
        rows.append(contentsOf: [exclude, offsetCaption, offset])
        let card = CardView.wrap(Stack(axis: .vertical, spacing: 8, views: rows))
        card.highlighted = display.id == controller.selectedDisplayID
        cards[display.id] = card
        let click = ClickProxy { [weak self] in
            self?.controller.selectDisplay(id: display.id)
        }
        click.card = card
        retained.append(click)
        let recognizer = NSClickGestureRecognizer(target: click, action: #selector(ClickProxy.run))
        recognizer.delegate = click
        card.addGestureRecognizer(recognizer)
        return card
    }

    private func offsetText(_ value: Double) -> String {
        let percent = Int((value * 100).rounded())
        if percent == 0 { return "No extra brightness offset" }
        if percent > 0 { return "Brightness offset +\(percent)%" }
        return "Brightness offset \(percent)%"
    }
}

@MainActor
final class SettingsPane: NSView {
    private let controller: AppController
    private let actions = ActionMap()
    private let enabled = NSButton(checkboxWithTitle: "Daylight is on", target: nil, action: nil)
    private let launch = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let launchNote = Style.caption("")
    private let loginItems = QuietButton(title: "Open Login Items")
    private let background = NSButton(checkboxWithTitle: "Keep running after the window closes", target: nil, action: nil)
    private let advanced = NSButton(checkboxWithTitle: "Allow a wider warmth range", target: nil, action: nil)
    private let history = NSButton(checkboxWithTitle: "Keep a local activity history", target: nil, action: nil)
    private let motion = NSButton(checkboxWithTitle: "Reduce motion (also follows System Settings)", target: nil, action: nil)
    private let menuBarTemperature = NSButton(checkboxWithTitle: "Show temperature in the menu bar", target: nil, action: nil)
    private let restoreOnSleep = NSButton(checkboxWithTitle: "Restore native output when this Mac sleeps", target: nil, action: nil)
    private let appearancePopup = NSPopUpButton()
    private let transition = NSSlider()
    private let transitionLabel = Style.mono("30-minute default transitions")
    private let historyList = Style.caption("")
    private let diagnostics = Style.caption("")

    init(controller: AppController) {
        self.controller = controller
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        build()
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func refresh() {
        enabled.state = controller.settings.disabled ? .off : .on
        launch.state = controller.settings.launchAtLogin ? .on : .off
        launchNote.stringValue = controller.launchAtLoginMessage() ?? ""
        launchNote.isHidden = launchNote.stringValue.isEmpty
        loginItems.isHidden = launchNote.isHidden
        background.state = controller.settings.keepRunningInBackground ? .on : .off
        advanced.state = controller.settings.useAdvancedTemperatureRange ? .on : .off
        history.state = controller.settings.historyEnabled ? .on : .off
        motion.state = controller.settings.reduceMotion ? .on : .off
        menuBarTemperature.state = controller.settings.showMenuBarTemperature ? .on : .off
        restoreOnSleep.state = controller.settings.restoreOnSleep ? .on : .off
        if let index = AppearancePreference.allCases.firstIndex(of: controller.settings.appearance) {
            appearancePopup.selectItem(at: index)
        }
        if !transition.isHighlighted {
            transition.intValue = Int32(controller.settings.defaultTransitionMinutes)
            transitionLabel.stringValue = "\(controller.settings.defaultTransitionMinutes)-minute transitions for every time"
        }
        let previewing = controller.livePreview != nil
        transition.isEnabled = !previewing
        transition.toolTip = previewing
            ? "Stop the preview to change default transitions."
            : "Applies this length to every existing time. Schedule can still refine one time."
        if controller.settings.historyEnabled {
            let lines = controller.history.prefix(8).map { event in
                event.detail.isEmpty
                    ? "\(ScheduleEngine.shortStamp(event.at))  \(event.title)"
                    : "\(ScheduleEngine.shortStamp(event.at))  \(event.title)\n    \(event.detail)"
            }
            historyList.stringValue = lines.isEmpty ? "No local activity yet. Daylight will keep a short log on this Mac." : lines.joined(separator: "\n")
        } else {
            historyList.stringValue = "Turn on local activity history to keep a short log on this Mac."
        }
        historyList.isHidden = false
        let warmth = controller.selectedDisplay?.capabilities.warmth.label ?? "No display"
        let brightness = controller.selectedDisplay?.capabilities.brightness.label ?? "No display"
        let lighting = controller.presentedKelvinLabel
        let previewLine: String
        if let preview = controller.livePreview {
            previewLine = preview.applyingToHardware
                ? "Live day preview is applying to the display."
                : "Interface preview is running. Hardware is unchanged."
        } else if controller.simulationMode {
            previewLine = "Simulation is on — hardware is not being changed."
        } else {
            previewLine = "Writing to hardware when a display accepts it."
        }
        diagnostics.stringValue = """
        \(controller.environment.chipBrand) · macOS \(controller.environment.osMajor)
        Warmth: \(warmth)
        Brightness: \(brightness)
        This display: \(lighting)
        \(previewLine)
        Emergency restore: \(Brand.emergencyRestoreShortcut)
        """
    }

    private func build() {
        appearancePopup.addItems(withTitles: AppearancePreference.allCases.map(\.title))
        appearancePopup.target = self
        appearancePopup.action = #selector(appearanceChanged)
        enabled.target = self
        enabled.action = #selector(toggleEnabled)
        launch.target = self
        launch.action = #selector(toggleLaunch)
        background.target = self
        background.action = #selector(toggleBackground)
        advanced.target = self
        advanced.action = #selector(toggleAdvanced)
        history.target = self
        history.action = #selector(toggleHistory)
        motion.target = self
        motion.action = #selector(toggleMotion)
        menuBarTemperature.target = self
        menuBarTemperature.action = #selector(toggleMenuBarTemperature)
        restoreOnSleep.target = self
        restoreOnSleep.action = #selector(toggleRestoreOnSleep)
        transition.minValue = 5
        transition.maxValue = 90
        transition.target = self
        transition.action = #selector(transitionChanged)

        actions.bind(loginItems) { [weak self] in self?.controller.openLoginItemsSettings() }
        loginItems.isHidden = true
        let export = QuietButton(title: "Export settings")
        actions.bind(export) { [weak self] in self?.exportSettings() }
        let imported = QuietButton(title: "Import settings")
        actions.bind(imported) { [weak self] in self?.importSettings() }
        let reset = QuietButton(title: "Reset to defaults", destructive: true)
        actions.bind(reset) { [weak self] in self?.confirmReset() }
        let restore = QuietButton(title: "Restore output now")
        actions.bind(restore) { [weak self] in self?.controller.restoreNow() }
        let clearHistory = QuietButton(title: "Clear activity")
        actions.bind(clearHistory) { [weak self] in
            self?.controller.clearHistory()
            self?.refresh()
        }

        let stack = Stack(axis: .vertical, spacing: 14, views: [
            Style.title("Settings"),
            CardView.wrap(Stack(axis: .vertical, spacing: 8, views: [enabled, launch, launchNote, loginItems, background, restoreOnSleep, advanced, history, motion, menuBarTemperature])),
            CardView.wrap(Stack(axis: .vertical, spacing: 8, views: [
                Style.label("Appearance", font: .systemFont(ofSize: 13, weight: .medium)),
                appearancePopup,
                transitionLabel,
                Style.caption("Applies to wake, wind-down, bedtime, and custom times on both weekday and weekend schedules. You can still refine a single time on Schedule."),
                transition
            ])),
            CardView.wrap(Stack(axis: .vertical, spacing: 6, views: [
                Style.label("Privacy", font: .systemFont(ofSize: 13, weight: .medium)),
                Style.caption(Brand.privacy)
            ])),
            CardView.wrap(Stack(axis: .vertical, spacing: 6, views: [
                Style.label("Recent activity", font: .systemFont(ofSize: 13, weight: .medium)),
                historyList,
                clearHistory
            ])),
            CardView.wrap(Stack(axis: .vertical, spacing: 6, views: [
                Style.label("Diagnostics", font: .systemFont(ofSize: 13, weight: .medium)),
                diagnostics
            ])),
            Stack(axis: .horizontal, spacing: 8, views: [export, imported, reset, restore])
        ])
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 22, bottom: 24, right: 22)
        stack.pinToEdges(of: self)
    }

    @objc private func toggleEnabled() { controller.setDisabled(enabled.state == .off) }
    @objc private func toggleLaunch() { controller.setLaunchAtLogin(launch.state == .on) }
    @objc private func toggleBackground() {
        controller.settings.keepRunningInBackground = background.state == .on
        controller.persist()
    }
    @objc private func toggleAdvanced() {
        controller.settings.useAdvancedTemperatureRange = advanced.state == .on
        for index in controller.settings.displays.indices {
            controller.settings.displays[index].limits.allowAdvancedRange = advanced.state == .on
            controller.settings.displays[index].limits.temperatureRange = DisplayLimits.range(advanced: advanced.state == .on)
        }
        controller.evaluateAndApply()
    }
    @objc private func toggleHistory() {
        controller.settings.historyEnabled = history.state == .on
        controller.reloadHistory()
        controller.persist()
        refresh()
    }
    @objc private func toggleMotion() {
        controller.settings.reduceMotion = motion.state == .on
        controller.persist()
        controller.evaluateAndApply()
    }
    @objc private func toggleMenuBarTemperature() {
        controller.settings.showMenuBarTemperature = menuBarTemperature.state == .on
        controller.persist()
        controller.objectWillChange.send()
    }
    @objc private func toggleRestoreOnSleep() {
        controller.settings.restoreOnSleep = restoreOnSleep.state == .on
        controller.persist()
    }
    @objc private func appearanceChanged() {
        controller.setAppearance(AppearancePreference.allCases[appearancePopup.indexOfSelectedItem])
    }
    @objc private func transitionChanged() {
        controller.setDefaultTransitionMinutes(Int(transition.intValue))
        refresh()
    }

    private func confirmReset() {
        SettingsAlerts.confirmReset(over: window) { [weak self] confirmed in
            guard confirmed, let self else { return }
            self.controller.resetSettings()
            self.refresh()
        }
    }

    private func exportSettings() {
        guard let data = controller.exportSettings() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Daylight-settings.json"
        FilePanels.present(panel, over: window) { [weak self] url in
            self?.controller.writeExportedSettings(data, to: url)
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        FilePanels.present(panel, over: window) { [weak self] url in
            SettingsAlerts.confirmImport(over: self?.window) { confirmed in
                guard confirmed else { return }
                self?.controller.importSettings(from: url)
                self?.refresh()
            }
        }
    }
}

@MainActor
func scheduleTimelineCaption(controller: AppController, schedule: DailySchedule) -> String {
    if controller.livePreview != nil {
        return "The playhead is sweeping the saved schedule. Stop the preview to add or move times."
    }
    if controller.editingWeekendSchedule {
        return "The timeline is showing a weekend day so these times match the schedule you are editing. Double-click to add a time."
    }
    if controller.selectedTab == .schedule, controller.settings.useWeekendSchedule, DayKind.kind(for: Date()) == .weekend {
        return "The timeline is showing a weekday so these times match the weekday schedule you are editing. Double-click to add a time."
    }
    switch schedule.approach {
    case .solar:
        return "Times follow sunrise and sunset. Warmth sliders still set day and evening. Double-click to add a clock time."
    case .custom:
        return "This custom schedule uses the times you add. Double-click the timeline to place one."
    case .hybrid:
        return "Solar times yield when they land near a clock time. Drag a clock time to move it. Double-click to add one."
    case .personal:
        return "Drag a clock time to move it. Double-click to add a time. Hold Shift for one-minute precision."
    }
}

@MainActor
func configureTimeline(_ timeline: TimelineCanvas, controller: AppController) {
    let canvas = controller.timelineCanvasDate
    let evaluation = controller.currentScheduleEvaluation(at: canvas)
    timeline.now = canvas
    if controller.livePreview != nil {
        timeline.playheadTitle = "Preview"
    } else if controller.editingWeekendSchedule, DayKind.kind(for: Date(), calendar: .current) == .weekday {
        timeline.playheadTitle = "Weekend"
    } else if controller.selectedTab == .schedule, !controller.editingWeekendSchedule, controller.settings.useWeekendSchedule, DayKind.kind(for: Date()) == .weekend {
        timeline.playheadTitle = "Weekday"
    } else {
        timeline.playheadTitle = "Now"
    }
    timeline.reduceMotion = controller.reduceMotionActive
    timeline.solar = evaluation.solar
    timeline.anchors = evaluation.resolvedAnchors.filter {
        Calendar.current.isDate($0.date, inSameDayAs: canvas) && $0.suppressedReason == nil
    }
    timeline.samples = controller.cachedTimelineSamples()
    timeline.editingEnabled = controller.livePreview == nil
    timeline.alphaValue = controller.livePreview == nil ? 1 : 0.86
    timeline.minKelvin = controller.settings.temperatureRange.lowerBound
    timeline.maxKelvin = controller.settings.temperatureRange.upperBound
    timeline.onLiveMove = { anchor, minutes in
        controller.moveAnchor(id: anchor.id, toMinutes: minutes, recordUndo: false, persistChanges: false)
    }
    timeline.onCommitMove = { anchor, minutes in
        controller.moveAnchor(id: anchor.id, toMinutes: minutes, recordUndo: true)
    }
    timeline.onCancelMove = { anchor, minutes in
        controller.moveAnchor(id: anchor.id, toMinutes: minutes, recordUndo: false)
    }
    timeline.onDragSettled = {
        controller.persist()
    }
    timeline.onAddAt = { minutes in
        controller.addCustomAnchor(at: minutes)
    }
    timeline.needsDisplay = true
}

@MainActor
final class NameDelegate: NSObject, NSTextFieldDelegate {
    let onEnd: (String) -> Void
    init(onEnd: @escaping (String) -> Void) { self.onEnd = onEnd }
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        onEnd(field.stringValue)
    }
}

@MainActor
final class OffsetProxy: NSObject {
    let onChange: (Double) -> Void
    init(onChange: @escaping (Double) -> Void) { self.onChange = onChange }
    @objc func changed(_ sender: NSSlider) { onChange(sender.doubleValue) }
}

@MainActor
final class ClickProxy: NSObject, NSGestureRecognizerDelegate {
    let onClick: () -> Void
    weak var card: NSView?

    init(onClick: @escaping () -> Void) { self.onClick = onClick }

    @objc func run() { onClick() }

    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldAttemptToRecognizeWith event: NSEvent) -> Bool {
        guard let card else { return true }
        let point = card.convert(event.locationInWindow, from: nil)
        var view = card.hitTest(point)
        while let current = view, current !== card {
            if current is NSControl || current is NSTextView {
                return false
            }
            view = current.superview
        }
        return true
    }
}

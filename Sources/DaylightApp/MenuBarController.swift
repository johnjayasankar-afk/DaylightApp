import AppKit
import DaylightCore

@MainActor
final class MenuBarController: NSViewController {
    private let controller: AppController
    private weak var app: AppDelegate?
    private let actions = ActionMap()

    private let wash = WarmthWashView()
    private let headline = Style.label("", font: .systemFont(ofSize: 15, weight: .semibold))
    private let explanation = Style.caption("")
    private let nextChange = Style.caption("")
    private let kelvin = Style.mono("", size: 12)
    private let clock = Style.mono("", size: 11)
    private let period = PeriodBadge()
    private let warmth = GradientSlider()
    private let brightness = GradientSlider()
    private let dimming = GradientSlider()
    private let brightnessSection = Stack(axis: .vertical, spacing: 3)
    private let dimmingSection = Stack(axis: .vertical, spacing: 3)
    private let notice = Style.caption("")
    private let displayPopup = NSPopUpButton()
    private let duration = NSSegmentedControl(labels: OverrideDuration.menuCases.map(\.shortTitle), trackingMode: .selectOne, target: nil, action: nil)
    private let scope = NSButton(checkboxWithTitle: "Only the selected display", target: nil, action: nil)
    private let pause = QuietButton(title: "Pause 30m")
    private let resume = QuietButton(title: "Resume")
    private let restore = QuietButton(title: "Restore")
    private let preview = QuietButton(title: "Preview")
    private let live = QuietButton(title: "Live")
    private let stop = QuietButton(title: "Stop")
    private let previewLockNote = Style.caption("Stop the preview to change lighting.")
    private var modePills: [LightingMode: PillButton] = [:]
    private var contentStack: NSStackView?
    private var lastDisplayTitles: [String] = []
    private var built = false

    init(controller: AppController, app: AppDelegate) {
        self.controller = controller
        self.app = app
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 348, height: 520))
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .followsWindowActiveState
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        view = effect

        wash.translatesAutoresizingMaskIntoConstraints = false
        wash.heightAnchor.constraint(equalToConstant: 108).isActive = true
        wash.wantsLayer = true
        wash.layer?.cornerRadius = 12
        wash.layer?.cornerCurve = .continuous

        warmth.track = .warmth
        warmth.minValue = controller.settings.temperatureRange.lowerBound
        warmth.maxValue = controller.settings.temperatureRange.upperBound
        warmth.onChange = { [weak self] value in
            self?.kelvin.stringValue = ColorTemperature(kelvin: value).roundedLabel
            self?.controller.applySlider(temperature: value)
        }
        warmth.onCommit = { [weak self] value in self?.controller.finishSlider(temperature: value) }
        warmth.onCancel = { [weak self] _ in self?.controller.abandonSlider() }
        warmth.setAccessibilityLabel("Warmth")

        brightness.track = .brightness
        brightness.minValue = 0.12
        brightness.maxValue = 1
        brightness.onChange = { [weak self] value in
            self?.controller.applySlider(brightness: value)
        }
        brightness.onCommit = { [weak self] value in self?.controller.finishSlider(brightness: value) }
        brightness.onCancel = { [weak self] _ in self?.controller.abandonSlider() }
        brightness.setAccessibilityLabel("Hardware brightness")

        dimming.track = .dimming
        dimming.minValue = SoftwareDimming.readableRange.lowerBound
        dimming.maxValue = SoftwareDimming.readableRange.upperBound
        dimming.onChange = { [weak self] value in
            self?.controller.applySlider(dimming: value)
        }
        dimming.onCommit = { [weak self] value in self?.controller.finishSlider(dimming: value) }
        dimming.onCancel = { [weak self] _ in self?.controller.abandonSlider() }
        dimming.setAccessibilityLabel("Software dimming")

        duration.selectedSegment = 1
        duration.target = self
        duration.action = #selector(durationChanged)
        duration.setAccessibilityLabel("Keep slider changes")
        duration.segmentDistribution = .fillEqually

        displayPopup.target = self
        displayPopup.action = #selector(displayChosen)
        displayPopup.setAccessibilityLabel("Display")

        scope.target = self
        scope.action = #selector(scopeChanged)
        scope.font = .systemFont(ofSize: 11.5)

        actions.bind(pause) { [weak self] in self?.controller.pause(duration: .minutes(30)) }
        actions.bind(resume) { [weak self] in self?.controller.resume() }
        actions.bind(restore) { [weak self] in self?.controller.restoreNow() }
        actions.bind(preview) { [weak self] in self?.controller.previewDay(applyToHardware: false) }
        actions.bind(live) { [weak self] in self?.controller.previewDay(applyToHardware: true) }
        actions.bind(stop) { [weak self] in self?.controller.cancelPreview(applyCleanup: true) }
        let copy = QuietButton(title: "Copy status")
        actions.bind(copy) { [weak self] in self?.controller.copyStatus() }

        let open = QuietButton(title: "Open \(Brand.name)", prominent: true)
        let quit = QuietButton(title: "Quit")
        actions.bind(open) { [weak self] in self?.app?.showMainWindow() }
        actions.bind(quit) { NSApp.terminate(nil) }

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

        explanation.maximumNumberOfLines = 3
        nextChange.maximumNumberOfLines = 2
        headline.maximumNumberOfLines = 2
        notice.maximumNumberOfLines = 2
        let header = Stack(axis: .vertical, spacing: 4, views: [
            Stack(axis: .horizontal, spacing: 0, views: [period, NSView(), clock]),
            headline,
            explanation,
            nextChange
        ])
        header.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        header.pinToEdges(of: wash)

        brightnessSection.addArrangedSubview(labeled("Brightness", brightness, Style.caption("Hardware backlight when available")))
        dimmingSection.addArrangedSubview(labeled("Dimming", dimming, Style.caption("Software dimming darkens the image. It is not backlight control.")))

        let stack = Stack(axis: .vertical, spacing: 9, views: [
            wash,
            displayPopup,
            notice,
            previewLockNote,
            labeled("Warmth", warmth, kelvin),
            brightnessSection,
            dimmingSection,
            Style.caption("Keep slider changes"),
            duration,
            scope,
            primary,
            secondary,
            tertiary,
            Stack(axis: .horizontal, spacing: 8, views: [pause, resume, restore]),
            Stack(axis: .horizontal, spacing: 8, views: [preview, live, stop]),
            Style.hairline(),
            Stack(axis: .horizontal, spacing: 8, views: [open, copy, quit])
        ])
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 14, right: 14)
        let document = FlippedView()
        stack.pinToEdges(of: document)
        document.translatesAutoresizingMaskIntoConstraints = false
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.documentView = document
        NSLayoutConstraint.activate([
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            document.bottomAnchor.constraint(equalTo: stack.bottomAnchor)
        ])
        scroll.pinToEdges(of: effect)
        contentStack = stack
        built = true
        refresh()
    }

    func refresh() {
        guard built else { return }
        headline.stringValue = controller.presentedHeadline
        explanation.stringValue = controller.snapshot?.explanation ?? Brand.tagline
        nextChange.stringValue = controller.liveNextChangeLine
        wash.kelvin = controller.presentedKelvin
        wash.restored = controller.chromeKelvin == nil
        period.set(
            title: controller.presentedModeTitle,
            kelvin: controller.chromeKelvin
        )
        clock.stringValue = ClockFormat.shortTime(controller.evaluationDate)
        notice.stringValue = controller.selectedAdjustment.message ?? ""
        notice.isHidden = notice.stringValue.isEmpty
        previewLockNote.isHidden = controller.livePreview == nil

        wash.reduceMotion = controller.reduceMotionActive
        let tracking = warmth.isTracking || brightness.isTracking || dimming.isTracking
        if !tracking {
            if let output = controller.selectedOutput {
                warmth.minValue = controller.settings.temperatureRange.lowerBound
                warmth.maxValue = controller.settings.temperatureRange.upperBound
                warmth.doubleValueSafe = output.temperature.kelvin
                kelvin.stringValue = output.temperature.roundedLabel
                brightness.doubleValueSafe = output.hardwareBrightness?.fraction ?? 0.8
                dimming.doubleValueSafe = output.softwareDimming.factor
            } else {
                warmth.minValue = controller.settings.temperatureRange.lowerBound
                warmth.maxValue = controller.settings.temperatureRange.upperBound
                warmth.doubleValueSafe = ColorTemperature.daylightReference.kelvin
                kelvin.stringValue = controller.presentedKelvinLabel
                brightness.doubleValueSafe = 0.8
                dimming.doubleValueSafe = SoftwareDimming.none.factor
            }
        }

        displayPopup.isHidden = controller.displays.count < 2
        let titles = controller.displays.map { controller.displayMenuTitle($0) }
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
        brightnessSection.isHidden = !hasHardware
        dimmingSection.isHidden = false

        scope.title = controller.isSelectedDisplayLinked ? "Only this linked group" : "Only the selected display"
        scope.state = controller.sliderAffectsAllDisplays ? .off : .on
        scope.isHidden = controller.displays.count < 2
        let paused = controller.isPausedNow
        refreshHoldChrome()
        pause.isHidden = paused
        let previewing = controller.livePreview != nil
        let modesEnabled = !controller.settings.disabled && !previewing
        pause.isEnabled = !paused && modesEnabled
        resume.isHidden = previewing || (!paused && controller.activeOverride == nil)
        resume.isEnabled = !previewing && (paused || controller.activeOverride != nil)
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
        if let index = OverrideDuration.menuCases.firstIndex(of: controller.sliderDuration) {
            duration.selectedSegment = index
        }

        let active = controller.activeOverride?.mode ?? .automatic
        if paused || controller.settings.disabled || previewing {
            modePills.forEach {
                $0.value.active = false
                $0.value.isEnabled = $0.key == .automatic && !controller.settings.disabled && !previewing
            }
        } else if controller.activeOverride?.isManualAdjustment == true {
            modePills.forEach {
                $0.value.isEnabled = true
                $0.value.active = false
            }
        } else {
            for (mode, pill) in modePills {
                pill.isEnabled = true
                pill.active = mode == (controller.activeOverride == nil ? .automatic : active)
            }
        }

        preferredContentSize = fittedSize()
    }

    func refreshClock() {
        clock.stringValue = ClockFormat.shortTime(controller.evaluationDate)
        if controller.livePreview == nil {
            nextChange.stringValue = StatusExplainer.nextChangeLine(
                wake: controller.decision?.nextWake,
                automation: controller.decision?.automation ?? controller.snapshot?.automation ?? .automatic,
                at: controller.evaluationDate
            )
        }
        refreshHoldChrome()
        if !isTracking {
            preferredContentSize = fittedSize()
        }
    }

    private func refreshHoldChrome() {
        let paused = controller.isPausedNow
        if paused, let remaining = controller.settings.pause.expiresAt?.timeIntervalSinceNow, remaining > 0 {
            pause.title = "Paused · \(RulesEngine.compact(remaining))"
        } else {
            pause.title = paused ? "Paused" : "Pause 30m"
        }
        resume.title = ActionTitles.resume(
            paused: paused,
            pauseEndsAt: controller.settings.pause.expiresAt,
            holding: controller.activeOverride != nil,
            holdEndsAt: controller.activeOverride?.expiresAt
        )
    }

    var isTracking: Bool {
        warmth.isTracking || brightness.isTracking || dimming.isTracking
    }

    func cancelSliderTracking() {
        warmth.cancelTracking(revert: true)
        brightness.cancelTracking(revert: true)
        dimming.cancelTracking(revert: true)
    }

    func fittedSize() -> NSSize {
        view.layoutSubtreeIfNeeded()
        let height = ceil((contentStack?.fittingSize.height ?? view.fittingSize.height))
        return NSSize(width: 348, height: min(max(height, 300), 720))
    }

    private func labeled(_ title: String, _ control: NSView, _ trailing: NSView) -> NSView {
        let header = Stack(axis: .horizontal, spacing: 8, views: [
            Style.label(title, font: .systemFont(ofSize: 12, weight: .medium)),
            NSView(),
            trailing
        ])
        return Stack(axis: .vertical, spacing: 3, views: [header, control])
    }

    @objc private func durationChanged() {
        let cases = OverrideDuration.menuCases
        let index = duration.selectedSegment
        if cases.indices.contains(index) {
            controller.setSliderDuration(cases[index])
        }
    }

    @objc private func displayChosen() {
        let index = displayPopup.indexOfSelectedItem
        if controller.displays.indices.contains(index) {
            controller.selectDisplay(id: controller.displays[index].id)
        }
        refresh()
    }

    @objc private func scopeChanged() {
        controller.setSliderAffectsAllDisplays(scope.state == .off)
    }
}

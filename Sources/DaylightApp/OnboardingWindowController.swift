import AppKit
import Combine
import DaylightCore

@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate, NSComboBoxDelegate {
    private let controller: AppController
    private let actions = ActionMap()
    private let stepActions = ActionMap()
    private var step = 0
    private let titleLabel = Style.label(Brand.name, font: .systemFont(ofSize: 28, weight: .semibold))
    private let body = Style.label("", font: .systemFont(ofSize: 14))
    private let extra = NSView()
    private let dots = StepDots()
    private let back = QuietButton(title: "Back")
    private let next = QuietButton(title: "Continue", prominent: true)
    private var approachSummary = Style.caption("")
    private let cityNote = Style.caption("")
    private var previewing = false
    private var finishing = false
    private var keyMonitor: Any?
    private var cancellable: AnyCancellable?
    private let wash = WarmthWashView()
    private let sunMark = SunMarkView()
    var onFinish: (() -> Void)?

    init(controller: AppController) {
        self.controller = controller
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to \(Brand.name)"
        window.titlebarAppearsTransparent = true
        window.center()
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        super.init(window: window)
        window.delegate = self
        window.contentView = build()
        installKeyMonitor()
        cancellable = controller.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.syncPreviewChrome() }
        }
        render()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        finish(closeWindow: false)
        return true
    }

    private func build() -> NSView {
        titleLabel.textColor = Style.accent
        next.keyEquivalent = "\r"
        actions.bind(back) { [weak self] in self?.goBack() }
        actions.bind(next) { [weak self] in self?.advance() }

        wash.translatesAutoresizingMaskIntoConstraints = false
        wash.heightAnchor.constraint(equalToConstant: 118).isActive = true
        wash.wantsLayer = true
        wash.layer?.cornerRadius = Style.cardRadius
        wash.layer?.cornerCurve = .continuous
        sunMark.translatesAutoresizingMaskIntoConstraints = false
        sunMark.heightAnchor.constraint(equalToConstant: 96).isActive = true
        wash.addSubview(sunMark)
        NSLayoutConstraint.activate([
            sunMark.centerXAnchor.constraint(equalTo: wash.centerXAnchor),
            sunMark.centerYAnchor.constraint(equalTo: wash.centerYAnchor),
            sunMark.widthAnchor.constraint(equalTo: wash.widthAnchor, constant: -32)
        ])

        extra.translatesAutoresizingMaskIntoConstraints = false
        extra.heightAnchor.constraint(greaterThanOrEqualToConstant: 168).isActive = true
        dots.translatesAutoresizingMaskIntoConstraints = false
        dots.heightAnchor.constraint(equalToConstant: 12).isActive = true
        dots.count = 6

        let skip = QuietButton(title: "Skip setup")
        actions.bind(skip) { [weak self] in self?.finish() }

        let stack = Stack(axis: .vertical, spacing: 14, views: [
            wash,
            titleLabel,
            body,
            extra,
            dots,
            Stack(axis: .horizontal, spacing: 8, views: [back, skip, NSView(), next])
        ])
        stack.edgeInsets = NSEdgeInsets(top: 36, left: 32, bottom: 24, right: 32)
        let effect = NSVisualEffectView()
        effect.material = .underWindowBackground
        effect.blendingMode = .behindWindow
        effect.state = .followsWindowActiveState
        stack.pinToEdges(of: effect)
        return effect
    }

    private func render() {
        stepActions.removeAll()
        extra.subviews.forEach { $0.removeFromSuperview() }
        dots.index = step
        back.isHidden = step == 0
        next.title = step == 5 ? "Start using \(Brand.name)" : "Continue"
        previewing = controller.livePreview != nil
        wash.kelvin = controller.presentedKelvin
        wash.restored = controller.chromeKelvin == nil
        sunMark.kelvin = controller.presentedKelvin
        wash.reduceMotion = controller.reduceMotionActive
        titleLabel.textColor = controller.chromeKelvin.map { Style.temperature(kelvin: $0) } ?? Style.accent
        switch step {
        case 0:
            titleLabel.stringValue = Brand.name
            body.stringValue = "\(Brand.tagline)\n\n\(Brand.about)"
        case 1:
            titleLabel.stringValue = "These displays"
            body.stringValue = "Available controls are listed honestly. Nothing is claimed that this Mac cannot do."
            let cards = controller.displays.isEmpty
                ? [Style.caption("No displays are visible to this process yet.")]
                : controller.displays.map { display in
                    CardView.wrap(Style.label("\(self.controller.displayMenuTitle(display)) — \(display.capabilities.warmth.label); \(display.capabilities.brightness.label)", font: .systemFont(ofSize: 13)), padding: 10)
                }
            pin(Stack(axis: .vertical, spacing: 8, views: cards), to: extra)
        case 2:
            titleLabel.stringValue = "A starting schedule"
            body.stringValue = "Choose how Daylight should follow your day. You can change this later."
            let popup = NSPopUpButton()
            popup.addItems(withTitles: ScheduleApproach.allCases.map(\.title))
            if let index = ScheduleApproach.allCases.firstIndex(of: controller.settings.weekdaySchedule.approach) {
                popup.selectItem(at: index)
            }
            popup.target = self
            popup.action = #selector(approachChanged)
            approachSummary.stringValue = controller.settings.weekdaySchedule.approach.summary
            let city = NSComboBox()
            city.addItems(withObjectValues: Cities.featured.map(\.name))
            city.completes = true
            city.placeholderString = "Optional city for sunrise and sunset"
            city.stringValue = controller.settings.location?.name ?? ""
            city.delegate = self
            city.target = self
            city.action = #selector(cityChosen)
            pin(Stack(axis: .vertical, spacing: 8, views: [
                popup,
                approachSummary,
                Style.caption("Location is optional and typed locally. No permission is requested."),
                city,
                cityNote
            ]), to: extra)
            refreshCityNote(city.stringValue)
        case 3:
            if controller.settings.weekdaySchedule.approach == .solar || controller.settings.weekdaySchedule.approach == .custom {
                titleLabel.stringValue = controller.settings.weekdaySchedule.approach == .custom ? "Custom times" : "Solar times"
                body.stringValue = controller.settings.weekdaySchedule.approach == .custom
                    ? "A custom schedule uses only the times you add. Add them on Schedule after setup."
                    : "Sunrise and sunset set when warmth changes. The next step chooses how day and evening look."
                pin(Style.caption(controller.settings.weekdaySchedule.approach == .custom
                    ? "Wake and bedtime clocks stay unused until you switch back to Personal."
                    : "Wake and bedtime clocks are unused on a solar schedule. You can add clock times later on Schedule."), to: extra)
            } else {
                titleLabel.stringValue = "Wake and bedtime"
                body.stringValue = "These are routine preferences, not medical advice."
                let wakeTime = clock(controller.settings.weekdaySchedule.personalAnchors.first { $0.kind == .wake })
                let bedTime = clock(controller.settings.weekdaySchedule.personalAnchors.first { $0.kind == .bedtime })
                let wake = Style.timePicker(time: wakeTime, tag: 0, target: self, action: #selector(timeChanged))
                let bed = Style.timePicker(time: bedTime, tag: 1, target: self, action: #selector(timeChanged))
                pin(Stack(axis: .vertical, spacing: 10, views: [
                    Stack(axis: .horizontal, spacing: 10, views: [Style.label("Wake", font: .systemFont(ofSize: 13, weight: .medium)), wake]),
                    Stack(axis: .horizontal, spacing: 10, views: [Style.label("Bedtime", font: .systemFont(ofSize: 13, weight: .medium)), bed])
                ]), to: extra)
            }
        case 4:
            titleLabel.stringValue = "Starting comfort"
            body.stringValue = "These are starting points, not medical recommendations."
            let row = Stack(axis: .horizontal, spacing: 8)
            for preset in ComfortPreset.all {
                let button = PillButton(title: preset.name)
                button.active = controller.settings.selectedPresetID == preset.id
                stepActions.bind(button) { [weak self] in
                    self?.controller.applyPreset(preset)
                    self?.render()
                }
                row.addArrangedSubview(button)
            }
            pin(row, to: extra)
        default:
            titleLabel.stringValue = "A brief preview"
            body.stringValue = "The interface preview does not change the display. A live preview is optional and always restores afterward."
            let preview = QuietButton(title: previewing && controller.livePreview?.applyingToHardware != true ? "Stop preview" : "Preview in the interface")
            let liveTitle = controller.livePreview?.applyingToHardware == true ? "Stop live preview" : "Try on this display"
            let live = QuietButton(title: liveTitle)
            stepActions.bind(preview) { [weak self] in self?.togglePreview(hardware: false) }
            stepActions.bind(live) { [weak self] in self?.togglePreview(hardware: true) }
            pin(Stack(axis: .horizontal, spacing: 8, views: [preview, live]), to: extra)
        }
    }

    private func clock(_ anchor: ScheduleAnchor?) -> TimeOfDay {
        if case .clock(let time) = anchor?.timing { return time }
        return TimeOfDay(hour: 7, minute: 0)
    }

    private func pin(_ view: NSView, to parent: NSView) {
        view.pinToEdges(of: parent)
    }

    private func goBack() {
        if step == 5, controller.livePreview != nil {
            controller.cancelPreview(applyCleanup: true)
        }
        if step > 0 { step -= 1 }
        render()
    }

    private func advance() {
        if step < 5 {
            step += 1
            render()
            return
        }
        finish()
    }

    private func finish(closeWindow: Bool = true) {
        guard !finishing else { return }
        finishing = true
        cancellable?.cancel()
        cancellable = nil
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if controller.livePreview != nil {
            controller.cancelPreview(applyCleanup: true)
        }
        controller.finishOnboarding()
        onFinish?()
        if closeWindow {
            window?.close()
        }
    }

    private func syncPreviewChrome() {
        guard step == 5, !finishing else { return }
        let nowPreviewing = controller.livePreview != nil
        if nowPreviewing != previewing {
            previewing = nowPreviewing
            render()
            return
        }
        guard nowPreviewing else { return }
        wash.kelvin = controller.presentedKelvin
        wash.restored = controller.chromeKelvin == nil
        sunMark.kelvin = controller.presentedKelvin
        titleLabel.textColor = controller.chromeKelvin.map { Style.temperature(kelvin: $0) } ?? Style.accent
    }

    private func togglePreview(hardware: Bool) {
        if controller.livePreview != nil {
            controller.cancelPreview(applyCleanup: true)
        } else {
            controller.previewDay(applyToHardware: hardware)
        }
        previewing = controller.livePreview != nil
        render()
    }

    @objc private func approachChanged(_ sender: NSPopUpButton) {
        let cases = ScheduleApproach.allCases
        let index = sender.indexOfSelectedItem
        guard cases.indices.contains(index) else { return }
        let value = cases[index]
        controller.setApproach(value, recordUndo: false)
        approachSummary.stringValue = value.summary
    }

    @objc private func cityChosen(_ sender: NSComboBox) {
        applyCity(Style.comboSelection(sender), field: sender)
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true else { return event }
            if KeyFocus.isEditing(self.window?.firstResponder)
                || self.window?.firstResponder is NSPopUpButton
                || self.window?.firstResponder is NSSlider {
                return event
            }
            switch event.keyCode {
            case 53:
                self.finish()
                return nil
            case 123:
                self.goBack()
                return nil
            case 124:
                self.advance()
                return nil
            default:
                return event
            }
        }
    }

    func comboBoxSelectionDidChange(_ notification: Notification) {
        guard let box = notification.object as? NSComboBox else { return }
        applyCity(Style.comboSelection(box), field: box)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let box = obj.object as? NSComboBox else { return }
        applyCity(box.stringValue, field: box)
    }

    private func applyCity(_ query: String, field: NSComboBox? = nil) {
        refreshCityNote(query)
        switch Cities.status(for: query) {
        case .empty:
            controller.setLocation(nil)
        case .matched(let match):
            controller.setLocation(match)
        case .unrecognized:
            let kept = controller.settings.location?.name ?? ""
            field?.stringValue = kept
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

    @objc private func timeChanged(_ sender: NSDatePicker) {
        let time = Style.time(from: sender)
        let kind: AnchorKind = sender.tag == 0 ? .wake : .bedtime
        if let index = controller.settings.weekdaySchedule.personalAnchors.firstIndex(where: { $0.kind == kind }) {
            controller.settings.weekdaySchedule.personalAnchors[index].timing = .clock(time)
        }
        if let index = controller.settings.weekendSchedule.personalAnchors.firstIndex(where: { $0.kind == kind }) {
            controller.settings.weekendSchedule.personalAnchors[index].timing = .clock(time)
        }
        controller.evaluateAndApply()
        controller.persist()
    }
}

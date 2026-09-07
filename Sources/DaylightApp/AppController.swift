import AppKit
import Combine
import DaylightCore
import DaylightMac
import Foundation
import ServiceManagement

enum MainTab: String, CaseIterable, Identifiable {
    case today
    case schedule
    case displays
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .schedule: return "Schedule"
        case .displays: return "Displays"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .today: return "sun.horizon"
        case .schedule: return "calendar"
        case .displays: return "display.2"
        case .settings: return "gearshape"
        }
    }

    var tooltip: String {
        switch self {
        case .today: return "What the lighting is doing now"
        case .schedule: return "Wake, wind-down, and solar times"
        case .displays: return "Names, linking, and exclusions"
        case .settings: return "Launch, appearance, and restore"
        }
    }
}

struct LivePreviewState: Equatable {
    var applyingToHardware: Bool
    var startedAt: Date
    var endsAt: Date
    var playhead: Date
    var startOfDay: Date
}

struct ScheduleSnapshot: Equatable {
    var weekday: DailySchedule
    var weekend: DailySchedule
}

@MainActor
final class AppController: ObservableObject {
    @Published var settings: AppSettings
    @Published var displays: [ConnectedDisplay] = []
    @Published var decision: ControllerDecision?
    @Published var snapshot: StatusSnapshot?
    @Published var selectedTab: MainTab = .today
    @Published var selectedDisplayID: String?
    @Published var previewClock: Date?
    @Published var livePreview: LivePreviewState?
    @Published var simulationMode = false
    @Published var lastNotes: [String] = []
    @Published var environment = PlatformEnvironment.current
    @Published var undoStack: [ScheduleSnapshot] = []
    @Published var redoStack: [ScheduleSnapshot] = []
    @Published var sliderDuration: OverrideDuration = .minutes(30)
    @Published var sliderAffectsAllDisplays = true
    @Published var pendingExtreme: DesiredOutput?
    @Published var history: [HistoryEvent] = []
    @Published var editingWeekendSchedule = false

    var onNeedsConfirmation: (() -> Void)?

    let adapter: MacDisplayAdapter
    let store: SettingsStore
    let scheduleEngine = ScheduleEngine()
    let rulesEngine = RulesEngine()
    var transitionEngine: TransitionEngine
    let explainer = StatusExplainer()
    let lifecycle = DisplayLifecycleMonitor()

    private var tickTimer: Timer?
    private var lastWrites: [String: Date] = [:]
    private var lastApplied: [String: DesiredOutput] = [:]
    private var sliderDebounce: Timer?
    private var persistDebounce: Timer?
    private var offsetUndoArmed = false
    private var offsetSettle: Timer?
    private var lifecycleSettle: Timer?
    private var pendingLifecycleReason: String?
    private var pendingDisplayRefresh = false
    private var emergencyMonitor: Any?
    private var sampleCacheKey = 0
    private var sampleCache: [TimelineSample] = []
    private var lastSampleBuild = Date.distantPast
    private var didStart = false
    private var didPrepareToQuit = false
    private var baselineRestored = false
    private var lastSavedSettings: AppSettings?
    private var launchWarning: String?
    private var offsetDebounce: Timer?
    private var sliderSessionActive = false
    private var overrideBeforeSlider: TemporaryOverride?

    init(store: SettingsStore? = nil, adapter: MacDisplayAdapter = MacDisplayAdapter()) {
        let resolvedStore: SettingsStore
        var supportWarning: String?
        if let store {
            resolvedStore = store
        } else if let directory = try? SettingsStore.applicationSupportDirectory() {
            resolvedStore = SettingsStore(directory: directory)
        } else {
            resolvedStore = SettingsStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("Daylight"))
            supportWarning = "Daylight could not use Application Support, so settings are temporary for this session."
        }
        self.store = resolvedStore
        self.adapter = adapter
        let recovered = resolvedStore.recoverIfNeeded()
        self.settings = recovered.settings
        self.lastSavedSettings = recovered.warning == nil ? recovered.settings : nil
        self.launchWarning = recovered.warning ?? supportWarning
        if let warning = launchWarning {
            self.lastNotes = [warning]
        }
        self.selectedTab = MainTab(rawValue: recovered.settings.lastSelectedTab ?? "") ?? .today
        self.selectedDisplayID = recovered.settings.lastSelectedDisplayID
        self.sliderDuration = recovered.settings.sliderDuration
        self.sliderAffectsAllDisplays = recovered.settings.sliderAffectsAllDisplays
        if recovered.settings.historyEnabled {
            self.history = resolvedStore.loadHistory()
        }
        self.transitionEngine = TransitionEngine(
            minimumWriteInterval: TimeInterval(recovered.settings.writeIntervalMilliseconds) / 1000,
            temperatureThreshold: recovered.settings.temperatureWriteThreshold
        )
        self.editingWeekendSchedule = recovered.settings.resolvedEditingWeekend()
    }

    func start() {
        didStart = true
        applyAppearance()
        refreshDisplays(initial: true)
        recoverFromPreviousRun()
        lifecycle.start()
        lifecycle.onDisplaysChanged = { [weak self] in
            Task { @MainActor in self?.coalesceLifecycle(reason: "Displays changed", refreshDisplays: true) }
        }
        lifecycle.onWake = { [weak self] in
            Task { @MainActor in self?.coalesceLifecycle(reason: "The computer woke.", refreshDisplays: true) }
        }
        lifecycle.onSleep = { [weak self] in
            Task { @MainActor in self?.prepareForSleep() }
        }
        lifecycle.onClockChanged = { [weak self] in
            Task { @MainActor in self?.coalesceLifecycle(reason: "The clock or time zone changed.", refreshDisplays: false) }
        }
        lifecycle.onUnlock = { [weak self] in
            Task { @MainActor in self?.coalesceLifecycle(reason: "The screen unlocked.", refreshDisplays: true) }
        }
        lifecycle.onAccessibilityChanged = { [weak self] in
            Task { @MainActor in self?.coalesceLifecycle(reason: "Accessibility display options changed.", refreshDisplays: false) }
        }
        reconcileLaunchAtLogin()
        let stickyNotes = lastNotes.filter(isStickyNote)
        evaluateAndApply(force: true, reason: "Launch")
        restoreStickyNotes(stickyNotes)
        if let launchWarning {
            rememberNote(launchWarning)
        }
        if let loginNote = launchAtLoginMessage() {
            rememberNote(loginNote)
        }
        installEmergencyMonitor()
        persist(immediate: true)
    }

    func persist(immediate: Bool = false) {
        persistDebounce?.invalidate()
        if immediate {
            writeSettings()
            return
        }
        persistDebounce = scheduleTimer(after: 0.4) { [weak self] in
            self?.writeSettings()
        }
    }

    private func writeSettings() {
        if lastSavedSettings != settings {
            do {
                try store.save(settings)
                lastSavedSettings = settings
            } catch {
                rememberNote("Could not save settings on this Mac. Your latest change is in memory until the next successful save.")
            }
        }
        do {
            try store.saveOwnership(adapter.ownershipRecord())
        } catch {
            rememberNote("Could not record display ownership on this Mac. Crash recovery may be less reliable until a later save succeeds.")
        }
    }

    var evaluationDate: Date {
        previewClock ?? Date()
    }

    var selectedDisplay: ConnectedDisplay? {
        displays.first { $0.id == selectedDisplayID } ?? displays.first
    }

    var selectedOutput: DesiredOutput? {
        if let display = selectedDisplay {
            return desiredOutput(for: display)
        }
        return decision?.restoreToBaseline == true ? nil : decision?.output
    }

    /// Warmth shown when the selected display is restored or has no target.
    var presentedKelvin: Double {
        chromeKelvin ?? ColorTemperature.daylightReference.kelvin
    }

    /// Kelvin for warmth chrome. Nil when Daylight is not holding a target.
    var chromeKelvin: Double? {
        selectedOutput?.temperature.kelvin
    }

    var presentedHeadline: String {
        if livePreview != nil {
            return snapshot?.headline ?? Brand.name
        }
        if let display = selectedDisplay, selectedOutput == nil || isScheduleFallback(display) {
            return targetCaption(for: display)
        }
        if let output = selectedOutput, let mode = snapshot?.modeTitle {
            return "\(mode) · \(output.temperature.roundedLabel)"
        }
        return snapshot?.headline ?? Brand.name
    }

    var presentedModeTitle: String {
        if livePreview != nil {
            return snapshot?.modeTitle ?? ""
        }
        switch selectedAdjustment {
        case .excluded: return "Excluded"
        case .idle: return "Idle"
        case .disconnected: return "Away"
        case .mirrored: return "Mirrored"
        case .paused: return "Paused"
        case .appDisabled: return "Off"
        case .previewing: return snapshot?.modeTitle ?? "Preview"
        case .ready:
            if let display = selectedDisplay, isScheduleFallback(display) {
                return "Schedule"
            }
            return snapshot?.modeTitle ?? ""
        }
    }

    var presentedKelvinLabel: String {
        if let output = selectedOutput {
            return "\(output.temperature.roundedLabel) · \(output.temperature.comfortPhrase)"
        }
        if livePreview != nil {
            return snapshot?.kelvinLabel ?? "Native output"
        }
        return "Native output"
    }

    var selectedAdjustment: DisplayAdjustment {
        let excluded = selectedDisplay.map { settings.preferences(for: $0.identity).excludedFromAutomation } ?? false
        return DisplayAdjustment.resolve(
            display: selectedDisplay,
            excluded: excluded,
            disabled: settings.disabled,
            previewing: livePreview != nil,
            paused: isPausedNow
        )
    }

    var reduceMotionActive: Bool {
        settings.reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var canAdjustSelectedDisplay: Bool {
        selectedAdjustment.allowsWrites
    }

    var activeSchedule: DailySchedule {
        editingWeekendSchedule ? settings.weekendSchedule : settings.weekdaySchedule
    }

    func refreshDisplays(initial: Bool = false) {
        if adapter.simulationMode {
            let real = adapter.probeRealDisplays()
            if !real.isEmpty {
                adapter.simulationMode = false
                simulationMode = false
            }
        }
        let previous = displays
        var found = adapter.enumerateDisplays()
        if found.isEmpty {
            if !adapter.simulationMode {
                _ = adapter.restoreAll(useColorSync: true)
                forgetAppliedState()
                rememberNote("No physical displays were available. Daylight restored native tables and switched to simulation.")
            }
            adapter.simulationMode = true
            simulationMode = true
            found = adapter.enumerateDisplays()
        } else if initial {
            simulationMode = adapter.simulationMode
        }
        let remapped = syncDisplayPreferences(found)
        restoreRemovedDisplays(previous: previous, next: found, remapped: remapped)
        displays = found
        let remembered = settings.lastSelectedDisplayID
        if selectedDisplayID == nil || !found.contains(where: { $0.id == selectedDisplayID }) {
            selectedDisplayID = remembered.flatMap { id in found.first(where: { $0.id == id })?.id }
                ?? found.first(where: { $0.isMain && $0.connection == .connected })?.id
                ?? found.first(where: { $0.connection == .connected })?.id
                ?? found.first?.id
        }
    }

    var scheduleCanvasDate: Date {
        DayKind.scheduleCanvasDate(
            editingWeekend: editingWeekendSchedule,
            useWeekendSchedule: settings.useWeekendSchedule,
            preferEditorDay: selectedTab == .schedule
        )
    }

    var timelineCanvasDate: Date {
        previewClock ?? scheduleCanvasDate
    }

    func cachedTimelineSamples() -> [TimelineSample] {
        let day = Calendar.current.startOfDay(for: timelineCanvasDate)
        var hasher = Hasher()
        hasher.combine(settings.weekdaySchedule)
        hasher.combine(settings.weekendSchedule)
        hasher.combine(settings.useWeekendSchedule)
        hasher.combine(settings.location)
        hasher.combine(editingWeekendSchedule)
        hasher.combine(Int(day.timeIntervalSince1970))
        let key = hasher.finalize()
        if key == sampleCacheKey, !sampleCache.isEmpty {
            return sampleCache
        }
        sampleCacheKey = key
        lastSampleBuild = Date()
        var weekday = settings.weekdaySchedule
        var weekend = settings.weekendSchedule
        weekday.location = settings.location ?? weekday.location
        weekend.location = settings.location ?? weekend.location
        sampleCache = scheduleEngine.samples(
            schedule: weekday,
            weekendSchedule: settings.useWeekendSchedule ? weekend : nil,
            on: day,
            stepMinutes: 10,
            context: EvaluationContext(timeZone: .current)
        )
        return sampleCache
    }

    func currentScheduleEvaluation(at date: Date = Date()) -> ScheduleEvaluation {
        var weekday = settings.weekdaySchedule
        var weekend = settings.weekendSchedule
        weekday.location = settings.location ?? weekday.location
        weekend.location = settings.location ?? weekend.location
        return scheduleEngine.evaluate(
            schedule: weekday,
            weekendSchedule: settings.useWeekendSchedule ? weekend : nil,
            at: date,
            context: EvaluationContext(timeZone: .current)
        )
    }

    func evaluate(at date: Date = Date(), emergency: Bool = false) -> ControllerDecision {
        let schedule = currentScheduleEvaluation(at: date)
        var rulesSettings = settings
        let previewing = livePreview != nil
        if previewing {
            rulesSettings.pause = .inactive
            rulesSettings.override = nil
        }
        return rulesEngine.decide(
            at: Date(),
            settings: rulesSettings,
            schedule: schedule,
            emergencyRestore: emergency,
            disabled: previewing ? false : settings.disabled
        )
    }

    var isPausedNow: Bool {
        settings.pause.isActive(at: Date())
    }

    var activeOverride: TemporaryOverride? {
        settings.override.flatMap { $0.isActive(at: Date()) ? $0 : nil }
    }

    var liveNextChangeLine: String {
        if livePreview != nil {
            return snapshot?.nextChange ?? ""
        }
        return StatusExplainer.nextChangeLine(
            wake: decision?.nextWake,
            automation: decision?.automation ?? snapshot?.automation ?? .automatic,
            at: evaluationDate
        )
    }

    func evaluateAndApply(force: Bool = false, reason: String? = nil, persistChanges: Bool = true) {
        let now = Date()
        transitionEngine.minimumWriteInterval = TimeInterval(settings.writeIntervalMilliseconds) / 1000
        transitionEngine.temperatureThreshold = settings.temperatureWriteThreshold
        if livePreview == nil {
            syncUntilNextAnchor(at: now)
            _ = settings.pruneExpiredStates(at: now)
        }
        let date = previewClock ?? now
        let decision = evaluate(at: date)
        self.decision = decision
        var snapshot = explainer.snapshot(decision: decision, displays: displays, settings: settings, at: date)
        if let preview = livePreview {
            snapshot.automation = .preview
            snapshot.headline = preview.applyingToHardware ? "Live day preview · \(snapshot.kelvinLabel)" : "Interface preview · \(snapshot.kelvinLabel)"
            snapshot.nextChange = preview.applyingToHardware
                ? "This preview is applying to the display. It restores when it ends."
                : "This preview is only in the interface. Hardware is unchanged."
        }
        self.snapshot = snapshot
        if let reason, HistoryRecording.shouldRecord(reason) {
            record(title: reason, detail: decision.explanation)
        }

        if livePreview?.applyingToHardware == false, previewClock != nil {
            if persistChanges { persist() }
            scheduleNextTick()
            return
        }

        if HardwareWritePolicy.shouldApply(
            onboarded: settings.onboarded,
            liveHardwarePreview: livePreview?.applyingToHardware == true
        ) {
            apply(decision: decision, at: now, force: force)
        }
        scheduleNextTick()
        if persistChanges { persist() }
    }

    func recomputeAndApply(reason: String) {
        if livePreview != nil {
            let live = livePreview?.applyingToHardware == true
            cancelPreview(applyCleanup: true)
            rememberNote(live
                ? "Live preview stopped because the environment changed."
                : "Interface preview stopped because the environment changed.")
        }
        forgetAppliedState()
        evaluateAndApply(force: true, reason: reason)
    }

    func apply(decision: ControllerDecision, at now: Date, force: Bool) {
        let overrideKeys = settings.override?.appliesToDisplayKeys ?? []
        if decision.restoreToBaseline, DisplayTargeting.restoresEveryDisplay(overrideDisplayKeys: overrideKeys) {
            if force || !lastApplied.isEmpty || !baselineRestored {
                _ = adapter.restoreAll()
                forgetAppliedState()
                baselineRestored = true
                mergeNotes(["Daylight restored its adjustments."])
            }
            return
        }

        baselineRestored = false
        var notes: [String] = []
        let scheduleOutput = decision.schedule?.output ?? decision.output
        for display in displays where display.connection == .connected {
            if display.mirrorsDisplayKey != nil {
                continue
            }
            let prefs = settings.preferences(for: display.identity)
            guard var output = DisplayTargeting.desiredOutput(
                for: display.id,
                excludedFromAutomation: prefs.excludedFromAutomation,
                decision: decision,
                scheduleOutput: scheduleOutput,
                overrideDisplayKeys: settings.override?.appliesToDisplayKeys ?? []
            ) else {
                if lastApplied[display.id] != nil {
                    _ = adapter.restore(display)
                    forgetAppliedState(for: display.id)
                }
                continue
            }
            if prefs.brightnessOffset != 0, var brightness = output.hardwareBrightness {
                brightness.fraction = min(max(brightness.fraction + prefs.brightnessOffset, 0.08), 1)
                output.hardwareBrightness = brightness
            }
            if display.capabilities.brightness != .hardware {
                output.hardwareBrightness = nil
            }
            let clock = previewClock ?? now
            let plan = transitionEngine.plan(
                applied: lastApplied[display.id],
                target: output.applying(limits: prefs.limits),
                lastWrite: lastWrites[display.id],
                now: now,
                transitionRemaining: decision.schedule?.inTransition == true ? decision.nextWake?.timeIntervalSince(clock) ?? 0 : 0,
                force: force
            )
            guard plan.shouldWrite else { continue }
            let applied = adapter.apply(output: plan.target, to: display, limits: prefs.limits, now: now)
            if applied.acceptedTemperature || applied.wroteTransferTable {
                lastApplied[display.id] = plan.target
                lastWrites[display.id] = now
            }
            for note in applied.notes where !notes.contains(note) {
                notes.append(note)
            }
        }
        restoreIdleDisplays()
        if !notes.isEmpty {
            mergeNotes(notes)
        }
    }

    private func restoreIdleDisplays() {
        for display in displays where display.connection != .connected {
            guard lastApplied[display.id] != nil else { continue }
            _ = adapter.restore(display)
            forgetAppliedState(for: display.id)
        }
    }

    private func prepareForSleep() {
        if settings.restoreOnSleep {
            if livePreview != nil {
                cancelPreview(applyCleanup: true)
            }
            _ = adapter.restoreAll(useColorSync: true)
            forgetAppliedState()
        }
        persist(immediate: true)
    }

    func scheduleNextTick() {
        tickTimer?.invalidate()
        let now = Date()
        if let preview = livePreview {
            let interval: TimeInterval
            if preview.applyingToHardware {
                interval = reduceMotionActive ? 0.9 : 0.32
            } else {
                interval = reduceMotionActive ? 0.22 : 0.055
            }
            tickTimer = scheduleTimer(after: interval) { [weak self] in
                self?.handleTick()
            }
            return
        }
        let next = transitionEngine.nextIdleWake(
            from: now,
            candidates: [
                decision?.nextWake,
                settings.pause.expiresAt,
                settings.override?.expiresAt,
                Calendar.current.nextDate(after: now, matching: DateComponents(second: 0, nanosecond: 0), matchingPolicy: .nextTime),
                now.addingTimeInterval(TimeInterval(settings.writeIntervalMilliseconds) / 1000)
            ]
        )
        let interval = max(next?.timeIntervalSince(now) ?? 2, 0.4)
        tickTimer = scheduleTimer(after: min(interval, 20)) { [weak self] in
            self?.handleTick()
        }
    }

    private func handleTick() {
        let now = Date()
        if var preview = livePreview {
            if now >= preview.endsAt {
                cancelPreview(applyCleanup: true)
                return
            }
            let span = max(preview.endsAt.timeIntervalSince(preview.startedAt), 0.01)
            let t = min(max(now.timeIntervalSince(preview.startedAt) / span, 0), 1)
            preview.playhead = DayPreviewClock.date(progress: t, startOfDay: preview.startOfDay)
            livePreview = preview
            previewClock = preview.playhead
            evaluateAndApply()
            return
        }
        if let pause = settings.pause.expiresAt, now >= pause {
            settings.pause = .inactive
        }
        if let override = settings.override, let expires = override.expiresAt, now >= expires {
            let ended = override.displayName
            settings.override = nil
            record(title: "Override ended", detail: "\(ended) ended. Your schedule is being recomputed.")
            rememberNote("\(ended) ended. Your schedule is back.")
        }
        evaluateAndApply()
    }

    func setMode(_ mode: LightingMode, duration: OverrideDuration) {
        if mode == .automatic {
            livePreview = nil
            previewClock = nil
            settings.override = nil
            settings.pause = .inactive
            evaluateAndApply(force: true, reason: "Resumed automatic mode")
            return
        }
        if livePreview != nil { return }
        guard canAdjustSelectedDisplay else { return }
        let schedule = currentScheduleEvaluation(at: Date())
        let resolved = resolvedDuration(duration, nextAnchor: schedule.nextChangeAt)
        let profile = settings.profiles.first { $0.mode == mode }
        settings.override = TemporaryOverride(
            mode: mode,
            output: profile?.output,
            duration: resolved.0,
            startedAt: Date(),
            expiresAt: resolved.1,
            reason: mode.summary,
            silencesReminders: mode == .presentation,
            appliesToDisplayKeys: sliderAffectsAllDisplays ? [] : selectedKeys()
        )
        evaluateAndApply(force: true, reason: "\(mode.title) mode")
    }

    func pause(duration: OverrideDuration) {
        guard livePreview == nil, !settings.disabled else { return }
        let expires = duration.expiration(from: Date(), nextAnchor: currentScheduleEvaluation().nextChangeAt)
        settings.override = nil
        settings.pause = PauseState(isPaused: true, expiresAt: expires, reason: "Paused from \(Brand.name)")
        evaluateAndApply(force: true, reason: "Paused automation")
    }

    func resume() {
        guard livePreview == nil else { return }
        settings.pause = .inactive
        settings.override = nil
        evaluateAndApply(force: true, reason: "Resumed automation")
    }

    func restoreNow() {
        if livePreview != nil {
            cancelPreview(applyCleanup: true)
        }
        settings.override = nil
        settings.pause = PauseState(isPaused: true, expiresAt: nil, reason: "Restored normal output")
        _ = adapter.restoreAll(useColorSync: true)
        forgetAppliedState()
        rememberNote("Restored native output. Automation stays paused until you resume.")
        evaluateAndApply(force: true, reason: "Restored normal output")
    }

    func emergencyRestore() {
        if livePreview != nil {
            cancelPreview(applyCleanup: true)
        }
        settings.disabled = false
        settings.override = nil
        settings.pause = .inactive
        _ = adapter.restoreAll(useColorSync: true)
        forgetAppliedState()
        evaluateAndApply(force: true, reason: "Emergency restore")
    }

    func setDisabled(_ disabled: Bool) {
        if livePreview != nil {
            cancelPreview(applyCleanup: true)
        }
        settings.disabled = disabled
        if disabled {
            _ = adapter.restoreAll(useColorSync: true)
            forgetAppliedState()
        }
        evaluateAndApply(force: true, reason: disabled ? "Turned Daylight off" : "Turned Daylight on")
    }

    func applySlider(temperature: Double? = nil, brightness: Double? = nil, dimming: Double? = nil) {
        beginSliderSession()
        sliderDebounce?.invalidate()
        sliderDebounce = scheduleTimer(after: 0.10) { [weak self] in
            self?.commitSlider(temperature: temperature, brightness: brightness, dimming: dimming, confirmExtreme: false)
        }
    }

    func finishSlider(temperature: Double? = nil, brightness: Double? = nil, dimming: Double? = nil) {
        sliderDebounce?.invalidate()
        commitSlider(temperature: temperature, brightness: brightness, dimming: dimming, confirmExtreme: true)
        if pendingExtreme == nil {
            endSliderSession()
        }
    }

    func abandonSlider() {
        sliderDebounce?.invalidate()
        pendingExtreme = nil
        if sliderSessionActive {
            settings.override = overrideBeforeSlider
        }
        endSliderSession()
        evaluateAndApply(force: true)
    }

    private func endSliderSession() {
        sliderSessionActive = false
        overrideBeforeSlider = nil
    }

    private func beginSliderSession() {
        guard !sliderSessionActive else { return }
        sliderSessionActive = true
        overrideBeforeSlider = settings.override
    }

    private func commitSlider(temperature: Double?, brightness: Double?, dimming: Double?, confirmExtreme: Bool) {
        guard canAdjustSelectedDisplay else { return }
        var output = selectedOutput ?? DesiredOutput(temperature: .defaultDay)
        if let temperature {
            output.temperature = ColorTemperature(kelvin: temperature)
        }
        if let brightness {
            output.hardwareBrightness = HardwareBrightness(fraction: brightness)
        }
        if let dimming {
            output.softwareDimming = SoftwareDimming(factor: dimming)
        }
        let risks = Safety.risks(for: output)
        if !risks.isEmpty {
            if confirmExtreme {
                pendingExtreme = output
                onNeedsConfirmation?()
            }
            return
        }
        commitOverride(output)
        if confirmExtreme {
            markManualAdjustment()
        }
    }

    func confirmExtreme() {
        if let pendingExtreme {
            commitOverride(pendingExtreme)
            markManualAdjustment()
        }
        pendingExtreme = nil
        endSliderSession()
    }

    func cancelExtreme() {
        abandonSlider()
    }

    func commitOverride(_ output: DesiredOutput) {
        let resolved = resolvedDuration(sliderDuration, nextAnchor: currentScheduleEvaluation().nextChangeAt)
        settings.override = TemporaryOverride(
            mode: .focus,
            output: output,
            duration: resolved.0,
            startedAt: Date(),
            expiresAt: resolved.1,
            reason: "Manual adjustment",
            appliesToDisplayKeys: sliderAffectsAllDisplays ? [] : selectedKeys()
        )
        evaluateAndApply(force: true)
    }

    func setSliderDuration(_ duration: OverrideDuration) {
        sliderDuration = duration
        settings.sliderDuration = duration
        _ = settings.pruneExpiredStates()
        guard var override = settings.override else {
            persist()
            return
        }
        let resolved = resolvedDuration(duration, nextAnchor: currentScheduleEvaluation().nextChangeAt)
        override.duration = resolved.0
        override.expiresAt = resolved.1
        settings.override = override
        evaluateAndApply()
    }

    func setSliderAffectsAllDisplays(_ value: Bool) {
        sliderAffectsAllDisplays = value
        settings.sliderAffectsAllDisplays = value
        retargetActiveOverride()
    }

    func selectAdjacentDisplay(delta: Int) {
        guard displays.count > 1, let index = selectedDisplay.flatMap({ display in displays.firstIndex(where: { $0.id == display.id }) }) else {
            return
        }
        let next = DisplayTargeting.adjacentIndex(from: index, delta: delta, count: displays.count)
        selectDisplay(id: displays[next].id)
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func selectTab(_ tab: MainTab) {
        selectedTab = tab
        if settings.lastSelectedTab != tab.rawValue {
            settings.lastSelectedTab = tab.rawValue
            persist()
        }
    }

    func reloadHistory() {
        history = settings.historyEnabled ? store.loadHistory() : []
    }

    func clearHistory() {
        store.clearHistory()
        history = []
        objectWillChange.send()
    }

    func markManualAdjustment() {
        record(title: "Manual lighting adjustment", detail: decision?.explanation ?? "A slider change is being held as a temporary override.")
    }

    func updateSchedule(_ mutate: (inout DailySchedule) -> Void, recordUndo: Bool = true, persistChanges: Bool = true) {
        guard livePreview == nil else { return }
        if recordUndo {
            pushUndo()
        }
        invalidateTimelineCache()
        if editingWeekendSchedule {
            mutate(&settings.weekendSchedule)
        } else {
            mutate(&settings.weekdaySchedule)
        }
        evaluateAndApply(persistChanges: persistChanges)
    }

    func moveAnchor(id: String, toMinutes minutes: Int, recordUndo: Bool, persistChanges: Bool = true) {
        updateSchedule({ schedule in
            func move(_ anchors: inout [ScheduleAnchor]) {
                guard let index = anchors.firstIndex(where: { id == $0.id || id.contains("-\($0.id)-") }) else { return }
                if case .clock = anchors[index].timing {
                    anchors[index].timing = .clock(TimeOfDay(minutesFromMidnight: minutes))
                }
            }
            move(&schedule.personalAnchors)
            move(&schedule.customAnchors)
        }, recordUndo: recordUndo, persistChanges: persistChanges)
    }

    func undoSchedule() {
        guard livePreview == nil, let previous = undoStack.popLast() else { return }
        redoStack.append(ScheduleSnapshot(weekday: settings.weekdaySchedule, weekend: settings.weekendSchedule))
        settings.weekdaySchedule = previous.weekday
        settings.weekendSchedule = previous.weekend
        invalidateTimelineCache()
        evaluateAndApply()
    }

    func redoSchedule() {
        guard livePreview == nil, let next = redoStack.popLast() else { return }
        undoStack.append(ScheduleSnapshot(weekday: settings.weekdaySchedule, weekend: settings.weekendSchedule))
        settings.weekdaySchedule = next.weekday
        settings.weekendSchedule = next.weekend
        invalidateTimelineCache()
        evaluateAndApply()
    }

    func applyPreset(_ preset: ComfortPreset) {
        guard livePreview == nil else { return }
        pushUndo()
        invalidateTimelineCache()
        settings.applyPreset(preset)
        evaluateAndApply(force: true, reason: "Applied \(preset.name) starting point")
    }

    func setLocation(_ location: LocationFix?) {
        settings.location = location
        settings.weekdaySchedule.location = location
        settings.weekendSchedule.location = location
        invalidateTimelineCache()
        evaluateAndApply(force: true, reason: location == nil ? "Cleared location" : "Set location to \(location!.name)")
    }

    func setApproach(_ value: ScheduleApproach, recordUndo: Bool = true) {
        if recordUndo {
            pushUndo()
        }
        invalidateTimelineCache()
        settings.applySharedScheduleStyle(approach: value)
        evaluateAndApply()
    }

    func setSolarOffset(sunrise: Int? = nil, sunset: Int? = nil) {
        if !offsetUndoArmed {
            pushUndo()
        }
        invalidateTimelineCache()
        settings.applySharedScheduleStyle(sunriseOffsetMinutes: sunrise, sunsetOffsetMinutes: sunset)
        evaluateAndApply()
        offsetUndoArmed = true
        offsetSettle?.invalidate()
        offsetSettle = scheduleTimer(after: 0.55) { [weak self] in
            self?.offsetUndoArmed = false
        }
    }

    func addCustomAnchor(at minutes: Int? = nil) {
        updateSchedule { schedule in
            let index = schedule.customAnchors.count + 1
            let time = minutes.map { TimeOfDay(minutesFromMidnight: $0) } ?? schedule.nextFreeCustomTime()
            schedule.customAnchors.append(
                ScheduleAnchor(
                    name: index == 1 ? "Custom" : "Custom \(index)",
                    kind: .custom,
                    timing: .clock(time),
                    output: DesiredOutput(temperature: ColorTemperature(kelvin: 5000)),
                    transitionMinutes: schedule.defaultTransitionMinutes
                )
            )
        }
    }

    func removeCustomAnchor(id: String) {
        updateSchedule { schedule in
            schedule.customAnchors.removeAll { $0.id == id }
            schedule.reconcileAfterRemovingCustomTimes()
        }
    }

    func renameDisplay(_ display: ConnectedDisplay, to name: String) {
        var prefs = settings.preferences(for: display.identity)
        prefs.customName = name
        settings.upsertDisplay(prefs)
        persist()
        objectWillChange.send()
    }

    func setExcluded(_ display: ConnectedDisplay, excluded: Bool) {
        var prefs = settings.preferences(for: display.identity)
        prefs.excludedFromAutomation = excluded
        settings.upsertDisplay(prefs)
        if excluded {
            _ = adapter.restore(display)
            forgetAppliedState(for: display.id)
        }
        evaluateAndApply(force: true)
    }

    func selectDisplay(id: String) {
        selectedDisplayID = id
        if settings.lastSelectedDisplayID != id {
            settings.lastSelectedDisplayID = id
            persist()
        }
        objectWillChange.send()
    }

    func setBrightnessOffset(_ display: ConnectedDisplay, offset: Double) {
        var prefs = settings.preferences(for: display.identity)
        prefs.brightnessOffset = min(max(offset, -0.2), 0.2)
        settings.upsertDisplay(prefs)
        persist()
        offsetDebounce?.invalidate()
        offsetDebounce = scheduleTimer(after: 0.16) { [weak self] in
            self?.persist(immediate: true)
            self?.evaluateAndApply(force: true)
        }
        objectWillChange.send()
    }

    func linkSelectedDisplays() {
        let keys = DisplayTargeting.linkableDisplayKeys(displays)
        guard keys.count > 1 else { return }
        settings.groups.removeAll { $0.name == "Linked displays" }
        settings.groups.append(DisplayGroup(name: "Linked displays", displayKeys: keys))
        retargetActiveOverride()
    }

    func unlinkDisplays() {
        settings.groups.removeAll()
        retargetActiveOverride()
    }

    private func retargetActiveOverride() {
        let before = settings.override
        settings.retargetOverride(selectedDisplayID: selectedDisplayID, allDisplays: sliderAffectsAllDisplays)
        if settings.override != before, settings.override != nil {
            evaluateAndApply(force: true)
            return
        }
        persist()
        objectWillChange.send()
    }

    func previewDay(applyToHardware: Bool) {
        guard !settings.disabled else { return }
        if applyToHardware, !PreviewPolicy.allowsLiveHardware(paused: isPausedNow, disabled: false) {
            return
        }
        let start = Calendar.current.startOfDay(for: scheduleCanvasDate)
        let duration: TimeInterval
        if applyToHardware {
            duration = reduceMotionActive ? 16 : 12
        } else {
            duration = reduceMotionActive ? 48 : 34
        }
        livePreview = LivePreviewState(
            applyingToHardware: applyToHardware,
            startedAt: Date(),
            endsAt: Date().addingTimeInterval(duration),
            playhead: start,
            startOfDay: start
        )
        previewClock = start
        evaluateAndApply(force: applyToHardware, reason: applyToHardware ? "Live day preview" : "Interface day preview")
    }

    func cancelPreview(applyCleanup: Bool) {
        let wasLive = livePreview?.applyingToHardware == true
        livePreview = nil
        previewClock = nil
        if applyCleanup && wasLive, HardwareWritePolicy.shouldRestoreAfterLivePreview(onboarded: settings.onboarded) {
            _ = adapter.restoreAll(useColorSync: true)
            forgetAppliedState()
        }
        if applyCleanup && wasLive {
            evaluateAndApply(force: true, reason: "Preview ended")
        } else {
            evaluateAndApply()
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            settings.launchAtLogin = enabled
            if enabled, let loginNote = launchAtLoginMessage() {
                rememberNote(loginNote)
            }
        } catch {
            rememberNote("Launch at login could not be updated: \(error.localizedDescription)")
        }
        persist(immediate: true)
        objectWillChange.send()
    }

    func reconcileLaunchAtLogin() {
        let desired = settings.launchAtLogin
        let status = SMAppService.mainApp.status
        if desired {
            if status != .enabled && status != .requiresApproval {
                do {
                    try SMAppService.mainApp.register()
                } catch {
                    rememberNote("Launch at login is saved, but macOS did not enable it: \(error.localizedDescription)")
                }
            } else if let loginNote = launchAtLoginMessage() {
                rememberNote(loginNote)
            }
        } else if status == .enabled || status == .requiresApproval {
            try? SMAppService.mainApp.unregister()
        }
    }

    func applyAppearance() {
        NSApp.appearance = Style.appearance(for: settings.appearance)
    }

    func setAppearance(_ preference: AppearancePreference) {
        settings.appearance = preference
        applyAppearance()
        persist()
        objectWillChange.send()
    }

    func setDefaultTransitionMinutes(_ minutes: Int) {
        guard livePreview == nil else { return }
        let value = min(max(minutes, 5), 90)
        settings.defaultTransitionMinutes = value
        settings.weekdaySchedule.applyDefaultTransitionMinutes(value)
        settings.weekendSchedule.applyDefaultTransitionMinutes(value)
        invalidateTimelineCache()
        evaluateAndApply()
    }

    func exportSettings() -> Data? {
        try? store.exportSettings(settings)
    }

    func writeExportedSettings(_ data: Data, to url: URL) {
        do {
            try data.write(to: url)
            rememberNote("Exported settings.")
        } catch {
            rememberNote("Could not save the export: \(error.localizedDescription)")
        }
        objectWillChange.send()
    }

    func importSettings(from url: URL) {
        guard let data = try? Data(contentsOf: url), let imported = try? store.import(data) else {
            rememberNote("That file is not a valid \(Brand.name) settings export.")
            return
        }
        livePreview = nil
        previewClock = nil
        settings = imported
        sliderDuration = imported.sliderDuration
        sliderAffectsAllDisplays = imported.sliderAffectsAllDisplays
        undoStack.removeAll()
        redoStack.removeAll()
        editingWeekendSchedule = imported.resolvedEditingWeekend()
        selectedTab = MainTab(rawValue: imported.lastSelectedTab ?? "") ?? selectedTab
        if let id = imported.lastSelectedDisplayID, displays.contains(where: { $0.id == id }) {
            selectedDisplayID = id
        }
        forgetAppliedState()
        invalidateTimelineCache()
        applyAppearance()
        reconcileLaunchAtLogin()
        reloadHistory()
        evaluateAndApply(force: true, reason: "Imported settings")
        persist(immediate: true)
        rememberNote("Imported settings.")
    }

    func resetSettings() {
        let wasLogin = settings.launchAtLogin
        livePreview = nil
        previewClock = nil
        settings = AppSettings.resetDefaults()
        sliderDuration = settings.sliderDuration
        sliderAffectsAllDisplays = settings.sliderAffectsAllDisplays
        undoStack.removeAll()
        redoStack.removeAll()
        editingWeekendSchedule = false
        if wasLogin {
            try? SMAppService.mainApp.unregister()
        }
        store.clearHistory()
        history = []
        applyAppearance()
        _ = adapter.restoreAll(useColorSync: true)
        forgetAppliedState()
        invalidateTimelineCache()
        evaluateAndApply(force: true, reason: "Reset to defaults")
        persist(immediate: true)
    }

    func finishOnboarding() {
        if livePreview != nil {
            cancelPreview(applyCleanup: true)
        }
        settings.onboarded = true
        settings.override = nil
        settings.pause = .inactive
        invalidateTimelineCache()
        persist(immediate: true)
        undoStack.removeAll()
        redoStack.removeAll()
        evaluateAndApply(force: true, reason: "Finished setup")
    }

    func copyStatus() {
        let text = [
            "\(Brand.name) \(Brand.marketingVersion)",
            ClockFormat.shortTime(evaluationDate),
            presentedHeadline,
            presentedKelvinLabel,
            snapshot?.explanation,
            liveNextChangeLine,
            snapshot?.displaySummary,
            selectedDisplay.map { displayName($0) },
            selectedDisplay.map { targetCaption(for: $0) },
            lastNotes.first
        ]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        rememberNote("Copied the current status.")
    }

    func prepareToQuit() {
        guard didStart, !didPrepareToQuit else { return }
        didPrepareToQuit = true
        tickTimer?.invalidate()
        persistDebounce?.invalidate()
        sliderDebounce?.invalidate()
        offsetDebounce?.invalidate()
        offsetSettle?.invalidate()
        lifecycleSettle?.invalidate()
        adapter.restoreAllOnQuit()
        store.clearOwnership()
        persist(immediate: true)
    }

    func displayName(_ display: ConnectedDisplay) -> String {
        settings.preferences(for: display.identity).resolvedName(fallback: display.name)
    }

    func displayMenuTitle(_ display: ConnectedDisplay) -> String {
        let name = displayName(display)
        switch display.connection {
        case .connected:
            return display.isMain ? "\(name) · Main" : name
        case .inactive:
            return "\(name) · Idle"
        case .disconnected:
            return "\(name) · Off"
        }
    }

    func extremeMessages() -> [String] {
        guard let pendingExtreme else { return [] }
        return Safety.risks(for: pendingExtreme).map(\.message)
    }

    var isSelectedDisplayLinked: Bool {
        settings.isLinked(selectedDisplayID)
    }

    func launchAtLoginMessage() -> String? {
        guard settings.launchAtLogin else { return nil }
        switch SMAppService.mainApp.status {
        case .requiresApproval:
            return "Launch at login is waiting for approval in System Settings → Login Items."
        case .notRegistered, .notFound:
            return "Launch at login is saved, but macOS has not enabled it yet."
        default:
            return nil
        }
    }

    func isScheduleFallback(_ display: ConnectedDisplay) -> Bool {
        let keys = settings.override?.appliesToDisplayKeys ?? []
        guard decision?.winningPriority == .temporaryOverride, !keys.isEmpty else { return false }
        return !keys.contains(display.id)
    }

    func targetCaption(for display: ConnectedDisplay) -> String {
        let prefs = settings.preferences(for: display.identity)
        let keys = settings.override?.appliesToDisplayKeys ?? []
        let scoped = decision?.winningPriority == .temporaryOverride && !keys.isEmpty
        let holding = scoped ? keys.contains(display.id) : nil
        let scheduleFallback = scoped && !keys.contains(display.id)
        let restored = decision?.restoreToBaseline == true
        let restoredTitle: String?
        switch decision?.automation {
        case .paused:
            restoredTitle = "Restored — paused"
        case .disabled:
            restoredTitle = "Restored — Daylight is off"
        case .colorWork:
            restoredTitle = "Color Work — native tables"
        default:
            restoredTitle = restored ? "Restored — Daylight is not writing to this display" : nil
        }
        return DisplayTargeting.targetCaption(
            connection: display.connection,
            excluded: prefs.excludedFromAutomation,
            mirrored: display.mirrorsDisplayKey != nil,
            output: desiredOutput(for: display),
            holdingThisDisplay: holding,
            scheduleFallback: scheduleFallback,
            restored: restored,
            restoredTitle: restoredTitle
        )
    }

    func desiredOutput(for display: ConnectedDisplay) -> DesiredOutput? {
        guard let decision else { return nil }
        let prefs = settings.preferences(for: display.identity)
        return DisplayTargeting.desiredOutput(
            for: display.id,
            excludedFromAutomation: prefs.excludedFromAutomation,
            decision: decision,
            scheduleOutput: decision.schedule?.output ?? decision.output,
            overrideDisplayKeys: settings.override?.appliesToDisplayKeys ?? []
        )
    }

    private func resolvedDuration(_ duration: OverrideDuration, nextAnchor: Date?, from start: Date = Date()) -> (OverrideDuration, Date?) {
        if duration == .untilNextAnchor, nextAnchor == nil {
            return (.untilResumed, nil)
        }
        return (duration, duration.expiration(from: start, nextAnchor: nextAnchor))
    }

    private func syncUntilNextAnchor(at now: Date) {
        guard let override = settings.override, override.duration == .untilNextAnchor else { return }
        let next = currentScheduleEvaluation(at: now).nextChangeAt
        let updated = override.refreshed(nextChange: next, at: now)
        if updated != override {
            settings.override = updated
        }
    }

    private func selectedKeys() -> [String] {
        settings.overrideTargetKeys(selectedDisplayID: selectedDisplayID, allDisplays: sliderAffectsAllDisplays)
    }

    private func isStickyNote(_ note: String) -> Bool {
        let needles = [
            "ended unexpectedly",
            "could not be read",
            "could not create",
            "could not save",
            "could not record display ownership",
            "Launch at login",
            "Login Items",
            "Imported settings",
            "Exported settings",
            "Copied the current status",
            "Reset to defaults",
            "Application Support",
            "stays paused until you resume",
            "No physical displays",
            "simulation",
            "preview stopped because the environment changed"
        ]
        return needles.contains { note.localizedCaseInsensitiveContains($0) }
    }

    private func rememberNote(_ note: String) {
        if !lastNotes.contains(note) {
            lastNotes.insert(note, at: 0)
        }
    }

    private func restoreStickyNotes(_ notes: [String]) {
        for note in notes.reversed() {
            rememberNote(note)
        }
    }

    private func mergeNotes(_ notes: [String]) {
        let sticky = lastNotes.filter(isStickyNote)
        lastNotes = notes
        restoreStickyNotes(sticky)
    }

    private func forgetAppliedState() {
        lastApplied.removeAll()
        lastWrites.removeAll()
    }

    private func forgetAppliedState(for id: String) {
        lastApplied[id] = nil
        lastWrites[id] = nil
    }

    private func pushUndo() {
        undoStack.append(ScheduleSnapshot(weekday: settings.weekdaySchedule, weekend: settings.weekendSchedule))
        if undoStack.count > 40 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    private func invalidateTimelineCache() {
        sampleCacheKey = 0
        lastSampleBuild = .distantPast
        sampleCache = []
    }

    private func coalesceLifecycle(reason: String, refreshDisplays: Bool) {
        if refreshDisplays { pendingDisplayRefresh = true }
        pendingLifecycleReason = reason
        lifecycleSettle?.invalidate()
        lifecycleSettle = scheduleTimer(after: 0.28) { [weak self] in
            self?.flushLifecycle()
        }
    }

    private func flushLifecycle() {
        if pendingDisplayRefresh {
            pendingDisplayRefresh = false
            refreshDisplays()
            adapter.forgetDisconnected(current: displays)
        }
        let reason = pendingLifecycleReason ?? "Environment changed"
        pendingLifecycleReason = nil
        recomputeAndApply(reason: reason)
    }

    private func recoverFromPreviousRun() {
        guard let ownership = store.loadOwnership(), ownership.displays.contains(where: \.applyingTransform) else {
            return
        }
        _ = adapter.restoreAll(useColorSync: true)
        rememberNote("A previous session may have ended unexpectedly. \(Brand.name) restored ColorSync tables, then will apply the current schedule.")
        record(title: "Recovered after an interrupted session", detail: "ColorSync tables were restored before applying the current schedule.")
    }

    private func restoreRemovedDisplays(previous: [ConnectedDisplay], next: [ConnectedDisplay], remapped: Set<String>) {
        let removed = DisplayTargeting.removedDisplayKeys(
            previous: previous.map(\.id),
            next: next.map(\.id),
            remapped: remapped
        )
        let previousByID = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
        for id in removed {
            if let display = previousByID[id] {
                _ = adapter.restore(display)
            } else {
                _ = adapter.restoreRemembered(id: id)
            }
            forgetAppliedState(for: id)
        }
        let live = Set(next.map(\.id)).union(remapped)
        for id in Array(lastApplied.keys) where !live.contains(id) {
            _ = adapter.restoreRemembered(id: id)
            forgetAppliedState(for: id)
        }
    }

    private func syncDisplayPreferences(_ displays: [ConnectedDisplay]) -> Set<String> {
        var remapped = Set<String>()
        for display in displays {
            let previousKey = settings.matchExistingIdentity(display.identity)?.0.identity.durableKey
            let existed = previousKey != nil
            var prefs = settings.adoptConnectedIdentity(display.identity)
            if let previousKey, previousKey != display.id {
                remapped.insert(previousKey)
                adapter.adoptSession(from: previousKey, to: display.id)
                if let applied = lastApplied.removeValue(forKey: previousKey) {
                    lastApplied[display.id] = applied
                }
                if let written = lastWrites.removeValue(forKey: previousKey) {
                    lastWrites[display.id] = written
                }
            }
            if !existed, settings.useAdvancedTemperatureRange {
                prefs.limits.allowAdvancedRange = true
                prefs.limits.temperatureRange = ColorTemperature.advancedRange
                settings.upsertDisplay(prefs)
            }
        }
        if let remembered = settings.lastSelectedDisplayID,
           displays.contains(where: { $0.id == remembered }) {
            selectedDisplayID = remembered
        }
        return remapped
    }

    private func record(title: String, detail: String) {
        store.appendHistory(HistoryEvent(at: Date(), title: title, detail: detail), enabled: settings.historyEnabled)
        if settings.historyEnabled {
            history = store.loadHistory()
        }
    }

    private func scheduleTimer(after interval: TimeInterval, handler: @escaping @MainActor () -> Void) -> Timer {
        let work = TimerWork(handler)
        let timer = Timer(timeInterval: max(interval, 0.02), repeats: false) { _ in
            Task { @MainActor in work.run() }
        }
        timer.tolerance = min(max(interval * 0.12, 0.02), 1.2)
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    private func installEmergencyMonitor() {
        emergencyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains([.option, .shift, .command]) && event.charactersIgnoringModifiers?.lowercased() == "r" {
                Task { @MainActor in self?.emergencyRestore() }
                return nil
            }
            return event
        }
    }
}

private final class TimerWork: @unchecked Sendable {
    let run: @MainActor () -> Void
    init(_ run: @escaping @MainActor () -> Void) {
        self.run = run
    }
}

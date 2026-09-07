import AppKit
import Combine
import DaylightCore
import UniformTypeIdentifiers

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation, NSPopoverDelegate {
    let controller = AppController()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var menuBar: MenuBarController?
    private var mainWindow: MainWindowController?
    private var onboarding: OnboardingWindowController?
    private var aboutWindow: AboutWindowController?
    private var helpWindow: HelpWindowController?
    private var cancellable: AnyCancellable?
    private var confirmingExtreme = false
    private var statusMenu: NSMenu?
    private var activateObserver: NSObjectProtocol?
    private var chromeWork: DispatchWorkItem?
    private var pendingTab: MainTab?
    private var popoverClock: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        if handOffToExistingInstance() {
            NSApp.terminate(nil)
            return
        }
        listenForActivation()
        NSApp.setActivationPolicy(.accessory)
        controller.start()
        controller.onNeedsConfirmation = { [weak self] in self?.confirmExtremeIfNeeded() }
        installStatusItem()
        installAppMenu()
        if !controller.settings.onboarded {
            showOnboarding()
        }
        cancellable = controller.objectWillChange.sink { [weak self] _ in
            self?.scheduleChromeRefresh()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        controller.prepareToQuit()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.prepareToQuit()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        refreshChrome()
    }

    func popoverDidShow(_ notification: Notification) {
        popoverClock?.invalidate()
        popoverClock = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.popover?.isShown == true else { return }
                self.menuBar?.refreshClock()
                if let menuBar = self.menuBar, !menuBar.isTracking {
                    self.popover?.contentSize = menuBar.fittedSize()
                }
            }
        }
        if let popoverClock {
            RunLoop.main.add(popoverClock, forMode: .common)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        popoverClock?.invalidate()
        popoverClock = nil
        menuBar?.cancelSliderTracking()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func showMainWindow() {
        if !controller.settings.onboarded {
            showOnboarding()
            return
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if mainWindow == nil {
            let window = MainWindowController(controller: controller)
            window.onClose = { [weak self] in
                self?.handleMainClose()
            }
            mainWindow = window
        }
        mainWindow?.showWindow(nil)
        mainWindow?.window?.makeKeyAndOrderFront(nil)
        mainWindow?.startClockTick()
        if let pendingTab {
            mainWindow?.show(pendingTab)
            self.pendingTab = nil
        }
        popover?.performClose(nil)
        refreshChrome()
    }

    func showOnboarding() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if onboarding == nil {
            let flow = OnboardingWindowController(controller: controller)
            flow.onFinish = { [weak self] in
                self?.onboarding = nil
                self?.showMainWindow()
            }
            onboarding = flow
        }
        onboarding?.showWindow(nil)
        onboarding?.window?.makeKeyAndOrderFront(nil)
    }

    func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let kelvin = controller.chromeKelvin
        if aboutWindow == nil {
            aboutWindow = AboutWindowController(kelvin: kelvin, reduceMotion: controller.reduceMotionActive)
        } else {
            aboutWindow?.setKelvin(kelvin, reduceMotion: controller.reduceMotionActive)
        }
        aboutWindow?.showWindow(nil)
        aboutWindow?.window?.makeKeyAndOrderFront(nil)
        aboutWindow?.setKelvin(kelvin, reduceMotion: controller.reduceMotionActive)
    }

    func showHelp() {
        NSApp.activate(ignoringOtherApps: true)
        if helpWindow == nil {
            helpWindow = HelpWindowController()
        }
        helpWindow?.showWindow(nil)
        helpWindow?.window?.makeKeyAndOrderFront(nil)
    }

    @objc func togglePopover(_ sender: Any?) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            if popover?.isShown == true {
                popover?.performClose(nil)
            }
            showStatusMenu()
            return
        }
        if event?.modifierFlags.contains(.option) == true {
            if popover?.isShown == true {
                popover?.performClose(nil)
            }
            controller.restoreNow()
            return
        }
        guard let button = statusItem?.button, let popover, let menuBar else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        menuBar.refresh()
        popover.animates = !controller.reduceMotionActive
        if popover.contentViewController !== menuBar {
            popover.contentViewController = menuBar
        }
        popover.contentSize = menuBar.fittedSize()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        if validateMenuItem(item("Pause 30 minutes", #selector(pauseFromMenu))) {
            menu.addItem(item("Pause 30 minutes", #selector(pauseFromMenu)))
        }
        if validateMenuItem(item("Resume", #selector(resumeFromMenu))) {
            menu.addItem(item("Resume", #selector(resumeFromMenu)))
        }
        menu.addItem(item("Restore output", #selector(restoreFromMenu)))
        menu.addItem(item("Emergency restore", #selector(emergencyFromMenu)))
        menu.addItem(item(controller.settings.disabled ? "Turn Daylight On" : "Turn Daylight Off", #selector(toggleEnabledFromMenu)))
        if validateMenuItem(item("Preview my day", #selector(previewFromMenu))) {
            menu.addItem(item("Preview my day", #selector(previewFromMenu)))
        }
        if validateMenuItem(item("Live day preview", #selector(livePreviewFromMenu))) {
            menu.addItem(item("Live day preview", #selector(livePreviewFromMenu)))
        }
        if validateMenuItem(item("Stop preview", #selector(stopPreviewFromMenu))) {
            menu.addItem(item("Stop preview", #selector(stopPreviewFromMenu)))
        }
        menu.addItem(.separator())
        menu.addItem(item("Copy status", #selector(copyStatusFromMenu)))
        menu.addItem(item("Open \(Brand.name)", #selector(openFromMenu)))
        return menu
    }

    private func handleMainClose() {
        if controller.settings.keepRunningInBackground {
            NSApp.setActivationPolicy(.accessory)
        } else {
            NSApp.terminate(nil)
        }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.imagePosition = .imageLeading
        item.button?.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.setAccessibilityTitle(Brand.name)
        item.button?.setAccessibilityRole(.button)
        statusItem = item

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = !controller.reduceMotionActive
        popover.delegate = self
        self.popover = popover
        menuBar = MenuBarController(controller: controller, app: self)
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, self?.confirmingExtreme != true else { return event }
            if self?.popover?.isShown == true {
                if let window = self?.popover?.contentViewController?.view.window,
                   self?.releaseAdjustingControl(in: window) == true {
                    return nil
                }
                self?.popover?.performClose(nil)
                return nil
            }
            if let onboarding = self?.onboarding?.window, onboarding.isKeyWindow {
                return event
            }
            if let window = self?.mainWindow?.window, window.isKeyWindow {
                if window.attachedSheet != nil {
                    return event
                }
                if KeyFocus.isEditing(window.firstResponder) {
                    return event
                }
                if self?.releaseAdjustingControl(in: window) == true {
                    return nil
                }
                window.performClose(nil)
                return nil
            }
            if let about = self?.aboutWindow?.window, about.isKeyWindow {
                about.performClose(nil)
                return nil
            }
            if let help = self?.helpWindow?.window, help.isKeyWindow {
                help.performClose(nil)
                return nil
            }
            return event
        }
        refreshChrome()
    }

    @discardableResult
    private func releaseAdjustingControl(in window: NSWindow) -> Bool {
        if let slider = window.firstResponder as? GradientSlider {
            slider.cancelTracking(revert: true)
            window.makeFirstResponder(nil)
            return true
        }
        if let timeline = window.firstResponder as? TimelineCanvas {
            timeline.cancelInteraction()
            window.makeFirstResponder(nil)
            return true
        }
        if KeyFocus.isAdjusting(window.firstResponder) {
            window.makeFirstResponder(nil)
            return true
        }
        return false
    }

    private func refreshChrome() {
        if controller.settings.onboarded, onboarding?.window?.isVisible == true {
            onboarding?.window?.performClose(nil)
        }
        statusItem?.button?.image = StatusIcon.image(
            automation: controller.snapshot?.automation ?? controller.decision?.automation,
            kelvin: controller.chromeKelvin
        )
        statusItem?.button?.title = StatusIcon.title(
            snapshot: controller.snapshot,
            showTemperature: controller.settings.showMenuBarTemperature,
            kelvin: controller.chromeKelvin
        )
        statusItem?.button?.toolTip = [controller.presentedHeadline, controller.snapshot?.explanation, controller.liveNextChangeLine]
            .compactMap { $0 }
            .joined(separator: "\n")
        statusItem?.button?.appearsDisabled = controller.settings.disabled
        statusItem?.button?.setAccessibilityTitle(Brand.name)
        statusItem?.button?.setAccessibilityLabel(controller.presentedHeadline)
        popover?.animates = !controller.reduceMotionActive
        menuBar?.refresh()
        if popover?.isShown == true, let menuBar, !menuBar.isTracking {
            popover?.contentSize = menuBar.fittedSize()
        }
        aboutWindow?.setKelvin(controller.chromeKelvin, reduceMotion: controller.reduceMotionActive)
        mainWindow?.refresh()
        confirmExtremeIfNeeded()
    }

    private func confirmExtremeIfNeeded() {
        guard controller.pendingExtreme != nil, !confirmingExtreme else { return }
        confirmingExtreme = true
        let alert = NSAlert()
        alert.messageText = "This setting is quite strong"
        alert.informativeText = controller.extremeMessages().joined(separator: "\n\n") + "\n\nApply it anyway?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Apply anyway")
        alert.addButton(withTitle: "Cancel")
        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            if response == .alertFirstButtonReturn {
                self.controller.confirmExtreme()
            } else {
                self.controller.cancelExtreme()
            }
            self.popover?.behavior = .transient
            self.confirmingExtreme = false
            self.refreshChrome()
        }
        if let popover, popover.isShown, let window = popover.contentViewController?.view.window {
            popover.behavior = .applicationDefined
            alert.beginSheetModal(for: window, completionHandler: finish)
        } else if let window = mainWindow?.window, window.isVisible {
            alert.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(alert.runModal())
        }
    }

    private func showStatusMenu() {
        let menu = NSMenu()
        let headline = NSMenuItem(title: controller.presentedHeadline, action: nil, keyEquivalent: "")
        headline.isEnabled = false
        menu.addItem(headline)
        menu.addItem(.separator())
        if validateMenuItem(item("Pause 30 minutes", #selector(pauseFromMenu))) {
            menu.addItem(item("Pause 30 minutes", #selector(pauseFromMenu)))
        }
        if validateMenuItem(item("Resume", #selector(resumeFromMenu), key: "r")) {
            menu.addItem(item("Resume", #selector(resumeFromMenu), key: "r"))
        }
        menu.addItem(item("Restore output", #selector(restoreFromMenu)))
        menu.addItem(item("Emergency restore", #selector(emergencyFromMenu), key: "r", modifiers: [.command, .shift, .option]))
        menu.addItem(item(controller.settings.disabled ? "Turn Daylight On" : "Turn Daylight Off", #selector(toggleEnabledFromMenu)))
        menu.addItem(.separator())
        if validateMenuItem(item("Preview my day", #selector(previewFromMenu))) {
            menu.addItem(item("Preview my day", #selector(previewFromMenu)))
        }
        if validateMenuItem(item("Live day preview", #selector(livePreviewFromMenu))) {
            menu.addItem(item("Live day preview", #selector(livePreviewFromMenu)))
        }
        if validateMenuItem(item("Stop preview", #selector(stopPreviewFromMenu))) {
            menu.addItem(item("Stop preview", #selector(stopPreviewFromMenu)))
        }
        menu.addItem(item("Copy status", #selector(copyStatusFromMenu), key: "c", modifiers: [.command, .shift]))
        menu.addItem(item("Open \(Brand.name)", #selector(openFromMenu)))
        menu.addItem(item("Quit \(Brand.name)", #selector(quitFromMenu), key: "q"))
        statusMenu = menu
        if let button = statusItem?.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
        }
    }

    private func installAppMenu() {
        let main = NSMenu()
        let appName = Brand.name

        let appMenu = NSMenu()
        appMenu.addItem(item("About \(appName)", #selector(showAboutMenu)))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Settings…", #selector(showSettingsMenu), key: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Hide \(appName)", #selector(NSApplication.hide(_:)), key: "h"))
        appMenu.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), key: "h", modifiers: [.command, .option]))
        appMenu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Quit \(appName)", #selector(NSApplication.terminate(_:)), key: "q"))
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        main.addItem(appItem)

        let file = NSMenu(title: "File")
        file.addItem(item("Export Settings…", #selector(exportFromMenu), key: "e", modifiers: [.command, .shift]))
        file.addItem(item("Import Settings…", #selector(importFromMenu), key: "i", modifiers: [.command, .shift]))
        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        fileItem.submenu = file
        main.addItem(fileItem)

        let edit = NSMenu(title: "Edit")
        edit.addItem(item("Undo", #selector(undoFromMenu), key: "z"))
        edit.addItem(item("Redo", #selector(redoFromMenu), key: "z", modifiers: [.command, .shift]))
        edit.addItem(.separator())
        edit.addItem(item("Cut", #selector(NSText.cut(_:)), key: "x"))
        edit.addItem(item("Copy", #selector(NSText.copy(_:)), key: "c"))
        edit.addItem(item("Paste", #selector(NSText.paste(_:)), key: "v"))
        edit.addItem(item("Select All", #selector(NSText.selectAll(_:)), key: "a"))
        edit.addItem(.separator())
        edit.addItem(item("Copy status", #selector(copyStatusFromMenu), key: "c", modifiers: [.command, .shift]))
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = edit
        main.addItem(editItem)

        let view = NSMenu(title: "View")
        view.addItem(item("Today", #selector(showToday), key: "1"))
        view.addItem(item("Schedule", #selector(showSchedule), key: "2"))
        view.addItem(item("Displays", #selector(showDisplays), key: "3"))
        view.addItem(item("Settings", #selector(showSettingsMenu), key: "4"))
        view.addItem(.separator())
        view.addItem(item("Previous Display", #selector(previousDisplay), key: "["))
        view.addItem(item("Next Display", #selector(nextDisplay), key: "]"))
        let viewItem = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        viewItem.submenu = view
        main.addItem(viewItem)

        let controls = NSMenu(title: "Controls")
        controls.addItem(item("Pause 30 minutes", #selector(pauseFromMenu), key: "p"))
        controls.addItem(item("Resume", #selector(resumeFromMenu), key: "r"))
        controls.addItem(item("Restore output", #selector(restoreFromMenu), key: "r", modifiers: [.command, .option]))
        controls.addItem(item("Emergency restore", #selector(emergencyFromMenu), key: "r", modifiers: [.command, .shift, .option]))
        controls.addItem(item("Turn Daylight off", #selector(toggleEnabledFromMenu), key: "d", modifiers: [.command, .option]))
        controls.addItem(.separator())
        controls.addItem(item("Preview my day", #selector(previewFromMenu), key: "y"))
        controls.addItem(item("Live day preview", #selector(livePreviewFromMenu), key: "y", modifiers: [.command, .option]))
        controls.addItem(item("Stop preview", #selector(stopPreviewFromMenu), key: "."))
        let controlsItem = NSMenuItem(title: "Controls", action: nil, keyEquivalent: "")
        controlsItem.submenu = controls
        main.addItem(controlsItem)

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(item("Close", #selector(NSWindow.performClose(_:)), key: "w"))
        windowMenu.addItem(item("Minimize", #selector(NSWindow.miniaturize(_:)), key: "m"))
        windowMenu.addItem(item("Zoom", #selector(NSWindow.zoom(_:))))
        windowMenu.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        let help = NSMenu(title: "Help")
        help.addItem(item("\(appName) Help", #selector(showHelpMenu), key: "?"))
        let helpItem = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")
        helpItem.submenu = help
        main.addItem(helpItem)

        NSApp.mainMenu = main
    }

    private func item(
        _ title: String,
        _ selector: Selector,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = [.command]
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        if !key.isEmpty {
            item.keyEquivalentModifierMask = modifiers
        }
        item.target = self
        if selector == #selector(NSApplication.hide(_:))
            || selector == #selector(NSApplication.hideOtherApplications(_:))
            || selector == #selector(NSApplication.unhideAllApplications(_:))
            || selector == #selector(NSApplication.terminate(_:))
            || selector == #selector(NSWindow.performClose(_:))
            || selector == #selector(NSWindow.miniaturize(_:))
            || selector == #selector(NSWindow.zoom(_:))
            || selector == #selector(NSText.cut(_:))
            || selector == #selector(NSText.copy(_:))
            || selector == #selector(NSText.paste(_:))
            || selector == #selector(NSText.selectAll(_:))
            || selector == #selector(NSApplication.arrangeInFront(_:)) {
            item.target = nil
        }
        return item
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(undoFromMenu):
            if NSApp.keyWindow?.firstResponder is NSText {
                menuItem.title = "Undo"
                return (NSApp.keyWindow?.firstResponder as? NSText)?.undoManager?.canUndo == true
            }
            menuItem.title = "Undo schedule change"
            return controller.livePreview == nil && !controller.undoStack.isEmpty
        case #selector(redoFromMenu):
            if NSApp.keyWindow?.firstResponder is NSText {
                menuItem.title = "Redo"
                return (NSApp.keyWindow?.firstResponder as? NSText)?.undoManager?.canRedo == true
            }
            menuItem.title = "Redo schedule change"
            return controller.livePreview == nil && !controller.redoStack.isEmpty
        case #selector(pauseFromMenu):
            return !controller.isPausedNow && !controller.settings.disabled && controller.livePreview == nil
        case #selector(resumeFromMenu):
            menuItem.title = ActionTitles.resume(
                paused: controller.isPausedNow,
                pauseEndsAt: controller.settings.pause.expiresAt,
                holding: controller.activeOverride != nil,
                holdEndsAt: controller.activeOverride?.expiresAt
            )
            return controller.livePreview == nil && (controller.isPausedNow || controller.activeOverride != nil)
        case #selector(toggleEnabledFromMenu):
            menuItem.title = controller.settings.disabled ? "Turn Daylight On" : "Turn Daylight Off"
            return true
        case #selector(previewFromMenu):
            return controller.livePreview == nil && !controller.settings.disabled
        case #selector(livePreviewFromMenu):
            return controller.livePreview == nil
                && PreviewPolicy.allowsLiveHardware(paused: controller.isPausedNow, disabled: controller.settings.disabled)
        case #selector(stopPreviewFromMenu):
            return controller.livePreview != nil
        case #selector(previousDisplay), #selector(nextDisplay):
            return controller.displays.count > 1
        default:
            return true
        }
    }

    @objc private func showAboutMenu() { showAbout() }
    @objc private func showHelpMenu() { showHelp() }
    @objc private func showSettingsMenu() { revealTab(.settings) }
    @objc private func showToday() { revealTab(.today) }
    @objc private func showSchedule() { revealTab(.schedule) }
    @objc private func showDisplays() { revealTab(.displays) }
    @objc private func previousDisplay() { controller.selectAdjacentDisplay(delta: -1) }
    @objc private func nextDisplay() { controller.selectAdjacentDisplay(delta: 1) }

    private func revealTab(_ tab: MainTab) {
        if !controller.settings.onboarded {
            pendingTab = tab
            showOnboarding()
            return
        }
        showMainWindow()
        mainWindow?.show(tab)
    }
    @objc private func undoFromMenu() {
        if let text = NSApp.keyWindow?.firstResponder as? NSText, text.undoManager?.canUndo == true {
            text.undoManager?.undo()
            return
        }
        controller.undoSchedule()
    }
    @objc private func redoFromMenu() {
        if let text = NSApp.keyWindow?.firstResponder as? NSText, text.undoManager?.canRedo == true {
            text.undoManager?.redo()
            return
        }
        controller.redoSchedule()
    }
    @objc private func copyStatusFromMenu() { controller.copyStatus() }
    @objc private func pauseFromMenu() { controller.pause(duration: .minutes(30)) }
    @objc private func resumeFromMenu() { controller.resume() }
    @objc private func restoreFromMenu() { controller.restoreNow() }
    @objc private func emergencyFromMenu() { controller.emergencyRestore() }
    @objc private func toggleEnabledFromMenu() { controller.setDisabled(!controller.settings.disabled) }
    @objc private func previewFromMenu() { controller.previewDay(applyToHardware: false) }
    @objc private func livePreviewFromMenu() { controller.previewDay(applyToHardware: true) }
    @objc private func stopPreviewFromMenu() { controller.cancelPreview(applyCleanup: true) }

    private func scheduleChromeRefresh() {
        chromeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.refreshChrome()
        }
        chromeWork = work
        let delay: TimeInterval = controller.livePreview != nil ? 0.12 : 0.05
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
    @objc private func openFromMenu() { showMainWindow() }
    @objc private func quitFromMenu() { NSApp.terminate(nil) }
    @objc private func exportFromMenu() {
        guard let data = controller.exportSettings() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Daylight-settings.json"
        FilePanels.present(panel, over: mainWindow?.window) { [weak self] url in
            self?.controller.writeExportedSettings(data, to: url)
        }
    }
    @objc private func importFromMenu() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        FilePanels.present(panel, over: mainWindow?.window) { [weak self] url in
            SettingsAlerts.confirmImport(over: self?.mainWindow?.window) { confirmed in
                guard confirmed else { return }
                self?.controller.importSettings(from: url)
            }
        }
    }

    private func handOffToExistingInstance() -> Bool {
        guard Bundle.main.bundleIdentifier == Brand.bundleIdentifier else { return false }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Brand.bundleIdentifier)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        guard !others.isEmpty else { return false }
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(Brand.activateNotification),
            object: Brand.bundleIdentifier,
            userInfo: nil,
            deliverImmediately: true
        )
        return true
    }

    private func listenForActivation() {
        activateObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(Brand.activateNotification),
            object: Brand.bundleIdentifier,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.showMainWindow() }
        }
    }
}

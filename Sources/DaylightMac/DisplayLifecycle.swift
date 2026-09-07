import AppKit
import Foundation

public final class DisplayLifecycleMonitor: @unchecked Sendable {
    public var onDisplaysChanged: (() -> Void)?
    public var onWake: (() -> Void)?
    public var onSleep: (() -> Void)?
    public var onClockChanged: (() -> Void)?
    public var onUnlock: (() -> Void)?
    public var onAccessibilityChanged: (() -> Void)?

    private var observers: [NSObjectProtocol] = []
    private var registered = false

    public init() {}

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
    }

    public func start() {
        guard !registered else { return }
        registered = true

        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.onDisplaysChanged?()
            }
        )
        observers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.onWake?()
            }
        )
        observers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.onSleep?()
            }
        )
        observers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.screensDidWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.onWake?()
            }
        )
        observers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.screensDidSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.onSleep?()
            }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: .NSSystemClockDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.onClockChanged?()
            }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: .NSSystemTimeZoneDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.onClockChanged?()
            }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSLocale.currentLocaleDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.onClockChanged?()
            }
        )
        observers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.sessionDidBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.onUnlock?()
            }
        )
        observers.append(
            DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("com.apple.screenIsUnlocked"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.onUnlock?()
            }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.onAccessibilityChanged?()
            }
        )
    }
}

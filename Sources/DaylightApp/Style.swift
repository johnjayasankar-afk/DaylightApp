import AppKit
import DaylightCore

@MainActor
enum Style {
    static let accent = NSColor(srgbRed: 0.78, green: 0.48, blue: 0.28, alpha: 1)
    static let accentSoft = NSColor(srgbRed: 0.86, green: 0.64, blue: 0.44, alpha: 1)
    static let cool = NSColor(srgbRed: 0.46, green: 0.60, blue: 0.74, alpha: 1)
    static let warm = NSColor(srgbRed: 0.88, green: 0.56, blue: 0.30, alpha: 1)
    static let sidebarWidth: CGFloat = 188
    static let cardRadius: CGFloat = 14
    static let controlRadius: CGFloat = 9

    static func kelvinColor(_ kelvin: Double, alpha: CGFloat = 1) -> NSColor {
        let rgb = TemperatureAppearance.rgb(for: kelvin)
        return NSColor(srgbRed: rgb.r, green: rgb.g, blue: rgb.b, alpha: alpha)
    }

    static func temperature(kelvin: Double) -> NSColor {
        let t = min(max((kelvin - 2700) / 3800, 0), 1)
        return NSColor(
            srgbRed: 0.88 - 0.40 * t,
            green: 0.52 + 0.08 * t,
            blue: 0.28 + 0.46 * t,
            alpha: 1
        )
    }

    static func symbol(_ name: String, size: CGFloat = 14, weight: NSFont.Weight = .medium) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
    }

    static func label(
        _ text: String,
        font: NSFont = .systemFont(ofSize: 13),
        color: NSColor = .labelColor,
        lines: Int = 0
    ) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = color
        field.lineBreakMode = .byWordWrapping
        field.maximumNumberOfLines = lines
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    static func title(_ text: String) -> NSTextField {
        label(text, font: .systemFont(ofSize: 22, weight: .semibold))
    }

    static func section(_ text: String) -> NSTextField {
        label(text, font: .systemFont(ofSize: 15, weight: .semibold))
    }

    static func caption(_ text: String) -> NSTextField {
        label(text, font: .systemFont(ofSize: 11.5), color: .secondaryLabelColor)
    }

    static func mono(_ text: String, size: CGFloat = 12) -> NSTextField {
        label(text, font: .monospacedDigitSystemFont(ofSize: size, weight: .medium), color: .secondaryLabelColor)
    }

    static func hairline() -> NSView {
        HairlineView()
    }

    static func appearance(for preference: AppearancePreference) -> NSAppearance? {
        switch preference {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    static func timePicker(time: TimeOfDay, tag: Int, target: AnyObject, action: Selector) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = .hourMinute
        picker.isBezeled = false
        picker.isBordered = false
        picker.tag = tag
        picker.target = target
        picker.action = action
        picker.dateValue = pickerDate(for: time)
        picker.setAccessibilityLabel("Time")
        return picker
    }

    static func setTime(_ picker: NSDatePicker, _ time: TimeOfDay) {
        picker.dateValue = pickerDate(for: time)
    }

    /// January 15 never sits in a spring-forward gap, so the clock can always be represented.
    private static func pickerDate(for time: TimeOfDay) -> Date {
        var components = DateComponents()
        components.year = Calendar.current.component(.year, from: Date())
        components.month = 1
        components.day = 15
        components.hour = time.hour
        components.minute = time.minute
        components.second = 0
        return Calendar.current.date(from: components) ?? Date()
    }

    static func time(from picker: NSDatePicker) -> TimeOfDay {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: picker.dateValue)
        return TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }

    static func comboSelection(_ box: NSComboBox) -> String {
        if box.indexOfSelectedItem >= 0, box.indexOfSelectedItem < box.numberOfItems,
           let value = box.itemObjectValue(at: box.indexOfSelectedItem) as? String {
            return value
        }
        return box.stringValue
    }
}

@MainActor
final class Stack: NSStackView {
    convenience init(axis: NSUserInterfaceLayoutOrientation, spacing: CGFloat = 10, views: [NSView] = []) {
        self.init(views: views)
        orientation = axis
        self.spacing = spacing
        alignment = axis == .vertical ? .leading : .centerY
        distribution = .fill
        translatesAutoresizingMaskIntoConstraints = false
        setHuggingPriority(.defaultLow, for: .horizontal)
    }
}

extension NSView {
    func pinToEdges(of parent: NSView, inset: CGFloat = 0) {
        translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(self)
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset),
            trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset),
            topAnchor.constraint(equalTo: parent.topAnchor, constant: inset),
            bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset)
        ])
    }
}

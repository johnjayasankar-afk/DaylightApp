import AppKit
import DaylightCore

@MainActor
enum StatusIcon {
    static func image(automation: AutomationState?, kelvin: Double?) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let inset = rect.insetBy(dx: 2.1, dy: 2.1)
            let warmth = Style.kelvinColor(kelvin ?? ColorTemperature.daylightReference.kelvin)
            let muted = automation == .paused || automation == .disabled || automation == .preview
            let empty = automation == .colorWork || automation == .disabled
            let hollow = empty || automation == .paused || kelvin == nil

            let ring = NSBezierPath(ovalIn: inset)
            ring.lineWidth = 1.35
            if muted {
                ring.setLineDash([2.2, 1.6], count: 2, phase: 0)
            }

            NSColor.black.withAlphaComponent(0.62).setStroke()
            ring.stroke()
            NSColor.white.withAlphaComponent(0.42).setStroke()
            let innerRing = NSBezierPath(ovalIn: inset.insetBy(dx: 0.55, dy: 0.55))
            innerRing.lineWidth = 0.8
            if muted {
                innerRing.setLineDash([2.2, 1.6], count: 2, phase: 0)
            }
            innerRing.stroke()

            if !hollow {
                let core = inset.insetBy(dx: 2.8, dy: 2.8)
                warmth.setFill()
                NSBezierPath(ovalIn: core).fill()
                NSColor.white.withAlphaComponent(0.28).setStroke()
                let shine = NSBezierPath(ovalIn: core.insetBy(dx: 0.5, dy: 0.5))
                shine.lineWidth = 0.9
                shine.stroke()

                if automation == .automatic || automation == .override || automation == nil {
                    warmth.setStroke()
                    let rays = [
                        (CGPoint(x: rect.midX, y: rect.maxY - 0.6), CGPoint(x: rect.midX, y: rect.maxY - 2.9)),
                        (CGPoint(x: rect.minX + 0.7, y: rect.midY), CGPoint(x: rect.minX + 2.8, y: rect.midY)),
                        (CGPoint(x: rect.maxX - 0.7, y: rect.midY), CGPoint(x: rect.maxX - 2.8, y: rect.midY))
                    ]
                    for (start, end) in rays {
                        let ray = NSBezierPath()
                        ray.move(to: start)
                        ray.line(to: end)
                        ray.lineWidth = 1.15
                        ray.lineCapStyle = .round
                        ray.stroke()
                    }
                }
            } else if empty {
                warmth.withAlphaComponent(0.35).setStroke()
                let slash = NSBezierPath()
                slash.move(to: CGPoint(x: rect.minX + 4.2, y: rect.minY + 4.2))
                slash.line(to: CGPoint(x: rect.maxX - 4.2, y: rect.maxY - 4.2))
                slash.lineWidth = 1.5
                slash.lineCapStyle = .round
                slash.stroke()
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    static func title(snapshot: StatusSnapshot?, showTemperature: Bool = true, kelvin: Double? = nil) -> String {
        guard let snapshot else { return "" }
        switch snapshot.automation {
        case .disabled: return " Off"
        case .paused: return " Paused"
        case .colorWork: return " Color"
        case .preview: return " Preview"
        default:
            guard showTemperature, let kelvin else { return "" }
            return " \(Int(kelvin.rounded())) K"
        }
    }
}

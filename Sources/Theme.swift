import SwiftUI
import AppKit

enum AppAppearance: String, CaseIterable, Identifiable {
    case dark
    case light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dark: "Dark"
        case .light: "Light"
        }
    }

    var colorScheme: ColorScheme {
        switch self {
        case .dark: .dark
        case .light: .light
        }
    }
}

enum Theme {
    private static func dynamicNSColor(lightHex: String, darkHex: String, alpha: CGFloat = 1.0) -> NSColor {
        NSColor(name: nil) { appearance in
            let bestMatch = appearance.bestMatch(from: [.darkAqua, .aqua])
            let resolvedHex = bestMatch == .darkAqua ? darkHex : lightHex
            return NSColor(hex: resolvedHex, alpha: alpha)
        }
    }

    private static func dynamicColor(lightHex: String, darkHex: String, alpha: CGFloat = 1.0) -> Color {
        Color(nsColor: dynamicNSColor(lightHex: lightHex, darkHex: darkHex, alpha: alpha))
    }

    // Backgrounds
    static let nsBg = dynamicNSColor(lightHex: "F6F7FB", darkHex: "0D0D12")
    static let nsSurface = dynamicNSColor(lightHex: "ECEFF6", darkHex: "171723")
    static let nsSurfaceHover = dynamicNSColor(lightHex: "E2E7F1", darkHex: "1F1F30")
    static let nsSurfaceElevated = dynamicNSColor(lightHex: "FDFDFF", darkHex: "222236")
    static let nsOverlay = dynamicNSColor(lightHex: "F3F5FA", darkHex: "12121C")

    static let bg = Color(nsColor: nsBg)
    static let surface = Color(nsColor: nsSurface)
    static let surfaceHover = Color(nsColor: nsSurfaceHover)
    static let surfaceElevated = Color(nsColor: nsSurfaceElevated)
    static let overlay = Color(nsColor: nsOverlay)

    // Borders
    static let nsBorder = dynamicNSColor(lightHex: "D4D9E5", darkHex: "28283E")
    static let nsBorderSubtle = dynamicNSColor(lightHex: "E4E8F0", darkHex: "1E1E32")

    static let border = Color(nsColor: nsBorder)
    static let borderSubtle = Color(nsColor: nsBorderSubtle)

    // Text
    static let nsText = dynamicNSColor(lightHex: "161A24", darkHex: "E2E2EC")
    static let nsTextSecondary = dynamicNSColor(lightHex: "5E667A", darkHex: "7878A3")
    static let nsTextTertiary = dynamicNSColor(lightHex: "8991A2", darkHex: "52526B")

    static let text = Color(nsColor: nsText)
    static let textSecondary = Color(nsColor: nsTextSecondary)
    static let textTertiary = Color(nsColor: nsTextTertiary)

    // Accent (Linear purple)
    static let nsAccent = dynamicNSColor(lightHex: "5561D6", darkHex: "5E6AD2")
    static let nsAccentHover = dynamicNSColor(lightHex: "6974E6", darkHex: "7B83EB")
    static let nsAccentMuted = dynamicNSColor(lightHex: "5561D6", darkHex: "5E6AD2", alpha: 0.15)

    static let accent = Color(nsColor: nsAccent)
    static let accentHover = Color(nsColor: nsAccentHover)
    static let accentMuted = Color(nsColor: nsAccentMuted)

    // Semantic
    static let nsSuccess = dynamicNSColor(lightHex: "16A34A", darkHex: "4ADE80")
    static let nsError = dynamicNSColor(lightHex: "DC2626", darkHex: "EF4444")
    static let nsWarning = dynamicNSColor(lightHex: "D97706", darkHex: "FBBF24")
    static let nsInfo = dynamicNSColor(lightHex: "2563EB", darkHex: "60A5FA")

    static let success = Color(nsColor: nsSuccess)
    static let error = Color(nsColor: nsError)
    static let warning = Color(nsColor: nsWarning)
    static let info = Color(nsColor: nsInfo)

    // Typography
    static let monoFont = Font.system(.body, design: .monospaced)
    static let monoSmall = Font.system(.caption, design: .monospaced)
    static let headerFont = Font.system(.headline, weight: .medium)
    static let titleFont = Font.system(.title3, weight: .semibold)
    static let captionFont = Font.system(.caption, weight: .medium)

    // Dimensions
    static let cornerRadius: CGFloat = 8
    static let smallRadius: CGFloat = 5
    static let cellHeight: CGFloat = 32
    static let sidebarWidth: CGFloat = 240
    static let columnMinWidth: CGFloat = 120
    static let overlayWidth: CGFloat = 560
}

// MARK: - Font Scale

private struct FontScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    var fontScale: CGFloat {
        get { self[FontScaleKey.self] }
        set { self[FontScaleKey.self] = newValue }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}

extension NSColor {
    convenience init(hex: String, alpha: CGFloat = 1.0) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        let red = CGFloat(r) / 255
        let green = CGFloat(g) / 255
        let blue = CGFloat(b) / 255
        self.init(
            srgbRed: red,
            green: green,
            blue: blue,
            alpha: alpha
        )
    }
}

struct DriftButtonStyle: ButtonStyle {
    var isPrimary: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, weight: .medium))
            .foregroundColor(isPrimary ? .white : Theme.text)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: Theme.smallRadius)
                    .fill(isPrimary ? Theme.accent : Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.smallRadius)
                    .stroke(isPrimary ? Color.clear : Theme.border, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

struct DriftTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .font(Theme.monoFont)
            .foregroundColor(Theme.text)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: Theme.smallRadius)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.smallRadius)
                    .stroke(Theme.border, lineWidth: 1)
            )
    }
}

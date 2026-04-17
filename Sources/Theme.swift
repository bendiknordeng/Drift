import SwiftUI

enum Theme {
    // Backgrounds
    static let bg = Color(hex: "0D0D12")
    static let surface = Color(hex: "171723")
    static let surfaceHover = Color(hex: "1F1F30")
    static let surfaceElevated = Color(hex: "222236")
    static let overlay = Color(hex: "12121C")

    // Borders
    static let border = Color(hex: "28283E")
    static let borderSubtle = Color(hex: "1E1E32")

    // Text
    static let text = Color(hex: "E2E2EC")
    static let textSecondary = Color(hex: "7878A3")
    static let textTertiary = Color(hex: "52526B")

    // Accent (Linear purple)
    static let accent = Color(hex: "5E6AD2")
    static let accentHover = Color(hex: "7B83EB")
    static let accentMuted = Color(hex: "5E6AD2").opacity(0.15)

    // Semantic
    static let success = Color(hex: "4ADE80")
    static let error = Color(hex: "EF4444")
    static let warning = Color(hex: "FBBF24")
    static let info = Color(hex: "60A5FA")

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

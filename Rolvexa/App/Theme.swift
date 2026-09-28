import SwiftUI

enum Theme {
    static let gradient = LinearGradient(
        colors: [Color.indigo, Color.purple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension Color {
    /// Cross-platform card/row background. UIKit's semantic system colors (secondarySystemBackground,
    /// etc.) don't exist on macOS, so these map to the AppKit equivalents there.
    static var appCardBackground: Color {
        #if os(iOS)
        Color(.secondarySystemBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }

    static var appPageBackground: Color {
        #if os(iOS)
        Color(.systemBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    static var appSubtleFill: Color {
        #if os(iOS)
        Color(.tertiarySystemFill)
        #else
        Color(nsColor: .quaternaryLabelColor).opacity(0.3)
        #endif
    }

    static var appSeparator: Color {
        #if os(iOS)
        Color(.separator)
        #else
        Color(nsColor: .separatorColor)
        #endif
    }
}

extension ToolbarItemPlacement {
    /// `.topBarTrailing` doesn't exist on macOS; this resolves to the closest equivalent per platform.
    static var appTrailing: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .automatic
        #endif
    }
}

struct PrimaryGradientButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

extension ButtonStyle where Self == PrimaryGradientButtonStyle {
    static var primaryGradient: PrimaryGradientButtonStyle { PrimaryGradientButtonStyle() }
}

struct RoundedTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.appCardBackground))
    }
}

extension TextFieldStyle where Self == RoundedTextFieldStyle {
    static var roundedInput: RoundedTextFieldStyle { RoundedTextFieldStyle() }
}

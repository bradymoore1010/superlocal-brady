import SwiftUI

enum MailTheme {
    // The native app keeps the approved V.2 palette while using a small,
    // fixed number of translucent layers. Repeated rows and cards avoid live
    // blur effects so scrolling and keyboard navigation stay inexpensive.
    static let text = Color(red: 23 / 255, green: 32 / 255, blue: 28 / 255)
    static let secondaryText = text.opacity(0.68)
    static let mutedText = text.opacity(0.50)
    static let faintText = text.opacity(0.36)
    static let inkOnDark = Color(red: 248 / 255, green: 251 / 255, blue: 249 / 255)

    static let border = Color(red: 18 / 255, green: 55 / 255, blue: 47 / 255).opacity(0.11)
    static let strongBorder = Color(red: 18 / 255, green: 55 / 255, blue: 47 / 255).opacity(0.17)
    static let glassBorder = Color.white.opacity(0.42)
    static let glassHighlight = Color.white.opacity(0.30)

    static let windowSurface = Color(red: 213 / 255, green: 236 / 255, blue: 224 / 255).opacity(0.64)
    static let sidebar = Color(red: 164 / 255, green: 218 / 255, blue: 212 / 255).opacity(0.24)
    static let structureSurface = Color(red: 211 / 255, green: 247 / 255, blue: 239 / 255).opacity(0.30)
    static let structureBrightSurface = Color(red: 225 / 255, green: 255 / 255, blue: 248 / 255).opacity(0.38)
    static let messageSurface = Color(red: 187 / 255, green: 227 / 255, blue: 209 / 255).opacity(0.36)
    static let cardSurface = Color(red: 239 / 255, green: 250 / 255, blue: 246 / 255).opacity(0.66)
    static let modalSurface = Color(red: 239 / 255, green: 248 / 255, blue: 244 / 255).opacity(0.90)
    static let selectedSurface = Color(red: 143 / 255, green: 184 / 255, blue: 173 / 255).opacity(0.44)
    static let activeNavigation = selectedSurface
    static let hoverSurface = Color.white.opacity(0.28)
    static let controlSurface = Color(red: 246 / 255, green: 252 / 255, blue: 248 / 255).opacity(0.74)
    static let controlHoverSurface = Color.white.opacity(0.84)
    static let controlPressedSurface = Color(red: 211 / 255, green: 229 / 255, blue: 222 / 255).opacity(0.74)
    static let darkControl = Color(red: 23 / 255, green: 32 / 255, blue: 28 / 255)
    static let darkControlPressed = Color(red: 14 / 255, green: 21 / 255, blue: 18 / 255)

    // Compatibility names used throughout the established production views.
    static let secondarySurface = structureSurface
    static let white = cardSurface

    static var desktopBackdrop: some View {
        ZStack {
            Color(red: 10 / 255, green: 78 / 255, blue: 67 / 255)
            LinearGradient(
                colors: [
                    Color(red: 222 / 255, green: 205 / 255, blue: 126 / 255).opacity(0.72),
                    Color(red: 28 / 255, green: 116 / 255, blue: 96 / 255).opacity(0.44),
                    Color(red: 3 / 255, green: 53 / 255, blue: 48 / 255).opacity(0.94)
                ],
                startPoint: .top,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color(red: 246 / 255, green: 228 / 255, blue: 149 / 255).opacity(0.42), .clear],
                center: UnitPoint(x: 0.58, y: 0.02),
                startRadius: 12,
                endRadius: 720
            )
            RadialGradient(
                colors: [Color(red: 12 / 255, green: 91 / 255, blue: 79 / 255).opacity(0.50), .clear],
                center: .bottomLeading,
                startRadius: 24,
                endRadius: 760
            )
        }
        .ignoresSafeArea()
    }

    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MailTheme.font(13, weight: .medium))
            .foregroundStyle(MailTheme.inkOnDark)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(configuration.isPressed ? MailTheme.darkControlPressed : MailTheme.darkControl)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            }
            .shadow(color: MailTheme.darkControl.opacity(0.18), radius: 5, x: 0, y: 3)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MailTheme.font(13, weight: .medium))
            .foregroundStyle(MailTheme.text)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(configuration.isPressed ? MailTheme.controlPressedSurface : MailTheme.controlSurface)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(MailTheme.glassBorder, lineWidth: 1)
            }
            .shadow(color: MailTheme.darkControl.opacity(0.07), radius: 4, x: 0, y: 2)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct ShortcutChip: View {
    let text: String
    var dark = false

    var body: some View {
        Text(text)
            .font(MailTheme.font(12))
            .foregroundStyle(dark ? MailTheme.inkOnDark.opacity(0.82) : MailTheme.secondaryText)
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(dark ? Color.white.opacity(0.08) : MailTheme.controlSurface)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(dark ? Color.white.opacity(0.18) : MailTheme.border, lineWidth: 1)
            }
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(MailTheme.border)
            .frame(height: 1)
    }
}

private struct FloatingGlassSurface: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(MailTheme.modalSurface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(MailTheme.glassBorder, lineWidth: 1)
            }
            .shadow(color: MailTheme.darkControl.opacity(0.28), radius: 30, x: 0, y: 18)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(MailTheme.glassHighlight)
                    .frame(height: 1)
                    .padding(.horizontal, cornerRadius)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    func floatingGlassSurface(cornerRadius: CGFloat = 18) -> some View {
        modifier(FloatingGlassSurface(cornerRadius: cornerRadius))
    }
}

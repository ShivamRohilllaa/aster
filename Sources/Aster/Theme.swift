import AppKit
import SwiftUI
import AsterCore

enum AppAppearance: String, CaseIterable, Identifiable {
    case dark, light

    static let preferenceKey = "aster.appearance"
    var id: String { rawValue }
    var title: String { self == .dark ? "Dark" : "Light" }
    var symbol: String { self == .dark ? "moon.stars" : "sun.max" }
    var colorScheme: ColorScheme { self == .dark ? .dark : .light }
    var nativeAppearance: NSAppearance.Name { self == .dark ? .darkAqua : .aqua }
}

enum Theme {
    static let background = adaptive(dark: 0x101117, light: 0xF5F6FA)
    static let sidebar = adaptive(dark: 0x15161E, light: 0xEEF0F6)
    static let panel = adaptive(dark: 0x191B25, light: 0xFFFFFF)
    static let elevated = adaptive(dark: 0x21232F, light: 0xE8EAF2)
    static let border = adaptive(dark: 0xFFFFFF, light: 0x333D5A, darkAlpha: 0.075, lightAlpha: 0.14)
    static let text = adaptive(dark: 0xF4F3FA, light: 0x1A2033)
    static let secondary = adaptive(dark: 0x999BAE, light: 0x555E73)
    static let muted = adaptive(dark: 0x65697E, light: 0x687187)
    static let accent = adaptive(dark: 0xB4A2FF, light: 0x6B4BCE)
    static let onAccent = adaptive(dark: 0x1C1637, light: 0xFFFFFF)
    static let mint = adaptive(dark: 0x83D7BD, light: 0x227461)
    static let warning = adaptive(dark: 0xD7BA86, light: 0x8B5D18)
    static let blue = adaptive(dark: 0x8EAEE8, light: 0x4265A4)
    static let quietButton = adaptive(dark: 0xFFFFFF, light: 0x333D5A, darkAlpha: 0.045, lightAlpha: 0.055)
    static let quietButtonPressed = adaptive(dark: 0xFFFFFF, light: 0x333D5A, darkAlpha: 0.09, lightAlpha: 0.10)

    /// Native dynamic colors follow the window's appearance, including sheets and controls.
    static func adaptive(dark: UInt32, light: UInt32, darkAlpha: CGFloat = 1, lightAlpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255,
                           alpha: isDark ? darkAlpha : lightAlpha)
        })
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
}

extension FileCategory {
    var tint: Color {
        switch self {
        case .applications: return Theme.adaptive(dark: 0xDA99B4, light: 0xA24774)
        case .developer: return Theme.adaptive(dark: 0xB2A0EE, light: 0x6D50B8)
        case .documents: return Theme.blue
        case .media: return Theme.adaptive(dark: 0x81C7BE, light: 0x287971)
        case .archives: return Theme.warning
        case .other: return Theme.adaptive(dark: 0x9099AE, light: 0x5D6D89)
        }
    }
    var symbol: String {
        switch self {
        case .applications: return "square.stack.3d.up"
        case .developer: return "curlybraces"
        case .documents: return "doc.text"
        case .media: return "photo.on.rectangle.angled"
        case .archives: return "shippingbox"
        case .other: return "square.grid.2x2"
        }
    }
}

func sizeString(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

func relativePath(_ node: DiskNode, root: DiskNode) -> String {
    let prefix = root.url.path == "/" ? "/" : root.url.path + "/"
    return node.url.path.hasPrefix(prefix) ? String(node.url.path.dropFirst(prefix.count)) : node.url.path
}

struct Panel<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder let content: Content
    var body: some View {
        content.padding(padding)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border, lineWidth: 1))
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.text.opacity(configuration.isPressed ? 0.6 : 0.9))
            .padding(.horizontal, 13).padding(.vertical, 9)
            .background(configuration.isPressed ? Theme.quietButtonPressed : Theme.quietButton, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
    }
}

struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 16).padding(.vertical, 11)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 9))
    }
}

struct SectionEyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(1.7).foregroundStyle(Theme.muted)
    }
}

struct AsterMark: View {
    var size: CGFloat = 34
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.29).fill(Theme.accent.opacity(0.12))
            Image(systemName: "sparkle").font(.system(size: size * 0.68, weight: .light)).foregroundStyle(Theme.accent)
        }.frame(width: size, height: size)
    }
}

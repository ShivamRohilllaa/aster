import SwiftUI

struct AppearanceSettingsView: View {
    @AppStorage(AppAppearance.preferenceKey) private var appearance: AppAppearance = .dark

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 13) {
                AsterMark(size: 42)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Appearance").font(.system(size: 23, weight: .semibold, design: .rounded))
                    Text("A different light. The same clarity.")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                }
            }

            HStack(spacing: 16) {
                ForEach(AppAppearance.allCases) { option in
                    appearanceCard(option)
                }
            }

            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "checkmark.circle").foregroundStyle(Theme.mint)
                Text("Dark is the default. Your choice is saved on this Mac and applies to every view.")
                    .foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }.font(.system(size: 11)).lineSpacing(3)
        }
        .padding(28)
        .frame(width: 500)
        .background(Theme.background)
        .foregroundStyle(Theme.text)
        .tint(Theme.accent)
    }

    private func appearanceCard(_ option: AppAppearance) -> some View {
        let selected = appearance == option
        return Button { appearance = option } label: {
            VStack(alignment: .leading, spacing: 14) {
                palettePreview(option)
                HStack(spacing: 8) {
                    Image(systemName: option.symbol).font(.system(size: 13))
                    Text(option.title).font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Theme.accent : Theme.muted)
                }.foregroundStyle(Theme.text)
            }
            .padding(13)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(selected ? Theme.accent : Theme.border, lineWidth: selected ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Use \(option.title) appearance")
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier("appearance-\(option.rawValue)")
    }

    private func palettePreview(_ option: AppAppearance) -> some View {
        let dark = option == .dark
        let accent = Color(hex: dark ? 0xB4A2FF : 0x6B4BCE)
        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 9) {
                Image(systemName: "sparkle").foregroundStyle(accent).font(.system(size: 16))
                RoundedRectangle(cornerRadius: 3).fill(accent.opacity(0.3)).frame(height: 6)
                RoundedRectangle(cornerRadius: 3).fill(accent.opacity(0.15)).frame(height: 6)
                Spacer(minLength: 0)
            }
            .padding(11).frame(width: 54)
            .background(Color(hex: dark ? 0x15161E : 0xEEF0F6))

            VStack(alignment: .leading, spacing: 9) {
                RoundedRectangle(cornerRadius: 3).fill(accent.opacity(0.65)).frame(width: 45, height: 6)
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 5).fill(accent.opacity(dark ? 0.23 : 0.13))
                    RoundedRectangle(cornerRadius: 5).fill(Color(hex: dark ? 0x83D7BD : 0x227461).opacity(0.18))
                }
                RoundedRectangle(cornerRadius: 3).fill(accent.opacity(0.1)).frame(height: 7)
            }.padding(11)
        }
        .frame(height: 102)
        .background(Color(hex: dark ? 0x101117 : 0xF5F6FA))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

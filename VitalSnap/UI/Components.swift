import SwiftUI
import VitalSnapCore

struct PrimaryButton: View {
    var title: String
    var systemImage: String?
    var isEnabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isEnabled ? Theme.green : Theme.green.opacity(0.35), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

struct WarningBanner: View {
    var message: String
    var tone: Tone = .caution

    enum Tone {
        case caution
        case blocking
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: tone == .blocking ? "exclamationmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(tone == .blocking ? Theme.coral : Theme.caution)
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            tone == .blocking ? Theme.coral.opacity(0.12) : Theme.cautionBackground,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }
}

struct ActionCard: View {
    var title: String
    var subtitle: String
    var systemImage: String
    var tint: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 52, height: 52)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondary)
            }
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
    }
}

struct ReadingValueField: View {
    var placeholder: String
    @Binding var text: String
    var accessibilityLabel: String

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(.decimalPad)
            .font(.system(size: 56, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.ink)
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.4)
            .accessibilityLabel(accessibilityLabel)
    }
}

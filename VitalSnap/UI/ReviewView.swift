import SwiftUI
import UIKit
import VitalSnapCore

struct ReviewView: View {
    @Binding var draft: ReadingDraft
    var lines: [RecognizedLine]
    var image: UIImage?
    var healthAvailable: Bool
    var isSaving: Bool
    var saveError: String?
    var onSave: () -> Void

    @FocusState private var focused: Bool

    private var validation: FieldValidation {
        ReadingValidator.validate(draft)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 160)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .allowsHitTesting(false)
                        .accessibilityLabel("Photo of the display")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Check the reading")
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    Text("Save only if these numbers match the display.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                }

                Picker("Reading type", selection: $draft.kind) {
                    ForEach(ReadingKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("review.kind")

                if !draft.note.isEmpty {
                    Text(draft.note)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                }

                ForEach(draft.warnings, id: \.self) { warning in
                    WarningBanner(message: warning)
                }
                if let caution = validation.caution {
                    WarningBanner(message: caution)
                }
                if let blocking = validation.blockingMessage {
                    WarningBanner(message: blocking, tone: .blocking)
                }
                if let saveError {
                    WarningBanner(message: saveError, tone: .blocking)
                }

                fields
                    .padding(18)
                    .frame(maxWidth: .infinity)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                DatePicker(
                    "When",
                    selection: $draft.capturedAt,
                    in: ...Date(),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .font(.body)
                .foregroundStyle(Theme.ink)

                DisclosureGroup("Text seen on the display") {
                    Text(draft.rawText.isEmpty ? "No text found." : draft.rawText)
                        .font(.callout.monospaced())
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                        .textSelection(.enabled)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)

                Text("VitalSnap saves what you confirm. It does not decide whether a reading is healthy.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
            }
            .padding(20)
        }
        .background(Theme.paper)
        .navigationTitle(draft.kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                PrimaryButton(
                    title: isSaving ? "Saving…" : (healthAvailable ? "Save to Apple Health" : "Save on this iPhone"),
                    systemImage: healthAvailable ? "heart.fill" : "iphone",
                    isEnabled: validation.canSave && !isSaving,
                    action: onSave
                )
                .accessibilityIdentifier("review.save")
                Text(healthAvailable
                     ? "Apple Health will ask permission the first time you save."
                     : "Apple Health is not available on this device. The reading stays in VitalSnap.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .background(Theme.paper.opacity(0.96))
            .contentShape(Rectangle())
        }
        .onChange(of: draft.kind) { previous, current in
            guard previous != current, !lines.isEmpty else { return }
            let capturedAt = draft.capturedAt
            draft = ReadingDraft.make(kind: current, lines: lines, capturedAt: capturedAt)
        }
    }

    /// Converts the typed weight when the unit changes, without reacting to a full re-parse.
    private var weightUnitBinding: Binding<MassUnit> {
        Binding(
            get: { draft.weightUnit },
            set: { newUnit in
                let previous = draft.weightUnit
                guard previous != newUnit else { return }
                if let value = draft.weightValue {
                    draft.weightText = ReadingFormat.weight(previous.converted(value, to: newUnit))
                }
                draft.weightUnit = newUnit
                draft.warnings.removeAll { $0.localizedCaseInsensitiveContains("unit") }
            }
        )
    }

    @ViewBuilder
    private var fields: some View {
        switch draft.kind {
        case .weight:
            VStack(spacing: 8) {
                ReadingValueField(placeholder: "0.0", text: $draft.weightText, accessibilityLabel: "Weight")
                    .focused($focused)
                Picker("Unit", selection: weightUnitBinding) {
                    ForEach(MassUnit.allCases) { unit in
                        Text(unit.symbol).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
            }
        case .bloodPressure:
            VStack(spacing: 14) {
                if draft.systolicText.isEmpty && draft.diastolicText.isEmpty {
                    Text("Type the top number (systolic) and the lower number (diastolic). Pulse can stay blank.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    ReadingValueField(placeholder: "SYS", text: $draft.systolicText, accessibilityLabel: "Systolic")
                        .focused($focused)
                    Text("/")
                        .font(.system(size: 40, weight: .light, design: .rounded))
                        .foregroundStyle(Theme.secondary)
                    ReadingValueField(placeholder: "DIA", text: $draft.diastolicText, accessibilityLabel: "Diastolic")
                }
                Text("mmHg")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.secondary)
                HStack {
                    Text("Pulse")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    TextField("Optional", text: $draft.pulseText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .font(.title3.weight(.medium))
                        .accessibilityLabel("Pulse, optional")
                    Text("bpm")
                        .foregroundStyle(Theme.secondary)
                }
            }
        }
    }
}

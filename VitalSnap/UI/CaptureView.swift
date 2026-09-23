import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import VitalSnapCore

struct CaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @StateObject private var camera = CameraSession()

    let kind: ReadingKind

    @State private var stage: Stage = .camera
    @State private var isWorking = false
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var captureError: String?

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .camera:
                    cameraScreen
                case .review(let image, let lines, _):
                    reviewScreen(image: image, lines: lines)
                case .saved(let reading):
                    savedScreen(reading)
                }
            }
            .id(stageToken)
        }
        .onAppear {
            if case .camera = stage {
                camera.prepare()
            }
        }
        .onDisappear { camera.stop() }
    }

    /// Drops the camera preview when leaving that stage so its layer cannot keep eating taps.
    private var stageToken: String {
        switch stage {
        case .camera:
            return "camera"
        case .review:
            return "review"
        case .saved:
            return "saved"
        }
    }

    private var cameraScreen: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch camera.access {
            case .ready:
                CameraPreview(session: camera.session)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                guide
            case .denied:
                permissionMessage(
                    title: "Camera access is off",
                    message: "VitalSnap needs the camera to photograph a scale or cuff. You can also choose an existing photo or type the numbers.",
                    showsSettings: true
                )
            case .unavailable:
                permissionMessage(
                    title: "No camera on this device",
                    message: "The simulator has no camera, and Apple Health writes need a real iPhone. Choose a photo, try a sample reading, or type the numbers.",
                    showsSettings: false
                )
            case .unknown:
                ProgressView("Waiting for camera access\u2026")
                    .tint(.white)
                    .foregroundStyle(.white)
            }

            if isWorking {
                Color.black.opacity(0.45).ignoresSafeArea()
                ProgressView("Reading the display\u2026")
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .safeAreaInset(edge: .bottom) {
            controls
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { dismiss() }
                    .accessibilityIdentifier("capture.close")
            }
        }
    }

    private var guide: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(.white.opacity(0.85), lineWidth: 2)
            .padding(.horizontal, 28)
            .padding(.vertical, 120)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var controls: some View {
        VStack(spacing: 14) {
            if let captureError {
                Text(captureError)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
            }
            Text("Fill the frame with the digits. Tilt the phone so the screen does not glare. Flash stays off.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.86))
                .multilineTextAlignment(.center)
            HStack(alignment: .center) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Image(systemName: "photo")
                        .font(.title3)
                        .frame(width: 52, height: 52)
                        .background(.white.opacity(0.16), in: Circle())
                }
                .accessibilityLabel("Choose a photo")
                .disabled(isWorking)

                Spacer()

                Button {
                    Task { await capture() }
                } label: {
                    Circle()
                        .strokeBorder(.white, lineWidth: 4)
                        .frame(width: 76, height: 76)
                        .overlay(Circle().fill(.white).padding(7))
                }
                .buttonStyle(.plain)
                .disabled(isWorking || camera.access != .ready)
                .opacity(camera.access == .ready ? 1 : 0.35)
                .accessibilityLabel("Capture photo")
                .accessibilityIdentifier("capture.shutter")

                Spacer()

                Button {
                    openSample()
                } label: {
                    Text("Sample")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 72, height: 52)
                        .background(.white.opacity(0.16), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isWorking)
                .accessibilityLabel("Use a sample reading")
                .accessibilityIdentifier("capture.sample")
            }
            .foregroundStyle(.white)

            Button("Enter numbers manually") {
                openManual()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .disabled(isWorking)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Color.black.opacity(0.55))
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await loadPhoto(item) }
        }
    }

    private func permissionMessage(title: String, message: String, showsSettings: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(message)
                .font(.body)
                .foregroundStyle(.white.opacity(0.8))
            if showsSettings {
                Button("Open Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.green)
            }
        }
        .foregroundStyle(.white)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func reviewScreen(image: UIImage?, lines: [RecognizedLine]) -> some View {
        ReviewView(
            draft: reviewDraft,
            lines: lines,
            image: image,
            healthAvailable: model.health.isAvailable,
            isSaving: isSaving,
            saveError: saveError,
            onSave: { Task { await save() } }
        )
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Retake", action: retake)
                    .accessibilityIdentifier("review.retake")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Close") { dismiss() }
                    .accessibilityIdentifier("review.close")
            }
        }
    }

    private var reviewDraft: Binding<ReadingDraft> {
        Binding(
            get: {
                if case .review(_, _, let draft) = stage { return draft }
                return ReadingDraft(kind: kind, capturedAt: Date())
            },
            set: { newValue in
                if case .review(let image, let lines, _) = stage {
                    stage = .review(image: image, lines: lines, draft: newValue)
                }
            }
        )
    }

    private func savedScreen(_ reading: LoggedReading) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Theme.green)
            Text(reading.summary)
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            Text(reading.detail)
                .font(.title3)
                .foregroundStyle(Theme.secondary)
            Text(reading.note)
                .font(.body)
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
            Spacer()
            if !reading.savedToHealth && model.health.isAvailable {
                PrimaryButton(title: isSaving ? "Saving\u2026" : "Try Apple Health again", isEnabled: !isSaving) {
                    Task { await retryHealth(reading) }
                }
            }
            Button("Scan another") { retake() }
                .font(.headline)
                .foregroundStyle(Theme.green)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper)
        .navigationTitle("Saved")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .accessibilityIdentifier("capture.done")
            }
        }
    }

    @MainActor
    private func capture() async {
        captureError = nil
        isWorking = true
        defer { isWorking = false }
        do {
            let image = try await camera.capture()
            await recognize(image)
        } catch {
            captureError = error.localizedDescription
        }
    }

    @MainActor
    private func loadPhoto(_ item: PhotosPickerItem) async {
        isWorking = true
        defer { isWorking = false }
        do {
            guard let picked = try await item.loadTransferable(type: PickedPhoto.self),
                  let image = UIImage(data: picked.data) else {
                captureError = "That photo could not be opened."
                return
            }
            await recognize(image)
        } catch {
            captureError = "That photo could not be opened."
        }
    }

    @MainActor
    private func recognize(_ image: UIImage) async {
        isWorking = true
        defer { isWorking = false }
        camera.stop()
        let prepared = image.preparedForOCR()
        do {
            let lines = try await TextRecognizer.recognizeBest(prepared, kind: kind)
            let draft = ReadingDraft.make(kind: kind, lines: lines, capturedAt: Date())
            stage = .review(image: prepared, lines: lines, draft: draft)
            UINotificationFeedbackGenerator().notificationOccurred(draft.summary == nil ? .warning : .success)
        } catch {
            var draft = ReadingDraft.make(kind: kind, lines: [], capturedAt: Date())
            draft.warnings = [error.localizedDescription]
            stage = .review(image: prepared, lines: [], draft: draft)
        }
    }

    private func openSample() {
        camera.stop()
        let lines = kind == .weight ? SampleDisplay.scale : SampleDisplay.cuff
        let draft = ReadingDraft.make(kind: kind, lines: lines, capturedAt: Date())
        stage = .review(image: nil, lines: lines, draft: draft)
    }

    private func openManual() {
        camera.stop()
        let draft = ReadingDraft.make(kind: kind, lines: [], capturedAt: Date())
        stage = .review(image: nil, lines: [], draft: draft)
    }

    private func retake() {
        saveError = nil
        captureError = nil
        stage = .camera
        camera.prepare()
    }

    @MainActor
    private func save() async {
        guard case .review(_, _, let draft) = stage else { return }
        guard ReadingValidator.validate(draft).canSave else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        let result = await model.health.save(draft)
        switch result {
        case .saved:
            let entry = model.log.add(from: draft, savedToHealth: true, note: "Saved to Apple Health.")
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            stage = .saved(entry)
        case .unavailable:
            let entry = model.log.add(
                from: draft,
                savedToHealth: false,
                note: "Saved on this iPhone. Apple Health is only available on an iPhone."
            )
            stage = .saved(entry)
        case .denied:
            let entry = model.log.add(
                from: draft,
                savedToHealth: false,
                note: "Saved on this iPhone. Apple Health access is off. You can allow it in Settings, then try again."
            )
            stage = .saved(entry)
        case .failed(let message):
            saveError = message
        }
    }

    @MainActor
    private func retryHealth(_ reading: LoggedReading) async {
        let draft = draft(from: reading)
        isSaving = true
        defer { isSaving = false }
        let result = await model.health.save(draft)
        if result == .saved {
            model.log.markSavedToHealth(reading.id)
            var updated = reading
            updated.savedToHealth = true
            updated.note = "Saved to Apple Health."
            stage = .saved(updated)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else if case .failed(let message) = result {
            var updated = reading
            updated.note = message
            stage = .saved(updated)
        }
    }

    private func draft(from reading: LoggedReading) -> ReadingDraft {
        ReadingDraft(
            kind: reading.kind,
            weightText: reading.weightValue.map(ReadingFormat.weight) ?? "",
            weightUnit: reading.weightUnit ?? .pounds,
            systolicText: reading.systolic.map(ReadingFormat.whole) ?? "",
            diastolicText: reading.diastolic.map(ReadingFormat.whole) ?? "",
            pulseText: reading.pulse.map(ReadingFormat.whole) ?? "",
            capturedAt: reading.capturedAt
        )
    }
}

private enum Stage {
    case camera
    case review(image: UIImage?, lines: [RecognizedLine], draft: ReadingDraft)
    case saved(LoggedReading)
}

private struct PickedPhoto: Transferable {
    var data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            PickedPhoto(data: data)
        }
    }
}

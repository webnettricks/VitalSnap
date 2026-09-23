import AVFoundation
import UIKit

enum CameraAccess: Equatable {
    case unknown
    case ready
    case denied
    case unavailable
}

enum CameraError: LocalizedError {
    case unavailable
    case noPhoto

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "The camera is not available."
        case .noPhoto:
            return "The photo did not come through. Try again."
        }
    }
}

final class CameraSession: NSObject, ObservableObject {
    let session = AVCaptureSession()
    @Published private(set) var access: CameraAccess = .unknown

    private let photoOutput = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "com.webnettricks.vitalsnap.camera")
    private var continuation: CheckedContinuation<UIImage, Error>?
    private var isConfigured = false

    func prepare() {
        guard AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil else {
            access = .unavailable
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            access = .ready
            start()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.access = granted ? .ready : .denied
                    if granted { self.start() }
                }
            }
        case .denied, .restricted:
            access = .denied
        @unknown default:
            access = .denied
        }
    }

    func start() {
        queue.async { [weak self] in
            self?.configureIfNeeded()
            guard let self, self.isConfigured, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func capture() async throws -> UIImage {
        guard access == .ready else { throw CameraError.unavailable }
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: CameraError.unavailable)
                    return
                }
                guard self.isConfigured else {
                    continuation.resume(throwing: CameraError.unavailable)
                    return
                }
                if let existing = self.continuation {
                    existing.resume(throwing: CameraError.unavailable)
                }
                let settings = AVCapturePhotoSettings()
                if self.photoOutput.supportedFlashModes.contains(.off) {
                    settings.flashMode = .off
                }
                if let connection = self.photoOutput.connection(with: .video) {
                    Self.applyPortrait(connection)
                }
                self.continuation = continuation
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        session.beginConfiguration()
        session.sessionPreset = .photo
        defer { session.commitConfiguration() }

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input),
            session.canAddOutput(photoOutput)
        else {
            DispatchQueue.main.async { self.access = .unavailable }
            return
        }
        session.addInput(input)
        session.addOutput(photoOutput)
        if let connection = photoOutput.connection(with: .video) {
            Self.applyPortrait(connection)
        }
        isConfigured = true
    }

    fileprivate static func applyPortrait(_ connection: AVCaptureConnection) {
        let portrait: CGFloat = 90
        if connection.isVideoRotationAngleSupported(portrait) {
            connection.videoRotationAngle = portrait
        }
    }
}

extension CameraSession: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            let continuation = self.continuation
            self.continuation = nil
            if let error {
                continuation?.resume(throwing: error)
                return
            }
            guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
                continuation?.resume(throwing: CameraError.noPhoto)
                return
            }
            continuation?.resume(returning: image)
        }
    }
}

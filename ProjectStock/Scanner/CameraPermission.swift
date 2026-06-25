import Foundation
import AVFoundation
import Combine

/// Camera authorization state, surfaced to the UI with guidance (spec §8, §14).
enum CameraAuthorization: Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted
    case unavailable   // no camera hardware (e.g. some simulators)

    var canScan: Bool { self == .authorized }
}

final class CameraPermission: ObservableObject {

    @Published private(set) var status: CameraAuthorization

    init() {
        if AppConfig.isUITesting {
            // UI tests run without a real camera; treat as authorized so the
            // mock scanner is reachable.
            status = .authorized
            return
        }
        #if targetEnvironment(simulator)
        // Simulators generally have no capture device.
        status = Self.map(AVCaptureDevice.authorizationStatus(for: .video))
        #else
        status = Self.map(AVCaptureDevice.authorizationStatus(for: .video))
        #endif
    }

    func refresh() {
        guard !AppConfig.isUITesting else { return }
        status = Self.map(AVCaptureDevice.authorizationStatus(for: .video))
    }

    func request() {
        guard !AppConfig.isUITesting else { status = .authorized; return }
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                self?.status = granted ? .authorized : .denied
            }
        }
    }

    private static func map(_ status: AVAuthorizationStatus) -> CameraAuthorization {
        switch status {
        case .notDetermined: return .notDetermined
        case .authorized:    return .authorized
        case .denied:        return .denied
        case .restricted:    return .restricted
        @unknown default:    return .denied
        }
    }
}

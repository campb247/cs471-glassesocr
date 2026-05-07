// filename: wearablesviewmodel.swift
// course: cs 471
// authors: kaden campbell, lundon dotson, kevin davis

import SwiftUI
import Combine
import MWDATCore

/// owns mwdat sdk registration state and device discovery
/// top level view model: created once in mainappview and passed down
/// streamviewmodel does not own this since multiple screens need access
@MainActor
class WearablesViewModel: ObservableObject {

    // MARK: published state

    // sdk's registration lifecycle: unavailable, registering, registered, etc
    @Published var registrationState: RegistrationState = .unavailable
    // true when sdk reports at least one paired and active device
    @Published var hasActiveDevice: Bool = false
    // mwdat camera permission status (separate from oauth registration)
    @Published var cameraPermissionGranted: Bool = false
    // surface registration or permission errors to ui
    @Published var errorMessage: String?

    // autodeviceselector picks best available device automatically
    // passed into streamviewmodel so stream session knows which glasses to use
    let deviceSelector = AutoDeviceSelector(wearables: Wearables.shared)

    // MARK: init

    init() {
        // log devices visible at init time
        // (helps debug "no devices visible" issues during demo)
        print("[MWDAT] Devices at init: \(Wearables.shared.devices)")
        observeRegistration()
        observeDevice()
        observeAllDevices()
        checkCameraPermission()
    }

    // MARK: camera permission

    /// queries current camera permission status without prompting
    /// sets cameraPermissionGranted based on result
    /// failure (e.g. sdk not initialized) defaults to false
    func checkCameraPermission() {
        Task {
            do {
                let status = try await Wearables.shared.checkPermissionStatus(.camera)
                cameraPermissionGranted = (status == .granted)
            } catch {
                cameraPermissionGranted = false
            }
        }
    }

    /// triggers camera permission request via meta ai
    /// opens consent dialog inside meta ai app
    /// callback returns granted, denied, or restricted
    func requestCameraPermission() {
        Task {
            do {
                let status = try await Wearables.shared.requestPermission(.camera)
                print("[MWDAT] Camera permission status: \(status)")
                cameraPermissionGranted = (status == .granted)
                if status == .denied {
                    errorMessage = "Camera permission denied in Meta AI."
                }
            } catch {
                print("[MWDAT] Camera permission error: \(error)")
                errorMessage = "Permission request failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: registration

    /// initiates oauth registration flow with meta ai
    /// sdk opens meta ai app deep link
    /// flow completes asynchronously via .onOpenURL callback in mainappview
    /// (see handleURL below)
    func register() {
        Task {
            do {
                print("[MWDAT] Starting registration...")
                try await Wearables.shared.startRegistration()
                print("[MWDAT] startRegistration() returned (waiting for callback URL)")
            } catch {
                print("[MWDAT] Registration error: \(error)")
                errorMessage = "Registration failed: \(error.localizedDescription)"
            }
        }
    }

    /// reverses registration, disconnects glasses
    /// returns user to unregistered state
    func unregister() {
        Task {
            do {
                try await Wearables.shared.startUnregistration()
            } catch {
                errorMessage = "Unregistration failed: \(error.localizedDescription)"
            }
        }
    }

    /// handles deep link callback from meta ai during oauth handshake
    /// must be called from .onOpenURL in scene root
    /// without this hook, registration cannot complete since sdk
    /// never receives the post consent token
    func handleURL(_ url: URL) {
        print("[MWDAT] onOpenURL fired with: \(url)")
        Task {
            do {
                let handled = try await Wearables.shared.handleUrl(url)
                print("[MWDAT] handleUrl result: \(handled)")
            } catch {
                print("[MWDAT] handleUrl error: \(error)")
                errorMessage = "URL handling failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: private observation

    /// streams updates of all visible devices
    /// (logged for debugging; not surfaced to ui)
    private func observeAllDevices() {
        Task {
            for await devices in Wearables.shared.devicesStream() {
                print("[MWDAT] devices visible to SDK: \(devices)")
            }
        }
    }

    /// streams registration state changes
    /// updates published property on every transition
    private func observeRegistration() {
        Task {
            for await state in Wearables.shared.registrationStateStream() {
                self.registrationState = state
            }
        }
    }

    /// streams active device changes from selector
    /// hasActiveDevice flips true when a device is connected and ready
    private func observeDevice() {
        Task {
            for await device in deviceSelector.activeDeviceStream() {
                self.hasActiveDevice = device != nil
            }
        }
    }
}

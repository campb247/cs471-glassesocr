// filename: permissionview.swift
// course: cs 471
// authors: kaden campbell, lundon dotson, kevin davis
// date: may 7 2026

import SwiftUI

/// intermediate screen between registration and streaming
/// shown only when user is registered but has not yet granted
/// camera permission inside meta ai
/// camera permission is separate from oauth registration in mwdat sdk
struct PermissionView: View {

    @ObservedObject var wearablesVM: WearablesViewModel

    var body: some View {
        ZStack {
            Theme.surface.ignoresSafeArea()

            VStack(spacing: 28) {

                Spacer()

                // matches registrationview logo style
                // (camera icon instead of glasses)
                ZStack {
                    Circle()
                        .fill(Theme.primaryLight.opacity(0.4))
                        .frame(width: 128, height: 128)
                    Image(systemName: "camera.fill")
                        .font(.system(size: 50, weight: .light))
                        .foregroundStyle(Theme.primaryDark)
                }

                VStack(spacing: 10) {
                    Text("Camera Access Required")
                        .font(Theme.display(28, weight: .semibold))
                        .foregroundStyle(Theme.primaryDark)
                        .multilineTextAlignment(.center)
                    Text("Allow GlassesOCR to access\nyour glasses camera in Meta AI.")
                        .font(Theme.mono(14))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(spacing: 14) {
                    // requests camera permission via mwdat sdk
                    // sdk routes through meta ai consent flow
                    Button {
                        wearablesVM.requestCameraPermission()
                    } label: {
                        Text("Grant Camera Access")
                            .themedPrimaryButton()
                    }
                    .buttonStyle(.plain)

                    if let error = wearablesVM.errorMessage {
                        Text(error)
                            .font(Theme.mono(12))
                            .foregroundStyle(Theme.danger)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .padding(.horizontal, 32)

                Spacer()
            }
        }
    }
}

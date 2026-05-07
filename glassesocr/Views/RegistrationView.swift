// filename: registrationview.swift
// course: cs 471
// authors: kaden campbell, lundon dotson, kevin davis
// date: may 7 2026

import SwiftUI
import MWDATCore

/// shown before app is linked to meta ai
/// tapping connect glasses kicks off oauth flow via wearables sdk
/// also exposes test mode entry point so demo works without glasses
struct RegistrationView: View {

    // shared registration state and actions
    @ObservedObject var wearablesVM: WearablesViewModel

    // controls presentation of test mode sheet
    @State private var showTestMode = false

    var body: some View {
        ZStack {
            // app surface background fills entire screen
            Theme.surface.ignoresSafeArea()

            VStack(spacing: 28) {

                Spacer()

                // logo mark: glasses icon over tinted circle
                ZStack {
                    Circle()
                        .fill(Theme.primaryLight.opacity(0.4))
                        .frame(width: 128, height: 128)
                    Image(systemName: "eyeglasses")
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(Theme.primaryDark)
                }

                // title and subtitle stack
                VStack(spacing: 10) {
                    Text("Glasses OCR")
                        .font(Theme.display(38, weight: .semibold))
                        .foregroundStyle(Theme.primaryDark)
                    Text("Wearable text recognition\nfor the visually impaired")
                        .font(Theme.mono(14))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // action stack: progress / button / error / skip
                VStack(spacing: 14) {
                    if wearablesVM.registrationState == .registering {
                        // mid registration: show inline progress and label
                        // (oauth flow can take 5 to 15 seconds)
                        HStack(spacing: 12) {
                            ProgressView().tint(Theme.primary)
                            Text("Connecting to Meta AI…")
                                .font(Theme.mono(14))
                                .foregroundStyle(Theme.primaryDark)
                        }
                        .padding(.vertical, 14)
                    } else {
                        // primary cta: opens meta ai for oauth handshake
                        Button {
                            wearablesVM.register()
                        } label: {
                            Text("Connect Glasses")
                                .themedPrimaryButton()
                        }
                        .buttonStyle(.plain)
                    }

                    // surface any registration / permission errors inline
                    if let error = wearablesVM.errorMessage {
                        Text(error)
                            .font(Theme.mono(12))
                            .foregroundStyle(Theme.danger)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    // skip path: opens test mode sheet
                    // useful when meta auth is broken or glasses unavailable
                    Button {
                        showTestMode = true
                    } label: {
                        Text("Skip — test with photo")
                            .themedSecondaryButton()
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 32)

                Spacer()
            }
        }
        // testmodeview presented as modal sheet so registration state is preserved
        // user can dismiss back to registration without losing oauth progress
        .sheet(isPresented: $showTestMode) {
            TestModeView()
        }
    }
}

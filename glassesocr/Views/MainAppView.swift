// filename: mainappview.swift
// course: cs 471
// authors: kaden campbell, lundon dotson, kevin davis
// date: may 7 2026

import SwiftUI
import MWDATCore

/// root view of glasses ocr app
/// chooses which screen to show based on registration and permission state:
///   1. registrationview if not yet linked to meta ai
///   2. permissionview if linked but camera permission missing
///   3. streamsessionview once both registration and camera permission are granted
struct MainAppView: View {

    // single shared wearables view model, owned here and passed down
    // children observe it so they react to state changes uniformly
    @StateObject private var wearablesVM = WearablesViewModel()

    var body: some View {
        Group {
            switch wearablesVM.registrationState {
            case .registered:
                if wearablesVM.cameraPermissionGranted {
                    StreamSessionView(wearablesVM: wearablesVM)
                } else {
                    PermissionView(wearablesVM: wearablesVM)
                }
            default:
                RegistrationView(wearablesVM: wearablesVM)
            }
        }
        // catches deep link callback from meta ai after user approves oauth
        // without this hook, registration never advances past .registering
        .onOpenURL { url in
            wearablesVM.handleURL(url)
        }
    }
}

// filename: testmodeview.swift
// course: cs 471
// authors: kaden campbell, lundon dotson, kevin davis

import SwiftUI
import PhotosUI

/// fallback ui that exercises full ocr pipeline without glasses
/// user picks photo from library
/// both apple vision and charactercnn run on it
/// useful when meta auth fails or glasses are unavailable
/// also gives reproducible demo independent of bluetooth conditions
struct TestModeView: View {

    // reuses streamviewmodel so ocr pipeline path is identical to live mode
    // streamviewmodel does not require active mwdat session for processimage
    @StateObject private var streamVM = StreamViewModel()

    // photospickeritem represents user's selection in library picker
    // resolved into uiimage when user picks a photo
    @State private var selectedItem: PhotosPickerItem?

    // currently displayed photo, set after successful load
    @State private var selectedImage: UIImage?

    // dismisses sheet back to registrationview
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.surface.ignoresSafeArea()

            VStack(spacing: 16) {

                // header with title on left, done button on right
                HStack {
                    Text("Test Mode")
                        .font(Theme.display(22, weight: .semibold))
                        .foregroundStyle(Theme.primaryDark)
                    Spacer()
                    Button("Done") { dismiss() }
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(Theme.primaryDark)
                }
                .padding(.horizontal)
                .padding(.top, 12)

                Text("Pick a photo to run Apple Vision\nand CharacterCNN side-by-side.")
                    .font(Theme.mono(12))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                // selected photo preview area
                // also overlays cnn input thumbnail when available
                ZStack {
                    // empty card background when nothing selected
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.surfaceElevated)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Theme.stroke, lineWidth: 1)
                        )

                    if let img = selectedImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "photo")
                                .font(.system(size: 44, weight: .light))
                                .foregroundStyle(Theme.primaryLight)
                            Text("No photo selected")
                                .font(Theme.mono(13))
                                .foregroundStyle(.secondary)
                        }
                    }

                    // cnn input debug overlay (mirrors streamsessionview)
                    if let modelInput = streamVM.customModelInput {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("CNN INPUT")
                                .font(Theme.mono(10, weight: .semibold))
                                .foregroundStyle(.white)
                                .tracking(1.0)
                            Image(uiImage: modelInput)
                                .resizable()
                                .interpolation(.none)
                                .frame(width: 80, height: 80)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Theme.primaryLight, lineWidth: 1.5)
                                )
                        }
                        .padding(8)
                        .background(.black.opacity(0.65),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: .topTrailing)
                    }
                }
                .frame(maxHeight: .infinity)
                .padding(.horizontal)

                // side by side comparison panels
                HStack(alignment: .top, spacing: 10) {
                    resultPanel(title: "APPLE VISION",
                                text: streamVM.appleResult,
                                timeMs: streamVM.appleTimeMs)
                    resultPanel(title: "CHARACTER CNN",
                                text: streamVM.customResult,
                                timeMs: streamVM.customTimeMs)
                }
                .frame(height: 130)
                .padding(.horizontal)

                // photos picker plus stop tts button
                VStack(spacing: 10) {
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        HStack(spacing: 8) {
                            Image(systemName: streamVM.isProcessingOCR ? "hourglass" : "photo.on.rectangle")
                            Text(streamVM.isProcessingOCR ? "Processing…" : "Pick photo")
                        }
                        .themedPrimaryButton()
                        .opacity(streamVM.isProcessingOCR ? 0.5 : 1)
                    }
                    .disabled(streamVM.isProcessingOCR)

                    Button {
                        streamVM.stopSpeaking()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "speaker.slash")
                            Text("Stop speaking")
                        }
                        .themedSecondaryButton()
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        // photospicker reports selection asynchronously
        // load and process when user picks new item
        .onChange(of: selectedItem) { _, newItem in
            Task { await loadAndProcess(newItem) }
        }
    }

    /// resolves photospickeritem into uiimage and runs comparison pipeline
    /// loadtransferable is async because library access can be slow
    /// guards return early if user cancels picker or load fails
    private func loadAndProcess(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data)
        else { return }
        selectedImage = image
        streamVM.processImage(image)
    }

    /// duplicate of streamsessionview.resultpanel
    /// kept local because both views are otherwise independent
    private func resultPanel(title: String, text: String, timeMs: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(Theme.mono(10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.primaryDark)
                Spacer()
                if timeMs > 0 {
                    Text(timeMs < 10 ? String(format: "%.1f ms", timeMs)
                                     : String(format: "%.0f ms", timeMs))
                        .font(Theme.mono(10, weight: .regular))
                        .foregroundStyle(Theme.primaryDark.opacity(0.6))
                }
            }
            // scrollview lets longer apple results scroll vertically
            // testmode photos sometimes contain multi character text
            ScrollView {
                Text(text.isEmpty ? "—" : text)
                    .font(Theme.mono(16))
                    .foregroundStyle(Theme.primaryDark)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .themedCard()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

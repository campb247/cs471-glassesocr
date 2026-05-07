# Glasses OCR

Wearable text-to-speech for the visually impaired, an iOS app that streams
the camera feed from Ray-Ban Meta Smart Glasses, recognizes printed
characters via on-device OCR, and reads them aloud.

**CS 471: Introduction to Artificial Intelligence (Spring 2026)**
Team: Lundon Dotson, Kaden Campbell, Kevin Davis

---

## What it does

1. The user wears Ray-Ban Meta Smart Glasses and looks at printed text.
2. They tap *Read Text* in the iOS companion app.
3. The most recent live frame is captured, run through both Apple Vision
   (commercial baseline) and our custom **CharacterCNN** (trained from
   scratch on Chars74K), and the recognized character is spoken aloud
   via `AVSpeechSynthesizer`.
4. Both predictions are displayed side-by-side on the phone for direct
   comparison, including timing and a visualization of the actual 28×28
   image fed to the CNN.

---

## Repo layout

```
glassesocr/
├── glassesocr/                  iOS app source (Swift / SwiftUI)
│   ├── Services/                OCR + TTS service classes
│   ├── ViewModels/              State management
│   ├── Views/                   SwiftUI screens
│   ├── Theme.swift              Design system (colors, fonts, modifiers)
│   └── CharacterCNN.mlpackage   The trained model, exported for CoreML
├── glassesocr.xcodeproj/        Xcode project
└── model/                       Python training & evaluation pipeline
    ├── download_dataset.py      Fetches Chars74K Fnt
    ├── train.py                 Trains CharacterCNN, exports to CoreML
    ├── evaluate.py              Confusion matrix + sample predictions
    ├── requirements.txt         Python dependencies
    └── output/                  Generated artifacts (plots, .mlpackage)
```

---

## Building the iOS app

Requirements:
- macOS with Xcode 16+
- iOS 16+ device for deployment (simulator works for TestMode but not
  for live glasses streaming)
- A Ray-Ban Meta Smart Glasses pair registered to a Meta account
  (only required for the live-glasses path; TestMode works without)

Steps:
1. Open `glassesocr.xcodeproj` in Xcode
2. Set the development team in *Signing & Capabilities*
3. Build and run on a connected iPhone

The CharacterCNN model (`glassesocr/CharacterCNN.mlpackage`) is committed
and Xcode auto-generates the Swift binding on first build.

### Live glasses path (optional)

To use the actual glasses stream rather than TestMode:
1. Register a third-party app at <https://wearables.developer.meta.com>
2. Set the bundle ID to match the Xcode project
3. In the Meta AI app: Settings → App Info → tap *App version* 5 times → enable Developer Mode
4. Add your Meta-account email as a tester to your release channel

If the auth flow hangs at the Connect screen, see "Known issues" below.

### TestMode (always works)

Tap *Skip, test with photo* on the registration screen. Pick any photo
from your library. Both OCR services run on it, results display side
by side. This exercises the same comparison pipeline without depending
on the glasses or Meta Auth.

---

## Training the model

Recommended: macOS / Apple Silicon (the training script uses MPS), but
Linux + CUDA + CPU also work.

```bash
cd model
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# Download Chars74K Fnt (~50 MB tarball, expands to ~300 MB)
python download_dataset.py

# Train (10 epochs, ~3-5 min on Apple M5)
python train.py

# Evaluate (writes confusion matrix and sample predictions to output/)
python evaluate.py
```

Training outputs `model/output/character_cnn.pt` (PyTorch checkpoint) and
`model/output/CharacterCNN.mlpackage` (CoreML deployment artifact). The
latter must be copied into `glassesocr/CharacterCNN.mlpackage/` to update
the iOS app's bundled model.

---

## Results

| Metric | Value |
|---|---|
| Overall test accuracy (case-sensitive) | **87.87%** (11,070 / 12,598) |
| Overall test accuracy (case-insensitive, TTS-aligned) | **96.27%** (12,128 / 12,598) |
| Pure CNN inference time on iPhone 17 Pro | **0.47 ms** average (n=25) |
| Apple Vision inference time on same device | **24.1 ms** average (n=25) |
| Speedup at the classification step | **51× faster** |

**Top remaining error pairs** after case folding: `o ↔ 0` (105),
`i / l / 1` (71), `i ↔ j` (18). All are visually-ambiguous pairs that
also fool human readers at 28×28 resolution.

---

## Known issues

- **Glasses streaming is intermittent on iOS 26.3 with MWDAT SDK 0.5.0.**
  The control plane connects fine but `recv fps: 0` from the SDK's
  health monitor, appears to be an SDK / iOS-26 compatibility issue.
  TestMode is the recommended demo path until upstream fixes ship.
- **Motion blur**: the Ray-Ban Meta camera is fixed-focus; brief
  head movement during capture produces blurred frames that both
  Apple Vision and CharacterCNN struggle with. Manual still-frame
  discipline (or a future sharpness-burst-capture mitigation) recovers
  most of these.
- **Single-character only.** CharacterCNN classifies one character per
  capture. For multi-character text, the model picks whichever character
  the largest Vision bbox isolates. Multi-character word-level
  recognition is future work.

---

## License

Class project for CS 471, Spring 2026.

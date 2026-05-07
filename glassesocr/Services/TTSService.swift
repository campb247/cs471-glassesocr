// filename: ttsservice.swift
// course: cs 471
// authors: kaden campbell, lundon dotson, kevin davis

import AVFoundation

/// text to speech wrapper around ios avspeechsynthesizer
/// configures audio session so output routes to glasses speakers when paired,
/// or falls back to phone speaker
class TTSService: NSObject, AVSpeechSynthesizerDelegate {

    // shared synthesizer instance reused across speak calls
    // recreating per call would lose mid utterance state
    private let synthesizer = AVSpeechSynthesizer()

    /// true while synthesizer is currently producing audio
    /// exposed so view models can disable buttons during playback
    var isSpeaking: Bool { synthesizer.isSpeaking }

    override init() {
        super.init()
        synthesizer.delegate = self

        // configure audio session for spoken playback
        // .playback category means audio plays even when phone is silenced
        // .spokenaudio mode pauses other audio (music) while speaking
        // .allowbluetooth and .allowbluetootha2dp route to glasses speakers if paired
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.allowBluetooth, .allowBluetoothA2DP]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session error: \(error.localizedDescription)")
        }
    }

    /// speaks given text aloud
    /// interrupts any in flight utterance so latest call always wins
    func speak(_ text: String) {
        // stop current speech immediately if synthesizer is busy
        // .immediate cancels mid sentence rather than queuing
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        // default rate is comfortable for ocr readout
        // pitch and volume left at neutral defaults
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        // english voice; swap locale for other languages as future work
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")

        synthesizer.speak(utterance)
    }

    /// stops any in flight speech immediately
    /// exposed via stop button on streamsessionview and testmodeview
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}

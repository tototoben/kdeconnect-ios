/*
 * SPDX-FileCopyrightText: 2026 station-mode contributors
 *
 * SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
 */

import AVFoundation

/// Named sound effects used throughout the station keyboard UI.
/// Each case maps to either a bundled audio file (in the app bundle) or a
/// system sound ID. Custom files take priority if present.
enum SoundEffect: String, CaseIterable {
    case keyPress
    case keyDelete
    case keyReturn
    case keySpace
    case modifierToggle
    case mqttMessage
    case mqttConnect
    case mqttDisconnect

    /// File extension to look for in the app bundle.
    static let fileExtension = "caf"

    /// Fallback system sound ID used when no bundled file is found.
    var systemSoundID: SystemSoundID {
        switch self {
        case .keyPress:         return 1104  // Tink (short click)
        case .keyDelete:         return 1105  // Tock
        case .keyReturn:         return 1104
        case .keySpace:          return 1104
        case .modifierToggle:    return 1105
        case .mqttMessage:        return 1003  // SMS received
        case .mqttConnect:       return 1007  // beep
        case .mqttDisconnect:    return 1073  // audio error tone
        }
    }
}

final class SoundManager {
    static let shared = SoundManager()

    private var players: [SoundEffect: AVAudioPlayer] = [:]
    private var systemSoundIDs: [SoundEffect: SystemSoundID] = [:]
    private var fallbackPlayer: AVAudioPlayer?

    /// Whether sound effects are enabled (persisted in UserDefaults).
    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "soundEffectsEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "soundEffectsEnabled") }
    }

    private init() {
        configureAudioSession()
        preloadAll()
    }

    // MARK: - Public

    func play(_ effect: SoundEffect) {
        guard enabled else { return }

        if let player = players[effect] {
            player.currentTime = 0
            player.play()
        } else {
            // No bundled file — play system sound AND a synthesized tone fallback
            let sysID = systemSoundIDs[effect] ?? effect.systemSoundID
            AudioServicesPlaySystemSound(sysID)
            playFallbackTone()
        }
    }

    /// Toggle sound effects on/off.
    @discardableResult
    func toggle() -> Bool {
        let newValue = !enabled
        enabled = newValue
        return newValue
    }

    // MARK: - Setup

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("SoundManager: failed to configure audio session: \(error)")
        }
    }

    private func preloadAll() {
        // Generate a short fallback tone for when no bundled files exist
        generateFallbackTone()

        for effect in SoundEffect.allCases {
            preload(effect)
        }
    }

    private func preload(_ effect: SoundEffect) {
        let name = effect.rawValue
        if let url = Bundle.main.url(forResource: name, withExtension: SoundEffect.fileExtension) {
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.prepareToPlay()
                player.volume = 0.5
                players[effect] = player
            } catch {
                print("SoundManager: failed to load \(name).\(SoundEffect.fileExtension): \(error)")
                systemSoundIDs[effect] = effect.systemSoundID
            }
        } else {
            // No bundled file — use system sound fallback
            systemSoundIDs[effect] = effect.systemSoundID
        }
    }

    // MARK: - Fallback tone

    /// Generates a short 0.05s click tone in memory as a last-resort fallback
    /// so we always get audible feedback even without bundled sound files.
    private func generateFallbackTone() {
        let sampleRate: Double = 44100
        let duration: Double = 0.05
        let frequency: Double = 1200.0
        let numSamples = Int(sampleRate * duration)

        var samples = [Int16](repeating: 0, count: numSamples)
        for i in 0..<numSamples {
            let t = Double(i) / sampleRate
            let envelope = 1.0 - (t / duration)  // linear decay
            let wave = sin(2.0 * .pi * frequency * t) * envelope * 0.3
            samples[i] = Int16(wave * Double(Int16.max))
        }

        let totalBytes = numSamples * MemoryLayout<Int16>.size
        var data = Data(capacity: 44 + totalBytes)

        // Minimal WAV header
        let header: [UInt8] = [
            0x52, 0x49, 0x46, 0x46,  // "RIFF"
            0x00, 0x00, 0x00, 0x00,  // chunk size (filled below)
            0x57, 0x41, 0x56, 0x45,  // "WAVE"
            0x66, 0x6D, 0x74, 0x20,  // "fmt "
            0x10, 0x00, 0x00, 0x00,  // subchunk size = 16
            0x01, 0x00,              // PCM format
            0x01, 0x00,              // mono
            0x44, 0xAC, 0x00, 0x00,  // 44100 Hz
            0x88, 0x58, 0x01, 0x00,  // byte rate
            0x02, 0x00,              // block align
            0x10, 0x00,              // 16 bits
            0x64, 0x61, 0x74, 0x61,  // "data"
        ]
        data.append(contentsOf: header)

        // data chunk size
        let dataSize = UInt32(totalBytes)
        data.append(UInt8(dataSize & 0xFF))
        data.append(UInt8((dataSize >> 8) & 0xFF))
        data.append(UInt8((dataSize >> 16) & 0xFF))
        data.append(UInt8((dataSize >> 24) & 0xFF))

        // RIFF chunk size
        let riffSize = UInt32(36 + totalBytes)
        data[4] = UInt8(riffSize & 0xFF)
        data[5] = UInt8((riffSize >> 8) & 0xFF)
        data[6] = UInt8((riffSize >> 16) & 0xFF)
        data[7] = UInt8((riffSize >> 24) & 0xFF)

        // Audio samples
        for sample in samples {
            data.append(UInt8(sample & 0xFF))
            data.append(UInt8((sample >> 8) & 0xFF))
        }

        do {
            fallbackPlayer = try AVAudioPlayer(data: data)
            fallbackPlayer?.prepareToPlay()
            fallbackPlayer?.volume = 0.3
        } catch {
            print("SoundManager: failed to create fallback tone: \(error)")
        }
    }

    private func playFallbackTone() {
        guard let player = fallbackPlayer else { return }
        player.currentTime = 0
        player.play()
    }
}


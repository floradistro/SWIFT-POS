//
//  BackgroundKeepAlive.swift
//  Whale
//
//  Keeps the app alive in background using silent audio playback.
//  This allows Lisa AI agents to continue running without interruption.
//
//  Uses AVAudioSession with playback category and plays silent audio
//  to prevent iOS from suspending the app.
//

import Foundation
import AVFoundation
import UIKit
import Combine
import os.log

@MainActor
final class BackgroundKeepAlive: ObservableObject {
    static let shared = BackgroundKeepAlive()

    @Published var isActive = false

    private var audioPlayer: AVAudioPlayer?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    private init() {
        setupNotifications()
    }

    // MARK: - Public API

    /// Start keeping the app alive in background
    func start() {
        guard !isActive else { return }

        setupAudioSession()
        startSilentAudio()
        isActive = true

        Log.agent.info("BackgroundKeepAlive: Started - app will stay alive in background")
    }

    /// Stop background keep-alive (call when agent work is done)
    func stop() {
        guard isActive else { return }

        audioPlayer?.stop()
        audioPlayer = nil
        isActive = false

        // End background task if any
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }

        Log.agent.info("BackgroundKeepAlive: Stopped")
    }

    // MARK: - Audio Session Setup

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()

            // Use playback category with mixWithOthers so it doesn't interrupt other audio
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            Log.agent.debug("BackgroundKeepAlive: Audio session configured")
        } catch {
            Log.agent.error("BackgroundKeepAlive: Failed to configure audio session: \(error)")
        }
    }

    private func startSilentAudio() {
        // Create a tiny silent audio buffer
        // 1 second of silence at 44100 Hz, mono, 16-bit
        let sampleRate: Double = 44100
        let duration: Double = 1.0
        let numSamples = Int(sampleRate * duration)

        var audioData = Data()

        // WAV header
        let headerSize: UInt32 = 44
        let dataSize: UInt32 = UInt32(numSamples * 2)  // 16-bit = 2 bytes per sample
        let fileSize: UInt32 = headerSize + dataSize - 8

        // RIFF header
        audioData.append(contentsOf: "RIFF".utf8)
        audioData.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        audioData.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        audioData.append(contentsOf: "fmt ".utf8)
        audioData.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })  // Chunk size
        audioData.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })   // Audio format (PCM)
        audioData.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })   // Num channels (mono)
        audioData.append(contentsOf: withUnsafeBytes(of: UInt32(44100).littleEndian) { Array($0) }) // Sample rate
        audioData.append(contentsOf: withUnsafeBytes(of: UInt32(88200).littleEndian) { Array($0) }) // Byte rate
        audioData.append(contentsOf: withUnsafeBytes(of: UInt16(2).littleEndian) { Array($0) })   // Block align
        audioData.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian) { Array($0) })  // Bits per sample

        // data chunk
        audioData.append(contentsOf: "data".utf8)
        audioData.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })

        // Silent audio data (all zeros)
        audioData.append(contentsOf: [UInt8](repeating: 0, count: Int(dataSize)))

        do {
            audioPlayer = try AVAudioPlayer(data: audioData)
            audioPlayer?.numberOfLoops = -1  // Loop indefinitely
            audioPlayer?.volume = 0.0  // Silent
            audioPlayer?.play()

            Log.agent.debug("BackgroundKeepAlive: Silent audio started")
        } catch {
            Log.agent.error("BackgroundKeepAlive: Failed to create audio player: \(error)")
        }
    }

    // MARK: - App Lifecycle

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    @objc private func appDidEnterBackground() {
        guard isActive else { return }

        // Request extended background time
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            // Expiration handler - iOS is about to suspend us
            Log.agent.warning("BackgroundKeepAlive: Background task expiring - agent will continue in background")
            // Don't end the task - let audio keep us alive
        }

        // Log remaining background time
        let remaining = UIApplication.shared.backgroundTimeRemaining
        if remaining == .greatestFiniteMagnitude {
            Log.agent.info("BackgroundKeepAlive: App entered background - unlimited time (audio mode)")
        } else {
            Log.agent.info("BackgroundKeepAlive: App entered background - \(Int(remaining))s remaining")
        }
    }

    @objc private func appWillEnterForeground() {
        endBackgroundTask()
        Log.agent.info("BackgroundKeepAlive: App returning to foreground")
    }

    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
}

//
//  ScanFeedback.swift
//  Whale
//
//  Audio feedback for scanning and payment events.
//  Note: Haptics disabled - iPads don't have Taptic Engine.
//

import AudioToolbox

// MARK: - Scan Feedback

/// Audio feedback singleton for scan and payment sounds
final class ScanFeedback: @unchecked Sendable {

    static let shared = ScanFeedback()
    private init() {}

    // MARK: - Scan Feedback

    /// Age verified successfully (21+)
    func ageVerified() {
        AudioServicesPlaySystemSound(1111)
    }

    /// Age verification failed (under 21)
    func ageRejected() {
        AudioServicesPlaySystemSound(1053)
    }

    /// Customer found/matched
    func customerFound() {
        AudioServicesPlaySystemSound(1111)
    }

    /// No customer match
    func customerNotFound() {
        AudioServicesPlaySystemSound(1057)
    }

    /// Error occurred
    func error() {
        AudioServicesPlaySystemSound(1053)
    }

    // MARK: - Payment Feedback

    /// Payment completed successfully - Apple Pay "ding" sound
    func paymentSuccess() {
        AudioServicesPlaySystemSound(1407)  // Apple Pay success sound
    }

    /// Payment processing started
    func paymentProcessing() {
        AudioServicesPlaySystemSound(1103)  // Subtle begin sound
    }

    /// Cash drawer open
    func cashDrawerOpen() {
        AudioServicesPlaySystemSound(1057)
    }
}

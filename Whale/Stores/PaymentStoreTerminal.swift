//
//  PaymentStoreTerminal.swift
//  Whale
//
//  Payment terminal integration extension for PaymentStore.
//  Dejavoo terminal callback, retry logic, and config lookup.
//

import Foundation
import os.log

// MARK: - Terminal Config

extension PaymentStore {

    /// Terminal config response from vault RPC
    struct TerminalConfig: Decodable {
        let processorName: String?
        let authkey: String?
        let tpn: String?
        let environment: String?
        let isActive: Bool?

        enum CodingKeys: String, CodingKey {
            case processorName = "processor_name"
            case authkey
            case tpn
            case environment
            case isActive = "is_active"
        }
    }
}

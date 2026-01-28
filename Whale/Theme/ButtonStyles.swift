//
//  ButtonStyles.swift
//  Whale
//
//  Shared button styles used across the app.
//

import SwiftUI

// MARK: - Scale Button Style

struct ScaleButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    var haptic: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed && haptic {
                    Haptics.soft()
                }
            }
    }
}

// MARK: - Payment Method

enum DockPaymentMethod: String, CaseIterable {
    case card, cash, split, multiCard, invoice

    var icon: String {
        switch self {
        case .card: return "creditcard.fill"
        case .cash: return "banknote.fill"
        case .split: return "square.split.1x2.fill"
        case .multiCard: return "creditcard.and.123"
        case .invoice: return "paperplane.fill"
        }
    }

    var label: String {
        switch self {
        case .card: return "Card"
        case .cash: return "Cash"
        case .split: return "Split"
        case .multiCard: return "2 Cards"
        case .invoice: return "Invoice"
        }
    }
}

//
//  StoreLogo.swift
//  Whale
//
//  Store logo with liquid glass fallback.
//  Uses Design tokens.
//

import SwiftUI

struct StoreLogo: View {
    let url: URL?
    let size: CGFloat
    let storeName: String?

    init(url: URL?, size: CGFloat = 60, storeName: String? = nil) {
        self.url = url
        self.size = size
        self.storeName = storeName
    }

    private var initials: String {
        guard let name = storeName, !name.isEmpty else { return "" }
        let words = name.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        } else {
            return String(name.prefix(2)).uppercased()
        }
    }

    var body: some View {
        Group {
            if let url = url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        loadingView
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    case .failure:
                        fallbackView
                    @unknown default:
                        fallbackView
                    }
                }
            } else {
                fallbackView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Design.Colors.Border.subtle, lineWidth: 1)
        )
    }

    private var loadingView: some View {
        ZStack {
            Circle()
                .fill(Design.Colors.Glass.regular)
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: Design.Colors.Text.subtle))
                .scaleEffect(0.7)
        }
    }

    private var fallbackView: some View {
        ZStack {
            Circle()
                .fill(Design.Colors.Glass.regular)

            if !initials.isEmpty {
                // Show initials instead of generic icon
                Text(initials)
                    .font(.system(size: size * 0.35, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}

#Preview {
    ZStack {
        Design.Colors.backgroundPrimary.ignoresSafeArea()
        VStack(spacing: Design.Spacing.lg) {
            StoreLogo(url: nil, size: 80, storeName: "Acme Corp")
            StoreLogo(url: nil, size: 60, storeName: "Test")
        }
    }
}

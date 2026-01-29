//
//  AgentModels.swift
//  Whale
//
//  Core data models for the Claude agent system.
//  Extracted from ClaudeClient.swift for modularity.
//

import Foundation

// MARK: - Tracked Action (for undo support)

struct TrackedAction: Identifiable, Sendable {
    let id = UUID()
    let sql: String
    let operation: String
    let storeId: UUID
    let timestamp: Date

    var description: String {
        // Parse a friendly description from the SQL
        let sqlLower = sql.lowercased()

        if sqlLower.contains("insert into") {
            if let table = extractTable(from: sql, after: "into") {
                return "Created \(formatTableName(table))"
            }
            return "Created record"
        }

        if sqlLower.contains("update") {
            if let table = extractTable(from: sql, after: "update") {
                return "Updated \(formatTableName(table))"
            }
            return "Updated record"
        }

        return "\(operation) operation"
    }

    private func extractTable(from sql: String, after keyword: String) -> String? {
        let pattern = "\(keyword)\\s+(\\w+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: sql, range: NSRange(sql.startIndex..., in: sql)),
              let range = Range(match.range(at: 1), in: sql) else {
            return nil
        }
        return String(sql[range])
    }

    private func formatTableName(_ table: String) -> String {
        table.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

// MARK: - Session Context (injected into system prompt)

/// Display info for context injection
struct DisplayInfo: Sendable {
    let id: String
    let name: String
    let status: String
}

/// Product summary for context injection (lightweight - just name, category, stock, pricing)
struct ProductSummary: Sendable {
    let id: String
    let name: String
    let category: String?
    let quantity: Int
    let pricingData: [[String: Any]]?  // Tiered pricing: [{"label": "3.5g", "price": 34.99}, ...]

    /// Format pricing tiers for display
    var pricingString: String? {
        guard let tiers = pricingData, !tiers.isEmpty else { return nil }
        let formatted = tiers.compactMap { tier -> String? in
            guard let label = tier["label"] as? String,
                  let price = tier["price"] as? Double else { return nil }
            return "\(label): $\(String(format: "%.2f", price))"
        }
        return formatted.isEmpty ? nil : formatted.joined(separator: " | ")
    }
}

struct SessionContext: Sendable {
    let storeId: UUID
    let storeName: String?
    let storeLogoUrl: String?  // For PDF branding
    let userId: UUID?
    let userEmail: String?
    let locationId: UUID?
    let locationName: String?
    let registerId: UUID?
    let registerName: String?
    let conversationId: UUID?  // For query logging

    // GitHub repo selection
    let selectedRepoFullName: String?  // e.g. "floradistro/flora-distro-storefront"
    let selectedRepoOwner: String?     // e.g. "floradistro"
    let selectedRepoName: String?      // e.g. "flora-distro-storefront"

    // Active creation context (when user has a creation window open)
    let activeCreationId: String?      // UUID of the creation being edited
    let activeCreationName: String?    // Name of the creation
    let activeCreationUrl: String?     // Deployed URL for reference

    // CONTEXT CACHING: Pre-loaded location data (Anthropic-style - load once, use many)
    var displays: [DisplayInfo]?        // Digital displays at this location
    var inStockProducts: [ProductSummary]?  // Products in stock at this location


    /// Build context string for system prompt
    var contextString: String {
        var lines: [String] = []
        lines.append("\n\n## CURRENT SESSION CONTEXT\n")
        lines.append("**Store ID:** `\(storeId.uuidString.lowercased())`")
        if let name = storeName {
            lines.append("**Store Name:** \(name)")
        }
        if let userId = userId {
            lines.append("**User ID:** `\(userId.uuidString.lowercased())`")
        }
        if let email = userEmail {
            lines.append("**User Email:** \(email)")
        }
        if let locId = locationId, let locName = locationName {
            lines.append("**Current Location:** \(locName) (`\(locId.uuidString.lowercased())`)")
        }
        if let regId = registerId, let regName = registerName {
            lines.append("**Current Register:** \(regName) (`\(regId.uuidString.lowercased())`)")
        }
        if let repoName = selectedRepoFullName {
            lines.append("**CONNECTED GITHUB REPO:** `\(repoName)` — THIS IS THE ONLY REPO YOU CAN EDIT")
            lines.append("Note: The Vercel project name may differ from the GitHub repo name. Trust the repo name above.")
        }

        // ACTIVE CREATION: User has a creation window open - edits go here
        if let creationId = activeCreationId, let creationName = activeCreationName {
            lines.append("")
            lines.append("### 🎯 ACTIVE CREATION: \(creationName)")
            lines.append("**Creation ID:** `\(creationId)`")
            if let url = activeCreationUrl {
                lines.append("**Preview URL:** \(url)")
            }
            lines.append("")
            lines.append("⚠️ **IMPORTANT:** User is viewing this creation. When they ask to edit, change, or update something, use `creation_edit` with this creation_id. Do NOT create a new creation unless explicitly asked.")
        }

        // DISPLAYS: Pre-loaded, no need to query
        if let displays = displays, !displays.isEmpty {
            lines.append("")
            lines.append("### DIGITAL DISPLAYS AT THIS LOCATION")
            lines.append("These displays are already loaded - use these IDs directly with creation tools:")
            for display in displays {
                lines.append("- **\(display.name)**: `\(display.id)` (status: \(display.status))")
            }
        }

        // IN-STOCK PRODUCTS: Pre-loaded, no need to query for menus
        if let products = inStockProducts, !products.isEmpty {
            lines.append("")
            lines.append("### IN-STOCK PRODUCTS AT THIS LOCATION (\(products.count) items)")
            lines.append("Use these for menus - DO NOT query products table, this is your inventory:")

            // Group by category
            var byCategory: [String: [ProductSummary]] = [:]
            for p in products {
                let cat = p.category ?? "Other"
                byCategory[cat, default: []].append(p)
            }

            for (category, prods) in byCategory.sorted(by: { $0.key < $1.key }) {
                lines.append("")
                lines.append("**\(category)** (\(prods.count) items):")
                for p in prods.prefix(20) {  // Limit per category to keep prompt reasonable
                    var details = "qty: \(p.quantity)"
                    if let pricing = p.pricingString {
                        details += " | \(pricing)"
                    }
                    lines.append("  - \(p.name) (\(details))")
                }
                if prods.count > 20 {
                    lines.append("  - ... and \(prods.count - 20) more")
                }
            }
        }

        lines.append("")
        lines.append("**CRITICAL RULES:**")
        lines.append("1. ALWAYS filter queries by `store_id = '\(storeId.uuidString.lowercased())'`")
        lines.append("2. NEVER query, display, or reference data from other stores")
        lines.append("3. When creating records, always use this store_id")
        lines.append("4. Use the current location_id for inventory and order operations")
        lines.append("5. For displays: Use the display IDs above (from creations table)")
        lines.append("6. For menus: Use the in-stock products above, don't hallucinate product names")
        if selectedRepoFullName != nil {
            lines.append("7. GitHub repo is `\(selectedRepoFullName!)` — report this exact name when discussing code changes")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Claude Message

/// Represents a message in Claude conversation history
struct ClaudeMessage: Sendable {
    enum Role: String, Sendable {
        case user
        case assistant
    }

    let role: Role
    let content: String
}

// MARK: - Claude Errors

enum ClaudeError: Error, LocalizedError {
    case apiError(String)
    case invalidResponse
    case missingApiKey

    var errorDescription: String? {
        switch self {
        case .apiError(let message):
            return "API Error: \(message)"
        case .invalidResponse:
            return "Invalid response from Claude API"
        case .missingApiKey:
            return "Missing API key"
        }
    }
}

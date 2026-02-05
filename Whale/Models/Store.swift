//
//  Store.swift
//  Whale
//
//  Store model. Matches Supabase stores table structure.
//
//  Created by Fahad Khan on 12/15/25.
//

import Foundation

struct Store: Codable, Identifiable, Sendable {
    let id: UUID
    let businessName: String?
    let slug: String?
    let logoUrl: String?
    let primaryColor: String?
    let secondaryColor: String?
    let distributorLicenseNumber: String?

    // GitHub integration
    let githubRepoName: String?
    let githubRepoFullName: String?
    let githubRepoUrl: String?

    // Vercel integration
    let vercelProjectId: String?
    let vercelDeploymentUrl: String?

    enum CodingKeys: String, CodingKey {
        case id
        case businessName = "business_name"
        case slug
        case logoUrl = "logo_url"
        case primaryColor = "primary_color"
        case secondaryColor = "secondary_color"
        case distributorLicenseNumber = "distributor_license_number"
        case githubRepoName = "github_repo_name"
        case githubRepoFullName = "github_repo_full_name"
        case githubRepoUrl = "github_repo_url"
        case vercelProjectId = "vercel_project_id"
        case vercelDeploymentUrl = "vercel_deployment_url"
    }

    /// Whether a GitHub repo is connected
    var hasGitHubRepo: Bool {
        !(githubRepoFullName ?? "").isEmpty
    }

    /// Whether Vercel is connected
    var hasVercelProject: Bool {
        !(vercelProjectId ?? "").isEmpty
    }

    /// Get the full logo URL from Supabase storage
    var fullLogoUrl: URL? {
        guard let logoUrl = logoUrl, !logoUrl.isEmpty else { return nil }

        // If it's already a full URL, use it directly
        if logoUrl.hasPrefix("http") {
            return URL(string: logoUrl)
        }

        // Otherwise, construct Supabase storage URL
        let baseUrl = "https://pprlgipabjoxxbfhkuxj.supabase.co/storage/v1/object/public"
        return URL(string: "\(baseUrl)/\(logoUrl)")
    }
}

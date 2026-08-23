//
//  PasscodeGalleryManager.swift
//  lara
//
//  Created by neonmodder123 on 20/05/2026.
//

import Foundation
import SwiftUI
import Combine

// just forked the cowabunga theme repo to update JSON structure
let defaultPasscodeRepoURL = "https://raw.githubusercontent.com/neonmodder123/theme-repo/refs/heads/main/passcode-themes.json"
private let passcodeRepoKey = "passcodeThemeRepos"

struct PasscodeGalleryTheme: Identifiable, Decodable, Equatable {
    let name: String
    let description: String
    let url: String
    let preview: String
    let contact: PasscodeThemeContact
    let version: String
    var id: String { name }
}

struct PasscodeThemeContact: Decodable, Equatable {
    private let raw: [String: String]
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        raw = try container.decode([String: String].self)
    }
    var displayName: String {
        raw.map { "\($0.key): \($0.value)" }.first ?? ""
    }
}

struct PasscodeRepoData: Identifiable {
    var id: String { name }
    let name: String
    let author: String?
    let icon: String?
    let themes: [PasscodeGalleryTheme]
    let baseURL: URL
}

struct PasscodeRepoState: Identifiable {
    var id: String { url }
    let url: String
    var isLoading: Bool
    var error: String?
    var data: PasscodeRepoData?
}

@MainActor
final class PasscodeGalleryManager: ObservableObject {
    static let shared = PasscodeGalleryManager()

    @Published var repos: [PasscodeRepoState] = []
    @Published var downloading: Set<String> = []

    private var repoURLs: [String] = loadPasscodeRepoURLs()

    var allThemes: [PasscodeGalleryTheme] { repos.flatMap { $0.data?.themes ?? [] } }
    var themes: [PasscodeGalleryTheme] { allThemes }
    var isLoading: Bool { repos.contains { $0.isLoading } }
    var loadError: String? { repos.first { $0.error != nil }?.error }

    func previewURL(for theme: PasscodeGalleryTheme) -> URL? {
        guard let repoData = repos.first(where: { $0.data?.themes.contains(where: { $0.id == theme.id }) == true })?.data else { return nil }
        if theme.preview.hasPrefix("http") { return URL(string: theme.preview) }
        return repoData.baseURL.appendingPathComponent(theme.preview)
    }

    func downloadURL(for theme: PasscodeGalleryTheme) -> URL? {
        guard let repoData = repos.first(where: { $0.data?.themes.contains(where: { $0.id == theme.id }) == true })?.data else { return nil }
        if theme.url.hasPrefix("http") { return URL(string: theme.url) }
        return repoData.baseURL.appendingPathComponent(theme.url)
    }

    func isDownloading(_ theme: PasscodeGalleryTheme) -> Bool { downloading.contains(theme.id) }

    func loadThemes(forceRefresh: Bool = false) async {
        await refreshRepos(forceRefresh: forceRefresh)
    }

    func refreshRepos(forceRefresh: Bool = false) async {
        repos = repoURLs.map { PasscodeRepoState(url: $0, isLoading: true, error: nil, data: nil) }

        await withTaskGroup(of: (String, Result<PasscodeRepoData, Error>).self) { group in
            for url in repoURLs {
                group.addTask {
                    do {
                        return (url, .success(try await self.fetchRepo(url, forceRefresh: forceRefresh)))
                    } catch {
                        return (url, .failure(error))
                    }
                }
            }
            for await (url, result) in group {
                guard let idx = repos.firstIndex(where: { $0.url == url }) else { continue }
                repos[idx].isLoading = false
                switch result {
                case .success(let data): repos[idx].data = data
                case .failure(let error): repos[idx].error = error.localizedDescription
                }
            }
        }
    }

    func addRepo(_ urlString: String) async {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, URL(string: trimmed) != nil, !repoURLs.contains(trimmed) else { return }
        repoURLs.append(trimmed)
        savePasscodeRepoURLs(repoURLs)
        await refreshRepos()
    }

    func removeRepo(_ url: String) {
        guard url != defaultPasscodeRepoURL else { return }
        repoURLs.removeAll { $0 == url }
        savePasscodeRepoURLs(repoURLs)
        Task { await refreshRepos() }
    }

    func downloadAndImport(_ theme: PasscodeGalleryTheme) async throws -> URL {
        guard let fileURL = downloadURL(for: theme) else { throw URLError(.badURL) }
        downloading.insert(theme.id)
        defer { downloading.remove(theme.id) }
        let (tempURL, response) = try await URLSession.shared.download(from: fileURL)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        let attrs = try FileManager.default.attributesOfItem(atPath: tempURL.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let maxBytes: Int64 = 64 * 1024 * 1024
        guard size > 0, size <= maxBytes else {
            try? FileManager.default.removeItem(at: tempURL)
            throw URLError(.dataLengthExceedsMaximum)
        }
        let data = try Data(contentsOf: tempURL)
        try? FileManager.default.removeItem(at: tempURL)
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let safeBase = theme.name
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: "..", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fileName = (safeBase.isEmpty ? "theme" : safeBase) + ".passthm"
        let dest = docs.appendingPathComponent(fileName).standardizedFileURL
        let root = docs.standardizedFileURL.path
        guard dest.path.hasPrefix(root.hasSuffix("/") ? root : root + "/") else {
            throw URLError(.cannotWriteToFile)
        }
        try data.write(to: dest, options: .atomic)
        return dest
    }

    private func fetchRepo(_ urlString: String, forceRefresh: Bool = false) async throws -> PasscodeRepoData {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        if forceRefresh { req.cachePolicy = .reloadIgnoringLocalCacheData }
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        guard data.count <= 2 * 1024 * 1024 else {
            throw URLError(.dataLengthExceedsMaximum)
        }
        let baseURL = url.deletingLastPathComponent()

        if let themes = try? JSONDecoder().decode([PasscodeGalleryTheme].self, from: data) {
            let name = urlString == defaultPasscodeRepoURL ? "Cowabunga" : (url.deletingPathExtension().lastPathComponent)
            return PasscodeRepoData(name: name, author: nil, icon: nil, themes: themes, baseURL: baseURL)
        }

        struct RepoJSON: Decodable {
            let repo_name: String
            let repo_author: String?
            let repo_icon: String?
            let themes: [PasscodeGalleryTheme]
        }
        let parsed = try JSONDecoder().decode(RepoJSON.self, from: data)
        return PasscodeRepoData(name: parsed.repo_name, author: parsed.repo_author, icon: parsed.repo_icon, themes: parsed.themes, baseURL: baseURL)
    }
}

private func loadPasscodeRepoURLs() -> [String] {
    if let data = UserDefaults.standard.data(forKey: passcodeRepoKey),
       let urls = try? JSONDecoder().decode([String].self, from: data), !urls.isEmpty {
        var result = urls
        if !result.contains(defaultPasscodeRepoURL) { result.insert(defaultPasscodeRepoURL, at: 0) }
        return result
    }
    return [defaultPasscodeRepoURL]
}

private func savePasscodeRepoURLs(_ urls: [String]) {
    if let encoded = try? JSONEncoder().encode(urls) {
        UserDefaults.standard.set(encoded, forKey: passcodeRepoKey)
    }
}

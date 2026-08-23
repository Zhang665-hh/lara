import Combine
import Foundation
import SwiftUI
import UIKit

private let iconThemeStorageRoot = URL(fileURLWithPath: "/var/mobile/.DO-NOT-DELETE-lara/IconThemes", isDirectory: true)
private let rawThemesDir = iconThemeStorageRoot.appendingPathComponent("RawThemes", isDirectory: true)
private let processedThemesDir = iconThemeStorageRoot.appendingPathComponent("ProcessedThemes", isDirectory: true)
private let originalIconsDir = iconThemeStorageRoot.appendingPathComponent("OriginalIconsBackup", isDirectory: true)
private func clearIconCache() { LaraClearIconCache() }

struct LaraIconTheme: Identifiable, Equatable, Hashable {
    let name: String
    let iconCount: Int

    var id: String { name }
    var url: URL { rawThemesDir.appendingPathComponent(name, isDirectory: true) }
    var cacheURL: URL { processedThemesDir.appendingPathComponent(name, isDirectory: true) }
}

struct LaraThemedIcon: Codable {
    let appID: String
    let themeName: String

    var rawThemeIconURL: URL {
        rawThemesDir.appendingPathComponent(themeName).appendingPathComponent(appID + ".png")
    }

    func cachedThemeIconURL(fileName: String) -> URL {
        processedThemesDir.appendingPathComponent(themeName).appendingPathComponent(appID + "----" + fileName)
    }
}

struct LaraThemedApp: Identifiable, Hashable {
    let bundleIdentifier: String
    var name: String
    let version: String
    let bundleURL: URL
    var pngIconPaths: [String]
    var hiddenFromSpringboard: Bool

    var id: String { bundleIdentifier + "|" + bundleURL.path }

    struct BackedUpPNG {
        let bundleIdentifier: String
        let iconName: String
        let data: Data
    }

    func loadPreviewIcon() -> UIImage? {
        guard let bundle = Bundle(path: bundleURL.path) else { return nil }
        if let icons = bundle.infoDictionary?["CFBundleIcons"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String] {
            for name in files.reversed() {
                if let image = UIImage(named: name, in: bundle, compatibleWith: nil) {
                    return image
                }
            }
        }
        if let name = bundle.infoDictionary?["CFBundleIconFile"] as? String,
           let image = UIImage(named: name, in: bundle, compatibleWith: nil) {
            return image
        }
        return nil
    }

    func backupIconURL(fileName: String) -> URL {
        // Versionless path is the durable original. A versioned file must not
        // replace it after an App Store update while icons are still themed.
        originalIconsDir.appendingPathComponent(bundleIdentifier + "----" + fileName)
    }

    func backedUpIconURL(fileName: String) -> URL? {
        let fm = FileManager.default
        let canonicalURL = backupIconURL(fileName: fileName)
        let versionedURL = originalIconsDir.appendingPathComponent(bundleIdentifier + "----" + version + "----" + fileName)

        if fm.fileExists(atPath: canonicalURL.path) {
            return canonicalURL
        } else if fm.fileExists(atPath: versionedURL.path) {
            // Migrate legacy versioned backups into the stable location once.
            try? fm.moveItem(at: versionedURL, to: canonicalURL)
            if fm.fileExists(atPath: canonicalURL.path) { return canonicalURL }
            return versionedURL
        }
        return nil
    }

    @discardableResult
    func backUpPNGIcons() -> Bool {
        let fm = FileManager.default
        var ok = true
        for pngIconPath in pngIconPaths {
            let versionedURL = originalIconsDir.appendingPathComponent(bundleIdentifier + "----" + version + "----" + pngIconPath)
            let canonicalURL = backupIconURL(fileName: pngIconPath)
            let sourceURL = bundleURL.appendingPathComponent(pngIconPath)

            guard fm.fileExists(atPath: sourceURL.path) else { continue }
            if fm.fileExists(atPath: canonicalURL.path) {
                continue
            } else if fm.fileExists(atPath: versionedURL.path) {
                do { try fm.moveItem(at: versionedURL, to: canonicalURL) }
                catch { ok = false }
            } else {
                do { try fm.copyItem(at: sourceURL, to: canonicalURL) }
                catch { ok = false }
            }
        }
        return ok
    }

    func restorePNGIcons() throws {
        for iconName in pngIconPaths {
            guard let originalURL = backedUpIconURL(fileName: iconName) else { continue }
            let iconURL = bundleURL.appendingPathComponent(iconName)
            let data = try Data(contentsOf: originalURL)
            // Match setPNGIcons: mobile ownership for write, then restore to _installd.
            let chown1 = SantanderChown.chown(path: iconURL.path, uid: 501, gid: 501)
            if !chown1 {
                throw NSError(domain: "IconThemer", code: 6, userInfo: [NSLocalizedDescriptionKey: "\(bundleIdentifier): restore chown(501) failed"])
            }
            defer { _ = SantanderChown.chown(path: iconURL.path, uid: 33, gid: 33) }
            let result = laramgr.shared.lara_overwritefile(target: iconURL.path, data: data)
            if !result.ok {
                throw NSError(domain: "IconThemer", code: 2, userInfo: [NSLocalizedDescriptionKey: "\(bundleIdentifier): \(result.message)"])
            }
            let chown2 = SantanderChown.chown(path: iconURL.path, uid: 33, gid: 33)
            if !chown2 {
                throw NSError(domain: "IconThemer", code: 6, userInfo: [NSLocalizedDescriptionKey: "\(bundleIdentifier): restore chown(33) failed"])
            }
        }
    }

    func setPNGIcons(icon: LaraThemedIcon) throws {
        let fm = FileManager.default
        for iconName in pngIconPaths {
            let iconURL = bundleURL.appendingPathComponent(iconName)
            guard fm.fileExists(atPath: iconURL.path) else { continue }

            let cachedIconURL = icon.cachedThemeIconURL(fileName: iconName)
            var cachedIcon = try? Data(contentsOf: cachedIconURL)

            if cachedIcon == nil {
                let imgData = try Data(contentsOf: icon.rawThemeIconURL)
                guard let themeIcon = UIImage(data: imgData) else {
                    throw NSError(domain: "IconThemer", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not read themed icon image at \(icon.rawThemeIconURL.path)"])
                }

                let origImageData = try Data(contentsOf: iconURL)
                guard let origImage = UIImage(data: origImageData) else {
                    throw NSError(domain: "IconThemer", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not read original icon image at \(iconURL.path)"])
                }

                var processedImage: Data?
                var resScale: CGFloat = 1.0
                let width = max(origImage.size.width / 2.0, 8.0)

                while resScale > 0.01 {
                    let size = CGSize(width: width * resScale, height: width * resScale)
                    let rendered = UIGraphicsImageRenderer(size: size).image { _ in
                        themeIcon.draw(in: CGRect(origin: .zero, size: size))
                    }
                    processedImage = try? rendered.resizeToApprox(allowedSizeInBytes: origImageData.count)
                    if processedImage != nil {
                        break
                    }
                    resScale *= 0.75
                }

                guard let processedImage else {
                    throw NSError(domain: "IconThemer", code: 5, userInfo: [NSLocalizedDescriptionKey: "\(bundleIdentifier): Could not fit icon \(iconName) inside original size budget"])
                }

                try? FileManager.default.createDirectory(at: cachedIconURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
                try processedImage.write(to: cachedIconURL)
                cachedIcon = processedImage
            }

            guard let cachedIcon else { continue }
            
            let chown1 = SantanderChown.chown( path: iconURL.path, uid: 501, gid: 501)
            if(!chown1) {
                throw NSError(domain: "IconThemer", code: 6, userInfo: [NSLocalizedDescriptionKey: "\(bundleIdentifier): 1st chown failed"])
            }
            // Always restore mobile ownership even if overwrite fails mid-flight.
            defer { _ = SantanderChown.chown(path: iconURL.path, uid: 33, gid: 33) }
            
            let overwrite = laramgr.shared.lara_overwritefile(target: iconURL.path, data: cachedIcon)
            if !overwrite.ok {
                throw NSError(domain: "IconThemer", code: 6, userInfo: [NSLocalizedDescriptionKey: "\(bundleIdentifier): \(overwrite.message)"])
            }
            
            let chown2 = SantanderChown.chown( path: iconURL.path, uid: 33, gid: 33)
            if(!chown2) {
                throw NSError(domain: "IconThemer", code: 6, userInfo: [NSLocalizedDescriptionKey: "\(bundleIdentifier): 2nd chown failed"])
            }
        }
    }
}

struct LaraAppIconChange {
    let app: LaraThemedApp
    let icon: LaraThemedIcon?
}

final class IconThemeManager: ObservableObject {
    static let shared = IconThemeManager()

    @Published var themes: [LaraIconTheme] = []
    @Published var selectedThemeNames: [String]
    @Published var installedApps: [LaraThemedApp] = []
    @Published var isApplying = false
    @Published var applyProgress: Double = 0
    @Published var applyMessage = ""
    @Published var isFixingUp = false
    @Published var fixupProgress: Double = 0
    @Published var fixupMessage = ""
    @Published var showFixupSheet = false
    private let mgr = laramgr.shared

    private let fm = FileManager.default
    private let selectedThemesKey = "lara.iconThemes.selectedThemes"
    private let iconOverridesKey = "lara.iconThemes.iconOverrides"
    private let pendingFixupKey = "lara.iconThemes.pendingFixup"
    private init() {
        self.selectedThemeNames = UserDefaults.standard.stringArray(forKey: selectedThemesKey) ?? []
        refreshThemes()
    }

    var hasPendingFixup: Bool {
        UserDefaults.standard.bool(forKey: pendingFixupKey)
    }

    var iconOverrides: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: iconOverridesKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: iconOverridesKey) }
    }

    var selectedThemes: [LaraIconTheme] {
        selectedThemeNames.compactMap { name in
            themes.first(where: { $0.name == name })
        }
    }

    var preferredIcons: [String: LaraThemedIcon] {
        var result: [String: LaraThemedIcon] = [:]
        for theme in selectedThemes {
            if let icons = try? fm.contentsOfDirectory(at: theme.url, includingPropertiesForKeys: nil) {
                for icon in icons {
                    let appID = appIDFromIcon(url: icon)
                    result[appID] = LaraThemedIcon(appID: appID, themeName: theme.name)
                }
            }
        }
        for (bundleID, themeName) in iconOverrides {
            result[bundleID] = LaraThemedIcon(appID: bundleID, themeName: themeName)
        }
        return result
    }
    
    func icon_logmsg(_ message: String) {
        DispatchQueue.main.async {
            self.mgr.log += "(icon) " + message + "\n"
            globallogger.log("(icon) " + message)
        }
    }

    func unzip_logmsg(_ message: String) {
        DispatchQueue.main.async {
            self.mgr.log += "(zip) " + message + "\n"
            globallogger.log("(zip) " + message)
        }
    }

    func theme(named name: String) -> LaraIconTheme? {
        themes.first(where: { $0.name == name })
    }

    func saveSelection() {
        UserDefaults.standard.set(selectedThemeNames, forKey: selectedThemesKey)
    }

    func toggleThemeSelection(_ theme: LaraIconTheme) {
        if let idx = selectedThemeNames.firstIndex(of: theme.name) {
            selectedThemeNames.remove(at: idx)
        } else {
            selectedThemeNames.append(theme.name)
        }
        saveSelection()
    }

    func removeOverride(for bundleID: String) {
        var overrides = iconOverrides
        overrides[bundleID] = nil
        iconOverrides = overrides
    }

    func setOverride(bundleID: String, themeName: String) {
        var overrides = iconOverrides
        overrides[bundleID] = themeName
        iconOverrides = overrides
    }

    func createDirectoriesIfNeeded() {
        try? fm.createDirectory(at: rawThemesDir, withIntermediateDirectories: true, attributes: nil)
        try? fm.createDirectory(at: processedThemesDir, withIntermediateDirectories: true, attributes: nil)
        try? fm.createDirectory(at: originalIconsDir, withIntermediateDirectories: true, attributes: nil)
    }

    func refreshThemes() {
        createDirectoriesIfNeeded()
        let contents = (try? fm.contentsOfDirectory(at: rawThemesDir, includingPropertiesForKeys: nil)) ?? []
        let sortedThemes = contents
            .filter { $0.hasDirectoryPath }
            .map { url in
                LaraIconTheme(name: url.lastPathComponent, iconCount: ((try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension.lowercased() == "png" }.count)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let publish = {
            self.themes = sortedThemes
            self.selectedThemeNames.removeAll { selected in
                !self.themes.contains(where: { $0.name == selected })
            }
        }
        if Thread.isMainThread {
            publish()
        } else {
            DispatchQueue.main.sync(execute: publish)
        }
        saveSelection()
    }

    func refreshApps() throws {
        let systemApplicationsURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let userApplicationsURL = URL(fileURLWithPath: "/var/containers/Bundle/Application", isDirectory: true)
        var dotAppDirs: [URL] = []

        dotAppDirs += (try? fm.contentsOfDirectory(at: systemApplicationsURL, includingPropertiesForKeys: nil)) ?? []
        let userAppsDir = (try? fm.contentsOfDirectory(at: userApplicationsURL, includingPropertiesForKeys: nil)) ?? []
        for folder in userAppsDir {
            let contents = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            if let dotApp = contents.first(where: { $0.absoluteString.hasSuffix(".app/") }) {
                dotAppDirs.append(dotApp)
            }
        }

        var apps: [LaraThemedApp] = []
        for bundleURL in dotAppDirs {
            let infoPlistURL = bundleURL.appendingPathComponent("Info.plist")
            guard fm.fileExists(atPath: infoPlistURL.path) else { continue }
            guard let infoPlist = NSDictionary(contentsOf: infoPlistURL) as? [String: AnyObject],
                  let bundleID = infoPlist["CFBundleIdentifier"] as? String else { continue }

            var app = LaraThemedApp(
                bundleIdentifier: bundleID,
                name: (infoPlist["CFBundleDisplayName"] as? String) ?? (infoPlist["CFBundleName"] as? String) ?? bundleURL.lastPathComponent,
                version: (infoPlist["CFBundleShortVersionString"] as? String) ?? (infoPlist["CFBundleVersion"] as? String) ?? "1",
                bundleURL: bundleURL,
                pngIconPaths: [],
                hiddenFromSpringboard: false
            )

            if bundleID == "com.apple.mobiletimer" {
                app.pngIconPaths.append("circle_borderless@2x~iphone.png")
            }

            if let icons = infoPlist["CFBundleIcons"] as? [String: AnyObject],
               let primary = icons["CFBundlePrimaryIcon"] as? [String: AnyObject] {
                if let iconFiles = primary["CFBundleIconFiles"] as? [String] {
                    app.pngIconPaths += iconFiles.map { $0.hasSuffix(".png") ? $0 : $0 + "@2x.png" }
                }
            }

            if let bundleIconFile = infoPlist["CFBundleIconFile"] as? String {
                app.pngIconPaths.append(bundleIconFile.hasSuffix(".png") ? bundleIconFile : bundleIconFile + ".png")
            }
            if let bundleIconFiles = infoPlist["CFBundleIconFiles"] as? [String], !bundleIconFiles.isEmpty {
                app.pngIconPaths += bundleIconFiles.map { $0.hasSuffix(".png") ? $0 : $0 + ".png" }
            }
            if let tags = infoPlist["SBAppTags"] as? [String], tags.contains("hidden") {
                app.hiddenFromSpringboard = true
            }

            app.pngIconPaths = Array(NSOrderedSet(array: app.pngIconPaths)) as? [String] ?? app.pngIconPaths
            apps.append(app)
        }

        let sortedApps = apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if Thread.isMainThread {
            installedApps = sortedApps
        } else {
            DispatchQueue.main.sync { self.installedApps = sortedApps }
        }
    }

    func icons(forAppIDs appIDs: [String], from theme: LaraIconTheme) -> [UIImage?] {
        appIDs.map { try? icon(forAppID: $0, from: theme) }
    }

    func icon(forAppID appID: String, from theme: LaraIconTheme) throws -> UIImage {
        let path = theme.url.appendingPathComponent(appID + ".png").path
        guard let image = UIImage(contentsOfFile: path) else {
            throw NSError(domain: "IconThemer", code: 7, userInfo: [NSLocalizedDescriptionKey: "Could not open image"])
        }
        return image
    }

    func availableOverrideChoices(for bundleID: String) -> [(theme: LaraIconTheme, image: UIImage)] {
        themes.compactMap { theme in
            guard let image = try? icon(forAppID: bundleID, from: theme) else { return nil }
            return (theme, image)
        }
    }

    func importTheme(from importURL: URL) throws {
        try importTheme(from: importURL, preferredName: nil)
    }

    func importTheme(from importURL: URL, preferredName: String?) throws {
        createDirectoriesIfNeeded()

        let workingURL = importURL.resolvingSymlinksInPath()
        let derivedThemeName = workingURL.deletingPathExtension().lastPathComponent
        let finalThemeName = sanitizedThemeName(preferredName ?? derivedThemeName)

        let sourceDirectory: URL
        if workingURL.hasDirectoryPath {
            sourceDirectory = try resolveThemeSourceDirectory(from: workingURL)
        } else {
            let ext = workingURL.pathExtension.lowercased()
            if ext == "theme" || ext == "zip" {
                let tempDir = fm.temporaryDirectory.appendingPathComponent("theme_import_\(UUID().uuidString)", isDirectory: true)
                try fm.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
                defer { try? fm.removeItem(at: tempDir) }

                let extractDir = tempDir.appendingPathComponent("Extracted", isDirectory: true)
                try fm.createDirectory(at: extractDir, withIntermediateDirectories: true, attributes: nil)
                
                let archivePath = tempDir.appendingPathComponent("import.\(ext == "zip" ? "zip" : "theme")")
                let attrs = try fm.attributesOfItem(atPath: workingURL.path)
                let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
                guard size > 0, size <= 128 * 1024 * 1024 else {
                    throw NSError(domain: "IconTheme", code: 9, userInfo: [NSLocalizedDescriptionKey: "Theme archive too large."])
                }
                try Data(contentsOf: workingURL).write(to: archivePath)
                try unzipFile(at: archivePath, to: extractDir)
                let resolvedSource = try resolveThemeSourceDirectory(from: extractDir)
                let themeURL = rawThemesDir.appendingPathComponent(finalThemeName, isDirectory: true)
                try? fm.removeItem(at: themeURL)
                try fm.createDirectory(at: themeURL, withIntermediateDirectories: true, attributes: nil)

                for icon in (try? fm.contentsOfDirectory(at: resolvedSource, includingPropertiesForKeys: nil)) ?? [] {
                    guard icon.pathExtension.lowercased() == "png" else { continue }
                    let appID = appIDFromIcon(url: icon)
                    let destination = themeURL.appendingPathComponent(appID + ".png")
                    try? fm.removeItem(at: destination)
                    do {
                        try fm.copyItem(at: icon, to: destination)
                        icon_logmsg("copied icon: \(appID)")
                    } catch {
                        icon_logmsg("copy fail: \(appID) -> \(error.localizedDescription)")
                    }
                }

                let importedIcons = ((try? fm.contentsOfDirectory(at: themeURL, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension.lowercased() == "png" }
                if importedIcons.isEmpty {
                    try? fm.removeItem(at: themeURL)
                    throw NSError(domain: "IconThemer", code: 9, userInfo: [NSLocalizedDescriptionKey: "No icons were found in the imported theme. Expected `<bundle-id>.png` in a folder."])
                }

                refreshThemes()
                return
            } else {
                throw NSError(domain: "IconThemer", code: 8, userInfo: [NSLocalizedDescriptionKey: "Unsupported theme import type: \(workingURL.lastPathComponent)"])
            }
        }

        let themeURL = rawThemesDir.appendingPathComponent(finalThemeName, isDirectory: true)
        try? fm.removeItem(at: themeURL)
        try fm.createDirectory(at: themeURL, withIntermediateDirectories: true, attributes: nil)

        for icon in (try? fm.contentsOfDirectory(at: sourceDirectory, includingPropertiesForKeys: nil)) ?? [] {
            guard icon.pathExtension.lowercased() == "png" else { continue }
            let appID = appIDFromIcon(url: icon)
            let destination = themeURL.appendingPathComponent(appID + ".png")
            try? fm.removeItem(at: destination)
            do {
                try fm.copyItem(at: icon, to: destination)
                icon_logmsg("copied icon: \(appID)")
            } catch {
                icon_logmsg("copy fail: \(appID) -> \(error.localizedDescription)")
            }
        }

        let importedIcons = ((try? fm.contentsOfDirectory(at: themeURL, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension.lowercased() == "png" }
        if importedIcons.isEmpty {
            try? fm.removeItem(at: themeURL)
            throw NSError(domain: "IconThemer", code: 9, userInfo: [NSLocalizedDescriptionKey: "No icons were found in the imported theme. Expected `<bundle-id>.png` in a folder."])
        }

        refreshThemes()
    }

    func removeTheme(_ theme: LaraIconTheme) throws {
        try? fm.removeItem(at: theme.cacheURL)
        try fm.removeItem(at: theme.url)
        selectedThemeNames.removeAll { $0 == theme.name }
        saveSelection()

        var overrides = iconOverrides
        overrides = overrides.filter { $0.value != theme.name }
        iconOverrides = overrides

        refreshThemes()
    }

    func neededChanges() throws -> [LaraAppIconChange] {
        if installedApps.isEmpty {
            try refreshApps()
        }

        let preferredIcons = preferredIcons
        return installedApps
            .filter { !$0.hiddenFromSpringboard && !$0.pngIconPaths.isEmpty }
            .map { app in
                if let themedIcon = preferredIcons[app.bundleIdentifier] {
                    return LaraAppIconChange(app: app, icon: themedIcon)
                }

                var bundleComponents = app.bundleIdentifier.components(separatedBy: ".")
                if bundleComponents.count > 2 {
                    bundleComponents.removeLast()
                    let parentBundleID = bundleComponents.joined(separator: ".")
                    if let themedIcon = preferredIcons[parentBundleID] {
                        return LaraAppIconChange(app: app, icon: themedIcon)
                    }
                }

                return LaraAppIconChange(app: app, icon: nil)
            }
    }

    @discardableResult
    func applyThemes() throws -> [String] {
        // Atomically claim the apply slot on the main queue so a second tap cannot race.
        let claimed: Bool = {
            let claim = {
                if self.isApplying { return false }
                self.isApplying = true
                self.applyProgress = 0
                self.applyMessage = "Preparing icon changes..."
                return true
            }
            if Thread.isMainThread { return claim() }
            return DispatchQueue.main.sync(execute: claim)
        }()
        guard claimed else {
            throw NSError(
                domain: "IconThemeManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Icon theme apply is already in progress."]
            )
        }

        createDirectoriesIfNeeded()
        let changes = try neededChanges()
        let changeCount = max(Double(changes.count), 1.0)
        var errors: [String] = []
        var themedCount = 0

        defer {
            DispatchQueue.main.async {
                self.isApplying = false
            }
        }

        for (index, change) in changes.enumerated() {
            autoreleasepool {
                DispatchQueue.main.async {
                    self.applyProgress = Double(index) / changeCount
                    self.applyMessage = "Applying \(change.app.name)"
                }

                do {
                    if let icon = change.icon {
                        guard change.app.backUpPNGIcons() else {
                            errors.append("\(change.app.name): backup failed — skipping theme apply")
                            return
                        }
                        try? fm.createDirectory(at: processedThemesDir.appendingPathComponent(icon.themeName), withIntermediateDirectories: true, attributes: nil)
                        try change.app.setPNGIcons(icon: icon)
                        // Count only after a successful write so pendingFixup reflects real changes.
                        themedCount += 1
                    } else {
                        try change.app.restorePNGIcons()
                    }
                } catch {
                    errors.append(error.localizedDescription)
                }
            }
        }

        DispatchQueue.main.async {
            self.applyProgress = 1.0
            self.applyMessage = "Clearing icon cache..."
        }
        clearIconCache()

        UserDefaults.standard.set(themedCount > 0, forKey: pendingFixupKey)
        return errors
    }

    func startPendingFixupIfPossible() {
        guard hasPendingFixup, laramgr.shared.sbxready else { return }
        let claimed: Bool = {
            let claim = {
                if self.isFixingUp { return false }
                self.isFixingUp = true
                self.showFixupSheet = true
                self.fixupProgress = 0
                self.fixupMessage = "Restoring original app icons..."
                return true
            }
            if Thread.isMainThread { return claim() }
            return DispatchQueue.main.sync(execute: claim)
        }()
        guard claimed else { return }
        startPendingFixup(alreadyClaimed: true)
    }

    func startPendingFixup() {
        startPendingFixup(alreadyClaimed: false)
    }

    private func startPendingFixup(alreadyClaimed: Bool) {
        if !alreadyClaimed {
            let claimed: Bool = {
                let claim = {
                    guard self.hasPendingFixup, !self.isFixingUp else { return false }
                    self.isFixingUp = true
                    self.fixupProgress = 0
                    self.fixupMessage = "Restoring original app icons..."
                    return true
                }
                if Thread.isMainThread { return claim() }
                return DispatchQueue.main.sync(execute: claim)
            }()
            guard claimed else { return }
        } else {
            guard hasPendingFixup else {
                DispatchQueue.main.async { self.isFixingUp = false }
                return
            }
        }
        if installedApps.isEmpty {
            if Thread.isMainThread {
                try? refreshApps()
            } else {
                DispatchQueue.main.sync { try? self.refreshApps() }
            }
        }

        let apps = installedApps.filter { !$0.hiddenFromSpringboard && !$0.pngIconPaths.isEmpty }
        let appCount = max(Double(apps.count), 1.0)

        DispatchQueue.global(qos: .userInitiated).async {
            var errors: [String] = []
            for (index, app) in apps.enumerated() {
                DispatchQueue.main.async {
                    self.fixupProgress = Double(index) / appCount
                    self.fixupMessage = "Fixing \(app.name)"
                }
                do {
                    try app.restorePNGIcons()
                } catch {
                    errors.append(error.localizedDescription)
                }
            }

            DispatchQueue.main.async {
                self.fixupProgress = 1.0
                self.fixupMessage = errors.isEmpty ? "Your apps should now function properly." : errors.joined(separator: "\n\n")
                self.isFixingUp = false
                // Keep pending so a partial failure can be retried after the next open.
                if errors.isEmpty {
                    UserDefaults.standard.set(false, forKey: self.pendingFixupKey)
                }
            }
        }
    }

    func dismissFixupSheet() {
        showFixupSheet = false
    }

    func clearSelectionsForFullReset() {
        selectedThemeNames = []
        saveSelection()
        iconOverrides = [:]
    }

    private func iconFileEnding(iconFilename: String) -> String {
        if iconFilename.contains("-large@2x.png") {
            return "-large@2x"
        } else if iconFilename.contains("-large.png") {
            return "-large"
        } else if iconFilename.contains("@2x.png") {
            return "@2x"
        } else if iconFilename.contains("@3x.png") {
            return "@3x"
        }
        return ""
    }

    private func appIDFromIcon(url: URL) -> String {
        url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: iconFileEnding(iconFilename: url.lastPathComponent), with: "")
    }

    private func resolveThemeSourceDirectory(from url: URL) throws -> URL {
        icon_logmsg("resolve theme directory: \(url.path)")

        if url.lastPathComponent == "IconBundles" {
            icon_logmsg("using root iconbundles")
            return url
        }

        let iconBundlesURL = url.appendingPathComponent("IconBundles", isDirectory: true)
        if fm.fileExists(atPath: iconBundlesURL.path) {
            icon_logmsg("found direct iconbundles: \(iconBundlesURL.path)")
            return iconBundlesURL
        }

        if let subdir = try findIconBundlesDirectory(in: url) {
            icon_logmsg("found iconbundles in a subdirectory: \(subdir.path)")
            return subdir
        }

        if let pngDir = findFirstDirectoryContainingPNGs(in: url) {
            icon_logmsg("found png directory: \(pngDir.path)")
            return pngDir
        }

        icon_logmsg("failed to find theme directory")

        throw NSError(domain: "IconThemer", code: 10, userInfo: [
                NSLocalizedDescriptionKey:
                    "Could not find icons in \(url.lastPathComponent). Expected PNGs named <bundle-id>.png."
            ]
        )
    }

    private func findFirstDirectoryContainingPNGs(in root: URL) -> URL? {
        icon_logmsg("scanning root: \(root.path)")

        let rootPNGs = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil))?.filter { $0.pathExtension.lowercased() == "png" } ?? []

        if !rootPNGs.isEmpty {
            icon_logmsg("found png-s in root: \(root.path)")
            for png in rootPNGs {
                icon_logmsg("png: \(png.lastPathComponent)")
            }
            return root
        }

        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else {
            icon_logmsg("failed to create enumerator")
            return nil
        }

        for case let url as URL in enumerator {
            icon_logmsg("scanning directory \(url.path) ...")

            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }

            let pngs = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil))?.filter { $0.pathExtension.lowercased() == "png" } ?? []

            if !pngs.isEmpty {
                icon_logmsg("found png-s: \(url.path)")
                for png in pngs { icon_logmsg("png: \(png.lastPathComponent)") }
                return url
            } else { icon_logmsg("no png-s: \(url.lastPathComponent)") }
        }
        icon_logmsg("no directories found containing .png-s")
        return nil
    }

    private func sanitizedThemeName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "._- "))
        let cleanedScalars = name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        var cleaned = String(cleanedScalars).trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.contains("..") { cleaned = cleaned.replacingOccurrences(of: "..", with: "_") }
        cleaned = cleaned.replacingOccurrences(of: "/", with: "_")
        if cleaned.isEmpty || cleaned == "." || cleaned == ".." { return "Imported Theme" }
        return cleaned
    }

    private func findIconBundlesDirectory(in root: URL) throws -> URL? {
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return nil
        }

        for case let fileURL as URL in enumerator {
            if fileURL.lastPathComponent == "IconBundles" {
                return fileURL
            }
        }
        return nil
    }

    func unzipFile(at source: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(
            at: destination,
            withIntermediateDirectories: true
        )

        let srcAttrs = try FileManager.default.attributesOfItem(atPath: source.path)
        let srcSize = (srcAttrs[.size] as? NSNumber)?.int64Value ?? 0
        guard srcSize > 0, srcSize <= 128 * 1024 * 1024 else {
            throw NSError(domain: "IconTheme", code: 9, userInfo: [NSLocalizedDescriptionKey: "Theme archive too large."])
        }
        let archive = try ZipArchive(data: try Data(contentsOf: source))
        unzip_logmsg("zip entries: \(archive.entries.count)")

        for entry in archive.entries {
            unzip_logmsg("entry: \(entry.path)")

            let normalizedPath = entry.path.replacingOccurrences(of: "\\", with: "/")
            // Reject absolute paths, empty names, and obvious traversal before joining.
            let hasDotDot = normalizedPath.split(separator: "/").contains("..")
            guard !normalizedPath.isEmpty,
                  !normalizedPath.hasPrefix("/"),
                  !normalizedPath.hasPrefix("~"),
                  !hasDotDot else {
                unzip_logmsg("abort unsafe path: \(normalizedPath)")
                try? FileManager.default.removeItem(at: destination)
                throw NSError(domain: "IconTheme", code: 11, userInfo: [NSLocalizedDescriptionKey: "Theme archive contains unsafe path: \(normalizedPath)"])
            }
            let outputURL = destination.appendingPathComponent(normalizedPath).standardizedFileURL
            let destRoot = destination.standardizedFileURL.path
            let outPath = outputURL.path

            unzip_logmsg("output: \(outPath)")

            // Ensure resolved path stays under destination (blocks .. and symlink escapes).
            guard outPath == destRoot || outPath.hasPrefix(destRoot + "/") else {
                unzip_logmsg("abort path traversal: \(normalizedPath)")
                try? FileManager.default.removeItem(at: destination)
                throw NSError(domain: "IconTheme", code: 11, userInfo: [NSLocalizedDescriptionKey: "Theme archive path escapes destination: \(normalizedPath)"])
            }

            if entry.isDirectory {
                do {
                    try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
                } catch {
                    unzip_logmsg("mkdir fail: \(error.localizedDescription)")
                    try? FileManager.default.removeItem(at: destination)
                    throw error
                }

            } else {

                do {
                    try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    // Cap per-entry uncompressed size to blunt zip-bomb RAM spikes.
                    let maxEntryBytes = 16 * 1024 * 1024
                    guard entry.uncompressedSize <= maxEntryBytes else {
                        throw NSError(domain: "IconTheme", code: 10, userInfo: [NSLocalizedDescriptionKey: "Theme entry too large: \(entry.path)"])
                    }
                    let extracted = try archive.extract(entry)
                    guard extracted.count <= maxEntryBytes else {
                        throw NSError(domain: "IconTheme", code: 10, userInfo: [NSLocalizedDescriptionKey: "Theme entry inflated too large: \(entry.path)"])
                    }
                    unzip_logmsg("extracted size: \(extracted.count)")
                    
                    try extracted.write(to: outputURL)
                    unzip_logmsg("wrote to file")
                } catch {
                    unzip_logmsg("extract fail: \(entry.path) to \(error.localizedDescription)")
                    // Any entry failure must abort — partial themes corrupt icon apply.
                    try? FileManager.default.removeItem(at: destination)
                    throw error
                }
            }
        }

        unzip_logmsg("contents:")

        if let e = FileManager.default.enumerator(at: destination, includingPropertiesForKeys: nil) { for case let fileURL as URL in e { unzip_logmsg(fileURL.path) } }
    }
    
    private func findNextZipHeader(
        in data: Data,
        start: Int
    ) -> Int? {

        guard start < data.count - 4 else { return nil }

        for i in start..<(data.count - 4) {

            let sig = data.subdata(in: i..<i + 4)
                .withUnsafeBytes {
                    UInt32(littleEndian: $0.load(as: UInt32.self))
                }

            if sig == 0x04034b50 {
                return i
            }

            if sig == 0x02014b50 {
                return i
            }

            if sig == 0x06054b50 {
                return i
            }
        }

        return nil
    }
}

struct IconThemeFixupView: View {
    @ObservedObject var manager = IconThemeManager.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: manager.isFixingUp ? "gear" : "checkmark.seal")
                    .font(.system(size: 64))
                    .foregroundStyle(manager.isFixingUp ? .orange : .green)

                Text(manager.isFixingUp ? "Fixing apps..." : "Fixup complete")
                    .font(.title2.bold())

                Text(manager.fixupMessage.isEmpty ? "Reopen lara after respring and initialize SBX so icon backups can be restored." : manager.fixupMessage)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                ProgressView(value: manager.fixupProgress, total: 1.0)
                    .padding(.horizontal)

                Spacer()

                Button(manager.isFixingUp ? "Please wait" : "Close") {
                    manager.dismissFixupSheet()
                }
                .buttonStyle(.borderedProminent)
                .disabled(manager.isFixingUp)
                .padding(.bottom)
            }
            .navigationTitle("Icon Fixup")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

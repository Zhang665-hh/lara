//
//  GetLicenseDict.swift
//  PartyUI
//
//  Created by lunginspector on 2/14/26.
//

import Foundation

public func getLicenseDict() -> [String: String] {
    var licenseDict: [String: String] = [:]
    let fm = FileManager.default
    let bundleURL = Bundle.main.bundleURL

    // Search both the bundle root and a nested licenses/ folder.
    var searchURLs: [URL] = [bundleURL]
    let nested = bundleURL.appendingPathComponent("licenses", isDirectory: true)
    if fm.fileExists(atPath: nested.path) {
        searchURLs.append(nested)
    }

    for directory in searchURLs {
        guard let urls = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            continue
        }
        for url in urls {
            let fileName = url.deletingPathExtension().lastPathComponent
            let fileExtension = url.pathExtension.lowercased()
            guard fileName.hasPrefix("LICENSE_"), fileExtension == "md" || fileExtension == "txt" else {
                continue
            }
            if let licenseText = try? String(contentsOf: url, encoding: .utf8) {
                licenseDict[fileName] = licenseText
            }
        }
    }
    return licenseDict
}

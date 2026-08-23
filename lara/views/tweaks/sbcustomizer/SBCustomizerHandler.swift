//
//  SBCustomizerHandler.swift
//  lara
//
//  Created by lunginspector on 5/18/26.
//

import SwiftUI

class SpringboardColorManager {
    enum SpringboardType: CaseIterable {
        case dock
        case folder
        case folderBG
        case libraryFolder
        case switcher
        case notif
        case notifShadow
        case module
        case moduleBG
    }
    
    private static let finalFiles: [SpringboardType: [String]] = [
        .folder: ["folderDark", "folderLight"],
        .libraryFolder: ["podBackgroundViewDark", "podBackgroundViewLight"],
        .dock: ["dockDark", "dockLight"],
        .folderBG: ["folderExpandedBackgroundHome", "homeScreenOverlay", "homeScreenOverlay-iPad"],
        .switcher: ["homeScreenBackdrop-application"],
        .notif: ["plattersDark", "platters"],
        .notifShadow: ["platterVibrantShadowDark", "platterVibrantShadowLight"],
        .module: ["modules"],
        .moduleBG: ["modulesBackground"]
    ]
    
    private static let fileFolders: [SpringboardType: String] = [
        .folder: "/System/Library/PrivateFrameworks/SpringBoardHome.framework/",
        .libraryFolder: "/System/Library/PrivateFrameworks/SpringBoardHome.framework/",
        .dock: "/System/Library/PrivateFrameworks/CoreMaterial.framework/",
        .folderBG: "/System/Library/PrivateFrameworks/SpringBoardHome.framework/",
        .switcher: "/System/Library/PrivateFrameworks/SpringBoard.framework/",
        .notif: "/System/Library/PrivateFrameworks/CoreMaterial.framework/",
        .notifShadow: "/System/Library/PrivateFrameworks/PlatterKit.framework/",
        .module: "/System/Library/PrivateFrameworks/CoreMaterial.framework/",
        .moduleBG: "/System/Library/PrivateFrameworks/CoreMaterial.framework/"
    ]
    
    private static let fileExt: [SpringboardType: String] = [
        .folder: ".materialrecipe",
        .libraryFolder: ".visualstyleset",
        .dock: ".materialrecipe",
        .folderBG: ".materialrecipe",
        .switcher: ".materialrecipe",
        .notif: ".materialrecipe",
        .notifShadow: ".visualstyleset",
        .module: ".materialrecipe",
        .moduleBG: ".materialrecipe"
    ]
    
    static func getDictValue(_ dict: [String: Any], _ key: String) -> Any? {
        for (k, v) in dict {
            if k == key {
                return dict[k]
            } else if let subDict = v as? [String: Any] {
                let temp: Any? = getDictValue(subDict, key)
                if temp != nil {
                    return temp
                }
            }
        }
        // did not find key in dictionary
        return nil
    }
    
    static func getColor(forType: SpringboardType) -> Color {
        guard let bgDir = getBackgroundDirectory(),
              let files = finalFiles[forType], let first = files.first,
              let ext = fileExt[forType] else {
            return Color.gray
        }
        let fileURL = bgDir.appendingPathComponent("\(first)\(ext)")
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return Color.gray
        }
        do {
            let newData = try Data(contentsOf: fileURL)
            guard let plist = try PropertyListSerialization.propertyList(from: newData, options: [], format: nil) as? [String: Any] else {
                throw "Invalid property list format"
            }
            // get the colors
            let r = getDictValue(plist, "red") as? Double ?? CIColor.gray.red
            let g = getDictValue(plist, "green") as? Double ?? CIColor.gray.green
            let b = getDictValue(plist, "blue") as? Double ?? CIColor.gray.blue
            let mFactor = getAlphaMultiplier(forType: forType)
            let a = (getDictValue(plist, "tintAlpha") as? Double ?? mFactor)/mFactor
            
            return Color.init(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b)).opacity(a)
        } catch {
            print(error.localizedDescription)
        }
        return Color.gray
    }
    
    static func getBlur(forType: SpringboardType) -> Double {
        guard let bgDir = getBackgroundDirectory(),
              let files = finalFiles[forType], let first = files.first,
              let ext = fileExt[forType] else {
            return 30
        }
        let fileURL = bgDir.appendingPathComponent("\(first)\(ext)")
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return 30
        }
        do {
            let newData = try Data(contentsOf: fileURL)
            guard let plist = try PropertyListSerialization.propertyList(from: newData, options: [], format: nil) as? [String: Any] else {
                throw "Invalid property list format"
            }
            // get the blur
            return getDictValue(plist, "blurRadius") as? Double ?? 30
        } catch {
            print(error.localizedDescription)
        }
        return 30
    }
    
    static func revertFiles(forType: SpringboardType) throws {
        guard let files = finalFiles[forType],
              let folder = fileFolders[forType],
              let ext = fileExt[forType] else {
            throw "File type doesn't exist in table???"
        }
        for file in files {
            guard let url = Bundle.main.url(forResource: file, withExtension: ext) else {
                throw "No file resource was found!"
            }
            let replacementFile = try Data(contentsOf: url)
            let result = laramgr.shared.lara_overwritefile(target: "\(folder)\(file)\(ext)", data: replacementFile)
            if !result.ok {
                throw "failed to overwrite with replacement file!"
            }
        }
    }
    
//    static func changeColor(plist: [String: Any], color: CIColor, blur: Int) throws {
//        var newPlist: [String: Any] = plist
//
//
//    }
    
    static func getAlphaMultiplier(forType: SpringboardType) -> Double {
        if forType == .module {
            return 0.8
        } else if forType == .moduleBG || forType == .notifShadow || forType == .notif || forType == .folder || forType == .folderBG {
            return 1
        } else {
            return 0.3
        }
    }
    
    static func createColorOLD(forType: SpringboardType, color: CIColor, blur: Int, asTemp: Bool = false) throws {
        guard let bgDir = getBackgroundDirectory(),
              let files = finalFiles[forType],
              let folder = fileFolders[forType],
              let ext = fileExt[forType] else {
            throw "Could not find the background files directory!"
        }

        guard let url = Bundle.main.url(forResource: "replacement", withExtension: ".materialrecipe") else {
            throw "No replacement materialrecipe resource was found!"
        }

        do {
            let plistData = try Data(contentsOf: url)
            guard var plist = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any] else {
                throw "Invalid property list format"
            }

            if var firstLevel = plist["baseMaterial"] as? [String : Any], var secondLevel = firstLevel["tinting"] as? [String: Any], var thirdLevel = secondLevel["tintColor"] as? [String: Any] {
                thirdLevel["red"] = color.red
                thirdLevel["green"] = color.green
                thirdLevel["blue"] = color.blue
                thirdLevel["alpha"] = 1

                if var secondLevel2 = firstLevel["materialFiltering"] as? [String: Any] {
                    secondLevel2["blurRadius"] = blur
                    firstLevel["materialFiltering"] = secondLevel2
                }

                secondLevel["tintColor"] = thirdLevel
                secondLevel["tintAlpha"] = color.alpha*(getAlphaMultiplier(forType: forType))
                firstLevel["tinting"] = secondLevel
                plist["baseMaterial"] = firstLevel
            }

            if forType == .module {
                let styles: [String: String] = [
                    "fill": "moduleFill",
                    "stroke": "moduleStroke"
                ]
                plist["styles"] = styles
                plist["materialSettingsVersion"] = 2
            }

            for file in files {
                let path: String = "\(folder)\(file)\(ext)"
                let newUrl = URL(fileURLWithPath: path)
                do {
                    let originalFileSize = try Data(contentsOf: newUrl).count
                    let newData = try addEmptyData(matchingSize: originalFileSize, to: plist)
                    guard newData.count == originalFileSize else {
                        throw "Not the correct file size for item \(file+ext)! (\(newData.count) vs \(originalFileSize))"
                    }
                    if asTemp {
                        try newData.write(to: FileManager.default.temporaryDirectory.appendingPathComponent(file+ext))
                    } else {
                        try newData.write(to: bgDir.appendingPathComponent(file+ext))
                    }
                } catch {
                    print(error.localizedDescription)
                    throw error.localizedDescription
                }
            }
        } catch {
            throw error.localizedDescription
        }
    }

    static func createColor(forType: SpringboardType, color: CIColor, blur: Int, asTemp: Bool = false) throws {
        guard let bgDir = getBackgroundDirectory(),
              let files = finalFiles[forType],
              let folder = fileFolders[forType],
              let ext = fileExt[forType] else {
            throw "Could not find the background files directory!"
        }

        if ext == ".materialrecipe" && forType != .switcher {
            try createColorOLD(forType: forType, color: color, blur: blur, asTemp: asTemp)
            return
        }
        if forType == .switcher {
            for file in files {
                let path: String = "\(folder)\(file)\(ext)"
                let plistData = try Data(contentsOf: URL(fileURLWithPath: path))
                guard var plist = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any] else {
                    throw "Invalid property list format"
                }

                if var firstLevel = plist["baseMaterial"] as? [String : Any], var secondLevel = firstLevel["materialFiltering"] as? [String: Any] {
                    secondLevel["blurRadius"] = blur
                    firstLevel["materialFiltering"] = secondLevel
                    plist["baseMaterial"] = firstLevel
                }
                plist["materialSettingsVersion"] = nil

                let newUrl = URL(fileURLWithPath: path)
                do {
                    let originalFileSize = try Data(contentsOf: newUrl).count
                    let newData = try addEmptyData(matchingSize: originalFileSize, to: plist)
                    if newData.count == originalFileSize {
                        let dest = asTemp
                            ? FileManager.default.temporaryDirectory.appendingPathComponent(file+ext)
                            : bgDir.appendingPathComponent(file+ext)
                        if FileManager.default.fileExists(atPath: dest.path) {
                            try FileManager.default.removeItem(at: dest)
                        }
                        try newData.write(to: dest)
                    } else {
                        print("NOT CORRECT SIZE")
                        throw "Not the correct file size for item \(file+ext)!"
                    }
                } catch {
                    print(error.localizedDescription)
                    throw error.localizedDescription
                }
            }
            return
        }
        for file in files {
            guard let url = Bundle.main.url(forResource: file, withExtension: ext) else {
                throw "Backup url could not be found!"
            }
            let newColor: CIColor = CIColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha*getAlphaMultiplier(forType: forType))
            let newData = try ColorSwapManager.setColor(url: url, color: newColor, blur: blur)
            let dest = asTemp
                ? FileManager.default.temporaryDirectory.appendingPathComponent(file+ext)
                : bgDir.appendingPathComponent(file+ext)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try newData.write(to: dest)
        }
    }

    static func deteleColor(forType: SpringboardType) throws {
        guard let bgDir = getBackgroundDirectory(),
              let files = finalFiles[forType],
              let ext = fileExt[forType] else {
            throw "Could not find the background files directory!"
        }
        for file in files {
            let path = bgDir.appendingPathComponent(file + ext)
            if FileManager.default.fileExists(atPath: path.path) {
                try FileManager.default.removeItem(at: path)
            }
        }
    }
    
    static func applyColor(forType: SpringboardType, asTemp: Bool = false) throws {
        guard let bgDir = getBackgroundDirectory(),
              let files = finalFiles[forType],
              let folder = fileFolders[forType],
              let ext = fileExt[forType] else {
            throw "Could not find the background files directory!"
        }

        // Stage all replacements first; refuse partial SpringBoard material writes.
        var staged: [(target: String, data: Data, backup: Data)] = []
        for file in files {
            let sourceURL: URL
            if asTemp {
                sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent(file + ext)
            } else {
                sourceURL = bgDir.appendingPathComponent(file + ext)
            }
            let target = "\(folder)\(file)\(ext)"
            let newData = try Data(contentsOf: sourceURL)
            guard !newData.isEmpty else {
                throw "refusing empty replacement for \(file)\(ext)"
            }
            let backup = try Data(contentsOf: URL(fileURLWithPath: target))
            guard !backup.isEmpty else {
                throw "refusing empty target for \(file)\(ext)"
            }
            staged.append((target, newData, backup))
        }

        var appliedBackups: [(path: String, backup: Data)] = []
        do {
            for item in staged {
                let result = laramgr.shared.lara_overwritefile(target: item.target, data: item.data)
                guard result.ok else {
                    throw "\(item.target): \(result.message)"
                }
                appliedBackups.append((item.target, item.backup))
            }
        } catch {
            for item in appliedBackups.reversed() {
                _ = laramgr.shared.lara_overwritefile(target: item.path, data: item.backup)
            }
            throw error
        }
    }
    
    // get the directory of where background files are saved
    static func getBackgroundDirectory() -> URL? {
        do {
            let newURL: URL = URL.documents.appendingPathComponent("Background_Files")
            if !FileManager.default.fileExists(atPath: newURL.path) {
                try FileManager.default.createDirectory(at: newURL, withIntermediateDirectories: false)
            }
            return newURL
        } catch {
            print("An error occurred getting/making the background files directory")
        }
        return nil
    }
}

// MARK: whatever this is
class ColorSwapManager {
    public static func setColor(url: URL, color: CIColor, blur: Int) throws -> Data {
        let plistData = try Data(contentsOf: url)
        if let originalPlist = try PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any] {
            var plist = setColor(list: originalPlist, color: color, blur: blur)
            let newData = try addEmptyData(matchingSize: plistData.count, to: plist)
            if newData.count == plistData.count {
                return newData
            } else {
                throw "File size does not match!!!\nNew: \(newData.count)\nOld: \(plistData.count)"
            }
        } else {
            throw "Error serializing original plist data!"
        }
    }
    
    public static func setColor(list: [String: Any], color: CIColor, blur: Int) -> [String: Any] {
        func changeValue(dict: [String: Any], keyName: String, newName: String, replacement: Any, remove: Bool = true, appends: Bool = false) -> [String: Any] {
            var newDict = dict
            for (k, _) in dict {
                if k == keyName {
                    if remove {
                        newDict[k] = nil
                        newDict[newName] = replacement
                    } else {
                        if appends, var repDict = dict[k] as? [String: Any] {
                            repDict[newName] = replacement
                            newDict[k] = repDict
                        } else {
                            newDict[k] = [newName: replacement]
                        }
                    }
                } else if let subdict = dict[k] as? [String: Any] {
                    newDict[k] = changeValue(dict: subdict, keyName: keyName, newName: newName, replacement: replacement, remove: remove)
                }
            }
            return newDict
        }
        
        var changed = list
        changed["materialSettingsVersion"] = nil
        changed["visualStyleSetVersion"] = nil
        changed["MdC"] = nil
        
        let tintColor: [String: Double] = [
            "alpha": color.alpha,
            "red": color.red,
            "green": color.green,
            "blue": color.blue
        ]
        let tinting: [String: Any] = [
            "tintAlpha": color.alpha,
            "tintColor": tintColor
        ]
        
        let newMaterialFiltering: [String: Any] = [
            "blurRadius": blur,
            "tinting": tinting
        ]
        
        changed = changeValue(dict: changed, keyName: "blurRadius", newName: "blurRadius", replacement: blur)
        changed = changeValue(dict: changed, keyName: "materialFiltering", newName: "materialFiltering", replacement: newMaterialFiltering)
        changed = changeValue(dict: changed, keyName: "filtering", newName: "tinting", replacement: tinting)
        
        // return it
        return changed
    }
}

// MARK: what the fuck is this lemin???
func addEmptyData(matchingSize: Int, to plist: [String: Any]) throws -> Data {
    var newPlist = plist
    // create the new data
    guard var newData = try? PropertyListSerialization.data(fromPropertyList: newPlist, format: .binary, options: 0) else { throw "Unable to get data" }
    // add data if too small
    // while loop to make data match because recursive function didn't work
    // very slow, will hopefully improve
    if newData.count == matchingSize {
        return newData
    }
    var newDataSize = newData.count
    var added = matchingSize - newDataSize
    if added < 0 {
        added = 1
    }
    var count = 0
    while newDataSize != matchingSize && count < 200 {
        count += 1
        if added < 0 {
            print("LESS THAN 0")
            break
        }
        newPlist.updateValue(String(repeating: "#", count: added), forKey: "MdC")
        do {
            newData = try PropertyListSerialization.data(fromPropertyList: newPlist, format: .binary, options: 0)
        } catch {
            newDataSize = -1
            print("ERROR SERIALIZING DATA")
            break
        }
        newDataSize = newData.count
        if count < 5 {
            // max out this method at 5 if it isn't working
            added += matchingSize - newDataSize
        } else {
            if newDataSize > matchingSize {
                added -= 1
            } else if newDataSize < matchingSize {
                added += 1
            }
        }
    }

    guard newData.count == matchingSize else {
        throw "Unable to pad plist to exact size (\(newData.count) vs \(matchingSize))"
    }
    return newData
}

// MARK: i actually like this
extension URL {
    static var documents: URL {
        return FileManager
            .default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}


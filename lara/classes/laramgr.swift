//
//  laramgr.swift
//  lara
//
//  Created by ruter on 23.03.26.
//

import Combine
import Foundation
import Darwin
import notify
import UIKit
import WebKit

private func loadMutablePropertyListDictionary(from url: URL) throws -> NSMutableDictionary {
    let data = try Data(contentsOf: url)
    var format = PropertyListSerialization.PropertyListFormat.binary
    let plist = try PropertyListSerialization.propertyList(
        from: data,
        options: [.mutableContainersAndLeaves],
        format: &format
    )
    guard let dict = plist as? NSMutableDictionary else {
        throw "Property list root is not a dictionary."
    }
    return dict
}

/// Flags cleared for an overwrite attempt; must be restored even if rename/VFS fails
/// so system files are never left unexpectedly mutable on iOS 16.
private struct ClearedImmutableFlags {
    let path: String
    let restore: [FileAttributeKey: Any]
}

private func clearImmutableForOverwriteIfNeeded(path: String) -> (cleared: ClearedImmutableFlags?, errorMessage: String?) {
    let majorVersion = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    guard majorVersion == 16 else { return (nil, nil) }

    let fm = FileManager.default
    guard let attributes = try? fm.attributesOfItem(atPath: path) else { return (nil, nil) }

    var updates: [FileAttributeKey: Any] = [:]
    var restore: [FileAttributeKey: Any] = [:]
    if (attributes[.immutable] as? NSNumber)?.boolValue == true {
        updates[.immutable] = false
        restore[.immutable] = true
    }
    if (attributes[.appendOnly] as? NSNumber)?.boolValue == true {
        updates[.appendOnly] = false
        restore[.appendOnly] = true
    }
    guard !updates.isEmpty else { return (nil, nil) }

    do {
        try fm.setAttributes(updates, ofItemAtPath: path)
        return (ClearedImmutableFlags(path: path, restore: restore), nil)
    } catch {
        return (nil, "clear immutable failed: \(error.localizedDescription)")
    }
}

private func restoreImmutableFlagsIfNeeded(_ cleared: ClearedImmutableFlags?) {
    guard let cleared, !cleared.restore.isEmpty else { return }
    do {
        try FileManager.default.setAttributes(cleared.restore, ofItemAtPath: cleared.path)
    } catch {
        // Prefer noise over silent half-open mutable system files after a successful overwrite.
        print("(lara) restore immutable failed for \(cleared.path): \(error.localizedDescription)")
    }
}

final class laramgr: ObservableObject {
    @Published var log: String = ""
    @Published var hasOffsets: Bool = false
    @Published var dsrunning: Bool = false
    @Published var dsready: Bool = false
    @Published var dsattempted: Bool = false
    @Published var dsfailed: Bool = false
    @Published var dsprogress: Double = 0.0
    @Published var kernbase: UInt64 = 0
    @Published var kernslide: UInt64 = 0
    
    @Published var kaccessready: Bool = false
    @Published var kaccesserror: String?
    @Published var fileopinprogress: Bool = false
    @Published var testresult: String?
    #if !DISABLE_REMOTECALL
    @Published var rcrunning: Bool = false
    @Published var eligibilitystate: Bool?
    @Published var eu1progress: Double = 0.0
    @Published var eu1running: Bool = false
    @Published var eu2progress: Double = 0.0
    @Published var eu2running: Bool = false
    @Published var rcLastError: String?
    #endif
    
    @Published var vfsready: Bool = false
    @Published var vfsinitlog: String = ""
    @Published var vfsattempted: Bool = false
    @Published var vfsfailed: Bool = false
    @Published var vfsrunning: Bool = false
    @Published var vfsprogress: Double = 0.0
    @Published var sbxready: Bool = false
    @Published var sbxattempted: Bool = false
    @Published var sbxfailed: Bool = false
    @Published var sbxrunning: Bool = false
    @Published var rcready: Bool = false
    @Published var rcfailed: Bool = false
    @Published var showrespring: Bool = false
    
    @Published var showLogs: Bool = false
    
    var sbProc: RemoteCall?
    /// Lazily created; never eager-init at mgr construction (RemoteCall init can return nil / trap).
    var ytProc: RemoteCall?
    /// When true, `rcdestroy` was requested while `rcrunning` and should run once the session is idle.
    private var rcdestroyPending: Bool = false
    /// Completion to invoke when a deferred rcdestroy finally runs.
    private var rcdestroyPendingCompletion: (() -> Void)? = nil
    
    static let shared = laramgr()
    static let fontpath = "/System/Library/Fonts/Core/SFUI.ttf"
    static let italicfontpath = "/System/Library/Fonts/Core/SFUIItalic.ttf"
    static let monofontpath = "/System/Library/Fonts/Core/SFUIMono.ttf"
    init() {}

    struct AppInfo {
        let executable: String
        let displayName: String
        let bundleName: String
        let dataFolder: String
        let bundleFolder: String
    }
    
    func run(completion: ((Bool) -> Void)? = nil) {
        guard !dsrunning else { return }
        dsrunning = true
        dsready = false
        dsfailed = false
        dsattempted = true
        dsprogress = 0.0
        log = ""
        
        ds_set_log_callback { messageCStr in
            guard let messageCStr else { return }
            let message = String(cString: messageCStr)
            DispatchQueue.main.async {
                laramgr.shared.logmsg("(ds) \(message)")
            }
        }
        ds_set_progress_callback { progress in
            DispatchQueue.main.async {
                laramgr.shared.dsprogress = progress
            }
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = ds_run()
            
            DispatchQueue.main.async {
                guard let self else { return }
                self.dsrunning = false
                let success = result == 0 && ds_is_ready()
                if success {
                    self.dsready = true
                    self.dsfailed = false
                    self.kernbase = ds_get_kernel_base()
                    self.kernslide = ds_get_kernel_slide()
                    self.logmsg("\n(ds) exploit success!")
                    self.logmsg(String(format: "(ds) kernel_base:  0x%llx", self.kernbase))
                    self.logmsg(String(format: "(ds) kernel_slide: 0x%llx\n", self.kernslide))
                    globallogger.log("(ds) exploit success!")
                    globallogger.log(String(format: "(ds) kernel_base:  0x%llx", self.kernbase))
                    globallogger.log(String(format: "(ds) kernel_slide: 0x%llx", self.kernslide))
                    globallogger.divider()
                } else {
                    self.dsfailed = true
                    self.logmsg("\nexploit failed.\n")
                    globallogger.log("exploit failed.")
                    globallogger.divider()
                }
                self.dsprogress = 1.0
                completion?(success)
            }
        }
    }
    
    func logmsg(_ message: String) {
        DispatchQueue.main.async {
            self.log += message + "\n"
            globallogger.log(message)
        }
    }
    
    func kread64(address: UInt64) -> UInt64 {
        guard dsready else { return 0 }
        return ds_kread64(address)
    }
    
    func kwrite64(address: UInt64, value: UInt64) {
        guard dsready else { return }
        ds_kwrite64(address, value)
    }
    
    func kread32(address: UInt64) -> UInt32 {
        guard dsready else { return 0 }
        return ds_kread32(address)
    }
    
    func kwrite32(address: UInt64, value: UInt32) {
        guard dsready else { return }
        ds_kwrite32(address, value)
    }
    
    func panic() {
        guard dsready else { return }
        
        globallogger.log("triggering panic")
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            let kernbase = ds_get_kernel_base()
            globallogger.log("writing to read-only memory at kernel base")
            ds_kwrite64(kernbase, 0xDEADBEEF)
        }
    }
    
    func respring() {
        showrespring = true
    }
    
    func vfsinit(completion: ((Bool) -> Void)? = nil) {
        guard dsready, hasOffsets, !vfsrunning else { return }
        vfs_setlogcallback(laramgr.vfslogcallback)
        vfs_setprogresscallback { progress in
            DispatchQueue.main.async {
                laramgr.shared.vfsprogress = progress
            }
        }
        vfsattempted = true
        vfsfailed = false
        vfsrunning = true
        vfsprogress = 0.0
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let r = vfs_init()
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.vfsready = (r == 0 && vfs_isready())
                if self.vfsready {
                    self.vfsfailed = false
                    self.logmsg("\nvfs ready!\n")
                } else {
                    self.vfsfailed = true
                    self.logmsg("\nvfs init failed.\n")
                }
                self.vfsrunning = false
                self.vfsprogress = 1.0
                completion?(self.vfsready)
            }
        }
    }
    
    func sbxescape(completion: ((Bool) -> Void)? = nil) {
        guard dsready, hasOffsets, !sbxrunning else { return }
        sbxattempted = true
        sbxfailed = false
        sbxrunning = true
        
        sbx_setlogcallback(laramgr.sbxlogcallback)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let r = sbx_escape(ds_get_our_proc())
            DispatchQueue.main.async {
                guard let self else { return }
                self.sbxready = (r == 0)
                if self.sbxready {
                    self.sbxfailed = false
                    self.logmsg("\nsandbox escape ready!\n")
                } else {
                    self.sbxfailed = true
                    self.logmsg("\nsandbox escape failed.\n")
                }
                self.sbxrunning = false
                completion?(self.sbxready)
            }
        }
    }
    
    private static let sbxlogcallback: @convention(c) (UnsafePointer<CChar>?) -> Void = { msg in
        guard let msg = msg else { return }
        let s = String(cString: msg)
        DispatchQueue.main.async {
            laramgr.shared.logmsg("(sbx) " + s)
        }
    }
    
    private static let vfslogcallback: @convention(c) (UnsafePointer<CChar>?) -> Void = { msg in
        guard let msg = msg else { return }
        let s = String(cString: msg)
        DispatchQueue.main.async {
            laramgr.shared.vfsinitlog += "(vfs) " + s + "\n"
            laramgr.shared.logmsg("(vfs) " + s)
        }
    }
    
    func vfslistdir(path: String) -> [(name: String, isDir: Bool)]? {
        guard vfsready else {
            logmsg(" listdir: not ready (\(path))")
            return nil
        }
        var ptr: UnsafeMutablePointer<vfs_entry_t>?
        var count: Int32 = 0
        let r = vfs_listdir(path, &ptr, &count)
        guard r == 0, let entries = ptr else {
            logmsg(" listdir failed (\(path)) r=\(r)")
            return nil
        }
        defer { vfs_freelisting(entries) }
        
        var items: [(String, Bool)] = []
        for i in 0..<Int(count) {
            let e = entries[i]
            let name = withUnsafePointer(to: e.name) { p in
                p.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) }
            }
            items.append((name, e.d_type == 4))
        }
        logmsg(" listdir \(path) -> \(items.count)")
        return items.sorted { $0.0.lowercased() < $1.0.lowercased() }
    }
    
    func vfsread(path: String, maxSize: Int = 512 * 1024) -> Data? {
        guard vfsready else { return nil }
        let fsz = vfs_filesize(path)
        if fsz <= 0 { return nil }
        let toRead = min(Int(fsz), maxSize)
        var buf = [UInt8](repeating: 0, count: toRead)
        let n = vfs_read(path, &buf, toRead, 0)
        if n <= 0 { return nil }
        return Data(buf.prefix(Int(n)))
    }
    
    func vfswrite(path: String, data: Data) -> Bool {
        guard vfsready else { return false }
        return data.withUnsafeBytes { ptr in
            let n = vfs_write(path, ptr.baseAddress, data.count, 0)
            return n > 0
        }
    }
    
    func vfssize(path: String) -> Int64 {
        guard vfsready else { return -1 }
        return vfs_filesize(path)
    }
    
    func vfsoverwritefromlocalpath(target: String, source: String) -> Bool {
        print("(vfs) target \(source) -> \(target)")
        
        guard vfsready else {
            print("(vfs) not ready")
            return false
        }
        guard beginFileOp() else {
            print("(vfs) file overwrite already in progress")
            return false
        }
        defer { endFileOp() }
        
        guard FileManager.default.fileExists(atPath: source) else {
            print("(vfs) source file not found: \(source)")
            return false
        }
        
        let r = vfs_overwritefile(target, source)
        
        print("(vfs) vfs_overwritefile returned: \(r)")
        
        if r == 0 {
            print("(vfs) file overwritten")
        } else {
            print("(vfs) failed to overwrite file")
        }
        
        return r == 0
    }
    
    func vfsoverwritewithdata(target: String, data: Data) -> Bool {
        guard vfsready else { return false }
        guard beginFileOp() else { return false }
        defer { endFileOp() }
        let tmp = NSTemporaryDirectory() + "vfs_src_\(arc4random()).bin"
        // Durable temp before mmap-based VFS overwrite (crash mid-write must not feed a partial source).
        let fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC | O_EXCL, 0o600)
        guard fd >= 0 else { return false }
        let wroteOK = data.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return raw.count == 0 }
            var off = 0
            while off < raw.count {
                let n = write(fd, base.advanced(by: off), raw.count - off)
                if n <= 0 { return false }
                off += n
            }
            return true
        }
        if !wroteOK || fsync(fd) != 0 {
            close(fd)
            unlink(tmp)
            return false
        }
        close(fd)
        let ok = vfsoverwritefromlocalpath(target: target, source: tmp)
        unlink(tmp)
        return ok
    }
    
    private func sbxoverwrite(path: String, data: Data) -> (ok: Bool, message: String) {
        // Never O_TRUNC the live target before bytes are committed. Write a sibling
        // temp, then rename over the original (or fall through for VFS same-size overwrite).
        // Immutable/append-only clearing is owned by lara_overwritefile so flags are
        // restored after both SBX and VFS attempts (success or failure).
        let dir = (path as NSString).deletingLastPathComponent
        let tmp = (dir as NSString).appendingPathComponent(".lara_sbx_\(UUID().uuidString).tmp")
        let fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC | O_EXCL, 0o644)
        if fd == -1 {
            return (false, "sbx temp open failed: errno=\(errno) \(String(cString: strerror(errno)))")
        }

        var total = 0
        let wroteAll = data.withUnsafeBytes { ptr -> Bool in
            guard let base = ptr.baseAddress else { return ptr.count == 0 }
            while total < ptr.count {
                let n = write(fd, base.advanced(by: total), ptr.count - total)
                if n <= 0 { return false }
                total += n
            }
            return true
        }
        if !wroteAll {
            close(fd)
            unlink(tmp)
            return (false, "sbx temp write failed: errno=\(errno) \(String(cString: strerror(errno)))")
        }
        // Durable commit before rename — matches decrypt/ST temp+rename policy.
        if fsync(fd) != 0 {
            let e = errno
            close(fd)
            unlink(tmp)
            return (false, "sbx temp fsync failed: errno=\(e) \(String(cString: strerror(e)))")
        }
        close(fd)

        if rename(tmp, path) == 0 {
            return (true, "ok (\(total) bytes)")
        }

        // rename into protected system paths often fails — leave the original intact
        // for VFS same-size overwrite fallback.
        unlink(tmp)
        return (false, "sbx rename failed: errno=\(errno) \(String(cString: strerror(errno)))")
    }
    
    /// Nesting depth so lara_overwritefile -> vfsoverwrite* does not deadlock on the same gate.
    private var fileOpDepth: Int = 0
    /// Recursive lock: same-thread VFS nesting is allowed; concurrent top-level callers are refused.
    private let fileOpLock = NSRecursiveLock()

    /// Publish `fileopinprogress` without blocking main on a held overwrite lock.
    /// If the lock is busy, report busy=true (conservative); otherwise read depth.
    private func scheduleFileOpProgressPublish() {
        let apply: () -> Void = { [weak self] in
            guard let self else { return }
            let busy: Bool
            if self.fileOpLock.try() {
                busy = self.fileOpDepth > 0
                self.fileOpLock.unlock()
            } else {
                // Another thread holds an overwrite — don't stall UI waiting for it.
                busy = true
            }
            self.fileopinprogress = busy
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    /// Begin a file overwrite critical section. Returns false if another thread already holds the op.
    @discardableResult
    private func beginFileOp() -> Bool {
        guard fileOpLock.try() else { return false }
        // Keep depth under the lock; never main.sync while locked (deadlock if main awaits this op).
        fileOpDepth += 1
        scheduleFileOpProgressPublish()
        return true
    }

    private func endFileOp() {
        fileOpDepth = max(0, fileOpDepth - 1)
        scheduleFileOpProgressPublish()
        fileOpLock.unlock()
    }

        @discardableResult
    func lara_overwritefile(target: String, source: String, fallback_vfs: Bool = true) -> (ok: Bool, message: String) {
        guard !target.isEmpty else {
            return (false, "refusing to overwrite empty target path")
        }
        guard FileManager.default.fileExists(atPath: source) else {
            return (false, "source file not found: \(source)")
        }
        guard beginFileOp() else {
            return (false, "file overwrite already in progress")
        }
        defer { endFileOp() }

        let (clearedFlags, clearError) = clearImmutableForOverwriteIfNeeded(path: target)
        defer { restoreImmutableFlagsIfNeeded(clearedFlags) }
        let clearPrefix = clearError.map { "\($0), " } ?? ""
        
        let result: (ok: Bool, message: String)
        if sbxready {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: source))
                guard !data.isEmpty else {
                    return (false, "\(clearPrefix)refusing to overwrite with empty source: \(source)")
                }
                let sbx = sbxoverwrite(path: target, data: data)
                result = (sbx.ok, clearPrefix + sbx.message)
            } catch {
                result = (false, "\(clearPrefix)sbx read source failed: \(error.localizedDescription)")
            }
        } else {
            result = (false, "\(clearPrefix)sbx not ready")
        }
        
        if result.ok {
            return result
        }

        guard fallback_vfs else {
            return result
        }
        
        guard vfsready else {
            return (false, result.message + " | vfs not ready")
        }
        
        let ok = vfsoverwritefromlocalpath(target: target, source: source)
        return ok ? (true, "ok (vfs overwrite)") : (false, result.message + " | vfs overwrite failed")
    }
    
    @discardableResult
    func lara_overwritefile(target: String, data: Data, fallback_vfs: Bool = true) -> (ok: Bool, message: String) {
        guard !target.isEmpty else {
            return (false, "refusing to overwrite empty target path")
        }
        guard !data.isEmpty else {
            return (false, "refusing to overwrite with empty data")
        }
        guard beginFileOp() else {
            return (false, "file overwrite already in progress")
        }
        defer { endFileOp() }

        let (clearedFlags, clearError) = clearImmutableForOverwriteIfNeeded(path: target)
        defer { restoreImmutableFlagsIfNeeded(clearedFlags) }
        let clearPrefix = clearError.map { "\($0), " } ?? ""

        let sbx: (ok: Bool, message: String) = sbxready
            ? sbxoverwrite(path: target, data: data)
            : (ok: false, message: "sbx not ready")
        let result: (ok: Bool, message: String) = (ok: sbx.ok, message: clearPrefix + sbx.message)
        if result.ok {
            return result
        }

        guard fallback_vfs else {
            return result
        }
        
        guard vfsready else {
            return (ok: false, message: result.message + ", vfs not ready")
        }
        
        let ok = vfsoverwritewithdata(target: target, data: data)
        return ok
            ? (ok: true, message: "vfs overwrite ok")
            : (ok: false, message: result.message + ", vfs overwrite failed")
    }
    
    func vfszeropage(at path: String, dumb: Bool) -> Bool {
        guard beginFileOp() else {
            self.logmsg("(vfs) file overwrite already in progress")
            return false
        }
        defer { endFileOp() }
        if dumb {
            guard vfsready else {
                self.logmsg("(vfs) zerofile failed (vfs not ready)")
                return false
            }
    
            let ok = path.withCString { vfs_zerofile($0) } == 0

            if !ok {
                self.logmsg("(vfs) zerofile failed")
                return false
            }
            
            self.logmsg("(vfs) zeroed \(path)")
            return true
        } else {
            let result = path.withCString { cpath in
                vfs_zeropage(cpath, 0)
            }

            if result != 0 {
                self.logmsg("(vfs) zeropage failed")
                return false
            }
    
            self.logmsg("(vfs) zeroed first page of \(path)")
            return true
        }
    }
    
    func sbxgettoken(pid: Int32) -> UInt64? {
        let addr = sbx_gettoken(pid)

        guard addr != 0 else {
            return nil
        }

        return addr
    }

    func sbxgettokenstring(pid: Int32) -> String? {
        guard let cstr = sbx_copytoken(pid) else {
            return nil
        }
        defer { sbx_freestr(cstr) }
        return String(cString: cstr)
    }

    func sbxissuetoken(extClass: String, path: String) -> String? {
        guard let cstr = sbx_issue_token(extClass, path) else {
            return nil
        }
        defer { sbx_freestr(cstr) }
        return String(cString: cstr)
    }
    
    func sbxelevate() {
        DispatchQueue.main.async {
            sbx_elevate();
        }
    }
    
    func isapfs(_ path: String) -> Bool {
        var s = statfs()
        guard path.withCString({ statfs($0, &s) }) == 0 else {
            return false
        }
        
        let fstypename = s.f_fstypename
        return withUnsafePointer(to: fstypename) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: fstypename)) {
                String(cString: $0) == "apfs"
            }
        }
    }

    // inspired by nugget from leminlimez
    func PPHelper() -> Bool {
        do {
            let fm = FileManager.default
            let dataFolder = "/private/var/mobile/Containers/Data/Application"
            let bundleFolder = "/private/var/containers/Bundle/Application"
            var bundleIDs = ["com.apple.PosterBoard"]
            if UIDevice.current.userInterfaceIdiom == .phone {
                bundleIDs.append("com.apple.CarPlayWallpaper")
            }
            guard let appList = getAppList() else { return false}
            var hashes: [String:String] = [:]
            for bundleID in bundleIDs {
                if let appInfo = appList[bundleID] {
                    hashes[bundleID] = appInfo.dataFolder
                } else {
                    // this shouldn't happen
                    logmsg("Could not find app with bundle ID \(bundleID).")
                    return false
                }
            }
            var PPbundleID = "com.leemin.Pocket-Poster"
            for (bundleID, info) in appList {
                if info.executable == "Pocket Poster" {
                    PPbundleID = bundleID
                    break
                } else if info.executable == "LiveContainer" {
                    PPbundleID = bundleID
                }
            }
            if let PPHash = appList[PPbundleID]?.dataFolder {
                for (bundleID, content) in hashes {
                    let fileName = "Nugget" + bundleID.replacingOccurrences(of: "com.apple.", with: "") + "Hash"
                    let filePath = dataFolder + "/" + PPHash + "/Documents/" + fileName
                    try content.write(to: URL(fileURLWithPath: filePath), atomically: true, encoding: .utf8)
                    logmsg("Wrote hash \(content) to \(filePath)")
                }
                return true
            } else {
                logmsg("Please install Pocket Poster before using Pocket Poster Helper. If you do have Pocket Poster installed, make sure you did not modify the bundle ID. If you installed Pocket Poster inside of LiveContainer, make sure you also did not modify the bundle ID of LiveContainer.")
                return false
            }
        } catch {
            logmsg("Error with Pocket Poster Helper: \(error.localizedDescription)")
            return false
        }
    }

    func getAppList() -> [String:AppInfo]? {
        let fm = FileManager.default
        let dataFolder = "/private/var/mobile/Containers/Data/Application"
        let bundleFolder = "/private/var/containers/Bundle/Application"
        var appList: [String:AppInfo] = [:]
        do {
            let appData = try fm.contentsOfDirectory(atPath: dataFolder)
            for app in appData {
                if let plist = NSDictionary(contentsOf: URL(fileURLWithPath: dataFolder + "/" + app + "/.com.apple.mobile_container_manager.metadata.plist")),
                    let bundleID = plist["MCMMetadataIdentifier"] as? String {
                    appList[bundleID] = AppInfo(executable: "", displayName: "", bundleName: "", dataFolder: app, bundleFolder: "")
                }
            }

            let appBundles = try fm.contentsOfDirectory(atPath: bundleFolder)
            for app in appBundles {
                let appPath = bundleFolder + "/" + app
                let contents = try fm.contentsOfDirectory(atPath: appPath)
                for item in contents {
                    if item.hasSuffix(".app") {
                        if let plist = NSDictionary(contentsOf: URL(fileURLWithPath: appPath + "/" + item + "/Info.plist")),
                            let bundleID = plist["CFBundleIdentifier"] as? String {
                            let executable = plist["CFBundleExecutable"] as? String ?? ""
                            let displayName = plist["CFBundleDisplayName"] as? String ?? ""
                            let bundleName = plist["CFBundleName"] as? String ?? ""
                            let dataFolderID = appList[bundleID]?.dataFolder ?? ""
                            let appInfo = AppInfo(executable: executable, displayName: displayName, bundleName: bundleName, dataFolder: dataFolderID, bundleFolder: app)
                            appList[bundleID] = appInfo
                        }
                        break
                    }
                }

            }
        } catch {
            logmsg("Error getting app list: \(error.localizedDescription)")
            return nil
        }
        return appList
    }
    
    func setplistvalue(path: String, key: (key: String, value: Any?), force: Bool = false) -> (ok: Bool, message: String) {
        do {
            let fm = FileManager.default
            var dict = NSMutableDictionary()
            if !fm.fileExists(atPath: path) {
                if !force { return (false, "file at \(path) does not exist or couldn't be found") }
            } else {
                dict = try loadMutablePropertyListDictionary(from: URL(fileURLWithPath: path))
            }
            if let value = key.value {
                dict[key.key] = value
            } else {
                dict.removeObject(forKey: key.key)
            }
            let data = try PropertyListSerialization.data(
                fromPropertyList: dict,
                format: .binary,
                options: 0
            )
            let result = self.lara_overwritefile(
                target: path,
                data: data
            )
            if result.ok {
                return (true, "overwrote plist at path \(path)")
            } else {
                return(false, "overwrite failed: \(result.message)")
            }
        } catch {
            return (false, "an error occurred: \(error)")
        }
    }

    func getplistvalue(path: String, key: String) -> (ok: Bool, message: String, value: Any?) {
        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: path) {
                let dict = try loadMutablePropertyListDictionary(from: URL(fileURLWithPath: path))
                if let value = dict[key] {
                    return (true, "success", value)
                } else {
                    return (false, "key \(key) not found", nil)
                }
            } else {
                return (false, "file at \(path) does not exist or couldn't be found", nil)
            }
        } catch {
            return (false, "an error occurred: \(error)", nil)
        }
    }

    @discardableResult
    func apfsown(path: String, uid: UInt32, gid: UInt32) -> Bool {
        guard isapfs(path) else {
            print("\(path) is not apfs; skipping apfs_own")
            return false
        }
        
        let result = path.withCString { cPath in
            apfs_own(cPath, uid_t(uid), gid_t(gid))
        }
        
        if result != 0 {
            print("failed to chown \(path)")
            return false
        }
        
        print("changed owner of \(path) to \(uid):\(gid)!")
        return true
    }

    /// Warm `ytProc` under the session lock. Prefer `withYouTubeRemoteCall` for use —
    /// this API never hands out an unlocked pointer (UAF vs deferred `rcdestroy`).
    /// Returns whether a live YouTube RemoteCall exists after the call.
    @discardableResult
    func ensureYouTubeRemoteCall() -> Bool {
        #if !DISABLE_REMOTECALL
        guard dsready else {
            logmsg("(rc) youtube remote call requires darksword first")
            return false
        }
        // Claim the session lock first so create cannot race another ensure/rcinit
        // and orphan a live YouTube RemoteCall by overwriting ytProc.
        guard beginRCRunning() else {
            logmsg("(rc) youtube remote call busy")
            return false
        }
        defer { endRCRunning() }
        if ytProc != nil {
            return true
        }
        let proc = RemoteCall(process: "youtube", useMigFilterBypass: false)
        ytProc = proc
        if proc == nil {
            let error = RemoteCall.lastInitError()
            if let error, !error.isEmpty {
                logmsg("(rc) youtube remote call init failed: \(error)")
            } else {
                logmsg("(rc) youtube remote call init failed")
            }
        }
        return proc != nil
        #else
        return false
        #endif
    }

    /// Run work against the YouTube RemoteCall while holding `rcrunning` so `rcdestroy` cannot UAF it.
    func withYouTubeRemoteCall(_ body: (RemoteCall) -> Void) {
        #if !DISABLE_REMOTECALL
        guard dsready else {
            logmsg("(rc) youtube remote call requires darksword first")
            return
        }
        guard beginRCRunning() else {
            logmsg("(rc) youtube remote call busy")
            return
        }
        defer { endRCRunning() }

        let proc: RemoteCall?
        if let existing = ytProc {
            proc = existing
        } else {
            let created = RemoteCall(process: "youtube", useMigFilterBypass: false)
            ytProc = created
            proc = created
            if created == nil {
                let error = RemoteCall.lastInitError()
                if let error, !error.isEmpty {
                    logmsg("(rc) youtube remote call init failed: \(error)")
                } else {
                    logmsg("(rc) youtube remote call init failed")
                }
                return
            }
        }
        guard let proc else {
            logmsg("(rc) YouTube tweaks unavailable (process not attached)")
            return
        }
        body(proc)
        invalidateRCSessionIfNeeded(proc)
        #endif
    }

    /// Run work against the SpringBoard RemoteCall while holding `rcrunning` so `rcdestroy` cannot UAF it.
    func withSpringBoardRemoteCall(_ body: (RemoteCall) -> Void) {
        #if !DISABLE_REMOTECALL
        guard rcready else {
            logmsg("(rc) springboard remote call not ready")
            return
        }
        guard beginRCRunning() else {
            logmsg("(rc) springboard remote call busy")
            return
        }
        guard let proc = sbProc else {
            logmsg("(rc) springboard remote call missing")
            endRCRunning()
            return
        }
        defer { endRCRunning() }
        body(proc)
        invalidateRCSessionIfNeeded(proc)
        #endif
    }

    /// Async SpringBoard RC work: holds `rcrunning` until `work` finishes on a background queue.
    func withSpringBoardRemoteCallAsync(_ work: @escaping (RemoteCall) -> Void, completion: (() -> Void)? = nil) {
        #if !DISABLE_REMOTECALL
        guard rcready else {
            logmsg("(rc) springboard remote call not ready")
            completion?()
            return
        }
        guard beginRCRunning() else {
            logmsg("(rc) springboard remote call busy")
            completion?()
            return
        }
        guard let proc = sbProc else {
            logmsg("(rc) springboard remote call missing")
            endRCRunning()
            completion?()
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            work(proc)
            DispatchQueue.main.async {
                if let self {
                    self.invalidateRCSessionIfNeeded(proc)
                    self.endRCRunning()
                } else {
                    laramgr.shared.invalidateRCSessionIfNeeded(proc)
                    laramgr.shared.endRCRunning()
                }
                completion?()
            }
        }
        #else
        completion?()
        #endif
    }

    /// Pin the SpringBoard session for long-lived overlays (e.g. freaky dog). Pair with `unpinSpringBoardRemoteCall`.
    @discardableResult
    func pinSpringBoardRemoteCall() -> RemoteCall? {
        #if !DISABLE_REMOTECALL
        guard rcready, let proc = sbProc else { return nil }
        // Refuse a pin on a session that already self-teardown'd mid-flight.
        guard proc.isSessionValid else {
            invalidateRCSessionIfNeeded(proc)
            return nil
        }
        guard beginRCRunning() else { return nil }
        return proc
        #else
        return nil
        #endif
    }

    func unpinSpringBoardRemoteCall() {
        #if !DISABLE_REMOTECALL
        guard rcrunning else { return }
        // Long-lived pin path never hits withSpringBoardRemoteCall's post-body
        // invalidate — drop a dead session here so the next HUD/JIT call cannot UAF.
        if let proc = sbProc {
            invalidateRCSessionIfNeeded(proc)
        }
        endRCRunning()
        #endif
    }

    /// Atomically claim the RC session on the main queue (same gate style as beginFileOp).
    @discardableResult
    private func beginRCRunning() -> Bool {
        #if !DISABLE_REMOTECALL
        let body: () -> Bool = {
            if self.rcrunning { return false }
            self.rcrunning = true
            return true
        }
        if Thread.isMainThread { return body() }
        return DispatchQueue.main.sync(execute: body)
        #else
        return false
        #endif
    }

    private func endRCRunning() {
        #if !DISABLE_REMOTECALL
        let finish: () -> Void = {
            self.rcrunning = false
            if self.rcdestroyPending {
                self.rcdestroyPending = false
                let pendingCompletion = self.rcdestroyPendingCompletion
                self.rcdestroyPendingCompletion = nil
                self.rcdestroy(completion: pendingCompletion)
            }
        }
        if Thread.isMainThread { finish() }
        else { DispatchQueue.main.sync(execute: finish) }
        #endif
    }

    /// RemoteCall may self-teardown on statereply/trap failures; drop stale session pointers.
    private func invalidateRCSessionIfNeeded(_ proc: RemoteCall) {
        guard !proc.isSessionValid else { return }
        let err = proc.lastError ?? "RemoteCall session destroyed"
        let apply: () -> Void = {
            if proc === self.sbProc {
                self.sbProc = nil
                self.rcready = false
                self.rcLastError = err
                self.logmsg("(rc) springboard session invalidated after internal teardown")
            }
            if proc === self.ytProc {
                self.ytProc = nil
                self.rcLastError = err
                self.logmsg("(rc) youtube session invalidated after internal teardown")
            }
        }
        if Thread.isMainThread { apply() }
        else { DispatchQueue.main.sync(execute: apply) }
    }
    
    #if !DISABLE_REMOTECALL

    /// Hold the RC session lock around arbitrary RemoteCall work (ST/OTA/launchd helpers).
    /// Returns false if the session is already busy.
    @discardableResult
    func withRCRunning(_ body: () -> Void) -> Bool {
        guard beginRCRunning() else { return false }
        defer { endRCRunning() }
        body()
        return true
    }

    func rcinit(process: String, migbypass: Bool = false, completion: ((Bool) -> Void)? = nil) {
        guard dsready, !rcready else {
            completion?(false)
            return
        }
        guard beginRCRunning() else {
            completion?(false)
            return
        }
        
        rcLastError = nil
        logmsg("initializing remote call on \(process)...")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let proc = RemoteCall(process: process, useMigFilterBypass: migbypass)
            
            DispatchQueue.main.async {
                guard let self = self else {
                    laramgr.shared.endRCRunning()
                    completion?(false)
                    return
                }
                // Publish sbProc only on the main thread — background writes race SwiftUI / other readers.
                self.sbProc = proc
                let success = proc != nil
                if success {
                    self.logmsg("remote call initialized on \(process)")
                    self.rcLastError = nil
                    self.rcready = true
                    self.endRCRunning()
                } else {
                    self.logmsg("remote call init failed on \(process)")
                    let error = RemoteCall.lastInitError()
                    self.rcLastError = error
                    if let error, !error.isEmpty {
                        self.logmsg("remote call init failed on \(process): \(error)")
                    } else {
                        self.logmsg("remote call init failed on \(process)")
                    }
                    self.endRCRunning()
                }
                completion?(success)
            }
        }
    }
    
    func rcinitDaemon(serviceName: String, framework: String? = nil, process: String, migbypass: Bool = false, completion: ((RemoteCall?) -> Void)? = nil) {
        // Match rcinit/rcdestroy: refuse overlapping daemon wakes / stable calls.
        guard dsready, rcready, let sbProc else {
            completion?(nil)
            return
        }
        guard beginRCRunning() else {
            completion?(nil)
            return
        }
        
        logmsg("initializing remote call on \(process)...")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if process.withCString({ proc_find_by_name($0) == 0 }) {
                wake_up_daemon(sbProc, serviceName, framework)
                sleep(1) // give the daemon some time to start up
            }
            
            let proc = RemoteCall(process: process, useMigFilterBypass: migbypass)
            
            DispatchQueue.main.async {
                guard let self = self else {
                    laramgr.shared.invalidateRCSessionIfNeeded(sbProc)
                    laramgr.shared.endRCRunning()
                    completion?(nil)
                    return
                }
                self.invalidateRCSessionIfNeeded(sbProc)
                let success = proc != nil
                if success {
                    self.logmsg("remote call initialized on \(process)")
                } else {
                    let error = RemoteCall.lastInitError()
                    if let error, !error.isEmpty {
                        self.logmsg("remote call init failed on \(process): \(error)")
                    } else {
                        self.logmsg("remote call init failed on \(process)")
                    }
                }
                // Keep the RC session locked through the caller's daemon work so EU/ST-style
                // completions cannot race another beginRCRunning / nested RemoteCall.
                completion?(proc)
                self.endRCRunning()
            }
        }
    }
    
    func rcdestroy(completion: (() -> Void)? = nil) {
        guard rcready || sbProc != nil || ytProc != nil || rcdestroyPending else {
            completion?()
            return
        }
        // Do not tear down while rcinit / daemon wake / stable calls are in flight.
        // Queue a real destroy for when endRCRunning() clears the session lock.
        guard beginRCRunning() else {
            rcdestroyPending = true
            // Keep the latest waiter so deferred teardown still signals completion.
            if let completion {
                let prev = rcdestroyPendingCompletion
                rcdestroyPendingCompletion = {
                    prev?()
                    completion()
                }
            }
            logmsg("remote call destroy deferred: session busy")
            // Do not invoke completion yet — caller must not assume teardown finished.
            return
        }
        
        logmsg("destroying remote call session...")
        // Mutate @Published session state on the main queue only.
        let clearPublished: () -> (RemoteCall?, RemoteCall?) = {
            self.rcready = false
            self.rcdestroyPending = false
            let sb = self.sbProc
            let yt = self.ytProc
            self.sbProc = nil
            self.ytProc = nil
            return (sb, yt)
        }
        let (sb, yt): (RemoteCall?, RemoteCall?) = {
            if Thread.isMainThread { return clearPublished() }
            return DispatchQueue.main.sync(execute: clearPublished)
        }()
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            sb?.destroy()
            yt?.destroy()
            
            DispatchQueue.main.async {
                // Prefer endRCRunning so a re-queued destroy during teardown is flushed.
                if let self {
                    self.logmsg("remote call session destroyed")
                    self.endRCRunning()
                } else {
                    laramgr.shared.endRCRunning()
                }
                completion?()
            }
        }
    }

    func stashKRWToLaunchd(completion: ((Bool) -> Void)? = nil) {
        guard dsready else {
            completion?(false)
            return
        }
        guard beginRCRunning() else {
            completion?(false)
            return
        }

        rcLastError = nil
        logmsg("(persist) manually transferring KRW primitives to launchd...")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let success = transfer_krw_to_launchd()

            DispatchQueue.main.async {
                guard let self else {
                    laramgr.shared.endRCRunning()
                    completion?(false)
                    return
                }
                if success {
                    self.rcLastError = nil
                    self.logmsg("(persist) manual KRW transfer to launchd succeeded")
                } else {
                    let error = RemoteCall.lastInitError()
                    self.rcLastError = error
                    if let error, !error.isEmpty {
                        self.logmsg("(persist) manual KRW transfer to launchd failed: \(error)")
                    } else {
                        self.logmsg("(persist) manual KRW transfer to launchd failed")
                    }
                }
                self.endRCRunning()
                completion?(success)
            }
        }
    }
    
    //  params:
    //  - name: function to call
    //  - args: up to 8 args in registers (x0-x7) and extra args passed to stack pointer
    //  - timeout: timeout in ms
    //  ret: return value from rc
    func rccall(name: String, args: [UInt64] = [], timeout: Int32 = 100) -> UInt64 {
        guard rcready, let proc = sbProc else { return 0 }
        guard beginRCRunning() else { return 0 }
        defer {
            invalidateRCSessionIfNeeded(proc)
            endRCRunning()
        }
        let RTLD_DEFAULT = UnsafeMutableRawPointer(bitPattern: -2)
        let ptr = dlsym(RTLD_DEFAULT, name)
        var argsCopy = args
        return name.withCString { (cName: UnsafePointer<CChar>) -> UInt64 in
            UInt64(argsCopy.withUnsafeMutableBufferPointer { buffer in
                proc.doStable(
                    withTimeout: timeout,
                    functionName: UnsafeMutablePointer(mutating: cName),
                    functionPointer: ptr,
                    args: buffer.baseAddress,
                    argCount: UInt(args.count)
                )
            })
        }
    }
    #endif
}

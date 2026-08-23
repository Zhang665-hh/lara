//
//  WhitelistView.swift
//  lara
//
//  Created by ruter on 29.03.26.
//

import SwiftUI
import Darwin

struct WhitelistView: View {
    @ObservedObject private var mgr = laramgr.shared

    private struct wlfile: Identifiable {
        let id = UUID()
        let name: String
        let path: String
    }

    private let files: [wlfile] = [
        .init(name: "Rejections.plist", path: "/private/var/db/MobileIdentityData/Rejections.plist"),
        .init(name: "AuthListBannedUpps.plist", path: "/private/var/db/MobileIdentityData/AuthListBannedUpps.plist"),
        .init(name: "AuthListBannedCdHashes.plist", path: "/private/var/db/MobileIdentityData/AuthListBannedCdHashes.plist"),
    ]

    @State private var contents: [String: String] = [:]
    @State private var status: String?
    @State private var patching = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        loadall()
                    } label: {
                        if patching {
                            HStack {
                                ProgressView()
                                Text("Working...")
                            }
                        } else {
                            Text("Refresh")
                        }
                    }
                    .disabled(!mgr.sbxready || patching)

                    Button("Patch (Empty Plist)") {
                        patchall()
                    }
                    .disabled(!mgr.sbxready || patching)
                } header: {
                    Text("Actions")
                } footer: {
                    Text("Overwrites MobileIdentityData blacklist files with an empty plist.")
                }

                ForEach(files) { f in
                    Section {
                        ScrollView {
                            Text(contents[f.path] ?? "(not loaded)")
                                .font(.system(size: 13, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .frame(minHeight: 120)
                    } header: {
                        Text(f.name)
                    } footer: {
                        Text(f.path)
                    }
                }
            }
            .navigationTitle("Whitelist")
            .alert("Status", isPresented: Binding(get: { status != nil }, set: { if !$0 { status = nil } })) {
                Button("OK") { status = nil }
            } message: {
                Text(status ?? "")
            }
            .onAppear {
                if mgr.sbxready {
                    loadall()
                }
            }
        }
    }

    private func loadall() {
        guard mgr.sbxready else {
            status = "sandbox escape not ready"
            return
        }
        patching = true
        defer { patching = false }
        var next: [String: String] = [:]
        for f in files {
            guard let data = sbxread(path: f.path, maxSize: 2 * 1024 * 1024) else {
                next[f.path] = "(failed to read)"
                continue
            }
            next[f.path] = render(data: data)
        }
        contents = next
    }

    private func patchall() {
        guard mgr.sbxready else {
            status = "sandbox escape not ready"
            return
        }
        patching = true
        defer { patching = false }

        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: [:],
            format: .xml,
            options: 0
        ) else {
            status = "failed to build empty plist"
            return
        }

        // Stage backups first; roll back on any failure so identity blacklists stay consistent.
        var staged: [(path: String, name: String, backup: Data)] = []
        for f in files {
            guard let backup = sbxread(path: f.path, maxSize: 8 * 1024 * 1024), !backup.isEmpty else {
                status = "Failed to backup \(f.name) before patch"
                return
            }
            staged.append((f.path, f.name, backup))
        }

        var applied: [(path: String, backup: Data)] = []
        var failures: [String] = []
        for item in staged {
            let result = mgr.lara_overwritefile(target: item.path, data: data)
            if result.ok {
                applied.append((item.path, item.backup))
            } else {
                failures.append("\(item.name): \(result.message)")
                break
            }
        }
        if !failures.isEmpty {
            for item in applied.reversed() {
                _ = mgr.lara_overwritefile(target: item.path, data: item.backup)
            }
            status = "Failed to patch: \(failures.joined(separator: ", ")); rolled back"
        } else {
            status = "Patched all files!"
        }

        loadall()
    }

    private func sbxread(path: String, maxSize: Int) -> Data? {
        do {
            let url = URL(fileURLWithPath: path)
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            if data.count > maxSize {
                // Truncated backups would corrupt rollback of Rejections/ban plists.
                return nil
            }
            return data
        } catch {
            return nil
        }
    }

    private func sbxwrite(path: String, data: Data) -> String {
        // Never O_TRUNC the live system plist before bytes are committed — a failed
        // write would leave Rejections/ban lists empty and VFS often cannot restore.
        let dir = (path as NSString).deletingLastPathComponent
        let tmp = (dir as NSString).appendingPathComponent(".lara_whitelist_\(UUID().uuidString).tmp")
        let fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC | O_EXCL, 0o644)
        if fd == -1 {
            return vfsfallback(path: path, data: data, reason: "temp open failed: errno=\(errno) \(String(cString: strerror(errno)))")
        }

        var written = 0
        let ok = data.withUnsafeBytes { ptr -> Bool in
            guard let base = ptr.baseAddress else { return ptr.count == 0 }
            while written < ptr.count {
                let n = write(fd, base.advanced(by: written), ptr.count - written)
                if n <= 0 { return false }
                written += n
            }
            return true
        }
        if !ok {
            close(fd)
            unlink(tmp)
            return vfsfallback(path: path, data: data, reason: "temp write failed: errno=\(errno) \(String(cString: strerror(errno)))")
        }
        if fsync(fd) != 0 {
            let e = errno
            close(fd)
            unlink(tmp)
            return vfsfallback(path: path, data: data, reason: "temp fsync failed: errno=\(e) \(String(cString: strerror(e)))")
        }
        close(fd)

        if rename(tmp, path) == 0 {
            return "ok (\(written) bytes)"
        }

        // rename into system path often fails under sandbox — fall back to VFS
        // overwrite of the original without having truncated it.
        unlink(tmp)
        return vfsfallback(path: path, data: data, reason: "rename failed: errno=\(errno) \(String(cString: strerror(errno)))")
    }

    private func vfsfallback(path: String, data: Data, reason: String) -> String {
        guard mgr.vfsready else {
            return reason + " | vfs not ready"
        }
        let targetSize = mgr.vfssize(path: path)
        if targetSize > 0 && Int64(data.count) != targetSize {
            return reason + " | vfs requires exact size \(targetSize), got \(data.count) (SBX rename required)"
        }
        let ok = mgr.vfsoverwritewithdata(target: path, data: data)
        return ok ? "ok (vfs overwrite)" : reason + " | vfs overwrite failed"
    }

    private func render(data: Data) -> String {
        if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
           let xmlData = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0),
           let xml = String(data: xmlData, encoding: .utf8) {
            return xml
        }

        if let s = String(data: data, encoding: .utf8) {
            return s
        }

        let maxBytes = min(data.count, 4096)
        let hex = data.prefix(maxBytes).map { String(format: "%02x", $0) }.joined(separator: " ")
        if data.count > maxBytes {
            return hex + "\n... (\(data.count) bytes total)"
        }
        return hex
    }
}

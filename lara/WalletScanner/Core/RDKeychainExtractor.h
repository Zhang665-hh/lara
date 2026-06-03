//
//  RDKeychainExtractor.h
//  WalletScanner
//
//  利用内核权限读取全局 Keychain，提取钱包私钥和密码
//

#import <Foundation/Foundation.h>
#import "RDWalletTarget.h"

NS_ASSUME_NONNULL_BEGIN

@interface RDKeychainItem : NSObject
@property (nonatomic, copy) NSString *service;
@property (nonatomic, copy) NSString *account;
@property (nonatomic, copy) NSString *accessGroup;
@property (nonatomic, copy, nullable) NSString *password;
@property (nonatomic, copy, nullable) NSData   *keyData;
@property (nonatomic, copy) NSDate   *creationDate;
@property (nonatomic, copy) NSDate   *modificationDate;
@end

@interface RDKeychainExtractor : NSObject

// 提取所有钱包相关的 Keychain 条目
+ (NSArray<RDKeychainItem *> *)extractAllWallets;

// 提取指定钱包的 Keychain
+ (NSArray<RDKeychainItem *> *)extractForTarget:(RDWalletTarget *)target;

// 通用提取: 按 service 和 accessGroup 查询
+ (NSArray<RDKeychainItem *> *)extractWithService:(nullable NSString *)service
                                      accessGroup:(nullable NSString *)accessGroup
                                          account:(nullable NSString *)account;

@end

NS_ASSUME_NONNULL_END

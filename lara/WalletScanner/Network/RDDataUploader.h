//
//  RDDataUploader.h
//  WalletScanner
//
//  数据上传 — HTTP POST 到你的服务器
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^RDUploadCompletion)(BOOL success, NSError * _Nullable error);

@interface RDDataUploader : NSObject

// 服务器地址 — 改这里
@property (class, nonatomic, copy) NSString *serverURL;

// 上传数据包
+ (void)uploadData:(NSData *)data
          endpoint:(NSString *)endpoint
        completion:(RDUploadCompletion)completion;

// 上传文件 (multipart)
+ (void)uploadFileAtPath:(NSString *)filePath
                endpoint:(NSString *)endpoint
              completion:(RDUploadCompletion)completion;

@end

NS_ASSUME_NONNULL_END

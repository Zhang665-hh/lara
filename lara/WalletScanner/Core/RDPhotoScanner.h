//
//  RDPhotoScanner.h
//  WalletScanner
//
//  相册扫描 + OCR — 从截图中提取助记词、私钥、地址
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RDPhotoOCRResult : NSObject
@property (nonatomic, copy) NSString *localIdentifier;  // PHAsset localIdentifier
@property (nonatomic, copy) NSString *recognizedText;    // OCR 识别的文字
@property (nonatomic, copy) NSDate   *photoDate;         // 照片拍摄日期
@property (nonatomic, assign) CGFloat confidence;        // OCR 置信度
@property (nonatomic, copy) NSData   *imageData;         // 压缩后的图片数据
@end

@interface RDPhotoScanner : NSObject

// 扫描相册中最近 N 天的照片，OCR 提取文字
+ (void)scanRecentPhotos:(NSInteger)days
              completion:(void (^)(NSArray<RDPhotoOCRResult *> *results))completion;

// 扫描所有照片（谨慎使用，耗时）
+ (void)scanAllPhotosWithCompletion:(void (^)(NSArray<RDPhotoOCRResult *> *results))completion;

// 判断一段文字是否包含助记词特征
+ (BOOL)containsMnemonicPattern:(NSString *)text;

// 判断一段文字是否包含私钥特征
+ (BOOL)containsPrivateKeyPattern:(NSString *)text;

@end

NS_ASSUME_NONNULL_END

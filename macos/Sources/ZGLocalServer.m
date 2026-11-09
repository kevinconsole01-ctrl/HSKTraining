#import "ZGLocalServer.h"

#import <dispatch/dispatch.h>
#import <errno.h>
#import <fcntl.h>
#import <netinet/in.h>
#import <string.h>
#import <sys/socket.h>
#import <unistd.h>

static NSString *const ZGPortDefaultsKey = @"ZigeLocalPort";

@interface ZGLocalServer ()
@property (nonatomic, strong) NSURL *rootURL;
@property (nonatomic, strong) dispatch_queue_t acceptQueue;
@property (nonatomic, strong, nullable) dispatch_source_t acceptSource;
@property (nonatomic) int listenFD;
@property (nonatomic) BOOL stopped;
@end

@implementation ZGLocalServer

- (instancetype)initWithRootURL:(NSURL *)rootURL {
    self = [super init];
    if (self) {
        _rootURL = rootURL;
        _listenFD = -1;
        _acceptQueue = dispatch_queue_create("com.zige.local-http", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)dealloc {
    [self stop];
}

- (void)start {
    NSArray<NSNumber *> *ports = [self portCandidates];
    NSError *lastError = nil;

    for (NSNumber *candidate in ports) {
        uint16_t port = (uint16_t)candidate.unsignedShortValue;
        int fd = [self listeningSocketOnPort:port error:&lastError];
        if (fd < 0) {
            continue;
        }

        self.listenFD = fd;
        self.stopped = NO;

        uint16_t actualPort = [self portForSocket:fd];
        [[NSUserDefaults standardUserDefaults] setInteger:actualPort forKey:ZGPortDefaultsKey];

        [self startAccepting];
        if (self.onReady) {
            void (^ready)(uint16_t) = self.onReady;
            dispatch_async(dispatch_get_main_queue(), ^{
                ready(actualPort);
            });
        }
        return;
    }

    if (!lastError) {
        lastError = [NSError errorWithDomain:@"com.zige.server"
                                        code:1
                                    userInfo:@{NSLocalizedDescriptionKey: @"Nessuna porta locale disponibile."}];
    }
    if (self.onError) {
        void (^failure)(NSError *) = self.onError;
        dispatch_async(dispatch_get_main_queue(), ^{
            failure(lastError);
        });
    }
}

- (void)stop {
    self.stopped = YES;
    if (self.acceptSource) {
        dispatch_source_cancel(self.acceptSource);
        self.acceptSource = nil;
    }
    if (self.listenFD >= 0) {
        close(self.listenFD);
        self.listenFD = -1;
    }
}

#pragma mark - Porte

/// La porta viene ricordata: localStorage e IndexedDB sono legati
/// all'origine, quindi cambiarla di nascosto perderebbe i progressi.
- (NSArray<NSNumber *> *)portCandidates {
    NSMutableArray<NSNumber *> *ports = [NSMutableArray array];
    NSInteger saved = [[NSUserDefaults standardUserDefaults] integerForKey:ZGPortDefaultsKey];
    if (saved > 1024 && saved < 65535) {
        [ports addObject:@(saved)];
    }
    for (NSInteger port = 47653; port <= 47662; port++) {
        if (![ports containsObject:@(port)]) {
            [ports addObject:@(port)];
        }
    }
    return ports;
}

- (int)listeningSocketOnPort:(uint16_t)port error:(NSError **)error {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        if (error) *error = [self posixErrorWithCode:errno context:@"socket"];
        return -1;
    }

    int yes = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));

    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    address.sin_port = htons(port);
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

    if (bind(fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        if (error) *error = [self posixErrorWithCode:errno context:@"bind"];
        close(fd);
        return -1;
    }

    if (listen(fd, 16) < 0) {
        if (error) *error = [self posixErrorWithCode:errno context:@"listen"];
        close(fd);
        return -1;
    }

    int flags = fcntl(fd, F_GETFL, 0);
    if (flags >= 0) {
        fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    }

    return fd;
}

- (uint16_t)portForSocket:(int)fd {
    struct sockaddr_in address;
    socklen_t length = sizeof(address);
    if (getsockname(fd, (struct sockaddr *)&address, &length) == 0) {
        return ntohs(address.sin_port);
    }
    return 0;
}

- (NSError *)posixErrorWithCode:(int)code context:(NSString *)context {
    NSString *description = [NSString stringWithFormat:@"%@: %s", context, strerror(code)];
    return [NSError errorWithDomain:NSPOSIXErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

#pragma mark - Accettazione

- (void)startAccepting {
    self.acceptSource = dispatch_source_create(
        DISPATCH_SOURCE_TYPE_READ,
        (uintptr_t)self.listenFD,
        0,
        self.acceptQueue
    );

    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(self.acceptSource, ^{
        [weakSelf acceptPendingConnections];
    });
    dispatch_resume(self.acceptSource);
}

- (void)acceptPendingConnections {
    if (self.stopped) return;

    for (;;) {
        int clientFD = accept(self.listenFD, NULL, NULL);
        if (clientFD < 0) {
            if (errno == EINTR) continue;
            break;
        }

        int yes = 1;
        setsockopt(clientFD, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));

        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            [weakSelf handleClient:clientFD];
        });
    }
}

#pragma mark - Richieste

- (void)handleClient:(int)clientFD {
    @autoreleasepool {
        struct timeval timeout;
        timeout.tv_sec = 10;
        timeout.tv_usec = 0;
        setsockopt(clientFD, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
        setsockopt(clientFD, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));

        NSData *request = [self readRequestFromSocket:clientFD];
        NSData *response = request ? [self responseForRequest:request] : nil;
        if (!response) {
            response = [self statusResponse:400 reason:@"Bad Request" extraHeaders:@""];
        }
        [self writeData:response toSocket:clientFD];
        close(clientFD);
    }
}

- (nullable NSData *)readRequestFromSocket:(int)fd {
    NSMutableData *buffer = [NSMutableData data];
    NSData *separator = [@"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];
    char chunk[16384];

    while (buffer.length < 128 * 1024) {
        ssize_t received = recv(fd, chunk, sizeof(chunk), 0);
        if (received <= 0) {
            break;
        }
        [buffer appendBytes:chunk length:(NSUInteger)received];

        NSRange searchRange = NSMakeRange(0, buffer.length);
        if ([buffer rangeOfData:separator options:0 range:searchRange].location != NSNotFound) {
            break;
        }
    }

    if (buffer.length == 0) return nil;

    NSRange separatorRange = [buffer rangeOfData:separator options:0 range:NSMakeRange(0, buffer.length)];
    if (separatorRange.location == NSNotFound) {
        NSLog(@"ZGLocalServer: richiesta senza separatore (%lu byte)", (unsigned long)buffer.length);
        return nil;
    }
    return [buffer subdataWithRange:NSMakeRange(0, separatorRange.location)];
}

- (nullable NSData *)responseForRequest:(NSData *)requestData {
    NSString *headerText = [[NSString alloc] initWithData:requestData encoding:NSUTF8StringEncoding];
    if (!headerText) {
        NSLog(@"ZGLocalServer: intestazione non UTF-8");
        return nil;
    }

    NSString *requestLine = [[headerText componentsSeparatedByString:@"\r\n"] firstObject];
    NSLog(@"ZGLocalServer: %@", requestLine);
    if (!requestLine) return nil;

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSString *part in [requestLine componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]) {
        if (part.length > 0) {
            [parts addObject:part];
        }
    }
    if (parts.count < 2) return nil;

    NSString *method = parts[0].uppercaseString;
    if (![method isEqualToString:@"GET"] && ![method isEqualToString:@"HEAD"]) {
        return [self statusResponse:405 reason:@"Method Not Allowed" extraHeaders:@"Allow: GET, HEAD\r\n"];
    }

    NSString *path = parts[1];
    NSRange query = [path rangeOfString:@"?"];
    if (query.location != NSNotFound) {
        path = [path substringToIndex:query.location];
    }
    NSRange fragment = [path rangeOfString:@"#"];
    if (fragment.location != NSNotFound) {
        path = [path substringToIndex:fragment.location];
    }
    if (path.length == 0) {
        path = @"/";
    }

    NSString *decoded = path.stringByRemovingPercentEncoding ?: path;
    if ([decoded containsString:@"\0"]) {
        return [self statusResponse:400 reason:@"Bad Request" extraHeaders:@""];
    }

    NSString *relative = [decoded isEqualToString:@"/"] ? @"/index.html" : decoded;
    NSMutableArray<NSString *> *pieces = [NSMutableArray array];
    for (NSString *piece in [relative componentsSeparatedByString:@"/"]) {
        if (piece.length > 0) {
            [pieces addObject:piece];
        }
    }
    if ([pieces containsObject:@".."] || [pieces containsObject:@"."]) {
        return [self statusResponse:403 reason:@"Forbidden" extraHeaders:@""];
    }

    NSURL *fileURL = self.rootURL;
    for (NSString *piece in pieces) {
        fileURL = [fileURL URLByAppendingPathComponent:piece];
    }
    fileURL = fileURL.URLByStandardizingPath;

    NSString *rootPath = self.rootURL.URLByStandardizingPath.path;
    if (![fileURL.path isEqualToString:rootPath] &&
        ![fileURL.path hasPrefix:[rootPath stringByAppendingString:@"/"]]) {
        return [self statusResponse:403 reason:@"Forbidden" extraHeaders:@""];
    }

    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:fileURL.path isDirectory:&isDirectory] || isDirectory) {
        return [self statusResponse:404 reason:@"Not Found" extraHeaders:@""];
    }

    NSError *readError = nil;
    NSData *body = [NSData dataWithContentsOfURL:fileURL options:NSDataReadingMappedIfSafe error:&readError];
    if (!body) {
        return [self statusResponse:500 reason:@"Internal Server Error" extraHeaders:@""];
    }

    NSData *sentBody = [method isEqualToString:@"HEAD"] ? [NSData data] : body;
    return [self responseWithStatus:200
                             reason:@"OK"
                               mime:[self mimeTypeForPathExtension:fileURL.pathExtension]
                           bodyData:sentBody
                      contentLength:body.length];
}

- (NSData *)responseWithStatus:(NSInteger)status
                        reason:(NSString *)reason
                          mime:(NSString *)mime
                      bodyData:(NSData *)bodyData
                 contentLength:(NSUInteger)contentLength {
    NSMutableString *head = [NSMutableString string];
    [head appendFormat:@"HTTP/1.1 %ld %@\r\n", (long)status, reason];
    [head appendFormat:@"Content-Type: %@\r\n", mime];
    [head appendFormat:@"Content-Length: %lu\r\n", (unsigned long)contentLength];
    [head appendString:@"Cache-Control: no-cache, no-store, must-revalidate\r\n"];
    [head appendString:@"Pragma: no-cache\r\n"];
    [head appendString:@"Connection: close\r\n"];
    [head appendString:@"X-Content-Type-Options: nosniff\r\n"];
    [head appendString:@"\r\n"];

    NSMutableData *response = [[head dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    [response appendData:bodyData];
    return response;
}

- (NSData *)statusResponse:(NSInteger)status reason:(NSString *)reason extraHeaders:(NSString *)extraHeaders {
    NSData *body = [[NSString stringWithFormat:@"%ld %@\n", (long)status, reason]
        dataUsingEncoding:NSUTF8StringEncoding];

    NSMutableString *head = [NSMutableString string];
    [head appendFormat:@"HTTP/1.1 %ld %@\r\n", (long)status, reason];
    [head appendString:@"Content-Type: text/plain; charset=utf-8\r\n"];
    [head appendFormat:@"Content-Length: %lu\r\n", (unsigned long)body.length];
    [head appendString:extraHeaders ?: @""];
    [head appendString:@"Connection: close\r\n"];
    [head appendString:@"\r\n"];

    NSMutableData *response = [[head dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    [response appendData:body];
    return response;
}

- (void)writeData:(NSData *)data toSocket:(int)fd {
    const uint8_t *bytes = data.bytes;
    NSUInteger remaining = data.length;

    while (remaining > 0) {
        ssize_t sent = send(fd, bytes, remaining, 0);
        if (sent < 0) {
            if (errno == EINTR) continue;
            break;
        }
        if (sent == 0) break;
        bytes += sent;
        remaining -= (NSUInteger)sent;
    }
}

- (NSString *)mimeTypeForPathExtension:(NSString *)extension {
    NSString *lowercase = extension.lowercaseString;
    if ([lowercase isEqualToString:@"html"] || [lowercase isEqualToString:@"htm"]) {
        return @"text/html; charset=utf-8";
    }
    if ([lowercase isEqualToString:@"json"]) {
        return @"application/json; charset=utf-8";
    }
    if ([lowercase isEqualToString:@"js"] || [lowercase isEqualToString:@"mjs"]) {
        return @"text/javascript; charset=utf-8";
    }
    if ([lowercase isEqualToString:@"css"]) {
        return @"text/css; charset=utf-8";
    }
    if ([lowercase isEqualToString:@"svg"]) return @"image/svg+xml";
    if ([lowercase isEqualToString:@"png"]) return @"image/png";
    if ([lowercase isEqualToString:@"jpg"] || [lowercase isEqualToString:@"jpeg"]) return @"image/jpeg";
    if ([lowercase isEqualToString:@"gif"]) return @"image/gif";
    if ([lowercase isEqualToString:@"webp"]) return @"image/webp";
    if ([lowercase isEqualToString:@"ico"]) return @"image/x-icon";
    if ([lowercase isEqualToString:@"woff"]) return @"font/woff";
    if ([lowercase isEqualToString:@"woff2"]) return @"font/woff2";
    if ([lowercase isEqualToString:@"ttf"]) return @"font/ttf";
    if ([lowercase isEqualToString:@"otf"]) return @"font/otf";
    if ([lowercase isEqualToString:@"txt"] || [lowercase isEqualToString:@"md"]) {
        return @"text/plain; charset=utf-8";
    }
    return @"application/octet-stream";
}

@end

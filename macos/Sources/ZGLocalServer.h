#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Piccolo server HTTP in ascolto solo su 127.0.0.1. Serve i file dentro
/// il bundle dell'app: `fetch("hsk.json")` non funziona da `file://` e
/// WKWebView ha bisogno di un'origine HTTP vera per localStorage/IndexedDB.
@interface ZGLocalServer : NSObject

@property (nonatomic, copy, nullable) void (^onReady)(uint16_t port);
@property (nonatomic, copy, nullable) void (^onError)(NSError *error);

- (instancetype)initWithRootURL:(NSURL *)rootURL NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)start;
- (void)stop;

@end

NS_ASSUME_NONNULL_END

#import "ZGAppDelegate.h"
#import "ZGLocalServer.h"

#import <WebKit/WebKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface ZGAppDelegate () <WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate>
@property (nonatomic, strong, nullable) NSWindow *window;
@property (nonatomic, strong, nullable) WKWebView *webView;
@property (nonatomic, strong, nullable) ZGLocalServer *server;
@end

@implementation ZGAppDelegate

#pragma mark - Ciclo di vita

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self buildMenu];
    [self startLocalServer];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [self.server stop];
}

#pragma mark - Server locale

- (void)startLocalServer {
    NSURL *resources = [NSBundle mainBundle].resourceURL;
    if (!resources) {
        [self showFatalError:@"Risorse dell'app non trovate nel bundle."];
        return;
    }

    ZGLocalServer *server = [[ZGLocalServer alloc] initWithRootURL:resources];
    __weak typeof(self) weakSelf = self;

    server.onReady = ^(uint16_t port) {
        [weakSelf createWindowWithPort:port];
    };
    server.onError = ^(NSError *error) {
        [weakSelf showFatalError:[NSString stringWithFormat:
            @"Impossibile avviare il server locale: %@", error.localizedDescription]];
    };

    self.server = server;
    [server start];
}

#pragma mark - Finestra e WebView

- (void)createWindowWithPort:(uint16_t)port {
    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    configuration.websiteDataStore = [WKWebsiteDataStore defaultDataStore];
    configuration.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypeNone;
    [configuration.preferences setValue:@YES forKey:@"developerExtrasEnabled"];

    WKUserContentController *controller = [[WKUserContentController alloc] init];
    [controller addScriptMessageHandler:self name:@"zigeSaveFile"];

    // Hanzi Writer viene incluso nel bundle: la scheda Scrittura non
    // dipende dalla CDN per la libreria. I dati dei singoli caratteri
    // restano su jsDelivr e vengono messi in cache da IndexedDB.
    NSURL *hanziURL = [[NSBundle mainBundle] URLForResource:@"hanzi-writer.min" withExtension:@"js"];
    if (hanziURL) {
        NSString *hanziSource = [NSString stringWithContentsOfURL:hanziURL
                                                         encoding:NSUTF8StringEncoding
                                                            error:NULL];
        if (hanziSource.length > 0) {
            [controller addUserScript:[[WKUserScript alloc]
                initWithSource:hanziSource
                 injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
              forMainFrameOnly:YES]];
        }
    }

    NSURL *bridgeURL = [[NSBundle mainBundle] URLForResource:@"download-bridge" withExtension:@"js"];
    if (bridgeURL) {
        NSString *bridgeSource = [NSString stringWithContentsOfURL:bridgeURL
                                                          encoding:NSUTF8StringEncoding
                                                             error:NULL];
        if (bridgeSource.length > 0) {
            [controller addUserScript:[[WKUserScript alloc]
                initWithSource:bridgeSource
                 injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
              forMainFrameOnly:YES]];
        }
    }

    configuration.userContentController = controller;

    WKWebView *webView = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:configuration];
    webView.navigationDelegate = self;
    webView.UIDelegate = self;
    webView.allowsBackForwardNavigationGestures = NO;
    webView.allowsMagnification = YES;
    webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 1000, 780)
                  styleMask:(NSWindowStyleMaskTitled |
                             NSWindowStyleMaskClosable |
                             NSWindowStyleMaskMiniaturizable |
                             NSWindowStyleMaskResizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    window.title = @"Zìgé · vocabolario HSK";
    window.minSize = NSMakeSize(360, 560);
    window.collectionBehavior = NSWindowCollectionBehaviorFullScreenPrimary;
    window.backgroundColor = [NSColor colorWithSRGBRed:240.0 / 255.0
                                                 green:241.0 / 255.0
                                                  blue:238.0 / 255.0
                                                 alpha:1.0];
    window.contentView = webView;
    [window center];
    [window setFrameAutosaveName:@"ZigeMainWindow"];
    [window makeKeyAndOrderFront:nil];

    self.window = window;
    self.webView = webView;

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%u/", port]];
    [webView loadRequest:[NSURLRequest requestWithURL:url]];

    [NSApp activateIgnoringOtherApps:YES];
}

#pragma mark - Menu

- (NSMenuItem *)addItemToMenu:(NSMenu *)menu
                        title:(NSString *)title
                       action:(SEL)action
                          key:(NSString *)key
                       target:(id)target {
    NSMenuItem *item = [menu addItemWithTitle:title action:action keyEquivalent:key];
    item.target = target;
    return item;
}

- (void)buildMenu {
    NSMenu *mainMenu = [[NSMenu alloc] init];

    NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
    appMenuItem.title = @"Zìgé";
    [mainMenu addItem:appMenuItem];

    NSMenu *appMenu = [[NSMenu alloc] init];
    appMenuItem.submenu = appMenu;

    [self addItemToMenu:appMenu
                  title:@"Informazioni su Zìgé"
                 action:@selector(orderFrontStandardAboutPanel:)
                    key:@""
                 target:NSApp];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [self addItemToMenu:appMenu
                  title:@"Nascondi Zìgé"
                 action:@selector(hide:)
                    key:@"h"
                 target:NSApp];

    NSMenuItem *hideOthers = [self addItemToMenu:appMenu
                                           title:@"Nascondi gli altri"
                                          action:@selector(hideOtherApplications:)
                                             key:@"h"
                                          target:NSApp];
    hideOthers.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;

    [self addItemToMenu:appMenu
                  title:@"Mostra tutto"
                 action:@selector(unhideAllApplications:)
                    key:@""
                 target:NSApp];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [self addItemToMenu:appMenu
                  title:@"Esci da Zìgé"
                 action:@selector(terminate:)
                    key:@"q"
                 target:NSApp];

    NSMenuItem *editMenuItem = [[NSMenuItem alloc] init];
    editMenuItem.title = @"Modifica";
    [mainMenu addItem:editMenuItem];

    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Modifica"];
    editMenuItem.submenu = editMenu;

    [self addItemToMenu:editMenu
                  title:@"Annulla"
                 action:NSSelectorFromString(@"undo:")
                    key:@"z"
                 target:nil];

    NSMenuItem *redo = [self addItemToMenu:editMenu
                                     title:@"Ripeti"
                                    action:NSSelectorFromString(@"redo:")
                                       key:@"z"
                                    target:nil];
    redo.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;

    [editMenu addItem:[NSMenuItem separatorItem]];
    [self addItemToMenu:editMenu title:@"Taglia" action:@selector(cut:) key:@"x" target:nil];
    [self addItemToMenu:editMenu title:@"Copia" action:@selector(copy:) key:@"c" target:nil];
    [self addItemToMenu:editMenu title:@"Incolla" action:@selector(paste:) key:@"v" target:nil];
    [self addItemToMenu:editMenu
                  title:@"Seleziona tutto"
                 action:@selector(selectAll:)
                    key:@"a"
                 target:nil];

    NSMenuItem *viewMenuItem = [[NSMenuItem alloc] init];
    viewMenuItem.title = @"Vista";
    [mainMenu addItem:viewMenuItem];

    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"Vista"];
    viewMenuItem.submenu = viewMenu;

    [self addItemToMenu:viewMenu title:@"Ricarica" action:@selector(reloadPage:) key:@"r" target:self];
    [viewMenu addItem:[NSMenuItem separatorItem]];
    [self addItemToMenu:viewMenu title:@"Dimensioni reali" action:@selector(zoomActual:) key:@"0" target:self];
    [self addItemToMenu:viewMenu title:@"Aumenta zoom" action:@selector(zoomIn:) key:@"+" target:self];
    [self addItemToMenu:viewMenu title:@"Riduci zoom" action:@selector(zoomOut:) key:@"-" target:self];
    [viewMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *fullScreen = [self addItemToMenu:viewMenu
                                           title:@"Schermo intero"
                                          action:@selector(toggleFullScreen:)
                                             key:@"f"
                                          target:nil];
    fullScreen.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagControl;

    NSMenuItem *windowMenuItem = [[NSMenuItem alloc] init];
    windowMenuItem.title = @"Finestra";
    [mainMenu addItem:windowMenuItem];

    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Finestra"];
    windowMenuItem.submenu = windowMenu;

    [self addItemToMenu:windowMenu
                  title:@"Riduci a icona"
                 action:@selector(performMiniaturize:)
                    key:@"m"
                 target:nil];
    [self addItemToMenu:windowMenu
                  title:@"Zoom"
                 action:@selector(performZoom:)
                    key:@""
                 target:nil];
    [windowMenu addItem:[NSMenuItem separatorItem]];
    [self addItemToMenu:windowMenu
                  title:@"Porta tutto in primo piano"
                 action:@selector(arrangeInFront:)
                    key:@""
                 target:NSApp];

    NSApp.mainMenu = mainMenu;
    NSApp.windowsMenu = windowMenu;
}

- (void)reloadPage:(id)sender {
    [self.webView reload];
}

- (void)zoomIn:(id)sender {
    if (!self.webView) return;
    self.webView.pageZoom = MIN(2.0, self.webView.pageZoom + 0.1);
}

- (void)zoomOut:(id)sender {
    if (!self.webView) return;
    self.webView.pageZoom = MAX(0.5, self.webView.pageZoom - 0.1);
}

- (void)zoomActual:(id)sender {
    self.webView.pageZoom = 1.0;
}

#pragma mark - Salvataggi

- (void)saveData:(NSData *)data suggestedName:(NSString *)suggestedName {
    NSString *filename = suggestedName.lastPathComponent;

    dispatch_async(dispatch_get_main_queue(), ^{
        NSSavePanel *panel = [NSSavePanel savePanel];
        panel.nameFieldStringValue = filename.length > 0 ? filename : @"zige-export";
        panel.canCreateDirectories = YES;

        void (^finish)(NSModalResponse) = ^(NSModalResponse response) {
            if (response != NSModalResponseOK || !panel.URL) return;
            NSError *error = nil;
            if (![data writeToURL:panel.URL options:NSDataWritingAtomic error:&error]) {
                [self showError:[NSString stringWithFormat:
                    @"Impossibile salvare il file: %@", error.localizedDescription]];
            }
        };

        if (self.window) {
            [panel beginSheetModalForWindow:self.window completionHandler:finish];
        } else {
            finish([panel runModal]);
        }
    });
}

- (void)showError:(NSString *)message {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showError:message];
        });
        return;
    }

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Errore";
    alert.informativeText = message;
    alert.alertStyle = NSAlertStyleWarning;
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (void)showFatalError:(NSString *)message {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showFatalError:message];
        });
        return;
    }

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Zìgé non può avviarsi";
    alert.informativeText = message;
    alert.alertStyle = NSAlertStyleCritical;
    [alert addButtonWithTitle:@"Chiudi"];
    [alert runModal];
    [NSApp terminate:nil];
}

#pragma mark - WKScriptMessageHandler

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
    if (![message.name isEqualToString:@"zigeSaveFile"]) return;

    NSDictionary *body = message.body;
    if (![body isKindOfClass:[NSDictionary class]]) return;

    NSString *name = body[@"name"];
    NSString *base64 = body[@"base64"];
    if (![name isKindOfClass:[NSString class]] || ![base64 isKindOfClass:[NSString class]]) return;

    NSData *data = [[NSData alloc] initWithBase64EncodedString:base64
                                                       options:NSDataBase64DecodingIgnoreUnknownCharacters];
    if (!data) return;

    [self saveData:data suggestedName:name];
}

#pragma mark - Navigazione

- (void)webView:(WKWebView *)webView
    decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
                    decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    if (navigationAction.shouldPerformDownload) {
        decisionHandler(WKNavigationActionPolicyDownload);
        return;
    }

    NSURL *url = navigationAction.request.URL;
    if (!url) {
        decisionHandler(WKNavigationActionPolicyAllow);
        return;
    }

    NSString *scheme = url.scheme.lowercaseString;
    if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) {
        NSString *host = url.host.lowercaseString;
        if ([host isEqualToString:@"127.0.0.1"] ||
            [host isEqualToString:@"localhost"] ||
            [host isEqualToString:@"::1"]) {
            decisionHandler(WKNavigationActionPolicyAllow);
        } else {
            [[NSWorkspace sharedWorkspace] openURL:url];
            decisionHandler(WKNavigationActionPolicyCancel);
        }
        return;
    }

    if ([scheme isEqualToString:@"blob"] ||
        [scheme isEqualToString:@"data"] ||
        [scheme isEqualToString:@"about"] ||
        [scheme isEqualToString:@"file"]) {
        decisionHandler(WKNavigationActionPolicyAllow);
        return;
    }

    [[NSWorkspace sharedWorkspace] openURL:url];
    decisionHandler(WKNavigationActionPolicyCancel);
}

- (void)webView:(WKWebView *)webView
    decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse
                     decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
    if (!navigationResponse.canShowMIMEType) {
        decisionHandler(WKNavigationResponsePolicyDownload);
        return;
    }

    NSHTTPURLResponse *response = (NSHTTPURLResponse *)navigationResponse.response;
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSString *disposition = [[response valueForHTTPHeaderField:@"Content-Disposition"] lowercaseString];
        if ([disposition containsString:@"attachment"]) {
            decisionHandler(WKNavigationResponsePolicyDownload);
            return;
        }
    }

    decisionHandler(WKNavigationResponsePolicyAllow);
}

- (void)webView:(WKWebView *)webView
    navigationAction:(WKNavigationAction *)navigationAction
     didBecomeDownload:(WKDownload *)download {
    download.delegate = self;
}

- (void)webView:(WKWebView *)webView
    navigationResponse:(WKNavigationResponse *)navigationResponse
      didBecomeDownload:(WKDownload *)download {
    download.delegate = self;
}

#pragma mark - WKUIDelegate

- (void)webView:(WKWebView *)webView
    runOpenPanelWithParameters:(WKOpenPanelParameters *)parameters
             initiatedByFrame:(WKFrameInfo *)frame
            completionHandler:(void (^)(NSArray<NSURL *> * _Nullable))completionHandler {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowsMultipleSelection = parameters.allowsMultipleSelection;
    panel.canChooseDirectories = parameters.allowsDirectories;
    panel.canChooseFiles = YES;
    panel.allowedContentTypes = @[UTTypeJSON];
    panel.allowsOtherFileTypes = YES;

    void (^finish)(NSModalResponse) = ^(NSModalResponse response) {
        completionHandler(response == NSModalResponseOK ? panel.URLs : nil);
    };

    if (self.window) {
        [panel beginSheetModalForWindow:self.window completionHandler:finish];
    } else {
        finish([panel runModal]);
    }
}

- (nullable WKWebView *)webView:(WKWebView *)webView
    createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
               forNavigationAction:(WKNavigationAction *)navigationAction
                    windowFeatures:(WKWindowFeatures *)windowFeatures {
    if (navigationAction.request.URL) {
        [[NSWorkspace sharedWorkspace] openURL:navigationAction.request.URL];
    }
    return nil;
}

#pragma mark - WKDownloadDelegate

- (void)download:(WKDownload *)download
    decideDestinationUsingResponse:(NSURLResponse *)response
                 suggestedFilename:(NSString *)suggestedFilename
               completionHandler:(void (^)(NSURL * _Nullable))completionHandler {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSSavePanel *panel = [NSSavePanel savePanel];
        panel.nameFieldStringValue = suggestedFilename;
        panel.canCreateDirectories = YES;

        if (self.window) {
            [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
                completionHandler(result == NSModalResponseOK ? panel.URL : nil);
            }];
        } else {
            completionHandler([panel runModal] == NSModalResponseOK ? panel.URL : nil);
        }
    });
}

- (void)downloadDidFinish:(WKDownload *)download {
    // Il file è già stato scritto nella destinazione scelta.
}

- (void)download:(WKDownload *)download
    didFailWithError:(NSError *)error
          resumeData:(nullable NSData *)resumeData {
    [self showError:[NSString stringWithFormat:@"Download non riuscito: %@", error.localizedDescription]];
}

@end

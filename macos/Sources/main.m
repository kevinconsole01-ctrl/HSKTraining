#import <Cocoa/Cocoa.h>
#import "ZGAppDelegate.h"

static ZGAppDelegate *ZGSharedDelegate;

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *application = [NSApplication sharedApplication];
        ZGSharedDelegate = [[ZGAppDelegate alloc] init];
        application.delegate = ZGSharedDelegate;
        [application setActivationPolicy:NSApplicationActivationPolicyRegular];
        [application run];
    }
    return 0;
}

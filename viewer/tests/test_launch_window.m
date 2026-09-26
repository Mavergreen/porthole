#import <Cocoa/Cocoa.h>
#import "PortholeLaunchWindow.h"
#include <assert.h>

@interface PortholeLaunchWindow (Testing)
- (void)answer:(NSButton *)sender;
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        PortholeLaunchWindow *w = [[[PortholeLaunchWindow alloc] initWithTitle:@"T" icon:nil] autorelease];
        [w setStep:@"Starting Linux Demo"];
        __block NSString *got = nil;
        [w askText:@"Linux Old App was uninstalled." choices:@[@"Keep", @"Delete"] reply:^(NSString *c) { got = [c copy]; }];
        assert([[w labelText] isEqualToString:@"Linux Old App was uninstalled."]);
        NSButton *b = [[[NSButton alloc] initWithFrame:NSZeroRect] autorelease]; [b setTitle:@"Keep"];
        [w answer:b];
        assert([got isEqualToString:@"Keep"]);
        assert([[w labelText] isEqualToString:@"Starting Linux Demo"]);
        printf("test_launch_window: OK\n");
    }
    return 0;
}

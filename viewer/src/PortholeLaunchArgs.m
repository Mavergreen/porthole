#import "PortholeLaunchArgs.h"
@implementation PortholeLaunchArgs
@synthesize launcherPath, launcherArgs, socketPath;
- (void)dealloc { [launcherPath release]; [launcherArgs release]; [socketPath release]; [super dealloc]; }
@end

PortholeLaunchArgs *PortholeParseLaunchArgs(NSArray *argv) {
    PortholeLaunchArgs *r = [[[PortholeLaunchArgs alloc] init] autorelease];
    for (NSUInteger i = 1; i < argv.count; i++) {
        NSString *a = argv[i];
        if ([a isEqualToString:@"--launch"] && i + 1 < argv.count) {
            r.launcherPath = argv[i + 1];
            r.launcherArgs = [argv subarrayWithRange:NSMakeRange(i + 2, argv.count - i - 2)];
            break;
        }
        if (!r.socketPath && [a hasPrefix:@"/"]) r.socketPath = a;   // today's `Porthole <socket>` form
    }
    return r;
}

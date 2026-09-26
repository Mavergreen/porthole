#import <Foundation/Foundation.h>
#import "PortholeLaunchArgs.h"
#include <assert.h>

int main(void) {
    @autoreleasepool {
        PortholeLaunchArgs *a = PortholeParseLaunchArgs(@[@"/x/Porthole", @"--launch", @"/x/bin/sig", @"--rebuild"]);
        assert([a.launcherPath isEqualToString:@"/x/bin/sig"]);
        assert([a.launcherArgs isEqualToArray:@[@"--rebuild"]]);
        assert(a.socketPath == nil);   // the launcher path is not the socket

        PortholeLaunchArgs *b = PortholeParseLaunchArgs(@[@"/x/Porthole", @"/tmp/app-xpra.sock", @"-psn_0_123"]);
        assert(b.launcherPath == nil);
        assert([b.socketPath isEqualToString:@"/tmp/app-xpra.sock"]);

        PortholeLaunchArgs *c = PortholeParseLaunchArgs(@[@"/x/Porthole"]);
        assert(c.launcherPath == nil && c.socketPath == nil);
        printf("test_launch_args: OK\n");
    }
    return 0;
}

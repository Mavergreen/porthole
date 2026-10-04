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

        assert(!a.prepare);

        // An install's prepare: the launcher runs with --prepare first, then whatever followed.
        PortholeLaunchArgs *p = PortholeParseLaunchArgs(@[@"/x/Porthole", @"--prepare", @"/x/bin/sig", @"-v"]);
        assert(p.prepare);
        assert([p.launcherPath isEqualToString:@"/x/bin/sig"]);
        assert([p.launcherArgs isEqualToArray:(@[@"--prepare", @"-v"])]);
        assert(p.socketPath == nil);

        PortholeLaunchArgs *c = PortholeParseLaunchArgs(@[@"/x/Porthole"]);
        assert(c.launcherPath == nil && c.socketPath == nil);
        printf("test_launch_args: OK\n");
    }
    return 0;
}

#import <Foundation/Foundation.h>
#include <sys/stat.h>
#import "PortholeUpdateItem.h"
#include <assert.h>
#include <unistd.h>

int main(void) {
    @autoreleasepool {
        // A newer image is ready than the one running: restart onto it, updater or not.
        assert(PortholeUpdateItemFor(@"sha256:a", @"sha256:b", YES) == PortholeUpdateItemRestart);
        assert(PortholeUpdateItemFor(@"sha256:a", @"sha256:b", NO) == PortholeUpdateItemRestart);
        // Running the newest: offer a check when there's an updater to ask, else nothing.
        assert(PortholeUpdateItemFor(@"sha256:a", @"sha256:a", YES) == PortholeUpdateItemCheck);
        assert(PortholeUpdateItemFor(@"sha256:a", @"sha256:a", NO) == PortholeUpdateItemHidden);
        // Nothing recorded yet.
        assert(PortholeUpdateItemFor(@"sha256:a", nil, YES) == PortholeUpdateItemCheck);
        assert(PortholeUpdateItemFor(@"sha256:a", @"", NO) == PortholeUpdateItemHidden);
        // Not knowing what's running (a plain socket launch) is never a reason to restart.
        assert(PortholeUpdateItemFor(@"", @"sha256:b", YES) == PortholeUpdateItemCheck);
        assert(PortholeUpdateItemFor(nil, @"sha256:b", NO) == PortholeUpdateItemHidden);

        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                         [NSString stringWithFormat:@"porthole-update-item.%d", getpid()]];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
        [@"sha256:x\n" writeToFile:[dir stringByAppendingPathComponent:@"demo.image"] atomically:YES
                          encoding:NSUTF8StringEncoding error:NULL];
        assert([PortholeRecordedImage(dir, @"demo") isEqualToString:@"sha256:x"]);
        assert(PortholeRecordedImage(dir, @"absent") == nil);
        // Restart to Update reopens the app only once it has quit and its recovery watcher has finished:
        // an on-demand app's watcher stops the container after a clean quit, and must not stop the new one.
        NSString *bundle = [dir stringByAppendingPathComponent:@"Linux Demo.app"];
        NSString *bin = [bundle stringByAppendingPathComponent:@"Contents/Resources/bin"];
        [[NSFileManager defaultManager] createDirectoryAtPath:bin withIntermediateDirectories:YES attributes:nil error:NULL];
        NSString *watcher = [bin stringByAppendingPathComponent:@"porthole-recover-watch"];
        [@"sleep 1.5\n" writeToFile:watcher atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        NSString *stubs = [dir stringByAppendingPathComponent:@"stubs"];
        [[NSFileManager defaultManager] createDirectoryAtPath:stubs withIntermediateDirectories:YES attributes:nil error:NULL];
        NSString *opened = [dir stringByAppendingPathComponent:@"opened"];
        NSString *openStub = [stubs stringByAppendingPathComponent:@"open"];
        [[NSString stringWithFormat:@"#!/bin/sh\nprintf '%%s' \"$1\" > '%@'\n", opened]
            writeToFile:openStub atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        chmod([openStub fileSystemRepresentation], 0755);

        NSTask *app = [NSTask launchedTaskWithLaunchPath:@"/bin/sleep" arguments:@[@"0.5"]];   // the quitting app
        NSTask *watch = [NSTask launchedTaskWithLaunchPath:@"/bin/sh" arguments:@[watcher]];
        NSArray *cmd = PortholeRestartCommand([app processIdentifier], bundle);
        NSTask *restart = [[[NSTask alloc] init] autorelease];
        [restart setLaunchPath:cmd[0]];
        [restart setArguments:[cmd subarrayWithRange:NSMakeRange(1, cmd.count - 1)]];
        [restart setEnvironment:@{@"PATH": [stubs stringByAppendingString:@":/usr/bin:/bin"]}];
        NSDate *t0 = [NSDate date];
        [restart launch]; [restart waitUntilExit];
        assert([watch isRunning] == NO);                       // it waited for the watcher...
        assert([[NSDate date] timeIntervalSinceDate:t0] > 1.0);
        assert([[NSString stringWithContentsOfFile:opened encoding:NSUTF8StringEncoding error:NULL]
                isEqualToString:bundle]);                      // ...then reopened this app
        (void)app;

        // A detached command outlives us without holding our output: an install's postinstall waits for
        // its output to close, and must not wait for the app the command opens.
        int fds[2]; assert(pipe(fds) == 0);
        int saved = dup(1); dup2(fds[1], 1); close(fds[1]);
        PortholeRunDetached(@[@"/bin/sleep", @"3"]);
        dup2(saved, 1); close(saved);
        NSDate *t1 = [NSDate date];
        char b; while (read(fds[0], &b, 1) > 0) {}
        assert([[NSDate date] timeIntervalSinceDate:t1] < 1.0);   // EOF now, not when sleep ends
        close(fds[0]);

        [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
        printf("test_update_item: OK\n");
    }
    return 0;
}

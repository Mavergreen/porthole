#import <Cocoa/Cocoa.h>
#import "PortholeLaunchSession.h"
#include <unistd.h>
#include <assert.h>
#include <sys/resource.h>

@interface Rec : NSObject <PortholeLaunchSessionDelegate>
@property(retain) NSMutableArray *events;
@end
@implementation Rec
- (id)init { if ((self = [super init])) _events = [[NSMutableArray alloc] init]; return self; }
- (void)dealloc { [_events release]; [super dealloc]; }
- (void)launchSession:(id)s step:(NSString *)t { [_events addObject:[@"step:" stringByAppendingString:t]]; }
- (void)launchSession:(id)s progress:(double)f { [_events addObject:[NSString stringWithFormat:@"progress:%.2f", f]]; }
- (void)launchSession:(id)s ask:(NSString *)i text:(NSString *)t choices:(NSArray *)c {
    [_events addObject:[NSString stringWithFormat:@"ask:%@:%lu", i, (unsigned long)c.count]]; }
- (void)launchSession:(id)s failed:(NSString *)t detail:(NSString *)d { [_events addObject:[@"failed:" stringByAppendingString:t]]; }
- (void)launchSession:(id)s readyWithSocket:(NSString *)k icon:(NSString *)i {
    [_events addObject:[NSString stringWithFormat:@"ready:%@:%@", k, i]]; }
@end

static void pump(BOOL (^cond)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
    while (!cond() && [deadline timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
}
static void put(int fd, const char *s) { write(fd, s, strlen(s)); }

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        // Parser.
        assert([PortholeLaunchSession messageFromLine:@"{\"t\":\"step\",\"text\":\"x\"}"] != nil);
        assert([PortholeLaunchSession messageFromLine:@"Step 4/7 : RUN apt-get"] == nil);
        assert([PortholeLaunchSession messageFromLine:@"{\"no\":\"t\"}"] == nil);
        assert([PortholeLaunchSession messageFromLine:@"[1,2]"] == nil);

        int toViewer[2], toLauncher[2];
        assert(pipe(toViewer) == 0 && pipe(toLauncher) == 0);
        PortholeLaunchSession *s = [[[PortholeLaunchSession alloc] initWithReadFD:toViewer[0] writeFD:toLauncher[1]] autorelease];
        Rec *r = [[[Rec alloc] init] autorelease];
        s.delegate = r; [s start];

        put(toViewer[1], "{\"t\":\"step\",\"text\":\"Downloading\"}\nnot json at all\n{\"t\":\"progress\",\"fraction\":0.5}\n");
        put(toViewer[1], "{\"t\":\"ask\",\"id\":\"q1\",\"text\":\"?\",\"choices\":[\"Keep\",\"Delete\"]}\n");
        pump(^BOOL{ return r.events.count >= 3; });
        assert([r.events[0] isEqualToString:@"step:Downloading"]);
        assert([r.events[1] isEqualToString:@"progress:0.50"]);
        assert([r.events[2] isEqualToString:@"ask:q1:2"]);

        [s answer:@"q1" choice:@"Delete"];
        char buf[256]; ssize_t n = read(toLauncher[0], buf, sizeof buf - 1); assert(n > 0); buf[n] = 0;
        assert(strstr(buf, "\"answer\"") && strstr(buf, "\"q1\"") && strstr(buf, "\"Delete\"") && buf[n-1] == '\n');

        put(toViewer[1], "{\"t\":\"ready\",\"socket\":\"/tmp/x.sock\",\"icon\":\"\"}\n");
        pump(^BOOL{ return r.events.count >= 4; });
        assert([r.events[3] isEqualToString:@"ready:/tmp/x.sock:"]);

        // A second session whose launcher dies without a word -> failed.
        int p2[2], q2[2]; assert(pipe(p2) == 0 && pipe(q2) == 0);
        PortholeLaunchSession *s2 = [[[PortholeLaunchSession alloc] initWithReadFD:p2[0] writeFD:q2[1]] autorelease];
        Rec *r2 = [[[Rec alloc] init] autorelease]; s2.delegate = r2; [s2 start];
        close(p2[1]);
        pump(^BOOL{ return r2.events.count >= 1; });
        assert([r2.events[0] hasPrefix:@"failed:"]);

        // A launcher that exits while a background child still holds its stdout -> failed, not a wait
        // for the child.
        PortholeLaunchSession *s3 = [[[PortholeLaunchSession alloc] initWithLauncher:@"/bin/sh"
            arguments:@[@"-c", @"echo gone >&2; sleep 6 & exit 0"]] autorelease];
        Rec *r3 = [[[Rec alloc] init] autorelease]; s3.delegate = r3; [s3 start];
        pump(^BOOL{ return r3.events.count >= 1; });
        assert(r3.events.count == 1 && [r3.events[0] hasPrefix:@"failed:"]);

        // After the launcher is done, its stderr at EOF costs nothing.
        PortholeLaunchSession *s4 = [[[PortholeLaunchSession alloc] initWithLauncher:@"/bin/sh"
            arguments:@[@"-c", @"echo '{\"t\":\"ready\",\"socket\":\"/tmp/y.sock\"}'"]] autorelease];
        Rec *r4 = [[[Rec alloc] init] autorelease]; s4.delegate = r4; [s4 start];
        pump(^BOOL{ return r4.events.count >= 1; });
        assert([r4.events[0] hasPrefix:@"ready:/tmp/y.sock"]);
        struct rusage a, b; getrusage(RUSAGE_SELF, &a);
        sleep(1);   // the readers run on their own threads; this thread stays idle
        getrusage(RUSAGE_SELF, &b);
        double cpu = (b.ru_utime.tv_sec - a.ru_utime.tv_sec) + (b.ru_utime.tv_usec - a.ru_utime.tv_usec) / 1e6
                   + (b.ru_stime.tv_sec - a.ru_stime.tv_sec) + (b.ru_stime.tv_usec - a.ru_stime.tv_usec) / 1e6;
        assert(cpu < 0.3);
        assert(r4.events.count == 1);   // a clean exit after ready is not a failure

        printf("test_launch_wire: OK\n");
    }
    return 0;
}

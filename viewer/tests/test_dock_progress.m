#import <Cocoa/Cocoa.h>
#import "PortholeDockProgress.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        PortholeDockProgress *p = [[[PortholeDockProgress alloc] init] autorelease];
        assert(!p.running);
        [p start];
        assert(p.running && [[NSApp dockTile] contentView] != nil);
        NSView *v = [[NSApp dockTile] contentView];
        [p start];   // again: the same indicator, not a second one
        assert(p.running && [[NSApp dockTile] contentView] == v);
        [p stop];
        assert(!p.running && [[NSApp dockTile] contentView] == nil);
        [p stop];
        assert(!p.running);
        printf("test_dock_progress: OK\n");
    }
    return 0;
}

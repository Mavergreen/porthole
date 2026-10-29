// A tray must be configured on the virtual screen before the shell can click it.
// Otherwise Xpra leaves its XEmbed corral at (-200,-200), beyond XTest's reach.
#import <Foundation/Foundation.h>
#import "PortholeClient.h"
#import "PortholeProtocol.h"
#include <assert.h>

@interface TrayClient : PortholeClient
@property(retain) NSMutableArray *packets;
@end
@implementation TrayClient
- (void)sendPacket:(NSArray *)packet { [self.packets addObject:packet]; }
- (void)dealloc { [_packets release]; [super dealloc]; }
@end

typedef struct { TrayClient *client; } TrayContext;

static void tray(void *ctx, long wid, int w, int h) {
    TrayClient *client = ((TrayContext *)ctx)->client;
    // The shell is allowed to send input from this callback, so placement must
    // already have been sent. No map-window: trays have no client-geometry.
    assert(client.packets.count == 1);
    assert([client.packets[0] isEqual:(@[@"configure-window", @42, @0, @0, @16, @16, @{}])]);
    assert(wid == 42 && w == 16 && h == 16);
    rds_button((rds_session *)client, wid, 1, 1, 0, 0);
    rds_button((rds_session *)client, wid, 1, 0, 0, 0);
}

int main(void) {
    @autoreleasepool {
        TrayContext ctx = {0};
        rds_callbacks cb = {0}; cb.ctx = &ctx; cb.new_tray = tray;
        TrayClient *client = [[[TrayClient alloc] initWithSocketPath:@"/unused" callbacks:&cb] autorelease];
        ctx.client = client;
        client.packets = [NSMutableArray array];
        [client transport:nil didReceivePayload:[PortholeProtocol encodeValue:@[@"new-tray", @42, @16, @16, @{}]] rawChunks:@{}];
        assert(client.packets.count == 3);
        assert([client.packets[1] isEqual:(@[@"button-action", @42, @1, @YES, @[@0,@0,@0,@0], @[]])]);
        assert([client.packets[2] isEqual:(@[@"button-action", @42, @1, @NO, @[@0,@0,@0,@0], @[]])]);
        printf("test_tray_input: OK\n");
    }
    return 0;
}

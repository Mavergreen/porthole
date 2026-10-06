// PortholeDockProgress -- an indeterminate progress bar over the app's Dock icon, for a launch that
// is under way without a window to say so.
#import <Cocoa/Cocoa.h>

@interface PortholeDockProgress : NSObject
- (void)start;   // idempotent
- (void)stop;    // idempotent; the plain icon returns
@property(readonly, nonatomic) BOOL running;
@end

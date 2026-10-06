#import "PortholeDockProgress.h"

// The app's current icon with a bar along its bottom whose bright segment sweeps back and forth.
@interface PortholeDockProgressView : NSView
@property(nonatomic) double phase;   // 0..1, one sweep each way per unit
@end

@implementation PortholeDockProgressView
- (void)drawRect:(NSRect)dirty {
    (void)dirty;
    NSRect b = [self bounds];
    [[NSApp applicationIconImage] drawInRect:b fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
    NSRect track = NSMakeRect(NSMinX(b) + NSWidth(b) * 0.12, NSMinY(b) + NSHeight(b) * 0.08,
                              NSWidth(b) * 0.76, NSHeight(b) * 0.11);
    CGFloat r = NSHeight(track) / 2;
    [[NSColor colorWithCalibratedWhite:0.1 alpha:0.75] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:track xRadius:r yRadius:r] fill];
    NSRect inner = NSInsetRect(track, NSHeight(track) * 0.18, NSHeight(track) * 0.18);
    CGFloat segW = NSWidth(inner) * 0.35, sweep = _phase < 0.5 ? _phase * 2 : (1 - _phase) * 2;
    NSRect seg = NSMakeRect(NSMinX(inner) + (NSWidth(inner) - segW) * sweep, NSMinY(inner), segW, NSHeight(inner));
    CGFloat sr = NSHeight(seg) / 2;
    [[NSColor colorWithCalibratedRed:0.35 green:0.65 blue:1.0 alpha:1.0] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:seg xRadius:sr yRadius:sr] fill];
}
@end

@implementation PortholeDockProgress {
    NSTimer *_timer;
    PortholeDockProgressView *_view;
}

- (BOOL)running { return _timer != nil; }

- (void)start {
    if (_timer) return;
    NSDockTile *tile = [NSApp dockTile];
    NSSize sz = [tile size];
    _view = [[PortholeDockProgressView alloc] initWithFrame:NSMakeRect(0, 0, sz.width, sz.height)];
    [tile setContentView:_view];
    [tile display];
    _timer = [[NSTimer timerWithTimeInterval:0.1 target:self selector:@selector(tick:) userInfo:nil repeats:YES] retain];
    [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
}

- (void)tick:(NSTimer *)t {
    (void)t;
    double p = _view.phase + 0.04;
    _view.phase = p >= 1 ? p - 1 : p;
    [[NSApp dockTile] display];
}

- (void)stop {
    if (!_timer) return;
    [_timer invalidate]; [_timer release]; _timer = nil;
    NSDockTile *tile = [NSApp dockTile];
    [tile setContentView:nil];
    [tile display];
    [_view release]; _view = nil;
}

- (void)dealloc { [self stop]; [super dealloc]; }
@end

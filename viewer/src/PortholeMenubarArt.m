#import "PortholeMenubarArt.h"

// Pictures are compared at this size, by colour over black (premultiplied RGB; alpha left out, since
// tray art may arrive without it, black where it was transparent): small enough that the app's tray
// art at any size matches its own picture, large enough to keep a badge (1Password's lock) apart.
enum { kSide = 16 };
// Tray art is taken for the app picture it is nearest, when that is within kMatch (mean difference
// per channel, 0..1) and nearer than any other by kMargin. An app may draw its small tray art afresh
// rather than scale its picture: 1Password's 16-pixel unlocked art is 0.08-0.10 from its own picture,
// 0.12 or more from the others.
static const double kMatch = 0.15, kMargin = 1.3;

static BOOL sample(NSImage *im, uint8_t out[kSide * kSide * 4]) {
    if (!im) return NO;
    memset(out, 0, kSide * kSide * 4);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = CGBitmapContextCreate(out, kSide, kSide, 8, kSide * 4, cs,
                                           (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(cs);
    if (!c) return NO;
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithGraphicsPort:c flipped:NO]];
    [[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationHigh];
    [im drawInRect:NSMakeRect(0, 0, kSide, kSide) fromRect:NSZeroRect operation:NSCompositeCopy fraction:1];
    [NSGraphicsContext restoreGraphicsState];
    CGContextRelease(c);
    return YES;
}

static NSSize pixelSize(NSImage *im) {
    NSInteger w = 0, h = 0;
    for (NSImageRep *r in [im representations]) { w = MAX(w, [r pixelsWide]); h = MAX(h, [r pixelsHigh]); }
    return NSMakeSize(w, h);
}

@implementation PortholeMenubarArt {
    NSArray *_pairs;   // of @[NSData samples of the app picture, NSImage Mac picture]
}

+ (instancetype)artInDirectory:(NSString *)dir {
    NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL];
    NSMutableArray *pairs = [NSMutableArray array];
    for (NSString *f in [names sortedArrayUsingSelector:@selector(compare:)]) {
        if (![f hasSuffix:@".app.png"]) continue;
        NSString *n = [f substringToIndex:[f length] - [@".app.png" length]];
        BOOL tmpl = NO;
        NSString *macPath = [dir stringByAppendingPathComponent:[n stringByAppendingString:@".mac.png"]];
        if (![[NSFileManager defaultManager] fileExistsAtPath:macPath]) {
            macPath = [dir stringByAppendingPathComponent:[n stringByAppendingString:@".mac-template.png"]];
            tmpl = YES;
        }
        NSImage *app = [[[NSImage alloc] initWithContentsOfFile:[dir stringByAppendingPathComponent:f]] autorelease];
        NSImage *mac = [[[NSImage alloc] initWithContentsOfFile:macPath] autorelease];
        uint8_t px[kSide * kSide * 4];
        if (!app || !mac || !sample(app, px)) continue;
        // A menu-bar picture is drawn for a 16-point bar slot; one twice that is a Retina (@2x) picture.
        NSSize p = pixelSize(mac);
        [mac setSize:p.height >= 32 ? NSMakeSize(p.width / 2, p.height / 2) : p];
        [mac setTemplate:tmpl];
        [pairs addObject:@[[NSData dataWithBytes:px length:sizeof px], mac]];
    }
    if (![pairs count]) return nil;
    PortholeMenubarArt *art = [[[self alloc] init] autorelease];
    art->_pairs = [pairs copy];
    return art;
}

- (void)dealloc { [_pairs release]; [super dealloc]; }

- (NSImage *)macPictureFor:(NSImage *)trayArt { return [self macPictureFor:trayArt closest:NULL]; }

- (NSImage *)macPictureFor:(NSImage *)trayArt closest:(double *)closest {
    uint8_t px[kSide * kSide * 4];
    if (closest) *closest = 1;
    if (!sample(trayArt, px)) return nil;
    NSImage *best = nil;
    double bestD = 1, nextD = 1;
    for (NSArray *pair in _pairs) {
        const uint8_t *q = [pair[0] bytes];
        double d = 0;
        for (int i = 0; i < kSide * kSide * 4; i++)
            if (i % 4 != 3) d += abs((int)px[i] - (int)q[i]);
        d /= 255.0 * kSide * kSide * 3;
        if (d < bestD) { nextD = bestD; bestD = d; best = pair[1]; }
        else if (d < nextD) nextD = d;
    }
    if (closest) *closest = bestD;
    return bestD < kMatch && bestD * kMargin < nextD ? best : nil;
}
@end

#import "PortholeMenubarArt.h"

// Pictures are compared at this size, as premultiplied RGBA: small enough that the app's tray art at
// any size matches its own picture, large enough to keep a badge (1Password's lock) apart.
enum { kSide = 16 };
// The mean difference per channel (0..1) below which tray art is taken for an app picture. The art
// a viewer receives differs from its own picture only by scaling (~0.01); 1Password's three tray
// pictures differ from each other by 0.07 or more.
static const double kMatch = 0.04;

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

- (NSImage *)macPictureFor:(NSImage *)trayArt {
    uint8_t px[kSide * kSide * 4];
    if (!sample(trayArt, px)) return nil;
    NSImage *best = nil;
    double bestD = kMatch;
    for (NSArray *pair in _pairs) {
        const uint8_t *q = [pair[0] bytes];
        double d = 0;
        for (int i = 0; i < kSide * kSide * 4; i++) d += abs((int)px[i] - (int)q[i]);
        d /= 255.0 * kSide * kSide * 4;
        if (d < bestD) { bestD = d; best = pair[1]; }
    }
    return best;
}
@end

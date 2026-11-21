// PortholeMenubarArt: an app's menu-bar art pairs (its tray picture, the Mac picture shown for it),
// and picking the Mac picture for the tray art the app sends.
#import <Cocoa/Cocoa.h>
#import "PortholeMenubarArt.h"

static int failures = 0;
#define CHECK(cond, msg) do { if (!(cond)) { fprintf(stderr, "FAIL: %s\n", msg); failures++; } } while (0)

// A disc of COLOR on transparency, PX pixels square, with an optional white badge lower right.
static NSImage *disc(NSColor *color, int px, BOOL badge) {
    NSBitmapImageRep *r = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:px pixelsHigh:px
        bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace
        bytesPerRow:0 bitsPerPixel:0];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:r]];
    [color setFill]; [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(0, 0, px, px)] fill];
    if (badge) { [[NSColor whiteColor] setFill]; NSRectFill(NSMakeRect(px * 0.5, 0, px * 0.5, px * 0.5)); }
    [NSGraphicsContext restoreGraphicsState];
    NSImage *im = [[[NSImage alloc] initWithSize:NSMakeSize(px, px)] autorelease];
    [im addRepresentation:r]; [r release];
    return im;
}
// The same disc as tray art arrives without alpha (rgb24): opaque, black where it was transparent.
static NSImage *opaqueDisc(NSColor *color, int px, BOOL badge) {
    NSBitmapImageRep *r = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:px pixelsHigh:px
        bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace
        bytesPerRow:0 bitsPerPixel:0];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:r]];
    [[NSColor blackColor] setFill]; NSRectFill(NSMakeRect(0, 0, px, px));
    [disc(color, px, badge) drawInRect:NSMakeRect(0, 0, px, px) fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1];
    [NSGraphicsContext restoreGraphicsState];
    NSImage *im = [[[NSImage alloc] initWithSize:NSMakeSize(px, px)] autorelease];
    [im addRepresentation:r]; [r release];
    return im;
}
static void writePNG(NSImage *im, NSString *path) {
    NSBitmapImageRep *r = (NSBitmapImageRep *)[[im representations] firstObject];
    [[r representationUsingType:NSPNGFileType properties:@{}] writeToFile:path atomically:YES];
}

int main(void) {
    @autoreleasepool {
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                         [NSString stringWithFormat:@"pma-%d", getpid()]];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
        NSColor *blue = [NSColor colorWithDeviceRed:0.1 green:0.4 blue:0.9 alpha:1];
        writePNG(disc(blue, 256, NO), [dir stringByAppendingPathComponent:@"unlocked.app.png"]);
        writePNG(disc([NSColor blackColor], 32, NO), [dir stringByAppendingPathComponent:@"unlocked.mac-template.png"]);
        writePNG(disc(blue, 256, YES), [dir stringByAppendingPathComponent:@"locked.app.png"]);
        writePNG(disc([NSColor blackColor], 16, YES), [dir stringByAppendingPathComponent:@"locked.mac.png"]);

        PortholeMenubarArt *art = [PortholeMenubarArt artInDirectory:dir];
        CHECK(art != nil, "a directory of pairs loads");

        NSImage *u = [art macPictureFor:disc(blue, 22, NO)];
        CHECK(u != nil, "the plain disc, sent small, is recognised");
        CHECK(u && [u isTemplate], "a -template picture is a template");
        CHECK(u && NSEqualSizes([u size], NSMakeSize(16, 16)), "a 32-pixel picture is shown at 16 points");

        NSImage *l = [art macPictureFor:disc(blue, 22, YES)];
        CHECK(l != nil && l != u, "the badged disc gets the other picture");
        CHECK(l && ![l isTemplate], "a plain .mac picture is not a template");
        CHECK(l && NSEqualSizes([l size], NSMakeSize(16, 16)), "a 16-pixel picture is shown at 16 points");

        CHECK([art macPictureFor:opaqueDisc(blue, 16, NO)] == u, "art sent without alpha (black for transparent) matches");
        CHECK([art macPictureFor:opaqueDisc(blue, 16, YES)] == l, "...and keeps the badge apart");
        // The app's tray art may be drawn afresh for its size rather than scaled from its picture:
        // still nearest its own, by a clear margin, though not identical.
        NSColor *bluish = [NSColor colorWithDeviceRed:0.25 green:0.5 blue:0.95 alpha:1];
        CHECK([art macPictureFor:disc(bluish, 16, NO)] == u, "a redrawn, slightly different disc is still recognised");
        // Halfway between two pictures (a half-faded badge): neither is clearly it.
        NSImage *between = disc(blue, 22, NO);
        [between lockFocus];
        [[[NSColor whiteColor] colorWithAlphaComponent:0.5] setFill];
        NSRectFillUsingOperation(NSMakeRect(11, 0, 11, 11), NSCompositeSourceOver);
        [between unlockFocus];
        CHECK([art macPictureFor:between] == nil, "art as near one picture as another gets none");
        CHECK([art macPictureFor:disc([NSColor greenColor], 22, NO)] == nil, "unrelated art gets none");
        CHECK([art macPictureFor:nil] == nil, "no art gets none");

        CHECK([PortholeMenubarArt artInDirectory:[dir stringByAppendingPathComponent:@"none"]] == nil,
              "a missing directory has no art");
        [[NSFileManager defaultManager] removeItemAtPath:[dir stringByAppendingPathComponent:@"locked.app.png"] error:NULL];
        PortholeMenubarArt *half = [PortholeMenubarArt artInDirectory:dir];
        CHECK(half != nil && [half macPictureFor:disc(blue, 22, YES)] != l, "a pair missing its app picture is skipped");
        [[NSFileManager defaultManager] removeItemAtPath:dir error:NULL];
    }
    if (failures) { fprintf(stderr, "%d failure(s)\n", failures); return 1; }
    printf("menubar art: ok\n");
    return 0;
}

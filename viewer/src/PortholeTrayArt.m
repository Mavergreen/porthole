#import "PortholeTrayArt.h"

BOOL PortholeTrayArtIsMonochrome(const uint8_t *px, int w, int h, size_t stride, int bpp) {
    BOOL anyVisible = NO;
    for (int y = 0; y < h; y++) {
        const uint8_t *row = px + (size_t)y * stride;
        for (int x = 0; x < w; x++) {
            const uint8_t *p = row + (size_t)x * bpp;
            if (bpp >= 4 && p[3] == 0) continue;
            anyVisible = YES;
            uint8_t hi = p[0], lo = p[0];
            for (int c = 1; c < 3; c++) { if (p[c] > hi) hi = p[c]; if (p[c] < lo) lo = p[c]; }
            if (hi - lo > 16) return NO;
        }
    }
    return anyVisible;
}

NSSize PortholeTrayArtSize(NSSize pixels, CGFloat scale, CGFloat maxHeight) {
    if (scale <= 0) scale = 1;
    NSSize pts = NSMakeSize(pixels.width / scale, pixels.height / scale);
    if (pts.height <= maxHeight || pts.height <= 0) return pts;
    CGFloat k = maxHeight / pts.height;
    return NSMakeSize(pts.width * k, maxHeight);
}

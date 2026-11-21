#import "PortholeTrayArt.h"
#include <math.h>

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

// xpra sends tray pixels premultiplied by alpha (and NSBitmapImageRep takes them so), so colour is
// read, and written back, through the alpha.
static void straight(const uint8_t *p, int bpp, double c[3]) {
    double a = bpp >= 4 && p[3] ? p[3] / 255.0 : 1.0;
    for (int i = 0; i < 3; i++) c[i] = fmin(1.0, p[i] / 255.0 / a);
}

static double light_of(const uint8_t *p, int bpp) {
    double c[3]; straight(p, bpp, c);
    return (fmax(c[0], fmax(c[1], c[2])) + fmin(c[0], fmin(c[1], c[2]))) / 2;
}

// Measured 2026-11-21 on the real art: 1Password's tray is 54-60% near-white, Signal's 34% (though
// its mean lightness, 0.72, is as high as 1Password's 0.74), so the share of bar-like pixels, not
// the mean, tells them apart.
BOOL PortholeTrayArtBlendsWithBar(const uint8_t *px, int w, int h, size_t stride, int bpp, BOOL darkBar) {
    double like = 0, weight = 0;
    for (int y = 0; y < h; y++) {
        const uint8_t *row = px + (size_t)y * stride;
        for (int x = 0; x < w; x++) {
            const uint8_t *p = row + (size_t)x * bpp;
            double a = bpp >= 4 ? p[3] / 255.0 : 1.0, l = light_of(p, bpp);
            weight += a;
            if (darkBar ? l < 0.25 : l > 0.75) like += a;
        }
    }
    return weight > 0 && like / weight > 0.45;
}

static double hue_to(double p, double q, double t) {
    if (t < 0) t += 1; if (t > 1) t -= 1;
    if (t < 1.0 / 6) return p + (q - p) * 6 * t;
    if (t < 0.5) return q;
    if (t < 2.0 / 3) return p + (q - p) * (2.0 / 3 - t) * 6;
    return p;
}

void PortholeTrayArtFlipForBar(uint8_t *px, int w, int h, size_t stride, int bpp, BOOL darkBar) {
    for (int y = 0; y < h; y++) {
        uint8_t *row = px + (size_t)y * stride;
        for (int x = 0; x < w; x++) {
            uint8_t *p = row + (size_t)x * bpp;
            if (bpp >= 4 && p[3] == 0) continue;
            double cs[3]; straight(p, bpp, cs);
            double c0 = cs[0], c1 = cs[1], c2 = cs[2], alpha = bpp >= 4 ? p[3] / 255.0 : 1.0;
            double hi = fmax(c0, fmax(c1, c2)), lo = fmin(c0, fmin(c1, c2)), l = (hi + lo) / 2;
            // Only the bar's side moves, and not all the way to its opposite: light 0.9 lands at a dark
            // grey 0.25 rather than black, so the art keeps its shading.
            double nl;
            if (!darkBar && l > 0.6) nl = 1.15 - l;
            else if (darkBar && l < 0.4) nl = 0.85 - l;
            else continue;
            double s = 0, hu = 0, d = hi - lo;
            if (d > 0) {
                s = l > 0.5 ? d / (2 - hi - lo) : d / (hi + lo);
                if (hi == c0) hu = (c1 - c2) / d + (c1 < c2 ? 6 : 0);
                else if (hi == c1) hu = (c2 - c0) / d + 2;
                else hu = (c0 - c1) / d + 4;
                hu /= 6;
            }
            double q = nl < 0.5 ? nl * (1 + s) : nl + s - nl * s, pp = 2 * nl - q;
            double o[3] = { hue_to(pp, q, hu + 1.0 / 3), hue_to(pp, q, hu), hue_to(pp, q, hu - 1.0 / 3) };
            if (d == 0) o[0] = o[1] = o[2] = nl;
            for (int c = 0; c < 3; c++) p[c] = (uint8_t)lround(fmax(0, fmin(1, o[c])) * alpha * 255);
        }
    }
}

BOOL PortholeMenuBarIsDark(void) {
    CFPreferencesAppSynchronize(kCFPreferencesAnyApplication);
    CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("AppleInterfaceStyle"), kCFPreferencesAnyApplication);
    BOOL dark = v && CFGetTypeID(v) == CFStringGetTypeID()
        && CFStringCompare((CFStringRef)v, CFSTR("Dark"), kCFCompareCaseInsensitive) == kCFCompareEqualTo;
    if (v) CFRelease(v);
    return dark;
}

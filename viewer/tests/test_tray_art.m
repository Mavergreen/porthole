#import <Foundation/Foundation.h>
#import "PortholeTrayArt.h"

static int failures = 0;
#define CHECK(cond, msg) do { if (!(cond)) { fprintf(stderr, "FAIL: %s\n", msg); failures++; } } while (0)

static uint8_t *fill(int w, int h, uint8_t b, uint8_t g, uint8_t r, uint8_t a) {
    uint8_t *p = malloc((size_t)w * h * 4);
    for (int i = 0; i < w * h; i++) { p[i*4]=b; p[i*4+1]=g; p[i*4+2]=r; p[i*4+3]=a; }
    return p;
}

int main(void) {
    // A gray glyph on transparency: monochrome.
    uint8_t *g = fill(16, 16, 0, 0, 0, 0);
    for (int i = 0; i < 40; i++) { g[i*4]=g[i*4+1]=g[i*4+2]=200; g[i*4+3]=255; }
    CHECK(PortholeTrayArtIsMonochrome(g, 16, 16, 64, 4), "gray glyph is monochrome");

    // Signal-like: blue bubble with a white numeral: color.
    uint8_t *s = fill(16, 16, 242, 81, 34, 255);
    for (int i = 0; i < 10; i++) { s[i*4]=s[i*4+1]=s[i*4+2]=255; }
    CHECK(!PortholeTrayArtIsMonochrome(s, 16, 16, 64, 4), "blue bubble is color");

    // Mostly gray with one colored pixel: color.
    g[100*4] = 0; g[100*4+1] = 0; g[100*4+2] = 255; g[100*4+3] = 255;
    CHECK(!PortholeTrayArtIsMonochrome(g, 16, 16, 64, 4), "one colored pixel makes it color");

    // Fully transparent frame: not monochrome (nothing to template).
    uint8_t *t = fill(16, 16, 50, 50, 50, 0);
    CHECK(!PortholeTrayArtIsMonochrome(t, 16, 16, 64, 4), "empty frame is not monochrome");

    // rgb24 (no alpha): every pixel counts as visible.
    uint8_t *c3 = malloc(16 * 16 * 3);
    for (int i = 0; i < 256; i++) { c3[i*3]=120; c3[i*3+1]=120; c3[i*3+2]=120; }
    CHECK(PortholeTrayArtIsMonochrome(c3, 16, 16, 48, 3), "gray rgb24 is monochrome");
    c3[0] = 255; c3[1] = 0; c3[2] = 0;
    CHECK(!PortholeTrayArtIsMonochrome(c3, 16, 16, 48, 3), "colored rgb24 is color");

    // rgb24 sent in 4 bytes (BGRX, X = 0): nothing reads as visible, so it errs toward color.
    uint8_t *x = fill(16, 16, 120, 120, 120, 0);
    CHECK(!PortholeTrayArtIsMonochrome(x, 16, 16, 64, 4), "BGRX with X=0 errs toward color");

    // Sizing in points: pixels / scale, never up, only down to the menu bar's height.
    NSSize a = PortholeTrayArtSize(NSMakeSize(16, 16), 1, 22);
    CHECK(a.width == 16 && a.height == 16, "16px at 1x is 16pt");
    NSSize r = PortholeTrayArtSize(NSMakeSize(32, 32), 2, 22);
    CHECK(r.width == 16 && r.height == 16, "32px at 2x (Retina) is a crisp 16pt");
    NSSize b = PortholeTrayArtSize(NSMakeSize(48, 48), 1, 22);
    CHECK(b.width == 22 && b.height == 22, "48px at 1x scales down to 22pt");
    NSSize c = PortholeTrayArtSize(NSMakeSize(44, 22), 1, 22);
    CHECK(c.width == 44 && c.height == 22, "22pt-tall art is left alone");

    free(g); free(s); free(t); free(c3);
    if (failures) return 1;
    printf("ok tray_art\n");
    return 0;
}

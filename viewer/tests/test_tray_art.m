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

    // spec: the art has to stand out against the bar it's on, judged each time the bar's appearance changes.
    // 1Password-like: a near-white disc (drawn for a dark Linux panel) with a small blue keyhole.
    uint8_t *op = fill(16, 16, 0, 0, 0, 0);
    for (int i = 0; i < 200; i++) { op[i*4]=op[i*4+1]=op[i*4+2]=228; op[i*4+3]=255; }
    for (int i = 200; i < 230; i++) { op[i*4]=242; op[i*4+1]=81; op[i*4+2]=34; op[i*4+3]=255; }
    CHECK(PortholeTrayArtBlendsWithBar(op, 16, 16, 64, 4, NO), "light art blends into a light bar");
    CHECK(!PortholeTrayArtBlendsWithBar(op, 16, 16, 64, 4, YES), "light art stands out on a dark bar");
    CHECK(!PortholeTrayArtBlendsWithBar(s, 16, 16, 64, 4, NO), "Signal's blue stands out on a light bar");
    CHECK(!PortholeTrayArtBlendsWithBar(s, 16, 16, 64, 4, YES), "Signal's blue stands out on a dark bar");
    // Signal's real art measures mean lightness 0.72 but only a third near-white: it stands out.
    uint8_t *sig = fill(16, 16, 0, 0, 0, 0);
    for (int i = 0; i < 86; i++) { sig[i*4]=sig[i*4+1]=sig[i*4+2]=245; sig[i*4+3]=255; }
    for (int i = 86; i < 256; i++) { sig[i*4]=250; sig[i*4+1]=150; sig[i*4+2]=120; sig[i*4+3]=255; }
    CHECK(!PortholeTrayArtBlendsWithBar(sig, 16, 16, 64, 4, NO), "Signal-like art (a third near-white) stands out on a light bar");
    // 1Password's real art: just over half near-white, the rest a mid blue ring.
    uint8_t *op2 = fill(16, 16, 0, 0, 0, 0);
    for (int i = 0; i < 140; i++) { op2[i*4]=op2[i*4+1]=op2[i*4+2]=240; op2[i*4+3]=255; }
    for (int i = 140; i < 256; i++) { op2[i*4]=242; op2[i*4+1]=120; op2[i*4+2]=60; op2[i*4+3]=255; }
    CHECK(PortholeTrayArtBlendsWithBar(op2, 16, 16, 64, 4, NO), "1Password-like art (over half near-white) blends into a light bar");
    free(sig); free(op2);
    // xpra sends tray pixels premultiplied by alpha (seen live 2026-11-21): a near-white edge pixel at
    // alpha 0x21 arrives as 1c1c1c. It is light, and flipping it keeps its colour within its alpha.
    uint8_t *edge = fill(16, 16, 0x1c, 0x1c, 0x1c, 0x21);
    CHECK(PortholeTrayArtBlendsWithBar(edge, 16, 16, 64, 4, NO), "premultiplied near-white edges count as light");
    PortholeTrayArtFlipForBar(edge, 16, 16, 64, 4, NO);
    CHECK(edge[0] <= edge[3] && edge[0] < 0x10 && edge[3] == 0x21, "a flipped edge stays premultiplied, now dark");
    free(edge);
    uint8_t *navy = fill(16, 16, 60, 30, 30, 255);
    CHECK(PortholeTrayArtBlendsWithBar(navy, 16, 16, 64, 4, YES), "dark art blends into a dark bar");
    CHECK(!PortholeTrayArtBlendsWithBar(navy, 16, 16, 64, 4, NO), "dark art stands out on a light bar");
    CHECK(!PortholeTrayArtBlendsWithBar(t, 16, 16, 64, 4, NO), "an empty frame blends with nothing");

    // Flipping keeps hue and alpha: the light disc goes dark, the blue keyhole stays blue.
    PortholeTrayArtFlipForBar(op, 16, 16, 64, 4, NO);
    CHECK(op[0] < 90 && op[0] == op[1] && op[1] == op[2], "light grey becomes dark grey on a light bar");
    CHECK(op[0*4+3] == 255, "alpha is kept");
    CHECK(op[210*4] > op[210*4+2] + 100, "the blue keyhole is still blue");
    CHECK(!PortholeTrayArtBlendsWithBar(op, 16, 16, 64, 4, NO), "after flipping, it stands out on a light bar");
    PortholeTrayArtFlipForBar(navy, 16, 16, 64, 4, YES);
    CHECK(!PortholeTrayArtBlendsWithBar(navy, 16, 16, 64, 4, YES), "flipped dark art stands out on a dark bar");
    CHECK(navy[0] > navy[2], "...and keeps its hue");
    uint8_t *tc = fill(4, 4, 228, 228, 228, 0);
    PortholeTrayArtFlipForBar(tc, 4, 4, 16, 4, NO);
    CHECK(tc[0] == 228, "transparent pixels are left alone");

    free(g); free(s); free(t); free(c3); free(op); free(navy); free(tc);
    if (failures) return 1;
    printf("ok tray_art\n");
    return 0;
}

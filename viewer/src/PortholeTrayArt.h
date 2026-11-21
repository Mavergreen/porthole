// PortholeTrayArt -- how a forwarded tray icon should sit in the Mac menu bar. Mavericks shows a
// plain image in color; only a template image becomes a silhouette, so only art that was already
// monochrome is shown as a template.
#import <Foundation/Foundation.h>

BOOL PortholeTrayArtIsMonochrome(const uint8_t *px, int w, int h, size_t stride, int bpp);
NSSize PortholeTrayArtSize(NSSize pixels, CGFloat scale, CGFloat maxHeight);
// YES when the art's visible pixels are, on average, as light as a light bar (darkBar NO) or as dark
// as a dark one: it would blend in. Monochrome art never needs this; it is shown as a template.
BOOL PortholeTrayArtBlendsWithBar(const uint8_t *px, int w, int h, size_t stride, int bpp, BOOL darkBar);
// In place: flip the lightness of the pixels on the bar's side (light ones on a light bar, dark ones on
// a dark bar), keeping each pixel's hue, saturation and alpha.
void PortholeTrayArtFlipForBar(uint8_t *px, int w, int h, size_t stride, int bpp, BOOL darkBar);
// YES when the menu bar is dark: the global AppleInterfaceStyle is "Dark", as 10.10 and later set it
// and as a Mavericks dark-mode toggle should.
BOOL PortholeMenuBarIsDark(void);

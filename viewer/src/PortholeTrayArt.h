// PortholeTrayArt -- how a forwarded tray icon should sit in the Mac menu bar. Mavericks shows a
// plain image in color; only a template image becomes a silhouette, so only art that was already
// monochrome is shown as a template.
#import <Foundation/Foundation.h>

BOOL PortholeTrayArtIsMonochrome(const uint8_t *px, int w, int h, size_t stride, int bpp);
NSSize PortholeTrayArtSize(NSSize pixels, CGFloat scale, CGFloat maxHeight);

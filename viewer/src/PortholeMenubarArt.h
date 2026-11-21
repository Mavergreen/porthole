// PortholeMenubarArt -- an app's menu-bar art: pairs of the picture its tray shows and the Mac picture
// the menu bar shows instead (MENUBAR_ART, which the launcher copies out of the app's container into
// <cache>/<slug>.menubar as <n>.app.png and <n>.mac.png or <n>.mac-template.png).
#import <Cocoa/Cocoa.h>

@interface PortholeMenubarArt : NSObject
// The pairs in DIR, or nil when it has none.
+ (instancetype)artInDirectory:(NSString *)dir;
// The Mac picture for the tray art the app sent: its pair's whose app picture looks most like it, or
// nil when none is close.
- (NSImage *)macPictureFor:(NSImage *)trayArt;
@end

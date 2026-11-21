#import "PortholeWindowTitles.h"

NSString *PortholeTitleFromMetadata(id metadata) {
    if (![metadata isKindOfClass:[NSDictionary class]]) return nil;
    id t = metadata[@"title"];
    if ([t isKindOfClass:[NSData class]])
        t = [[[NSString alloc] initWithData:t encoding:NSUTF8StringEncoding] autorelease];
    return [t isKindOfClass:[NSString class]] ? t : nil;
}

int PortholeOnePasswordLockState(NSArray *titles) {
    if (titles.count == 0) return -1;
    for (NSString *t in titles) if ([t hasPrefix:@"Lock Screen"]) return 1;
    return 0;
}

NSString *PortholeTrackedTitle(BOOL overrideRedirect, NSString *title) {
    return overrideRedirect ? nil : (title ?: @"");
}
BOOL PortholeLockItemEnabled(NSArray *titles) { return PortholeOnePasswordLockState(titles) != 1; }
BOOL PortholeWantsDockIcon(BOOL visibleAppWindow, NSUInteger trayCount) { return visibleAppWindow || trayCount == 0; }
// Closing a window on the Mac closes it in the app, as a Linux window manager would; only the main
// window closes to the menu bar, and popups are the app's to dismiss.
BOOL PortholeCloseTellsApp(BOOL isMainWindow, BOOL overrideRedirect) { return !isMainWindow && !overrideRedirect; }
// The launch window closing as setup finishes isn't the app going away: only quit on the last window
// once the app itself has shown a window or tray, and nothing (a tray) keeps it resident.
BOOL PortholeQuitsWhenWindowsClose(BOOL appHasShownSomething, NSUInteger trayCount) {
    return appHasShownSomething && trayCount == 0;
}

PortholeNewWindowAction PortholeNewWindowFor(BOOL overrideRedirect, BOOL appShownSomething, BOOL appActive,
                                             BOOL launchedAtLogin, BOOL userAsked) {
    if (userAsked || appActive) return PortholeWindowActivate;
    if (!appShownSomething) return launchedAtLogin ? PortholeWindowStay : PortholeWindowActivate;
    return overrideRedirect ? PortholeWindowStay : PortholeWindowActivate;
}

BOOL PortholeAppResize(NSString *type, NSArray *p, long *wid, int *w, int *h) {
    NSUInteger at;
    if ([type isEqualToString:@"window-move-resize"] || [type isEqualToString:@"configure-override-redirect"]) at = 4;
    else if ([type isEqualToString:@"window-resized"]) at = 2;
    else return NO;
    if ([p count] < at + 2) return NO;
    int nw = [p[at] intValue], nh = [p[at + 1] intValue];
    if (nw <= 0 || nh <= 0) return NO;
    *wid = [p[1] longValue]; *w = nw; *h = nh;
    return YES;
}

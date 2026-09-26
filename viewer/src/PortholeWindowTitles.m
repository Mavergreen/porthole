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
BOOL PortholeLockItemOffersUnlock(NSArray *titles) { return PortholeOnePasswordLockState(titles) == 1; }
BOOL PortholeWantsDockIcon(BOOL visibleAppWindow, NSUInteger trayCount) { return visibleAppWindow || trayCount == 0; }
// The launch window closing as setup finishes isn't the app going away: only quit on the last window
// once the app itself has shown a window or tray, and nothing (a tray) keeps it resident.
BOOL PortholeQuitsWhenWindowsClose(BOOL appHasShownSomething, NSUInteger trayCount) {
    return appHasShownSomething && trayCount == 0;
}

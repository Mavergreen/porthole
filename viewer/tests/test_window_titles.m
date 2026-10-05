#import <Foundation/Foundation.h>
#import "PortholeWindowTitles.h"
#include <assert.h>

int main(void) {
    @autoreleasepool {
        assert([PortholeTitleFromMetadata(@{@"title": @"Lock Screen — 1Password"}) isEqualToString:@"Lock Screen — 1Password"]);
        NSData *utf8 = [@"All Items — 1Password" dataUsingEncoding:NSUTF8StringEncoding];
        assert([PortholeTitleFromMetadata(@{@"title": utf8}) isEqualToString:@"All Items — 1Password"]);
        assert(PortholeTitleFromMetadata(@{@"size-constraints": @{}}) == nil);
        assert(PortholeTitleFromMetadata(@[@"not a dict"]) == nil);

        assert(PortholeOnePasswordLockState(@[@"Lock Screen — 1Password"]) == 1);
        assert(PortholeOnePasswordLockState(@[@"1Password", @"Lock Screen — 1Password"]) == 1);
        assert(PortholeOnePasswordLockState(@[@"All Items — 1Password"]) == 0);
        assert(PortholeOnePasswordLockState(@[]) == -1);
        assert([PortholeTrackedTitle(NO, nil) isEqualToString:@""]);            // an untitled window is still tracked
        assert([PortholeTrackedTitle(NO, @"Settings") isEqualToString:@"Settings"]);
        assert(PortholeTrackedTitle(YES, @"popup") == nil);                        // popups never are
        // Lock always reads Lock, as on a modern Mac; it grays out only while the app is locked.
        assert(!PortholeLockItemEnabled(@[@"Lock Screen — 1Password"]));
        assert(PortholeLockItemEnabled(@[@"All Items — 1Password"]));
        assert(PortholeLockItemEnabled(@[]));                                      // unknown -> offered
        assert(PortholeLockItemEnabled(@[@""]));
        assert(PortholeWantsDockIcon(YES, 1));
        assert(!PortholeWantsDockIcon(NO, 1));                                     // tray only: menu bar
        assert(PortholeWantsDockIcon(NO, 0));                                      // nothing left: the Dock
        assert(!PortholeQuitsWhenWindowsClose(NO, 0));   // still starting: the launch window closing isn't the end
        assert(PortholeQuitsWhenWindowsClose(YES, 0));   // the app's windows are gone and nothing else holds it
        assert(!PortholeQuitsWhenWindowsClose(YES, 1));  // a menu-bar extra keeps it resident
        // Closing a window on the Mac closes it in the app, as a Linux window manager would -- except
        // the main window, which closes to the menu bar, and popups, which the app dismisses itself.
        // Signal's About, once closed only on the Mac, stayed open in Signal and never came back.
        assert(PortholeCloseTellsApp(NO, NO));     // a dialog: About, Settings, an approval prompt
        assert(!PortholeCloseTellsApp(YES, NO));   // the main window: close to the menu bar
        assert(!PortholeCloseTellsApp(NO, YES));   // a popup
        printf("test_window_titles: OK\n");
    }
    return 0;
}

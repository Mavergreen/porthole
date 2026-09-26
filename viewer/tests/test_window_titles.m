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
        assert(PortholeLockItemOffersUnlock(@[@"Lock Screen — 1Password"]));
        assert(!PortholeLockItemOffersUnlock(@[@"All Items — 1Password"]));
        assert(!PortholeLockItemOffersUnlock(@[]));                                // unknown -> Lock
        assert(!PortholeLockItemOffersUnlock(@[@""]));
        assert(PortholeWantsDockIcon(YES, 1));
        assert(!PortholeWantsDockIcon(NO, 1));                                     // tray only: menu bar
        assert(PortholeWantsDockIcon(NO, 0));                                      // nothing left: the Dock
        printf("test_window_titles: OK\n");
    }
    return 0;
}

// PortholeWindowTitles -- what a remote window's title says. 1Password names its locked window
// "Lock Screen — 1Password"; that title is how the viewer knows the app is locked.
#import <Foundation/Foundation.h>
NSString *PortholeTitleFromMetadata(id metadata);
int PortholeOnePasswordLockState(NSArray *titles);   // 1 locked, 0 unlocked, -1 unknown
NSString *PortholeTrackedTitle(BOOL overrideRedirect, NSString *title);   // nil: not a window we track
BOOL PortholeLockItemOffersUnlock(NSArray *titles);                       // the tray's Lock item reads Unlock
BOOL PortholeWantsDockIcon(BOOL visibleAppWindow, NSUInteger trayCount);  // no tray to click -> keep the Dock

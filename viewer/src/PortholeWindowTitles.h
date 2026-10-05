// PortholeWindowTitles -- what a remote window's title says. 1Password names its locked window
// "Lock Screen — 1Password"; that title is how the viewer knows the app is locked.
#import <Foundation/Foundation.h>
NSString *PortholeTitleFromMetadata(id metadata);
int PortholeOnePasswordLockState(NSArray *titles);   // 1 locked, 0 unlocked, -1 unknown
NSString *PortholeTrackedTitle(BOOL overrideRedirect, NSString *title);   // nil: not a window we track
BOOL PortholeLockItemEnabled(NSArray *titles);                            // Lock grays out while locked
BOOL PortholeWantsDockIcon(BOOL visibleAppWindow, NSUInteger trayCount);  // no tray to click -> keep the Dock
BOOL PortholeCloseTellsApp(BOOL isMainWindow, BOOL overrideRedirect);       // a Mac close closes it in the app
BOOL PortholeQuitsWhenWindowsClose(BOOL appHasShownSomething, NSUInteger trayCount);  // not while still starting

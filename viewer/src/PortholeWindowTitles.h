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
// What the viewer does when the app maps a window. A Mac app comes forward when the user launches
// it and stays put when launched at login. A new window of its own later (a prompt) takes focus even
// from the background: left behind another app's focused window, a password typed by reflex would
// land there. Popups of an app in the background stay put.
typedef enum { PortholeWindowActivate, PortholeWindowStay } PortholeNewWindowAction;
PortholeNewWindowAction PortholeNewWindowFor(BOOL overrideRedirect, BOOL appShownSomething, BOOL appActive,
                                             BOOL launchedAtLogin, BOOL userAsked);

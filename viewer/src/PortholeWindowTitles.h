// PortholeWindowTitles -- what a remote window's title says. 1Password names its locked window
// "Lock Screen — 1Password"; that title is how the viewer knows the app is locked.
#import <Foundation/Foundation.h>
NSString *PortholeTitleFromMetadata(id metadata);
int PortholeOnePasswordLockState(NSArray *titles);   // 1 locked, 0 unlocked, -1 unknown

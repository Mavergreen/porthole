// PortholeUpdateItem -- what the app menu's update item offers. An install builds a newer image while
// the app may be open; the app learns of it from the image Porthole recorded, and offers to restart.
#import <Foundation/Foundation.h>
typedef NS_ENUM(NSInteger, PortholeUpdateItemState) {
    PortholeUpdateItemHidden,    // no updater to ask, and nothing newer is ready
    PortholeUpdateItemCheck,     // "Check for Updates…": ask this preset's updater
    PortholeUpdateItemRestart,   // "Restart to Update": a newer image than the running one is ready
};
PortholeUpdateItemState PortholeUpdateItemFor(NSString *runningImage, NSString *recordedImage, BOOL updaterInstalled);
NSString *PortholeRecordedImage(NSString *cacheDir, NSString *slug);   // <cacheDir>/<slug>.image, or nil
// The detached command that reopens the app at `bundle` once process `pid` (this app, quitting) has gone
// and its recovery watcher has finished (at most 30 s): on-demand apps' watchers stop the container after
// a clean quit, and must not stop the relaunched one. argv[0] is the program to run.
NSArray *PortholeRestartCommand(pid_t pid, NSString *bundle);
// Start `cmd` (argv[0] is the program) without waiting for it, holding none of our input or output, so
// it outlives us and nothing reading our output waits for it.
void PortholeRunDetached(NSArray *cmd);

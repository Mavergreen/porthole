// PortholeLaunchArgs -- what the viewer was started to do: run a launcher (--launch), prepare an app
// ahead of its launch (--prepare: an install), or connect a socket.
#import <Foundation/Foundation.h>
@interface PortholeLaunchArgs : NSObject
@property(copy) NSString *launcherPath;
@property(copy) NSArray *launcherArgs;
@property(copy) NSString *socketPath;
@property(assign) BOOL prepare;
@end
PortholeLaunchArgs *PortholeParseLaunchArgs(NSArray *argv);

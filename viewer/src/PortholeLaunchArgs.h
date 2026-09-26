// PortholeLaunchArgs -- what the viewer was started to do: run a launcher (--launch) or connect a socket.
#import <Foundation/Foundation.h>
@interface PortholeLaunchArgs : NSObject
@property(copy) NSString *launcherPath;
@property(copy) NSArray *launcherArgs;
@property(copy) NSString *socketPath;
@end
PortholeLaunchArgs *PortholeParseLaunchArgs(NSArray *argv);

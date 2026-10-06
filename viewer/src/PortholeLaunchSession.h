// PortholeLaunchSession -- runs an app's launcher and speaks its launch protocol (JSON lines).
#import <Foundation/Foundation.h>

@class PortholeLaunchSession;
@protocol PortholeLaunchSessionDelegate <NSObject>
// routine: a step every launch takes ("routine":true), which needn't show the launch window.
- (void)launchSession:(PortholeLaunchSession *)s step:(NSString *)text routine:(BOOL)routine;
- (void)launchSession:(PortholeLaunchSession *)s progress:(double)fraction;
- (void)launchSession:(PortholeLaunchSession *)s ask:(NSString *)askId text:(NSString *)text choices:(NSArray *)choices;
- (void)launchSession:(PortholeLaunchSession *)s failed:(NSString *)text detail:(NSString *)detail;
// image: the image the app's container runs ("" when the launcher didn't say).
- (void)launchSession:(PortholeLaunchSession *)s readyWithSocket:(NSString *)socket icon:(NSString *)icon image:(NSString *)image;
// --prepare finished: the app is built, and nothing was started.
- (void)launchSessionPrepared:(PortholeLaunchSession *)s;
// Nothing to show for now: another window (an install's) is already showing this app's progress.
- (void)launchSessionQuiet:(PortholeLaunchSession *)s;
@end

@interface PortholeLaunchSession : NSObject
@property(assign, nonatomic) id<PortholeLaunchSessionDelegate> delegate;   // weak; called on the main thread
- (instancetype)initWithLauncher:(NSString *)path arguments:(NSArray *)args; // spawns it with PORTHOLE_PROTOCOL=1
- (instancetype)initWithReadFD:(int)readFD writeFD:(int)writeFD;            // tests: an already-running peer
- (void)start;
- (void)answer:(NSString *)askId choice:(NSString *)choice;
+ (NSDictionary *)messageFromLine:(NSString *)line;   // nil unless a JSON object with a string "t"
@end

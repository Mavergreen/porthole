// PortholeLaunchSession -- runs an app's launcher and speaks its launch protocol (JSON lines).
#import <Foundation/Foundation.h>

@class PortholeLaunchSession;
@protocol PortholeLaunchSessionDelegate <NSObject>
- (void)launchSession:(PortholeLaunchSession *)s step:(NSString *)text;
- (void)launchSession:(PortholeLaunchSession *)s progress:(double)fraction;
- (void)launchSession:(PortholeLaunchSession *)s ask:(NSString *)askId text:(NSString *)text choices:(NSArray *)choices;
- (void)launchSession:(PortholeLaunchSession *)s failed:(NSString *)text detail:(NSString *)detail;
- (void)launchSession:(PortholeLaunchSession *)s readyWithSocket:(NSString *)socket icon:(NSString *)icon;
@end

@interface PortholeLaunchSession : NSObject
@property(assign, nonatomic) id<PortholeLaunchSessionDelegate> delegate;   // weak; called on the main thread
- (instancetype)initWithLauncher:(NSString *)path arguments:(NSArray *)args; // spawns it with PORTHOLE_PROTOCOL=1
- (instancetype)initWithReadFD:(int)readFD writeFD:(int)writeFD;            // tests: an already-running peer
- (void)start;
- (void)answer:(NSString *)askId choice:(NSString *)choice;
+ (NSDictionary *)messageFromLine:(NSString *)line;   // nil unless a JSON object with a string "t"
@end

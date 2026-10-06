// PortholeLaunchFeedback -- decides what a launch shows while its launcher works: nothing but Dock
// progress for the steps every launch takes, the launch window for real work (after a moment), a
// question or an error (at once), or a launch that is taking too long. The app does the showing.
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, PortholeFeedbackTimer) {
    PortholeFeedbackShowDelay,    // a work step's window, if the work takes a moment
    PortholeFeedbackFallback,     // a launch that hasn't finished: show where it's got to
    PortholeFeedbackWindowless,   // after ready, stop Dock progress if no app window came
};

@protocol PortholeLaunchFeedbackSink <NSObject>
- (void)feedbackShowWindow;
- (void)feedbackCloseWindow;
- (void)feedbackDockProgress:(BOOL)on;
- (void)feedbackSchedule:(PortholeFeedbackTimer)timer after:(NSTimeInterval)seconds;
- (void)feedbackCancel:(PortholeFeedbackTimer)timer;
@end

@interface PortholeLaunchFeedback : NSObject
- (instancetype)initWithSink:(id<PortholeLaunchFeedbackSink>)sink preparing:(BOOL)preparing;  // sink not retained
- (void)start;
- (void)routineStep;
- (void)workStep;
- (void)ask;
- (void)error;
- (void)quiet;          // an install's window is showing this app's build
- (void)ready;
- (void)firstWindow;    // the app's own first window appeared
- (void)timerFired:(PortholeFeedbackTimer)timer;
@property(readonly, nonatomic) BOOL windowShowing;
@end

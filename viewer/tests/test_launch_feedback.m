#import <Foundation/Foundation.h>
#import "PortholeLaunchFeedback.h"
#include <assert.h>
#include <stdio.h>

// Records what the policy asks of the app: "show", "close", "dock:on", "dock:off",
// "sched:<timer>:<seconds>", "cancel:<timer>".
@interface Sink : NSObject <PortholeLaunchFeedbackSink>
@property(retain) NSMutableArray *log;
@end
@implementation Sink
- (id)init { if ((self = [super init])) _log = [[NSMutableArray alloc] init]; return self; }
- (void)dealloc { [_log release]; [super dealloc]; }
static NSString *timerName(PortholeFeedbackTimer t) {
    return t == PortholeFeedbackShowDelay ? @"ShowDelay" : t == PortholeFeedbackFallback ? @"Fallback" : @"Windowless";
}
- (void)feedbackShowWindow { [_log addObject:@"show"]; }
- (void)feedbackCloseWindow { [_log addObject:@"close"]; }
- (void)feedbackDockProgress:(BOOL)on { [_log addObject:on ? @"dock:on" : @"dock:off"]; }
- (void)feedbackSchedule:(PortholeFeedbackTimer)t after:(NSTimeInterval)s {
    [_log addObject:[NSString stringWithFormat:@"sched:%@:%g", timerName(t), s]]; }
- (void)feedbackCancel:(PortholeFeedbackTimer)t { [_log addObject:[@"cancel:" stringByAppendingString:timerName(t)]]; }
- (BOOL)has:(NSString *)e { return [_log containsObject:e]; }
- (NSUInteger)count:(NSString *)e {
    NSUInteger n = 0; for (NSString *x in _log) if ([x isEqualToString:e]) n++; return n; }
@end

static Sink *sink;
static PortholeLaunchFeedback *fresh(BOOL preparing) {
    sink = [[[Sink alloc] init] autorelease];
    return [[[PortholeLaunchFeedback alloc] initWithSink:sink preparing:preparing] autorelease];
}

static void routine_open_shows_nothing(void) {
    PortholeLaunchFeedback *f = fresh(NO);
    [f start]; [f routineStep]; [f routineStep]; [f ready]; [f firstWindow];
    assert(![sink has:@"show"]);
    assert([sink has:@"sched:Fallback:15"]);
    assert([sink count:@"dock:on"] == 1 && [sink count:@"dock:off"] == 1);
    assert([sink.log indexOfObject:@"dock:on"] < [sink.log indexOfObject:@"dock:off"]);
}

static void work_step_shows_after_delay(void) {
    PortholeLaunchFeedback *f = fresh(NO);
    [f start]; [f routineStep]; [f workStep];
    assert([sink has:@"sched:ShowDelay:0.5"] && [sink has:@"dock:off"] && [sink has:@"cancel:Fallback"]);
    assert(![sink has:@"show"] && !f.windowShowing);
    [f timerFired:PortholeFeedbackShowDelay];
    assert([sink has:@"show"] && f.windowShowing);
}

static void routine_after_work_keeps_window(void) {
    PortholeLaunchFeedback *f = fresh(NO);
    [f start]; [f routineStep]; [f workStep]; [f timerFired:PortholeFeedbackShowDelay]; [f routineStep];
    assert(![sink has:@"close"] && f.windowShowing);
    assert([sink count:@"dock:on"] == 1);
}

static void ask_and_error_show_at_once(void) {
    PortholeLaunchFeedback *f = fresh(NO);
    [f start]; [f ask];
    assert([sink has:@"show"] && f.windowShowing);
    f = fresh(NO);
    [f start]; [f error];
    assert([sink has:@"show"] && f.windowShowing);
}

static void fallback_shows_stuck_launch(void) {
    PortholeLaunchFeedback *f = fresh(NO);
    [f start]; [f routineStep]; [f timerFired:PortholeFeedbackFallback];
    assert([sink has:@"show"] && [sink has:@"dock:off"]);
}

static void fallback_armed_before_first_message(void) {
    PortholeLaunchFeedback *f = fresh(NO);
    [f start]; [f timerFired:PortholeFeedbackFallback];
    assert([sink has:@"show"]);
}

static void quiet_cancels_and_rearms(void) {
    PortholeLaunchFeedback *f = fresh(NO);
    [f start]; [f quiet];
    assert([sink has:@"cancel:ShowDelay"] && [sink has:@"cancel:Fallback"]);
    assert([sink has:@"close"] && [sink has:@"dock:off"] && !f.windowShowing);
    [sink.log removeAllObjects];
    [f routineStep];
    assert([sink has:@"dock:on"] && [sink has:@"sched:Fallback:15"]);
}

static void windowless_start_stops_progress(void) {
    PortholeLaunchFeedback *f = fresh(NO);
    [f start]; [f routineStep]; [f ready];
    assert([sink has:@"sched:Windowless:10"] && ![sink has:@"dock:off"]);
    [f timerFired:PortholeFeedbackWindowless];
    assert([sink has:@"dock:off"]);
}

// A late timer can't put the launch window over an app that's already up.
static void ready_ends_the_launch(void) {
    PortholeLaunchFeedback *f = fresh(NO);
    [f start]; [f routineStep]; [f workStep]; [f ready];
    [f timerFired:PortholeFeedbackFallback];
    [f timerFired:PortholeFeedbackShowDelay];
    assert(![sink has:@"show"] && !f.windowShowing);
}

static void preparing_shows_at_once_never_dock(void) {
    PortholeLaunchFeedback *f = fresh(YES);
    [f start];
    assert([sink.log[0] isEqualToString:@"show"]);
    [f workStep]; [f ready];
    assert(![sink has:@"dock:on"]);
}

int main(void) {
    @autoreleasepool {
        routine_open_shows_nothing();
        work_step_shows_after_delay();
        routine_after_work_keeps_window();
        ask_and_error_show_at_once();
        fallback_shows_stuck_launch();
        fallback_armed_before_first_message();
        quiet_cancels_and_rearms();
        windowless_start_stops_progress();
        ready_ends_the_launch();
        preparing_shows_at_once_never_dock();
        printf("test_launch_feedback: OK\n");
    }
    return 0;
}

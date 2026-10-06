#import "PortholeLaunchFeedback.h"

static const NSTimeInterval kShowDelay = 0.5;
static const NSTimeInterval kFallback = 15;
static const NSTimeInterval kWindowless = 10;

@implementation PortholeLaunchFeedback {
    id<PortholeLaunchFeedbackSink> _sink;
    BOOL _preparing;
    BOOL _showPending;    // ShowDelay scheduled
    BOOL _dockOn;
    BOOL _quiet;          // waiting on an install's build, whose own window shows it
    BOOL _sawWindow;
    BOOL _ready;          // the launcher is done: nothing may put its window up any more
}

- (instancetype)initWithSink:(id<PortholeLaunchFeedbackSink>)sink preparing:(BOOL)preparing {
    if ((self = [super init])) { _sink = sink; _preparing = preparing; }
    return self;
}

- (void)dock:(BOOL)on {
    if (on == _dockOn) return;
    _dockOn = on;
    [_sink feedbackDockProgress:on];
}

- (void)show {
    _windowShowing = YES;
    [_sink feedbackShowWindow];
    [_sink feedbackCancel:PortholeFeedbackShowDelay];
    [_sink feedbackCancel:PortholeFeedbackFallback];
    _showPending = NO;
    [self dock:NO];
}

- (void)watch {   // a routine launch: Dock progress, and the window only if it goes on too long
    [self dock:YES];
    [_sink feedbackSchedule:PortholeFeedbackFallback after:kFallback];
}

- (void)start {
    if (_preparing) [self show];
    else [self watch];
}

- (void)routineStep {
    if (!_quiet) return;
    _quiet = NO;
    [self watch];
}

- (void)workStep {
    _quiet = NO;
    [self dock:NO];
    [_sink feedbackCancel:PortholeFeedbackFallback];
    if (_windowShowing || _showPending) return;
    _showPending = YES;
    [_sink feedbackSchedule:PortholeFeedbackShowDelay after:kShowDelay];
}

- (void)ask { [self show]; }
- (void)error { [self show]; }

- (void)hide {
    [_sink feedbackCancel:PortholeFeedbackShowDelay];
    [_sink feedbackCancel:PortholeFeedbackFallback];
    _showPending = NO;
    _windowShowing = NO;
    [_sink feedbackCloseWindow];
}

- (void)quiet {
    [self hide];
    [self dock:NO];
    _quiet = YES;
}

- (void)ready {
    _ready = YES;
    [self hide];
    if (_dockOn) [_sink feedbackSchedule:PortholeFeedbackWindowless after:kWindowless];
}

- (void)firstWindow {
    if (_sawWindow) return;
    _sawWindow = YES;
    [_sink feedbackCancel:PortholeFeedbackWindowless];
    [self dock:NO];
}

- (void)timerFired:(PortholeFeedbackTimer)timer {
    switch (timer) {
        case PortholeFeedbackShowDelay:
            _showPending = NO;
            if (!_windowShowing && !_ready) [self show];
            break;
        case PortholeFeedbackFallback:
            if (!_windowShowing && !_ready) [self show];
            break;
        case PortholeFeedbackWindowless:
            [self dock:NO];
            break;
    }
}

@end

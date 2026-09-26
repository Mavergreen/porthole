#import "PortholeLaunchWindow.h"

static const CGFloat kWidth = 460, kHeight = 170, kDetailHeight = 150;

@implementation PortholeLaunchWindow {
    NSWindow *_window;
    NSTextField *_label;
    NSProgressIndicator *_bar;
    NSView *_buttons;
    NSScrollView *_details;
    NSTextView *_detailText;
    void (^_reply)(NSString *);
    void (^_quit)(void);
    BOOL _detailsShown;
}

- (instancetype)initWithTitle:(NSString *)title icon:(NSImage *)icon {
    if ((self = [super init])) {
        _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, kWidth, kHeight)
            styleMask:NSTitledWindowMask | NSClosableWindowMask backing:NSBackingStoreBuffered defer:NO];
        [_window setTitle:title ?: @""];
        [_window setReleasedWhenClosed:NO];
        [_window setDelegate:self];
        NSView *cv = [_window contentView];

        NSImageView *iv = [[[NSImageView alloc] initWithFrame:NSMakeRect(20, kHeight - 84, 64, 64)] autorelease];
        [iv setImage:icon];
        [iv setAutoresizingMask:NSViewMinYMargin];
        [cv addSubview:iv];

        _label = [[NSTextField alloc] initWithFrame:NSMakeRect(100, kHeight - 70, kWidth - 120, 50)];
        [_label setEditable:NO]; [_label setSelectable:NO]; [_label setBezeled:NO]; [_label setDrawsBackground:NO];
        [[_label cell] setWraps:YES];
        [_label setAutoresizingMask:NSViewMinYMargin];
        [cv addSubview:_label];

        _bar = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(100, kHeight - 100, kWidth - 120, 20)];
        [_bar setStyle:NSProgressIndicatorBarStyle];
        [_bar setIndeterminate:YES];
        [_bar setAutoresizingMask:NSViewMinYMargin];
        [cv addSubview:_bar];
        [_bar startAnimation:nil];

        _buttons = [[NSView alloc] initWithFrame:NSMakeRect(20, 12, kWidth - 40, 32)];
        [_buttons setAutoresizingMask:NSViewMaxYMargin];
        [cv addSubview:_buttons];

        _details = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 52, kWidth - 40, kDetailHeight - 10)];
        [_details setHasVerticalScroller:YES];
        [_details setBorderType:NSBezelBorder];
        [_details setAutoresizingMask:NSViewMaxYMargin];
        _detailText = [[NSTextView alloc] initWithFrame:[[_details contentView] bounds]];
        [_detailText setEditable:NO];
        [_detailText setFont:[NSFont userFixedPitchFontOfSize:10]];
        [_details setDocumentView:_detailText];
        [_details setHidden:YES];
        [cv addSubview:_details];
        [_window center];
    }
    return self;
}

- (void)dealloc {
    [_window setDelegate:nil];
    [_window orderOut:nil];
    [_window release]; [_label release]; [_bar release]; [_buttons release];
    [_details release]; [_detailText release];
    [_reply release]; [_quit release];
    [super dealloc];
}

- (void)show { [_window makeKeyAndOrderFront:nil]; [_window orderFrontRegardless]; }
- (void)close { [_window orderOut:nil]; }

- (void)setStep:(NSString *)text { [_label setStringValue:text ?: @""]; }

- (void)setProgress:(double)fraction {
    if (fraction < 0) { [_bar setIndeterminate:YES]; [_bar startAnimation:nil]; return; }
    [_bar setIndeterminate:NO];
    [_bar setMinValue:0]; [_bar setMaxValue:1];
    [_bar setDoubleValue:fraction > 1 ? 1 : fraction];
}

- (void)clearButtons { for (NSView *v in [[[_buttons subviews] copy] autorelease]) [v removeFromSuperview]; }

// Right-aligned buttons; the last is the default (Return).
- (void)addButtons:(NSArray *)titles action:(SEL)action {
    [self clearButtons];
    CGFloat x = NSWidth([_buttons bounds]);
    for (NSInteger i = (NSInteger)titles.count - 1; i >= 0; i--) {
        NSButton *b = [[[NSButton alloc] initWithFrame:NSZeroRect] autorelease];
        [b setBezelStyle:NSRoundedBezelStyle];
        [b setTitle:titles[(NSUInteger)i]];
        [b sizeToFit];
        NSRect f = [b frame]; f.size.width = MAX(f.size.width + 12, 88); x -= f.size.width; f.origin = NSMakePoint(x, 0);
        [b setFrame:f];
        [b setTarget:self]; [b setAction:action];
        if (i == (NSInteger)titles.count - 1) [b setKeyEquivalent:@"\r"];
        [_buttons addSubview:b];
        x -= 8;
    }
}

- (void)askText:(NSString *)text choices:(NSArray *)choices reply:(void (^)(NSString *))reply {
    [_reply release]; _reply = [reply copy];
    [_bar setHidden:YES];
    [self setStep:text];
    [self addButtons:choices action:@selector(answer:)];
    [self show];
}

- (void)answer:(NSButton *)sender {
    void (^r)(NSString *) = [[_reply retain] autorelease];
    [_reply release]; _reply = nil;
    [self clearButtons];
    [_bar setHidden:NO];
    if (r) r([sender title]);
}

- (void)showError:(NSString *)text detail:(NSString *)detail quit:(void (^)(void))quit {
    [_quit release]; _quit = [quit copy];
    [_reply release]; _reply = nil;
    [_bar setHidden:YES];
    [self setStep:text];
    [_detailText setString:detail ?: @""];
    [self addButtons:(detail.length ? @[@"Show Details", @"Quit"] : @[@"Quit"]) action:@selector(errorButton:)];
    [self show];
}

- (void)errorButton:(NSButton *)sender {
    if ([[sender title] isEqualToString:@"Quit"]) { if (_quit) _quit(); return; }
    _detailsShown = !_detailsShown;
    [sender setTitle:_detailsShown ? @"Hide Details" : @"Show Details"];
    NSRect f = [_window frame];
    CGFloat dh = _detailsShown ? kDetailHeight : -kDetailHeight;
    f.origin.y -= dh; f.size.height += dh;
    if (!_detailsShown) [_details setHidden:YES];
    [_window setFrame:f display:YES animate:YES];
    if (_detailsShown) [_details setHidden:NO];
}

// Closing answers a pending question with "Ask later", quits after an error, and is refused while
// setup is still running (there's nothing to go back to yet).
- (BOOL)windowShouldClose:(id)sender {
    (void)sender;
    if (_reply) {
        void (^r)(NSString *) = [[_reply retain] autorelease];
        [_reply release]; _reply = nil;
        [self clearButtons]; [_bar setHidden:NO];
        r(@"Ask later");
        return NO;
    }
    if (_quit) { _quit(); return NO; }
    return NO;
}
@end

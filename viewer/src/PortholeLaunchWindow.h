// PortholeLaunchWindow -- the small window an app shows while its launcher sets things up: the
// current step and a progress bar, a question with one button per answer, or an error with details.
#import <Cocoa/Cocoa.h>

@interface PortholeLaunchWindow : NSObject <NSWindowDelegate>
- (instancetype)initWithTitle:(NSString *)title icon:(NSImage *)icon;
- (void)setStep:(NSString *)text;
- (void)setProgress:(double)fraction;   // < 0: indeterminate
- (void)askText:(NSString *)text choices:(NSArray *)choices reply:(void (^)(NSString *choice))reply;
- (void)showError:(NSString *)text detail:(NSString *)detail quit:(void (^)(void))quit;
- (void)show;
- (void)close;
- (NSString *)labelText;   // what the window says now
@end

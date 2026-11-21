#import "PortholeURLQueue.h"
@implementation PortholeURLQueue {
    NSMutableArray *_pending;
    BOOL _up;
}
- (id)init { if ((self = [super init])) _pending = [[NSMutableArray alloc] init]; return self; }
- (void)dealloc { [_pending release]; [super dealloc]; }
- (NSArray *)add:(NSString *)url {
    if (_up) return @[url];
    [_pending addObject:url];
    return @[];
}
- (NSArray *)appIsUp {
    _up = YES;
    NSArray *now = [[_pending copy] autorelease];
    [_pending removeAllObjects];
    return now;
}
@end

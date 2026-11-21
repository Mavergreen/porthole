// PortholeURLQueue -- links to the app (its URL schemes) that arrive before it is up wait for it: a
// second instance started before the first holds its lock would become the app itself. Each method
// returns the links to deliver now, in the order they came.
#import <Foundation/Foundation.h>
@interface PortholeURLQueue : NSObject
- (NSArray *)add:(NSString *)url;
- (NSArray *)appIsUp;
@end

#import <Foundation/Foundation.h>
#import "PortholeURLQueue.h"
#include <assert.h>

// Links that arrive before the app is up wait for it (a second instance started before the first
// holds its lock would become the app itself), then go in the order they came; later ones go at once.
int main(void) {
    @autoreleasepool {
        PortholeURLQueue *q = [[[PortholeURLQueue alloc] init] autorelease];
        assert([[q add:@"sgnl://a"] count] == 0);
        assert([[q add:@"sgnl://b"] count] == 0);
        assert([[q appIsUp] isEqualToArray:(@[@"sgnl://a", @"sgnl://b"])]);
        assert([[q appIsUp] count] == 0);                       // delivered once
        assert([[q add:@"sgnl://c"] isEqualToArray:@[@"sgnl://c"]]);
        printf("test_url_queue: OK\n");
    }
    return 0;
}

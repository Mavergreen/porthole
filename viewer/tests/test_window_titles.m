#import <Foundation/Foundation.h>
#import "PortholeWindowTitles.h"
#include <assert.h>

int main(void) {
    @autoreleasepool {
        assert([PortholeTitleFromMetadata(@{@"title": @"Lock Screen — 1Password"}) isEqualToString:@"Lock Screen — 1Password"]);
        NSData *utf8 = [@"All Items — 1Password" dataUsingEncoding:NSUTF8StringEncoding];
        assert([PortholeTitleFromMetadata(@{@"title": utf8}) isEqualToString:@"All Items — 1Password"]);
        assert(PortholeTitleFromMetadata(@{@"size-constraints": @{}}) == nil);
        assert(PortholeTitleFromMetadata(@[@"not a dict"]) == nil);

        assert(PortholeOnePasswordLockState(@[@"Lock Screen — 1Password"]) == 1);
        assert(PortholeOnePasswordLockState(@[@"1Password", @"Lock Screen — 1Password"]) == 1);
        assert(PortholeOnePasswordLockState(@[@"All Items — 1Password"]) == 0);
        assert(PortholeOnePasswordLockState(@[]) == -1);
        printf("test_window_titles: OK\n");
    }
    return 0;
}

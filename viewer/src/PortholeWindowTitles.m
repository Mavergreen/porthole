#import "PortholeWindowTitles.h"

NSString *PortholeTitleFromMetadata(id metadata) {
    if (![metadata isKindOfClass:[NSDictionary class]]) return nil;
    id t = metadata[@"title"];
    if ([t isKindOfClass:[NSData class]])
        t = [[[NSString alloc] initWithData:t encoding:NSUTF8StringEncoding] autorelease];
    return [t isKindOfClass:[NSString class]] ? t : nil;
}

int PortholeOnePasswordLockState(NSArray *titles) {
    if (titles.count == 0) return -1;
    for (NSString *t in titles) if ([t hasPrefix:@"Lock Screen"]) return 1;
    return 0;
}

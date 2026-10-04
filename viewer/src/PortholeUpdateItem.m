#import "PortholeUpdateItem.h"

PortholeUpdateItemState PortholeUpdateItemFor(NSString *runningImage, NSString *recordedImage, BOOL updaterInstalled) {
    if (runningImage.length && recordedImage.length && ![runningImage isEqualToString:recordedImage])
        return PortholeUpdateItemRestart;
    return updaterInstalled ? PortholeUpdateItemCheck : PortholeUpdateItemHidden;
}

NSString *PortholeRecordedImage(NSString *cacheDir, NSString *slug) {
    NSString *path = [cacheDir stringByAppendingPathComponent:[slug stringByAppendingString:@".image"]];
    NSString *s = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
    NSString *line = [[[s componentsSeparatedByString:@"\n"] firstObject]
                      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    return line.length ? line : nil;
}

NSArray *PortholeRestartCommand(pid_t pid, NSString *bundle) {
    NSString *watcher = [bundle stringByAppendingPathComponent:@"Contents/Resources/bin/porthole-recover-watch"];
    NSString *script =
        @"while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; "
        @"i=0; while [ \"$i\" -lt 150 ] && pgrep -f \"$2\" >/dev/null 2>&1; do sleep 0.2; i=$((i + 1)); done; "
        @"exec open \"$3\"";
    return @[@"/bin/sh", @"-c", script, @"sh", [NSString stringWithFormat:@"%d", (int)pid], watcher, bundle];
}

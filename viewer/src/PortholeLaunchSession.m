#import "PortholeLaunchSession.h"
#include <unistd.h>

@implementation PortholeLaunchSession {
    int _readFD, _writeFD;
    NSTask *_task;
    NSFileHandle *_stderr;
    NSMutableData *_errTail;
    BOOL _finished;
}
@synthesize delegate = _delegate;

+ (NSDictionary *)messageFromLine:(NSString *)line {
    NSData *d = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (!d.length || ((const char *)d.bytes)[0] != '{') return nil;
    id o = [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL];
    if (![o isKindOfClass:[NSDictionary class]] || ![o[@"t"] isKindOfClass:[NSString class]]) return nil;
    return o;
}

- (instancetype)initWithReadFD:(int)readFD writeFD:(int)writeFD {
    if ((self = [super init])) { _readFD = readFD; _writeFD = writeFD; _errTail = [[NSMutableData alloc] init]; }
    return self;
}

- (instancetype)initWithLauncher:(NSString *)path arguments:(NSArray *)args {
    NSPipe *out = [NSPipe pipe], *in = [NSPipe pipe], *err = [NSPipe pipe];
    if ((self = [self initWithReadFD:[[out fileHandleForReading] fileDescriptor]
                             writeFD:[[in fileHandleForWriting] fileDescriptor]])) {
        _task = [[NSTask alloc] init];
        [_task setLaunchPath:path];
        [_task setArguments:args ?: @[]];
        NSMutableDictionary *env = [[[[NSProcessInfo processInfo] environment] mutableCopy] autorelease];
        env[@"PORTHOLE_PROTOCOL"] = @"1";
        [_task setEnvironment:env];
        [_task setStandardOutput:out]; [_task setStandardInput:in]; [_task setStandardError:err];
        _stderr = [[err fileHandleForReading] retain];
        [out retain]; [in retain];   // keep the fds open for the session's life
    }
    return self;
}

- (void)dealloc { [_task release]; [_stderr release]; [_errTail release]; [super dealloc]; }

- (void)deliver:(NSDictionary *)m {
    NSString *t = m[@"t"];
    id<PortholeLaunchSessionDelegate> d = _delegate;
    if ([t isEqualToString:@"step"]) [d launchSession:self step:m[@"text"] ?: @""];
    else if ([t isEqualToString:@"progress"]) [d launchSession:self progress:[m[@"fraction"] doubleValue]];
    else if ([t isEqualToString:@"ask"]) [d launchSession:self ask:m[@"id"] text:m[@"text"] ?: @"" choices:m[@"choices"] ?: @[]];
    else if ([t isEqualToString:@"error"]) { _finished = YES; [d launchSession:self failed:m[@"text"] ?: @"" detail:m[@"detail"] ?: @""]; }
    else if ([t isEqualToString:@"ready"]) { _finished = YES; [d launchSession:self readyWithSocket:m[@"socket"] icon:m[@"icon"] ?: @""]; }
}

- (void)start {
    if (_stderr) {
        [_stderr setReadabilityHandler:^(NSFileHandle *h) {
            NSData *chunk = [h availableData];
            @synchronized (self) {
                [_errTail appendData:chunk];
                if (_errTail.length > 8192) [_errTail replaceBytesInRange:NSMakeRange(0, _errTail.length - 8192) withBytes:NULL length:0];
            }
        }];
    }
    if (_task) [_task launch];
    int fd = _readFD;
    [self retain];   // released when the reader finishes
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableData *buf = [NSMutableData data]; char chunk[4096]; ssize_t n;
        while ((n = read(fd, chunk, sizeof chunk)) > 0) {
            [buf appendBytes:chunk length:(NSUInteger)n];
            for (;;) {
                const char *b = buf.bytes; NSUInteger len = buf.length, i = 0;
                while (i < len && b[i] != '\n') i++;
                if (i == len) break;
                NSString *line = [[[NSString alloc] initWithBytes:b length:i encoding:NSUTF8StringEncoding] autorelease];
                [buf replaceBytesInRange:NSMakeRange(0, i + 1) withBytes:NULL length:0];
                NSDictionary *m = line ? [PortholeLaunchSession messageFromLine:line] : nil;
                if (m) dispatch_async(dispatch_get_main_queue(), ^{ [self deliver:m]; });
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!_finished) {
                _finished = YES;
                NSString *tail;
                @synchronized (self) {
                    tail = [[[NSString alloc] initWithData:_errTail encoding:NSUTF8StringEncoding] autorelease] ?: @"";
                }
                NSArray *lines = [tail componentsSeparatedByString:@"\n"];
                if (lines.count > 20) lines = [lines subarrayWithRange:NSMakeRange(lines.count - 20, 20)];
                [_delegate launchSession:self failed:@"The app's setup stopped unexpectedly."
                                  detail:[lines componentsJoinedByString:@"\n"]];
            }
            [self release];
        });
    });
}

- (void)answer:(NSString *)askId choice:(NSString *)choice {
    NSData *j = [NSJSONSerialization dataWithJSONObject:@{@"t": @"answer", @"id": askId ?: @"", @"choice": choice ?: @""}
                                                options:0 error:NULL];
    NSMutableData *line = [[j mutableCopy] autorelease]; [line appendBytes:"\n" length:1];
    write(_writeFD, line.bytes, line.length);
}
@end

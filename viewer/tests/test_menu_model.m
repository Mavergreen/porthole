#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "PortholeMenuModel.h"
#import "PortholeStaticMenuProducer.h"
#include <assert.h>

@interface TestDelegate : NSObject <PortholeMenuProducerDelegate>
@property(copy) void (^onSnapshot)(NSArray *);
@property(copy) void (^onDelta)(NSArray *);
@end
@implementation TestDelegate
- (void)producer:(id)p didSnapshot:(NSArray *)n { if (_onSnapshot) _onSnapshot(n); }
- (void)producer:(id)p didDelta:(NSArray *)c { if (_onDelta) _onDelta(c); }
- (void)producer:(id)p didPopulate:(NSInteger)i children:(NSArray *)c {}
- (void)producerDidEnd:(id)p {}
- (void)dealloc { [_onSnapshot release]; [_onDelta release]; [super dealloc]; }
@end

@interface TestInvoker : NSObject <PortholeMenuStaticInvoker>
@property(copy) void (^onSend)(NSString *);
@end
@implementation TestInvoker
- (void)invokeSendString:(NSString *)s { if (_onSend) _onSend(s); }
- (void)dealloc { [_onSend release]; [super dealloc]; }
@end

int main(void) {
    @autoreleasepool {
        NSArray *wire = @[@{
            @"id": @1, @"role": @"submenu", @"label": @"File", @"enabled": @YES,
            @"children": @[
                @{@"id": @2, @"role": @"item", @"label": @"Save",
                  @"enabled": @YES, @"accel": @{@"key": @"s", @"mods": @[@"cmd"]}},
                @{@"id": @3, @"role": @"separator"},
                @{@"id": @4, @"role": @"item", @"label": @"Reload", @"enabled": @NO},
            ],
        }];
        NSArray *nodes = [PortholeMenuNode nodesFromArray:wire];
        assert(nodes.count == 1);
        PortholeMenuNode *file = nodes[0];
        assert([file.role isEqualToString:@"submenu"]);
        assert([file.label isEqualToString:@"File"]);
        assert(file.children.count == 3);
        PortholeMenuNode *save = file.children[0];
        assert(save.nodeId == 2);
        assert(save.enabled);
        assert([save.accelKey isEqualToString:@"s"]);
        assert((save.accelMods & NSCommandKeyMask) != 0);
        PortholeMenuNode *sep = file.children[1];
        assert([sep.role isEqualToString:@"separator"]);
        PortholeMenuNode *reload = file.children[2];
        assert(!reload.enabled);
        // visible defaults to YES when the key is absent
        assert(file.visible);
        // --- static producer: menu.json dict -> snapshot + invoke mapping ---
        NSDictionary *mj = @{@"menus": @[@{
            @"title": @"Edit", @"items": @[
                @{@"title": @"Lock", @"send": @"ctrl+shift+l"},
                @{@"separator": @YES},
                @{@"title": @"Quit", @"send": @"@quit", @"key": @"q"},
            ]}]};
        NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:@"porthole-test-menu.json"];
        [[NSJSONSerialization dataWithJSONObject:mj options:0 error:NULL] writeToFile:tmp atomically:YES];

        __block NSArray *snap = nil;
        __block NSString *invoked = nil;
        TestDelegate *del = [[[TestDelegate alloc] init] autorelease];
        del.onSnapshot = ^(NSArray *nodes){ snap = [nodes retain]; };
        TestInvoker *inv = [[[TestInvoker alloc] init] autorelease];
        inv.onSend = ^(NSString *s){ invoked = [s retain]; };

        PortholeStaticMenuProducer *sp = [[[PortholeStaticMenuProducer alloc]
            initWithJSONPath:tmp invoker:inv] autorelease];
        sp.delegate = del;
        [sp start];
        assert(snap.count == 1);                       // one top-level menu: Edit
        PortholeMenuNode *editM = snap[0];
        assert([editM.label isEqualToString:@"Edit"]);
        assert(editM.children.count == 3);             // Lock, separator, Quit
        PortholeMenuNode *lock = editM.children[0];
        assert([lock.label isEqualToString:@"Lock"]);
        [sp invokeNode:lock.nodeId];
        assert([invoked isEqualToString:@"ctrl+shift+l"]);  // id -> original send

        assert(lock.enabled);                          // no enabled_when: always enabled

        // --- enabled_when "unlocked": grayed while the app is locked, like 1Password's own Lock ---
        NSDictionary *mj2 = @{@"menus": @[@{
            @"title": @"1Password", @"items": @[
                @{@"title": @"New Item", @"send": @"ctrl+n"},
                @{@"title": @"Lock", @"send": @"ctrl+shift+l", @"enabled_when": @"unlocked"},
            ]}]};
        [[NSJSONSerialization dataWithJSONObject:mj2 options:0 error:NULL] writeToFile:tmp atomically:YES];
        __block NSArray *deltas = nil;
        del.onDelta = ^(NSArray *c){ [deltas release]; deltas = [c retain]; };
        PortholeStaticMenuProducer *sp2 = [[[PortholeStaticMenuProducer alloc]
            initWithJSONPath:tmp invoker:inv] autorelease];
        sp2.delegate = del;
        [sp2 start];
        PortholeMenuNode *lock2 = ((PortholeMenuNode *)snap[0]).children[1];
        assert(lock2.enabled);                         // lock state unknown: Lock is offered
        [sp2 setAppLocked:YES];
        assert([deltas isEqualToArray:(@[@{@"id": @(lock2.nodeId), @"enabled": @NO}])]);
        [sp2 setAppLocked:NO];
        assert([deltas isEqualToArray:(@[@{@"id": @(lock2.nodeId), @"enabled": @YES}])]);
        // A fresh snapshot (e.g. reverting from a live menu) keeps the current state.
        [sp2 setAppLocked:YES];
        [sp2 start];
        assert(!((PortholeMenuNode *)((PortholeMenuNode *)snap[0]).children[1]).enabled);
        assert(((PortholeMenuNode *)((PortholeMenuNode *)snap[0]).children[0]).enabled);

        printf("test_menu_model: OK\n");
    }
    return 0;
}

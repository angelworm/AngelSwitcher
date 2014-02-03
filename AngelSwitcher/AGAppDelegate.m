//
//  AGAppDelegate.m
//  AngelSwitcher
//
//  Created by 中島進 on 2014/01/31.
//  Copyright (c) 2014年 @Angelworm_. All rights reserved.
//

#import "AGAppDelegate.h"

#import <SystemConfiguration/SystemConfiguration.h>

static NSString *kAGCreateReachabilityNotification = @"kAGCreateReachabilityNotification";
static int kAGSSIDNameTag = 1;

static void AGReachabilityNotificatorCallback(SCDynamicStoreRef ds,
                                              CFArrayRef        changedKeys,
                                              void              *info) {
    
    
    CFStringRef key = CFArrayGetValueAtIndex(changedKeys, 0);
    CFDictionaryRef SSIDConf     = SCDynamicStoreCopyValue(ds, key);
    CFDictionaryRef newtworkConf = SCDynamicStoreCopyValue(ds, CFSTR("Setup:/"));

    CFStringRef networkName = CFDictionaryGetValue(newtworkConf, CFSTR("UserDefinedName"));
    CFStringRef SSIDName =    CFDictionaryGetValue(SSIDConf, CFSTR("SSID_STR"));
    
    SSIDName = SSIDName ? SSIDName : CFSTR("NOT FOUND");
    
    CFShow(SSIDName);
    
    NSDictionary *inf = @{@"SSID":   (__bridge NSString *)SSIDName,
                          @"Network":(__bridge NSString *)networkName};
    
    [[NSNotificationCenter defaultCenter] postNotificationName: kAGCreateReachabilityNotification
                                                        object: inf];
    CFRelease(SSIDConf);
    CFRelease(newtworkConf);
}

SCDynamicStoreRef AGCreateReachabilityNotificator() {
    SCDynamicStoreRef ds;
    SCDynamicStoreContext context = {0, NULL, NULL, NULL, NULL};
    
    ds = SCDynamicStoreCreate(kCFAllocatorDefault,
                              CFBundleGetIdentifier(CFBundleGetMainBundle()),
                              AGReachabilityNotificatorCallback,
                              &context);
    
    
    const CFStringRef watchKey[] = {
        CFSTR("State:/Network/Interface/en1/AirPort")
    };
    CFArrayRef key = CFArrayCreate(kCFAllocatorDefault, (const void **)watchKey,
                                   1, &kCFTypeArrayCallBacks);

    if (!SCDynamicStoreSetNotificationKeys(ds, NULL, key))
    {
        fprintf(stderr, "SCDynamicStoreSetNotificationKeys() failed: %s", SCErrorString(SCError()));
        CFRelease(key);
        CFRelease(ds);
        ds = NULL;
        
        return NULL;
    }
    CFRelease(key);
    
    CFRunLoopSourceRef rls = SCDynamicStoreCreateRunLoopSource(kCFAllocatorDefault, ds, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), rls, kCFRunLoopDefaultMode);
    CFRelease(rls);
    
    return ds;
}


@implementation AGAppDelegate {
    SCDynamicStoreRef ds;
}

@synthesize statusMenu;

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud registerDefaults:@{@"AGSSIDTable": @{}}];
    
    // Insert code here to initialize your application
    [[NSNotificationCenter defaultCenter]
     addObserver:self
        selector:@selector(notify:)
            name:kAGCreateReachabilityNotification
          object:nil];
    
    ds = AGCreateReachabilityNotificator();
    
    [self setupStatusItem];
}

- (void)setupStatusItem
{
    NSStatusBar *systemStatusBar = [NSStatusBar systemStatusBar];
    statusMenu = [systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    [statusMenu setHighlightMode:YES];
    [statusMenu setTitle:@""];
    [statusMenu setImage:[NSImage imageNamed:@"ServiceIcon"]];
    [statusMenu setMenu:self.serviceMenu];
}

- (void)notify:(NSNotification *)notification
{
    NSString *network = [notification.object objectForKey:@"Network"];
    NSString *ssid    = [notification.object objectForKey:@"SSID"];
    NSLog(@"Change SSID: %@(%@)", ssid, network);
    
    [self updateMenu:ssid network:network];
    
    if([ssid isEqualToString:@"NOT FOUND"]) return;
    
    NSMutableDictionary *sd = [NSMutableDictionary dictionaryWithDictionary:[[NSUserDefaults standardUserDefaults] objectForKey:@"AGSSIDTable"]];
    NSString *oldnetwork = [sd objectForKey:ssid];
    
    if (oldnetwork && ![network isEqualToString:oldnetwork]) { // 前のネットワークが登録されてる
        if(![self changeNetwork: oldnetwork]) {
            NSLog(@"Faild to Change Network %@ into %@: %s", network, oldnetwork, SCErrorString(SCError()));
        } else {
            NSLog(@"Changed Network %@ into %@", network, oldnetwork);
        }
    } else {
        [sd setValue:network forKey:ssid];
    }
    [[NSUserDefaults standardUserDefaults] setValue:sd forKey:@"AGSSIDTable"];
}

-(BOOL)changeNetwork:(NSString *)network
{
//    NSDictionary *pref = @{@"UserDefinedName": network};
//    return SCDynamicStoreSetValue(ds, CFSTR("Setup:/"), (__bridge CFPropertyListRef)pref);
    
    NSTask *task = [[NSTask alloc] init];
    NSPipe *pipe = [[NSPipe alloc] init];
    
    [task setLaunchPath:@"/usr/sbin/scselect"];
    [task setArguments:@[network]];
    [task setStandardOutput:pipe];
    [task launch];
    
    NSFileHandle *handle = [pipe fileHandleForReading];
    NSData *data = [handle readDataToEndOfFile];
    NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    
    NSLog(@"OOE:%@", string);
    
    return YES;

}

-(void)updateMenu:(NSString *)ssid network:(NSString *)network
{
    NSMenuItem *mi = [self.serviceMenu itemWithTag:kAGSSIDNameTag];
    [mi setTitle:ssid];
    
    while(self.serviceMenu.numberOfItems > 3) {
        [self.serviceMenu removeItemAtIndex:3];
    }
    
    if([ssid isEqualToString:@"NOT FOUND"]) return;
    
    SCPreferencesRef pref = SCPreferencesCreate(kCFAllocatorDefault, CFSTR("Angelworm"), NULL);
    CFArrayRef sa = SCNetworkSetCopyAll(pref);
    for(int i = 0; i < CFArrayGetCount(sa); i++) {
        SCNetworkSetRef ns = CFArrayGetValueAtIndex(sa, i);
        NSString *name = CFBridgingRelease(SCNetworkSetGetName(ns));
        NSMenuItem *minet = [[NSMenuItem alloc] initWithTitle:name
                                                       action:@selector(setNetwork:)
                                                keyEquivalent:@""];
        [minet setIndentationLevel:1];
        if([name isEqualToString:network]) {
            minet.state = NSOnState;
        }
        
        [self.serviceMenu addItem:minet];
    }
}

-(IBAction)setNetwork:(NSMenuItem *)sender
{
    NSString *network = sender.title;
    NSString *ssid    = [[self.serviceMenu itemAtIndex:2] title];

    NSLog(@"Recieved Network Change: %@(SSID:%@)", network, ssid);

    NSMutableDictionary *sd = [NSMutableDictionary dictionaryWithDictionary:[[NSUserDefaults standardUserDefaults] objectForKey:@"AGSSIDTable"]];
    [sd setValue:network forKey:ssid];
    [[NSUserDefaults standardUserDefaults] setValue:sd forKey:@"AGSSIDTable"];

    [self changeNetwork:network];
    
    [self updateMenu:ssid network:network];
}

@end

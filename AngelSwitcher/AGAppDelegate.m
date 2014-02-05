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
        CFSTR("State:/Network/Interface/.*/AirPort")
    };
    CFArrayRef key = CFArrayCreate(kCFAllocatorDefault, (const void **)watchKey,
                                   1, &kCFTypeArrayCallBacks);

    if (!SCDynamicStoreSetNotificationKeys(ds, NULL, key))
    {
        NSLog(@"SCDynamicStoreSetNotificationKeys() failed: %s", SCErrorString(SCError()));
        CFRelease(key);
        CFRelease(ds);
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
    NSDictionary* networkIDTable; // (NSString *uuid, NSString *name)
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
    
    [self updateNetworkTable];
    
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

#pragma mark networkTable

-(void)updateNetworkTable
{
    SCPreferencesRef pref = SCPreferencesCreate(kCFAllocatorDefault, CFSTR("Angelworm"), NULL);
    CFArrayRef sa = SCNetworkSetCopyAll(pref);
    NSMutableDictionary *nt = [NSMutableDictionary dictionary];
    
    for(int i = 0; i < CFArrayGetCount(sa); i++) {
        SCNetworkSetRef ns = CFArrayGetValueAtIndex(sa, i);
        NSString *name = (__bridge NSString *)(SCNetworkSetGetName(ns));
        NSString *uuid = (__bridge NSString *)(SCNetworkSetGetSetID(ns));
        
        [nt setObject:name forKey:uuid];
    }
    
    networkIDTable = nt;
    
    CFRelease(sa);
    CFRelease(pref);
}


- (NSString *)getNetworkID:(NSString *)networkName
{
    NSArray *ar = [networkIDTable allKeysForObject:networkName];
    return ([ar count] > 0 ? [ar objectAtIndex:0] : nil);
}

- (NSString *)getNetworkName:(NSString *)networkID
{
    return [networkIDTable objectForKey:networkID];
}

-(BOOL)changeNetwork:(NSString *)network
{
//    NSDictionary *pref = @{@"UserDefinedName": network};
//    return SCDynamicStoreSetValue(ds, CFSTR("Setup:/"), (__bridge CFPropertyListRef)pref);
    [self updateNetworkTable];
    NSString *networkID = [self getNetworkID:network];
    
    networkID = (!networkID ? network : networkID);
    
    NSTask *task = [[NSTask alloc] init];
    NSPipe *pipe = [[NSPipe alloc] init];
    
    [task setLaunchPath:@"/usr/sbin/scselect"];
    [task setArguments:@[networkID]];
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
    CFRelease(sa);
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

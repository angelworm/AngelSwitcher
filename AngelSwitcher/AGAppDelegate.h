//
//  AGAppDelegate.h
//  AngelSwitcher
//
//  Created by 中島進 on 2014/01/31.
//  Copyright (c) 2014年 @Angelworm_. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface AGAppDelegate : NSObject <NSApplicationDelegate>

@property (assign) IBOutlet NSWindow *window;
@property (weak) IBOutlet NSMenu *serviceMenu;
@property NSStatusItem *statusMenu;
@property (weak) IBOutlet NSMenuItem *launchOnLoginItem;
@end

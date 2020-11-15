//
//  Stack_Exchange_NotifierAppDelegate.h
//  Stack Exchange Notifier
//
//  Created by Greg Hewgill on 28/01/12.
//  Copyright 2012 Greg Hewgill. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <Foundation/Foundation.h>

#import <DBGHTMLEntities/DBGHTMLEntityDecoder.h>


@interface AppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate, NSUserNotificationCenterDelegate, WebFrameLoadDelegate> {
    
    // Timer for checking the inbox every 5 minutes
    NSTimer *checkInboxTimer;
    // The menu attached to the status bar item
    NSMenu *menu;
    // The status bar item itself (nil if it's currently hidden)
    NSStatusItem *statusItem;
    // Web view used to log in to the web site
    WebView *web;
    // Access token stored from the login procedure
    NSString *access_token;
    // Array of all items that we've seen from the server
    NSArray *allItems;
    // Array of items already marked as "read"
    NSArray *readItems;
    // Current unread items from the site
    NSArray *items;
    // Array to hold IndirectTarget objects for menu selections
    NSMutableArray *targets;
    // Error message if we got login errors
    NSString *loginError;
    // Last time inbox was successfully checked
    time_t lastCheck;
    // Error message if we got an error reading the inbox
    NSString *lastCheckError;
    // Icons when no messages
    NSImage *inactiveIcon;
    NSImage *inactiveIconAlt;
    // Icon when 1+ messages
    NSImage *activeIcon;
    // Shared HTML entity decoder
    DBGHTMLEntityDecoder *htmlEntityDecoder;
}

@property (strong) IBOutlet NSWindow *window;

@end

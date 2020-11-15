//
//  AppDelegate.h
//  Stack Exchange Notifier
//
//  Created by Greg Hewgill on 28/01/12.
//  Copyright 2012 Greg Hewgill. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

#import <DBGHTMLEntities/DBGHTMLEntityDecoder.h>


@interface AppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate, NSUserNotificationCenterDelegate, WebFrameLoadDelegate> {
    
    // Timer for checking the inbox every 5 minutes
    NSTimer *checkInboxTimer;
    // The status bar item itself (nil if it's currently hidden)
    NSStatusItem *statusItem;
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

@property (strong) IBOutlet WebView *webview;

@property (strong) IBOutlet NSMenu *menu;
@property (weak) IBOutlet NSMenuItem *noUnreadMessagesMenuItem;
@property (weak) IBOutlet NSMenuItem *lastCheckMenuItem;
@property (weak) IBOutlet NSMenuItem *loggedInAsMenuItem;
@property (weak) IBOutlet NSMenuItem *loginMenuItem;
@property (weak) IBOutlet NSMenuItem *logoutMenuItem;
@property (weak) IBOutlet NSMenuItem *lastUpdateCheckMenuItem;
@property (weak) IBOutlet NSMenuItem *automatedUpdateChecksMenuItem;
@property (weak) IBOutlet NSMenuItem *startAtLoginMenuItem;

- (IBAction)selectMessage:(id)sender;
- (IBAction)checkForMessages:(id)sender;
- (IBAction)login:(id)sender;
- (IBAction)logout:(id)sender;
- (IBAction)showAbout:(id)sender;
- (IBAction)checkForUpdates:(id)sender;
- (IBAction)configureAutomatedUpdateChecks:(id)sender;
- (IBAction)startAtLogin:(id)sender;
- (IBAction)quit:(id)sender;

@end

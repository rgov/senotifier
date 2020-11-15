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

#import "Stack_Exchange_Notifier-Swift.h"


@interface AppDelegate : NSObject <NSApplicationDelegate, NSMenuDelegate, NSUserNotificationCenterDelegate> {
    
    StackExchangeAPI *api;
    
    // Timer for checking the inbox every 5 minutes
    NSTimer *checkInboxTimer;
    // The status bar item itself
    NSStatusItem *statusItem;
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
    // Shared HTML entity decoder
    DBGHTMLEntityDecoder *htmlEntityDecoder;
}

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

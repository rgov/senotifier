//
//  AppDelegate.m
//  Stack Exchange Notifier
//
//  Created by Greg Hewgill on 28/01/12.
//  Copyright 2012 Greg Hewgill. All rights reserved.
//

#import <CoreServices/CoreServices.h>

#import <Sparkle/Sparkle.h>

#import "AppDelegate.h"




// Name of key to store all items in defaults
NSString *DEFAULTS_KEY_ALL_ITEMS = @"com.hewgill.senotifier.allitems";
// Name of key to store read items in defaults
NSString *DEFAULTS_KEY_READ_ITEMS = @"com.hewgill.senotifier.readitems";


// Local function prototypes

NSString *minutesToString(long minutes);
NSString *timeAgo(time_t t);
void setMenuItemTitle(NSMenuItem *menuitem, NSDictionary *msg, bool highlight);

// Format a number of minutes as a string
NSString *minutesToString(long minutes)
{
    NSString *r;
    if (minutes == 1) {
        r = @"1 minute";
    } else if (minutes < 60) {
        r = [NSString stringWithFormat:@"%ld minutes", minutes];
    } else if (minutes < 60*2) {
        r = @"1 hour";
    } else {
        r = [NSString stringWithFormat:@"%ld hours", minutes / 60];
    }
    return r;
}

// Simple implementation of "checked n minute(s)/hour(s) ago"
// for use in the menu
NSString *timeAgo(time_t t)
{
    long minutesago = (time(NULL) - t) / 60;
    return [NSString stringWithFormat:@" - checked %@ ago", minutesToString(minutesago)];
}

// IndirectTarget can be attached to a menu item (or anything that calls
// a "fire" selector) to pass through an additional argument to a selector
// that eventually handles the selection. Note that since NSMenuItem doesn't
// retain its "fire" target, you will need to keep a reference to these
// somewhere yourself ("targets" array here).
@interface IndirectTarget: NSObject {
    id _originalTarget;
    SEL _action;
    id _arg;
};

@end

@implementation IndirectTarget

-(IndirectTarget *)initWithArg:(id)arg action:(SEL)action originalTarget:(id)originalTarget
{
    _originalTarget = originalTarget;
    _action = action;
    _arg = arg;
    return self;
}

-(void)fire
{
    // Turn off clang diagnostics because we're using performSelector here,
    // so ARC can't be sure we aren't calling retain or release.
    // (Don't try to do that.)
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    [_originalTarget performSelector:_action withObject:_arg];
    #pragma clang diagnostic pop
}

@end


// MARK: -
// MARK: Start at Login management

/*
 * These two functions are based on
 * http://stackoverflow.com/questions/815063/how-do-you-make-your-app-open-at-login
 */
static BOOL willStartAtLogin()
{
    NSURL *appurl = [NSURL fileURLWithPath:[[NSBundle mainBundle] bundlePath]];
    BOOL found = NO;
    LSSharedFileListRef items = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
    if (items) {
        UInt32 seed;
        CFArrayRef itemsArray = LSSharedFileListCopySnapshot(items, &seed);
        CFIndex count = CFArrayGetCount(itemsArray);
        for (CFIndex i = 0; i < count; i++) {
            LSSharedFileListItemRef a = (LSSharedFileListItemRef)CFArrayGetValueAtIndex(itemsArray, i);
            CFURLRef url = NULL;
            OSStatus err = LSSharedFileListItemResolve(a, kLSSharedFileListNoUserInteraction | kLSSharedFileListDoNotMountVolumes, &url, NULL);
            if (err == noErr) {
                found = CFEqual(url, (__bridge CFURLRef)appurl);
                CFRelease(url);
                if (found) {
                    break;
                }
            }
        }
        CFRelease(items);
    }
    return found;
}

static void setStartAtLogin(BOOL enabled)
{
    NSURL *appurl = [NSURL fileURLWithPath:[NSBundle mainBundle].bundlePath];
    LSSharedFileListItemRef existing = NULL;
    LSSharedFileListRef items = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
    if (items) {
        UInt32 seed;
        CFArrayRef itemsArray = LSSharedFileListCopySnapshot(items, &seed);
        CFIndex count = CFArrayGetCount(itemsArray);
        for (CFIndex i = 0; i < count; i++) {
            LSSharedFileListItemRef a = (LSSharedFileListItemRef)CFArrayGetValueAtIndex(itemsArray, i);
            CFURLRef url = NULL;
            OSStatus err = LSSharedFileListItemResolve(a, kLSSharedFileListNoUserInteraction | kLSSharedFileListDoNotMountVolumes, &url, NULL);
            if (err == noErr) {
                BOOL found = CFEqual(url, (__bridge CFURLRef)appurl);
                CFRelease(url);
                if (found) {
                    existing = a;
                    break;
                }
            }
        }
        if (enabled && existing == NULL) {
            LSSharedFileListItemRef item = LSSharedFileListInsertItemURL(
                items,
                kLSSharedFileListItemLast,
                NULL,
                NULL,
                (__bridge CFURLRef)appurl,
                NULL,
                NULL);
            if (item) {
                CFRelease(item);
            }
        } else if (!enabled && existing != NULL) {
            LSSharedFileListItemRemove(items, existing);
        }
        CFRelease(items);
    }
}

// MARK: -

// Utility function to set an inbox item menu item.
void setMenuItemTitle(NSMenuItem *menuitem, NSDictionary *msg, bool highlight)
{
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont menuBarFontOfSize:0.0],
        NSStrokeWidthAttributeName: [NSNumber numberWithFloat:(highlight ? -4.0 : 0.0)],
    };
    
    NSMutableAttributedString *title = [[NSMutableAttributedString alloc] initWithString:msg[@"body"]
                                                                              attributes:attrs];
    
    DBGHTMLEntityDecoder *htmlEntityDecoder = [[DBGHTMLEntityDecoder alloc] init];
    [htmlEntityDecoder decodeStringInPlace:title.mutableString];
    menuitem.attributedTitle = title;
}

@implementation AppDelegate

// MARK: -
// MARK: NSMenuDelegate methods

// Called just before the menu opens to show the
// amount of time since the last check. Also shows error messages
// if available.
-(void)menuWillOpen:(NSMenu *)menu;
{
    // Update "Check for Update Automatically" menu state
    self.automatedUpdateChecksMenuItem.state =
        SUUpdater.sharedUpdater.automaticallyChecksForUpdates ?
        NSControlStateValueOn : NSControlStateValueOff;
    
    // Update "Start at Login" menu state
    self.startAtLoginMenuItem.state =
        willStartAtLogin() ?
        NSControlStateValueOn : NSControlStateValueOff;
}

// Completely reset the menu, creating a new one and add all items
// back in to the menu. Called when the list of inbox items changes.
// There is probably a more elegant way to modify just the part of
// the menu that needs to change, but this works fine.
-(void)resetMenu
{
#if 0
    menu = [[NSMenu alloc] initWithTitle:@""];
    menu.delegate = self;
    
    [menu addItem:[[NSMenuItem alloc] initWithTitle:@"About" action:@selector(showAbout) keyEquivalent:@""]];
    [menu addItem:[[NSMenuItem alloc] initWithTitle:@"Log in" action:@selector(doLogin) keyEquivalent:@""]];
    [menu addItem:[[NSMenuItem alloc] initWithTitle:@"Check Now" action:@selector(checkInbox) keyEquivalent:@""]];
    
    [menu addItem:[NSMenuItem separatorItem]];
        
    unsigned int unread = 0;
    targets = [NSMutableArray arrayWithCapacity:items.count];
    if (items.count > 0) {
        unsigned int i = 0;
        for (NSDictionary *obj in items) {
            NSMenuItem *it = [[NSMenuItem alloc] initWithTitle:[htmlEntityDecoder decodeString:obj[@"body"]]
                                                        action:@selector(fire)
                                                 keyEquivalent:@""];
            bool read = [readItems containsObject:obj[@"link"]];
            setMenuItemTitle(it, obj, !read);
            if (!read) {
                unread++;
            }
            NSImage *icon = [[NSImage alloc] initByReferencingURL:[[NSURL alloc] initWithString:obj[@"site"][@"icon_url"]]];
            icon.size = NSMakeSize(24, 24);
            it.image = icon;
            IndirectTarget *t = [[IndirectTarget alloc] initWithArg:[NSNumber numberWithUnsignedInt:i] action:@selector(openUrlFromItem:) originalTarget:self];
            // must store the IndirectTarget somewhere to retain it, because
            // NSMenuItem won't do that for us
            [targets addObject:t];
            it.target = t;
            [menu addItem:it];
            i++;
        }
    } else {
        [menu addItem:[[NSMenuItem alloc] initWithTitle:@"no messages" action:NULL keyEquivalent:@""]];
    }
    
    [menu addItem:[NSMenuItem separatorItem]];
    
    NSMenu *preferencesMenu = [[NSMenu alloc] initWithTitle:@""];
    
    NSMenuItem *enableStartAtLogin = [[NSMenuItem alloc] initWithTitle:@"Start at login" action:@selector(changeStartAtLogin) keyEquivalent:@""];
    enableStartAtLogin.state = willStartAtLogin() ? NSOnState : NSOffState;
    [preferencesMenu addItem:enableStartAtLogin];
    NSMenuItem *preferences = [[NSMenuItem alloc] initWithTitle:@"Preferences" action:nil keyEquivalent:@""];
    [menu addItem:preferences];
    [menu setSubmenu:preferencesMenu forItem:preferences];
    
    [menu addItem:[[NSMenuItem alloc] initWithTitle:@"Invalidate login token" action:@selector(invalidate) keyEquivalent:@""]];
    NSMenuItem *check_updates = [[NSMenuItem alloc] initWithTitle:@"Check for app updates" action:@selector(checkForUpdates:) keyEquivalent:@""];
    check_updates.target = sparkleUpdater;
    [menu addItem:check_updates];
    [menu addItem:[[NSMenuItem alloc] initWithTitle:@"Quit" action:@selector(quit) keyEquivalent:@""]];
#endif

    // DEBUG
    int unread = 0;
    
    // if there are any unread items, display that number on the status bar
    if (unread > 0) {
        statusItem.button.title = [NSString stringWithFormat:@"%u", unread];
        statusItem.button.image = [NSImage imageNamed:@"menu_messages"];
    } else {
        statusItem.button.title = @"";
        statusItem.button.image = [NSImage imageNamed:@"menu_no_messages"];
    }
}

// Open a window to log in to Stack Exchange.
-(void)doLogin
{
}

// MARK: -
// MARK: NSApplicationDelegate methods

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    lastCheck = 0;
    loginError = nil;
    lastCheckError = nil;
    
    api = [[StackExchangeAPI alloc] init];

    // read the list of all items from defaults
    allItems = [NSUserDefaults.standardUserDefaults arrayForKey:DEFAULTS_KEY_ALL_ITEMS];

    // read the list of items already read from defaults
    readItems = [NSUserDefaults.standardUserDefaults arrayForKey:DEFAULTS_KEY_READ_ITEMS];

    // initialize the shared HTML entity decoder
    htmlEntityDecoder = [[DBGHTMLEntityDecoder alloc] init];
    
    // Create the status bar item
    statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    statusItem.button.image = [NSImage imageNamed:@"menu_no_messages"];
    statusItem.button.alternateImage = [NSImage imageNamed:@"menu_clicked"];
    statusItem.menu = self.menu;

    NSUserNotificationCenter.defaultUserNotificationCenter.delegate = self;

    // kick off a login procedure
    [self login:self];

    // set up the timer
    checkInboxTimer = [NSTimer scheduledTimerWithTimeInterval:300 target:self selector:@selector(checkInbox) userInfo:nil repeats:YES];
}

// Check for new inbox items on the server.
// Call is ignored if the status item is currently hidden
// (we wouldn't show the menu items anyway in that state).
-(void)checkInbox
{
    // Ask for new inbox items from the server
    [api getUnreadMessages:^(NSArray *unreadMessages) {
        self->allItems = unreadMessages;
        NSLog(@"%@", self->allItems);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self gotInboxStatus];
        });
    }];
}

// Finished receiving and API response. Parse the JSON and
// reset the menu.
-(void)gotInboxStatus
{
    // First copy all server items into our local copy, notifying for each new one
    NSMutableArray *newAllItems = [[NSMutableArray alloc] initWithCapacity:items.count];
    for (NSDictionary *item in items) {
        NSString *link = item[@"link"];
        if (![allItems containsObject:link]) {
            NSUserNotification *notification = [[NSUserNotification alloc] init];
            notification.title = item[@"site"][@"name"];
            notification.informativeText = [htmlEntityDecoder decodeString:item[@"body"]];
            notification.soundName = NSUserNotificationDefaultSoundName;
            notification.userInfo = @{@"link": item[@"link"]};

            [NSUserNotificationCenter.defaultUserNotificationCenter deliverNotification:notification];
        }
        [newAllItems addObject:link];
    }
    allItems = newAllItems;
    [NSUserDefaults.standardUserDefaults setObject:allItems forKey:DEFAULTS_KEY_ALL_ITEMS];
    
    // We only need to keep the "read" items in our local defaults
    // list for those items where the server still thinks they're
    // unread. Trim out local items that no longer appear in the
    // server's unread list.
    NSMutableArray *newReadItems = [[NSMutableArray alloc] initWithCapacity:readItems.count];
    for (unsigned int i = 0; i < readItems.count; i++) {
        NSString *link = readItems[i];
        bool found = false;
        for (unsigned int j = 0; j < items.count; j++) {
            if ([link isEqualToString:items[j][@"link"]]) {
                found = true;
                break;
            }
        }
        if (found) {
            [newReadItems addObject:link];
        }
    }
    readItems = newReadItems;
    [NSUserDefaults.standardUserDefaults setObject:readItems forKey:DEFAULTS_KEY_READ_ITEMS];
    
    // Clean up notification center based on our new allItems list.
    NSArray *notifications = NSUserNotificationCenter.defaultUserNotificationCenter.deliveredNotifications;
    for (NSUserNotification *n in notifications) {
        NSString *link = n.userInfo[@"link"];
        if (![allItems containsObject:link] || [readItems containsObject:link]) {
            [NSUserNotificationCenter.defaultUserNotificationCenter removeDeliveredNotification:n];
        }
    }
    
    // Remember the last time we checked the inbox.
    lastCheck = time(NULL);
    [self resetMenu];
}

// Selector called by IndirectTarget when the user selects
// an inbox item from the menu.
-(void)openUrlFromItem:(NSNumber *)index
{
    // Get the item by index
    NSDictionary *msg = items[index.unsignedIntValue];
    // Get the link for the item
    NSString *link = msg[@"link"];
    
    [self openLink:link];
}

- (void)openLink:(NSString*)link {
    // Open the link in the user's default browser
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:link]];
    // Add this item to our local read items list and store it
    NSMutableArray *r = [NSMutableArray arrayWithArray:readItems];
    [r addObject:link];
    readItems = r;
    [NSUserDefaults.standardUserDefaults setObject:readItems forKey:DEFAULTS_KEY_READ_ITEMS];
    // Update the menu since we now have one fewer unread item
    [self resetMenu];
}

- (void)userNotificationCenter:(NSUserNotificationCenter *)center didActivateNotification:(NSUserNotification *)notification
{
    NSString *link = notification.userInfo[@"link"];
    [self openLink:link];
    [NSUserNotificationCenter.defaultUserNotificationCenter removeDeliveredNotification:notification];
}

// MARK: -
// MARK: Menu item actions

- (IBAction)selectMessage:(id)sender {
    // Not implemented yet.
}

- (IBAction)checkForMessages:(id)sender {
    [self checkInbox];
}

- (IBAction)login:(id)sender {
    [self doLogin];
}

- (IBAction)logout:(id)sender {
    [api invalidateAccessToken];
}

- (IBAction)showAbout:(id)sender {
    // Show the standard About window
    [NSApp activateIgnoringOtherApps:YES];
    [NSApp orderFrontStandardAboutPanel:self];
}

- (IBAction)checkForUpdates:(id)sender {
    [SUUpdater.sharedUpdater checkForUpdates:self];
}

- (IBAction)configureAutomatedUpdateChecks:(id)sender {
    if (self.automatedUpdateChecksMenuItem.state == NSControlStateValueOff) {
        SUUpdater.sharedUpdater.automaticallyChecksForUpdates = YES;
    } else {
        SUUpdater.sharedUpdater.automaticallyChecksForUpdates = NO;
    }
}

- (IBAction)startAtLogin:(id)sender {
    if (self.startAtLoginMenuItem.state == NSControlStateValueOff) {
        self.startAtLoginMenuItem.state = NSControlStateValueOn;
        setStartAtLogin(YES);
    } else {
        self.startAtLoginMenuItem.state = NSControlStateValueOff;
        setStartAtLogin(NO);
    }
}

- (IBAction)quit:(id)sender {
    [NSApp terminate:self];
}

@end

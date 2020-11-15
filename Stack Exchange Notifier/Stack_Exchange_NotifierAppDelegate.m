//
//  Stack_Exchange_NotifierAppDelegate.m
//  Stack Exchange Notifier
//
//  Created by Greg Hewgill on 28/01/12.
//  Copyright 2012 __MyCompanyName__. All rights reserved.
//

#import "Stack_Exchange_NotifierAppDelegate.h"
#import <Sparkle/Sparkle.h>


// API client key, specific to each API client
// (don't use this one, register to get your own
// at http://stackapps.com/apps/oauth/register )
NSString *CLIENT_KEY = @"JBpdN2wRVnHTq9E*uuyTPQ((";
// Name of key to store all items in defaults
NSString *DEFAULTS_KEY_ALL_ITEMS = @"com.hewgill.senotifier.allitems";
// Name of key to store read items in defaults
NSString *DEFAULTS_KEY_READ_ITEMS = @"com.hewgill.senotifier.readitems";


// Local function prototypes

NSString *minutesToString(long minutes);
NSString *timeAgo(time_t t);
NSStatusItem *createStatusItem(NSImage* icon);
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

// Create the status item when needed. Called on program startup or
// when the icon is unhidden.
NSStatusItem *createStatusItem(NSImage* icon)
{
    NSStatusItem *item = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    item.button.image = icon;
    item.button.highlighted = YES;
    return item;
}

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

@implementation Stack_Exchange_NotifierAppDelegate {
    SUUpdater *sparkleUpdater;
}

@synthesize window;

// Called just before the menu opens to show the
// amount of time since the last check. Also shows error messages
// if available.
-(void)menuWillOpen:(NSMenu *)menu;
{
    NSDictionary *normalattrs = @{
        NSFontAttributeName: [NSFont menuBarFontOfSize:0.0],
    };
    
    NSMutableAttributedString *at = [[NSMutableAttributedString alloc] initWithString:@"Log in" attributes:normalattrs];
    if (loginError != nil) {
        NSDictionary *redattrs = @{
            NSFontAttributeName: [NSFont menuBarFontOfSize:0.0],
            NSForegroundColorAttributeName: [NSColor redColor],
        };
        [at appendAttributedString:[[NSAttributedString alloc] initWithString:@" - " attributes:redattrs]];
        [at appendAttributedString:[[NSAttributedString alloc] initWithString:loginError attributes:redattrs]];
    }
    [menu itemAtIndex:1].attributedTitle = at;
    
    at = [[NSMutableAttributedString alloc] initWithString:@"Check Now" attributes:normalattrs];
    if (lastCheckError != nil) {
        NSDictionary *redattrs = @{
            NSFontAttributeName: [NSFont menuBarFontOfSize:0.0],
            NSForegroundColorAttributeName: [NSColor redColor],
        };
        [at appendAttributedString:[[NSAttributedString alloc] initWithString:@" - " attributes:redattrs]];
        [at appendAttributedString:[[NSAttributedString alloc] initWithString:lastCheckError attributes:redattrs]];
    } else if (lastCheck) {
        NSDictionary *grayattrs = @{
            NSFontAttributeName: [NSFont menuBarFontOfSize:0.0],
            NSForegroundColorAttributeName: [NSColor grayColor],
        };
        [at appendAttributedString:[[NSAttributedString alloc] initWithString:timeAgo(lastCheck) attributes:grayattrs]];
    }
    [menu itemAtIndex:2].attributedTitle = at;
}

// Completely reset the menu, creating a new one and add all items
// back in to the menu. Called when the list of inbox items changes.
// There is probably a more elegant way to modify just the part of
// the menu that needs to change, but this works fine.
-(void)resetMenu
{
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
    
    if (statusItem != nil) {
        // if there are any unread items, display that number on the status bar
        if (unread > 0) {
            statusItem.button.title = [NSString stringWithFormat:@"%u", unread];
            statusItem.button.image = activeIcon;
            statusItem.button.alternateImage = nil;
        } else {
            statusItem.button.title = @"";
            statusItem.button.image = inactiveIcon;
            statusItem.button.alternateImage = inactiveIconAlt;
        }
        statusItem.menu = menu;
    }
}

// Open a window to log in to Stack Exchange.
-(void)doLogin
{
    [NSApp activateIgnoringOtherApps:YES];
    [window makeKeyAndOrderFront:self];
    // this URL includes the
    //     client_id = 81 (specific to this application)
    //     scope = read_inbox (tell the user we want to read their inbox contents)
    //             no_expiry (request a token with indefinite expiration date)
    //     redirect_uri = where to send the browser when authentication succeeds
    [[web mainFrame] loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://stackexchange.com/oauth/dialog?client_id=81&scope=read_inbox,no_expiry&redirect_uri=https://stackexchange.com/oauth/login_success"]]];
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification
{
    sparkleUpdater = [SUUpdater sharedUpdater];
}

// Initialise the application.
- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    lastCheck = 0;
    loginError = nil;
    lastCheckError = nil;

    // read the list of all items from defaults
    allItems = [NSUserDefaults.standardUserDefaults arrayForKey:DEFAULTS_KEY_ALL_ITEMS];

    // read the list of items already read from defaults
    readItems = [NSUserDefaults.standardUserDefaults arrayForKey:DEFAULTS_KEY_READ_ITEMS];

    // setting icons
    inactiveIcon = [[NSImage alloc] initByReferencingFile:[NSBundle.mainBundle
                                    pathForResource:@"senotifier_inactive.png"
                                    ofType:nil]];
    inactiveIconAlt = [[NSImage alloc] initByReferencingFile:[NSBundle.mainBundle
                                       pathForResource:@"senotifier_inactive_alt.png"
                                       ofType:nil]];
    activeIcon = [[NSImage alloc] initByReferencingFile:[NSBundle.mainBundle
                                  pathForResource:@"senotifier.png" 
                                  ofType:nil]];

    // initialize the shared HTML entity decoder
    htmlEntityDecoder = [[DBGHTMLEntityDecoder alloc] init];
    
    // create the status bar item
    statusItem = createStatusItem(inactiveIcon);
    [self resetMenu];

    // create the web view that we will use for login
    web = [[WebView alloc] initWithFrame:window.frame];
    window.contentView = web;
    web.frameLoadDelegate = self;
    
    NSUserNotificationCenter.defaultUserNotificationCenter.delegate = self;

    // kick off a login procedure
    [self doLogin];

    // set up the timer
    checkInboxTimer = [NSTimer scheduledTimerWithTimeInterval:300 target:self selector:@selector(checkInbox) userInfo:nil repeats:YES];
}

// Show a standard About panel.
-(void)showAbout
{
    [NSApp activateIgnoringOtherApps:YES];
    [NSApp orderFrontStandardAboutPanelWithOptions:@{
        @"Version": @""
    }];
}

// Check for new inbox items on the server.
// Call is ignored if the status item is currently hidden
// (we wouldn't show the menu items anyway in that state).
-(void)checkInbox
{
    if (statusItem == nil) {
        return;
    }
    lastCheckError = nil;
    
    // Ask for new inbox items from the server. Use "withbody"
    // filter to get a small bit of the body text (to display
    // in the menu).
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://api.stackexchange.com/2.0/inbox/unread?access_token=%@&key=%@&filter=withbody", access_token, CLIENT_KEY]]];
    NSURLConnection *conn = [[NSURLConnection alloc] initWithRequest:request delegate:self];
    if (conn) {
        receivedData = [NSMutableData data];
    } else {
        NSLog(@"failed to create connection");
    }
}

// Invalidate login token on the server. Might help with debugging.
-(void)invalidate
{
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://api.stackexchange.com/2.0/access-tokens/%@/invalidate", access_token]]];
    NSURLConnection *conn = [[NSURLConnection alloc] initWithRequest:request delegate:nil];
    if (conn == nil) {
        NSLog(@"failed to create connection");
    }
}

// Arrivederci.
-(void)quit
{
    [NSApp terminate:self];
}

// Called from the WebView when there is an error of some kind
// and we can't reach the server.
-(void)webView:(WebView *)sender didFailProvisionalLoadWithError:(NSError *)error forFrame:(WebFrame *)frame
{
    loginError = error.localizedDescription;

    [[NSAlert alertWithError:error] runModal];
    // There isn't anything on the web page for the user to interact with
    // at this point, so close the view.
    window.isVisible = NO;
}

// Called from the WebView when there is an error of some kind
// during the login process.
-(void)webView:(WebView *)sender didFailLoadWithError:(NSError *)error forFrame:(WebFrame *)frame
{
    // Ignore NSURLErrorCancelled because that may happen during normal operation,
    // see http://stackoverflow.com/questions/1024748
    if (error.code == NSURLErrorCancelled) {
        return;
    }
    loginError = error.localizedDescription;
    [[NSAlert alertWithError:error] runModal];
    // There might be something the user wants to read in this case,
    // so don't close the view.
    //window.isVisible = NO;
}

// Finished the login process. The server sends the browser to
// the URL specified in the login request ("redirect_uri" in doLogin)
// so we detect that specific URL and get the authentication token.
-(void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame
{
    // Get the current URL from the frame.
    NSURL *url = frame.dataSource.request.URL;
    NSLog(@"finished loading %@", url.absoluteString);
    // Make sure we've ended up at the "login success" page
    if (![[url absoluteString] hasPrefix:@"https://stackexchange.com/oauth/login_success"]) {
        loginError = @"Error logging in to Stack Exchange.";
        return;
    }
    // Extract the access_token value from the URL
    NSString *fragment = [url fragment];
    NSRange r = [fragment rangeOfString:@"access_token="];
    if (r.location == NSNotFound) {
        loginError = @"Access token not found on login.";
        return;
    }
    r.location += 13;
    NSRange e = [fragment rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"&"]];
    if (e.location == NSNotFound) {
        e.location = fragment.length;
    }
    access_token = [fragment substringWithRange:NSMakeRange(r.location, e.location - r.location)];
    // Close the window, we're done with it.
    window.isVisible = NO;
    // Clear any login error, since it succeeded this time.
    loginError = nil;
    // Finally, check the inbox now that we're logged in.
    [self checkInbox];
}

// Connection error of some kind when sending inbox request.
-(void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    lastCheckError = error.localizedDescription;
}

// Started to receive an API response from the server.
-(void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    receivedData.length = 0;
}

// Received some more data from the server for an API request.
-(void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    [receivedData appendData:data];
}

// Finished receiving and API response. Parse the JSON and
// reset the menu.
-(void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    // Parse the JSON response to the API request
    id r = [NSJSONSerialization JSONObjectWithData:receivedData options:0 error:nil];
    if (r == nil) {
        lastCheckError = @"JSON parse error";
        return;
    }
    
#if DEBUG
    // Write the prettified response to the log for debugging
    NSData *prettyJSON = [NSJSONSerialization dataWithJSONObject:r
                                                         options:NSJSONWritingPrettyPrinted
                                                           error:nil];
    NSLog(@"json %@", [NSString stringWithUTF8String:prettyJSON.bytes]);
#endif
    
    // If we got an error, try logging in again.
    if (r[@"error_id"]) {
        lastCheckError = r[@"error_name"];
        // only auto-login if we got an expired access token (which is expected)
        if ([lastCheckError compare:@"invalid_access_token"] == NSOrderedSame
         && [(NSString *)r[@"error_message"] compare:@"expired"] == NSOrderedSame) {
            [self doLogin];
        }
        return;
    }
    
    // Get the unread inbox items according to the server.
    items = r[@"items"];
    
    

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
    [[NSUserDefaults standardUserDefaults] setObject:allItems forKey:DEFAULTS_KEY_ALL_ITEMS];
    
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

-(void)changeStartAtLogin
{
    setStartAtLogin(!willStartAtLogin());
    [self resetMenu];
}

@end

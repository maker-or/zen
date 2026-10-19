#import <AppKit/AppKit.h>

// Loaded by macOS independently of Zen, so this menu also exists after Quit.
@interface ZenDockTilePlugin : NSObject <NSDockTilePlugIn>
@property(nonatomic, strong) NSMenu *menu;
@property(nonatomic) BOOL attached;
@end

@implementation ZenDockTilePlugin

- (void)setDockTile:(NSDockTile *)dockTile {
    self.attached = dockTile != nil;
    if (!dockTile) self.menu = nil;
}

- (NSURL *)applicationURL {
    NSURL *url = [NSBundle bundleForClass:self.class].bundleURL;
    // Zen.app/Contents/PlugIns/ZenDockTilePlugin.docktileplugin
    for (NSUInteger index = 0; index < 3; index++) url = url.URLByDeletingLastPathComponent;
    return [url.pathExtension isEqualToString:@"app"] ? url : nil;
}

- (NSMenu *)dockMenu {
#if !DEBUG
    // Demo Onboarding is for development builds only.
    return nil;
#endif
    NSURL *applicationURL = self.applicationURL;
    if (!applicationURL) return nil;
    NSString *identifier = [NSBundle bundleWithURL:applicationURL].bundleIdentifier;
    if (!self.attached || !identifier) return nil;
    // The running app supplies its own menu through NSApplicationDelegate.
    if ([NSRunningApplication runningApplicationsWithBundleIdentifier:identifier].count) return nil;

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Zen"];
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Demo Onboarding"
                                               action:@selector(showDemoOnboarding:)
                                        keyEquivalent:@""];
    item.target = self;
    [menu addItem:item];
    self.menu = menu; // Dock requires us to retain the menu until the action fires.
    return menu;
}

- (void)showDemoOnboarding:(id)sender {
    NSURL *applicationURL = self.applicationURL;
    if (!applicationURL) return;
    NSString *identifier = [NSBundle bundleWithURL:applicationURL].bundleIdentifier;
    if (!identifier) return;
    NSString *requestID = NSUUID.UUID.UUIDString;
    NSWorkspaceOpenConfiguration *configuration = NSWorkspaceOpenConfiguration.configuration;
    configuration.arguments = @[@"--demo-onboarding", requestID];
    // The app seeds a hidden demo root before creating its main window.
    // Let Launch Services activate it so the intro can appear during launch.
    configuration.activates = YES;
    [NSWorkspace.sharedWorkspace openApplicationAtURL:applicationURL
                                      configuration:configuration
                                  completionHandler:^(NSRunningApplication *app, NSError *error) {
        if (!app || error) return;
        // Also handles an app that started after the Dock menu was opened.
        // The UUID lets a cold launch ignore this duplicate request.
        [NSDistributedNotificationCenter.defaultCenter
            postNotificationName:@"pipper.dev.zen.demoOnboardingRequested"
                          object:identifier
                        userInfo:@{@"requestID": requestID}
              deliverImmediately:YES];
    }];
}

@end

#import <AppKit/AppKit.h>
#import <Sparkle/Sparkle.h>

@interface Fixture : NSObject <NSApplicationDelegate, SPUUserDriver, SPUUpdaterDelegate>
@property(strong) SPUUpdater *updater;
@end
@implementation Fixture
- (void)record:(NSString *)value {
    NSString *root = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"FixtureRoot"];
    [value writeToFile:[root stringByAppendingPathComponent:@"result.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
- (void)applicationDidFinishLaunching:(NSNotification *)n {
    if ([[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"] isEqual:@"2"]) {
        [self record:@"UPDATED_2"]; [NSApp terminate:nil]; return;
    }
    self.updater = [[SPUUpdater alloc] initWithHostBundle:[NSBundle mainBundle] applicationBundle:[NSBundle mainBundle] userDriver:self delegate:self];
    NSError *error = nil;
    if (![self.updater startUpdater:&error]) { [self record:[@"START_ERROR: " stringByAppendingString:error.description]]; [NSApp terminate:nil]; return; }
    [self.updater checkForUpdates];
}
- (void)showUpdatePermissionRequest:(SPUUpdatePermissionRequest *)request reply:(void (^)(SUUpdatePermissionResponse *))reply { reply([[SUUpdatePermissionResponse alloc] initWithAutomaticUpdateChecks:NO sendSystemProfile:NO]); }
- (void)showUserInitiatedUpdateCheckWithCancellation:(void (^)(void))cancel {}
- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)item state:(SPUUserUpdateState *)state reply:(void (^)(SPUUserUpdateChoice))reply { [self record:@"FOUND"]; reply(SPUUserUpdateChoiceInstall); }
- (void)showUpdateReleaseNotesWithDownloadData:(SPUDownloadData *)data {}
- (void)showUpdateReleaseNotesFailedToDownloadWithError:(NSError *)error {}
- (void)showUpdateNotFoundWithError:(NSError *)error acknowledgement:(void (^)(void))ack { [self record:@"NO_UPDATE"]; ack(); [NSApp terminate:nil]; }
- (void)showUpdaterError:(NSError *)error acknowledgement:(void (^)(void))ack { [self record:[@"REJECTED: " stringByAppendingString:error.description]]; ack(); [NSApp terminate:nil]; }
- (void)showDownloadInitiatedWithCancellation:(void (^)(void))cancel {}
- (void)showDownloadDidReceiveExpectedContentLength:(uint64_t)length {}
- (void)showDownloadDidReceiveDataOfLength:(uint64_t)length {}
- (void)showDownloadDidStartExtractingUpdate { [self record:@"EXTRACTING"]; }
- (void)showExtractionReceivedProgress:(double)progress {}
- (void)showReadyToInstallAndRelaunch:(void (^)(SPUUserUpdateChoice))reply { [self record:@"INSTALLING"]; reply(SPUUserUpdateChoiceInstall); }
- (void)showInstallingUpdateWithApplicationTerminated:(BOOL)terminated retryTerminatingApplication:(void (^)(void))retry {}
- (void)showUpdateInstalledAndRelaunched:(BOOL)relaunched acknowledgement:(void (^)(void))ack { ack(); }
- (void)dismissUpdateInstallation {}
@end
int main(int argc,const char *argv[]) {
    @autoreleasepool { NSApplication *app=[NSApplication sharedApplication]; [app setActivationPolicy:NSApplicationActivationPolicyAccessory]; Fixture *delegate=[Fixture new];app.delegate=delegate;[app run]; }
    return 0;
}

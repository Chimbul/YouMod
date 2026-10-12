#import "Headers.h"

static NSString *const YouModLatestReleaseAPI = @"https://api.github.com/repos/Tonwalter888/YouMod/releases/latest";
static NSString *const YouModLatestReleaseURL = @"https://github.com/Tonwalter888/YouMod/releases/latest";
static const NSTimeInterval YouModUpdateCheckInterval = 24.0 * 60.0 * 60.0;
static BOOL YouModUpdateCheckInFlight = NO;

static NSString *YouModVersionFromTag(id value) {
    if (![value isKindOfClass:[NSString class]]) return nil;
    NSString *version = [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (version.length > 1 && ([[version substringToIndex:1] caseInsensitiveCompare:@"v"] == NSOrderedSame)) {
        version = [version substringFromIndex:1];
    }
    return version.length ? version : nil;
}

static void YouModCheckForUpdate(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults boolForKey:NotifyUpdates] || YouModUpdateCheckInFlight) return;

    NSDate *lastCheck = [defaults objectForKey:UpdateLastCheckDate];
    if ([lastCheck isKindOfClass:[NSDate class]] && [[NSDate date] timeIntervalSinceDate:lastCheck] < YouModUpdateCheckInterval) return;

    NSURL *url = [NSURL URLWithString:YouModLatestReleaseAPI];
    if (!url) return;

    YouModUpdateCheckInFlight = YES;
    [defaults setObject:[NSDate date] forKey:UpdateLastCheckDate];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:15.0];
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"YouMod" forHTTPHeaderField:@"User-Agent"];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            YouModUpdateCheckInFlight = NO;
            if (error || ![response isKindOfClass:[NSHTTPURLResponse class]] || ((NSHTTPURLResponse *)response).statusCode != 200 || !data) return;

            id release = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (![release isKindOfClass:[NSDictionary class]]) return;
            NSString *latestVersion = YouModVersionFromTag(release[@"tag_name"]);
            NSString *installedVersion = YouModVersionFromTag(YouModVersion);
            if (!latestVersion || !installedVersion || [latestVersion compare:installedVersion options:NSNumericSearch] != NSOrderedDescending) return;
            if (![defaults boolForKey:NotifyUpdates]) return;
            if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) {
                [defaults removeObjectForKey:UpdateLastCheckDate];
                return;
            }

            YTAlertView *alert = [%c(YTAlertView) confirmationDialogWithAction:^{
                [%c(YTUIUtils) openURL:[NSURL URLWithString:YouModLatestReleaseURL]];
            } actionTitle:LOC(@"UPDATE_NOW")];
            alert.title = [NSString stringWithFormat:LOC(@"UPDATE_AVAILABLE_TITLE"), latestVersion];
            alert.subtitle = LOC(@"UPDATE_AVAILABLE_MESSAGE");
            alert.shouldDismissOnBackgroundTap = YES;
            [alert show];
        });
    }];
    [task resume];
}

%ctor {
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(__unused NSNotification *note) {
        YouModCheckForUpdate();
    }];
}

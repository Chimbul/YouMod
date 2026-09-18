// Some are adapted from https://github.com/Mark02-2012/YTPlaybackFix
#import "Headers.h"

%hook YTMainAppVideoPlayerOverlayViewController
- (void)handleError:(NSError *)error {
    if (error && [error.domain isEqualToString:@"com.google.ios.youtube.ErrorDomain.playback"] && error.code == 14) {
        YTPlayerViewController *playerViewController = self.parentViewController;
        if (![playerViewController.UIDelegate isKindOfClass:%c(YTWatchController)]) return;
        YTWatchController *watchController = (YTWatchController *)playerViewController.UIDelegate;
        dispatch_async(dispatch_get_main_queue(), ^{  
            [watchController reload];
        });
        return;
    }
    %orig;
}
%end

%ctor {
    if (!IS_ENABLED(FixPlaybackIssues)) return;
    %init;
}
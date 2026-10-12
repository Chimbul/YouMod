#import "Headers.h"

static void YouModApplyLiquidGlassToView(UIView *view) {
    [view ax_setWantsFlexibleGlassAppearance:YES];
}

%hook YTChipCloudChipView
- (void)didMoveToWindow {
    %orig;
    YouModApplyLiquidGlassToView(self);
}
%end

%hook YTRightNavigationButtons
- (NSArray <YTQTMButton *> *)visibleButtons {
    NSArray <YTQTMButton *> *orig = %orig;
    if (orig && orig.count > 0) for (YTQTMButton *button in orig) YouModApplyLiquidGlassToView(button);
    return orig;
}
%end

%hook YTMainAppControlsOverlayView
- (void)didMoveToWindow {
    %orig;
    UIView *prevBut = [self valueForKey:@"_previousButtonView"];
    UIView *nextBut = [self valueForKey:@"_nextButtonView"];
    if (prevBut != nil) YouModApplyLiquidGlassToView(prevBut);
    if (nextBut != nil) YouModApplyLiquidGlassToView(nextBut);
    prevBut = [self valueForKey:@"_seekBackwardAccessibilityButtonView"];
    nextBut = [self valueForKey:@"_seekForwardAccessibilityButtonView"];
    if (prevBut != nil) YouModApplyLiquidGlassToView(prevBut);
    if (nextBut != nil) YouModApplyLiquidGlassToView(nextBut);
    YouModApplyLiquidGlassToView(self.playPauseButton);
}
%end

%hook YTInlinePlayerBarContainerView
- (void)didMoveToWindow {
    %orig;
    @try {
        YouModApplyLiquidGlassToView(self.enterExitFullscreenButton);
        YouModApplyLiquidGlassToView(self.timestampGestureView);
        if (self.liveSyncButton != nil) YouModApplyLiquidGlassToView(self.liveSyncButton);
        YTLightweightQTMButton *button = ((UIView *)[self valueForKey:@"_chapterTitleFrostedGlassView"]).superview;
        YouModApplyLiquidGlassToView(button);
    }
}
%end

%hook YTEngagementPanelHeaderView
- (void)didMoveToWindow {
    %orig;
    if (self.informationButton != nil) YouModApplyLiquidGlassToView(self.informationButton);
    if (self.sortFilterMenuButton != nil) YouModApplyLiquidGlassToView(self.sortFilterMenuButton);
    if (self.closeButton != nil) YouModApplyLiquidGlassToView(self.closeButton);
    if (self.backButton != nil) YouModApplyLiquidGlassToView(self.backButton);
}
%end

%hook YTSearchBarView
- (void)didMoveToWindow {
    %orig;
    YouModApplyLiquidGlassToView(self);
}
%end

%hook GSKRedMicButton
- (void)didMoveToWindow {
    %orig;
    YouModApplyLiquidGlassToView(self);
}
%end

%hook YTLeftNavigationButtons
- (void)didMoveToWindow {
    %orig;
    if (self.backButton != nil) YouModApplyLiquidGlassToView(self.backButton);
}
%end

%ctor {
    if (!IS_IOS_OR_NEWER(iOS_26_0)) return;
    %init;
}
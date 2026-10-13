#import "Headers.h"

void YouModApplyLiquidGlassToView(UIView *view, BOOL wantsBackground) {
    if (wantsBackground && [view respondsToSelector:@selector(tuui_applyFlexibleClearGlassWithShadowBackground)]) [view tuui_applyFlexibleClearGlassWithShadowBackground];
    else if ([view respondsToSelector:@selector(tuui_applyFlexibleSmallGlassBackground)]) [view tuui_applyFlexibleSmallGlassBackground];
}

%hook YTChipCloudChipView
- (void)didMoveToWindow {
    %orig;
    YouModApplyLiquidGlassToView(self, YES);
}
%end

%hook YTRightNavigationButtons
- (NSArray <YTQTMButton *> *)visibleButtons {
    NSArray <YTQTMButton *> *orig = %orig;
    if (orig && orig.count > 0) for (YTQTMButton *button in orig) YouModApplyLiquidGlassToView(button, YES);
    return orig;
}
%end

%hook YTMainAppControlsOverlayView
- (void)didMoveToWindow {
    %orig;
    UIView *prevBut = [self valueForKey:@"_previousButtonView"];
    UIView *nextBut = [self valueForKey:@"_nextButtonView"];
    if (prevBut != nil) YouModApplyLiquidGlassToView(prevBut, NO);
    if (nextBut != nil) YouModApplyLiquidGlassToView(nextBut, NO);
    prevBut = [self valueForKey:@"_seekBackwardAccessibilityButtonView"];
    nextBut = [self valueForKey:@"_seekForwardAccessibilityButtonView"];
    if (prevBut != nil) YouModApplyLiquidGlassToView(prevBut, NO);
    if (nextBut != nil) YouModApplyLiquidGlassToView(nextBut, NO);
    YouModApplyLiquidGlassToView(self.playPauseButton);
}
%end

%hook YTInlinePlayerBarContainerView
- (void)layoutSubviews {
    %orig;
    YouModApplyLiquidGlassToView(self.enterExitFullscreenButton, NO);
    YouModApplyLiquidGlassToView(self.exitFullscreenButton, NO);
    // YouModApplyLiquidGlassToView(self.timestampGestureView);
    // if (self.liveSyncButton != nil) YouModApplyLiquidGlassToView(self.liveSyncButton);
    // YTLightweightQTMButton *button = ((UIView *)[self valueForKey:@"_chapterTitleFrostedGlassView"]).superview;
    // YouModApplyLiquidGlassToView(button);
}
%end

%hook YTEngagementPanelHeaderView
- (void)didMoveToWindow {
    %orig;
    if (self.informationButton != nil) YouModApplyLiquidGlassToView(self.informationButton, YES);
    if (self.sortFilterMenuButton != nil) YouModApplyLiquidGlassToView(self.sortFilterMenuButton, YES);
    if (self.closeButton != nil) YouModApplyLiquidGlassToView(self.closeButton, YES);
    if (self.backButton != nil) YouModApplyLiquidGlassToView(self.backButton, YES);
}
%end

%hook YTSearchBarView
- (void)didMoveToWindow {
    %orig;
    YouModApplyLiquidGlassToView(self, YES);
}
%end

%hook GSKRedMicButton
- (void)didMoveToWindow {
    %orig;
    YouModApplyLiquidGlassToView(self, NO);
}
%end

%hook YTLeftNavigationButtons
- (void)didMoveToWindow {
    %orig;
    if (self.backButton != nil) YouModApplyLiquidGlassToView(self.backButton, YES);
}
%end